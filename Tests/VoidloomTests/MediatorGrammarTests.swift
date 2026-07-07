import XCTest
@testable import VoidloomCore
@testable import VoidloomAI

final class MediatorGrammarTests: XCTestCase {
    func testGrammarDeclaresARuleForEveryCommandCase() {
        let g = MediatorGrammar.rootGrammar
        for c in MediatorCommandSchema.cases {
            XCTAssertTrue(g.contains("\"\\\"\(c.name)\\\"\""),
                          "grammar missing a literal key for \(c.name)")
        }
        // Root alternates over exactly the 8 case rules.
        XCTAssertTrue(g.contains("root ::="))
    }

    func testKindIsConstrainedToAgentKindValuesNotFreeString() {
        let g = MediatorGrammar.rootGrammar
        // spawn kind alternation lists the concrete values, no open-ended string rule for kind.
        for value in MediatorCommandSchema.agentKindValues {
            XCTAssertTrue(g.contains("\"\\\"\(value)\\\"\""), "grammar missing kind value \(value)")
        }
    }

    func testGeneratedGrammarMatchesTheFrozenGoldenFile() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "mediator", withExtension: "gbnf"))
        let golden = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(
            MediatorGrammar.rootGrammar.trimmingCharacters(in: .whitespacesAndNewlines),
            golden.trimmingCharacters(in: .whitespacesAndNewlines),
            "generated GBNF drifted from the spike-validated golden — update golden ONLY after re-validating with llama"
        )
    }

    func testEverySchemaSampleIsAcceptedByTheReferenceRecognizer() throws {
        // A minimal GBNF recognizer covering the subset the generator emits, so
        // headless CI proves samples parse under the grammar without llama.
        let recognizer = try GBNFRecognizer(grammar: MediatorGrammar.rootGrammar)
        for (name, json) in MediatorCommandSchema.samples {
            XCTAssertTrue(recognizer.matches(json), "grammar rejects the frozen sample for \(name)")
        }
    }

    func testMalformedCommandsAreRejectedByTheReferenceRecognizer() throws {
        // Proves acceptance is meaningful: the recognizer discriminates against
        // JSON that violates the schema the grammar encodes.
        let recognizer = try GBNFRecognizer(grammar: MediatorGrammar.rootGrammar)
        let rejects: [String: String] = [
            "unknown top-level key": #"{"bogus":{}}"#,
            "kind outside agentKindValues": #"{"spawnAgents":{"count":2,"kind":"gpt"}}"#,
            "count is not a positive integer": #"{"spawnAgents":{"count":0,"kind":"claude"}}"#,
            "missing a required parameter": #"{"sendPrompt":{"target":"ember"}}"#,
            "cardKind outside allCases": #"{"createCard":{"kind":"widget"}}"#,
            "trailing garbage after a valid command": #"{"readOutput":{"target":"ember"}}x"#,
            "empty string is not a command": "",
        ]
        for (reason, json) in rejects {
            XCTAssertFalse(recognizer.matches(json), "grammar should reject: \(reason)")
        }
    }

    func testCommandsWithOptionalFieldsOmittedAreAccepted() throws {
        // The optional params (`spawnAgents.names`, `createCard.content`) are
        // omitted when nil (Swift's Codable drops the key); the grammar must
        // still accept the object without them.
        let recognizer = try GBNFRecognizer(grammar: MediatorGrammar.rootGrammar)
        XCTAssertTrue(recognizer.matches(#"{"spawnAgents":{"count":4,"kind":"claude"}}"#),
                      "grammar must accept spawnAgents without the optional names")
        XCTAssertTrue(recognizer.matches(#"{"createCard":{"kind":"note"}}"#),
                      "grammar must accept createCard without the optional content")
    }

    func testRecognizerRejectsGrammarWithNonGBNFEscape() {
        // `\:` is not a valid GBNF escape; llama.cpp throws "unknown escape".
        // The recognizer must fail to parse such a grammar rather than silently
        // treating `\:` as a literal colon (which previously masked the bug).
        XCTAssertThrowsError(try GBNFRecognizer(grammar: #"root ::= "\:""#)) { error in
            guard case GBNFRecognizer.GBNFError.parse = error else {
                return XCTFail("expected a parse error, got \(error)")
            }
        }
    }
}

// MARK: - Test-only GBNF-subset recognizer

/// A tiny recursive-descent recognizer for the GBNF subset the generator emits
/// (`::=`, `|`, string literals, rule refs, `?`, `*`, `+`, `[...]`/`[^...]`
/// char classes, `( … )` groups, insignificant whitespace between terms). It
/// exists so "sampled commands parse under the generated GBNF" is provable
/// headlessly — it is NOT the acceptance guarantee (that is Task 7's gated
/// llama integration test). Matching is backtracking-by-construction: each rule
/// yields the set of all input positions reachable after matching it, and a
/// string matches iff matching `root` from index 0 can consume the whole input.
struct GBNFRecognizer {
    enum GBNFError: Error { case parse(String) }

    enum Quant { case one, optional, star, plus }

    indirect enum Term {
        case literal([Character])
        case charClass(negated: Bool, ranges: [(Character, Character)])
        case ref(String)
        case group(Alternation)
    }

    struct QTerm { let term: Term; let quant: Quant }
    typealias Sequence = [QTerm]
    typealias Alternation = [Sequence]

    let rules: [String: Alternation]

    init(grammar: String) throws {
        var parsed: [String: Alternation] = [:]
        for rawLine in grammar.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            guard let sep = line.range(of: "::=") else {
                throw GBNFError.parse("missing ::= in line: \(line)")
            }
            let name = line[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
            var parser = BodyParser(chars: Array(line[sep.upperBound...]))
            parsed[name] = try parser.parseBody()
        }
        rules = parsed
    }

    func matches(_ input: String) -> Bool {
        guard let root = rules["root"] else { return false }
        let chars = Array(input)
        return matchAlternation(root, chars, 0).contains(chars.count)
    }

    private func matchAlternation(_ alt: Alternation, _ chars: [Character], _ start: Int) -> Set<Int> {
        var out: Set<Int> = []
        for seq in alt { out.formUnion(matchSequence(seq, chars, start)) }
        return out
    }

    private func matchSequence(_ seq: Sequence, _ chars: [Character], _ start: Int) -> Set<Int> {
        var current: Set<Int> = [start]
        for qt in seq {
            var next: Set<Int> = []
            for pos in current { next.formUnion(matchQTerm(qt, chars, pos)) }
            if next.isEmpty { return [] }
            current = next
        }
        return current
    }

    private func matchQTerm(_ qt: QTerm, _ chars: [Character], _ pos: Int) -> Set<Int> {
        switch qt.quant {
        case .one:
            return matchTerm(qt.term, chars, pos)
        case .optional:
            var s = matchTerm(qt.term, chars, pos)
            s.insert(pos)
            return s
        case .star:
            return closure(qt.term, chars, pos, includeStart: true)
        case .plus:
            return closure(qt.term, chars, pos, includeStart: false)
        }
    }

    /// All positions reachable by matching `term` zero-or-more (`includeStart`)
    /// or one-or-more times, via monotone frontier expansion (terminates because
    /// reachable positions are bounded by the input length).
    private func closure(_ term: Term, _ chars: [Character], _ pos: Int, includeStart: Bool) -> Set<Int> {
        var reachable = includeStart ? Set([pos]) : matchTerm(term, chars, pos)
        var frontier = reachable
        while !frontier.isEmpty {
            var discovered: Set<Int> = []
            for p in frontier {
                for np in matchTerm(term, chars, p) where !reachable.contains(np) {
                    discovered.insert(np)
                }
            }
            reachable.formUnion(discovered)
            frontier = discovered
        }
        return reachable
    }

    private func matchTerm(_ term: Term, _ chars: [Character], _ pos: Int) -> Set<Int> {
        switch term {
        case .literal(let lit):
            let end = pos + lit.count
            guard end <= chars.count, Array(chars[pos..<end]) == lit else { return [] }
            return [end]
        case .charClass(let negated, let ranges):
            guard pos < chars.count else { return [] }
            let c = chars[pos]
            let inSet = ranges.contains { c >= $0.0 && c <= $0.1 }
            return (inSet != negated) ? [pos + 1] : []
        case .ref(let name):
            guard let r = rules[name] else { return [] }
            return matchAlternation(r, chars, pos)
        case .group(let alt):
            return matchAlternation(alt, chars, pos)
        }
    }

    // MARK: Parser

    private struct BodyParser {
        let chars: [Character]
        var i = 0

        mutating func parseBody() throws -> Alternation {
            let alt = try parseAlternation()
            skipWs()
            guard i >= chars.count else { throw GBNFError.parse("trailing input in rule body at \(i)") }
            return alt
        }

        mutating func parseAlternation() throws -> Alternation {
            var alts: Alternation = [try parseSequence()]
            skipWs()
            while i < chars.count, chars[i] == "|" {
                i += 1
                alts.append(try parseSequence())
                skipWs()
            }
            return alts
        }

        mutating func parseSequence() throws -> Sequence {
            var seq: Sequence = []
            skipWs()
            while i < chars.count, chars[i] != "|", chars[i] != ")" {
                let term = try parseTerm()
                let quant = parseQuant()
                seq.append(QTerm(term: term, quant: quant))
                skipWs()
            }
            return seq
        }

        mutating func parseTerm() throws -> Term {
            skipWs()
            guard i < chars.count else { throw GBNFError.parse("unexpected end of body") }
            switch chars[i] {
            case "\"": return .literal(try parseStringLiteral())
            case "[": return try parseCharClass()
            case "(":
                i += 1
                let alt = try parseAlternation()
                skipWs()
                guard i < chars.count, chars[i] == ")" else { throw GBNFError.parse("expected )") }
                i += 1
                return .group(alt)
            default:
                return .ref(try parseIdentifier())
            }
        }

        mutating func parseQuant() -> Quant {
            guard i < chars.count else { return .one }
            switch chars[i] {
            case "?": i += 1; return .optional
            case "*": i += 1; return .star
            case "+": i += 1; return .plus
            default: return .one
            }
        }

        mutating func parseStringLiteral() throws -> [Character] {
            i += 1 // opening quote
            var out: [Character] = []
            while i < chars.count {
                let c = chars[i]
                if c == "\"" { i += 1; return out }
                if c == "\\" {
                    i += 1
                    guard i < chars.count else { throw GBNFError.parse("dangling escape in string") }
                    out.append(try unescape(chars[i]))
                    i += 1
                } else {
                    out.append(c)
                    i += 1
                }
            }
            throw GBNFError.parse("unterminated string literal")
        }

        mutating func parseCharClass() throws -> Term {
            i += 1 // [
            var negated = false
            if i < chars.count, chars[i] == "^" { negated = true; i += 1 }
            var ranges: [(Character, Character)] = []
            while i < chars.count, chars[i] != "]" {
                let lo = try readClassChar()
                if i < chars.count, chars[i] == "-", i + 1 < chars.count, chars[i + 1] != "]" {
                    i += 1 // -
                    let hi = try readClassChar()
                    ranges.append((lo, hi))
                } else {
                    ranges.append((lo, lo))
                }
            }
            guard i < chars.count, chars[i] == "]" else { throw GBNFError.parse("unterminated char class") }
            i += 1
            return .charClass(negated: negated, ranges: ranges)
        }

        mutating func readClassChar() throws -> Character {
            guard i < chars.count else { throw GBNFError.parse("eof in char class") }
            let c = chars[i]
            if c == "\\" {
                i += 1
                guard i < chars.count else { throw GBNFError.parse("dangling escape in char class") }
                let e = try unescape(chars[i])
                i += 1
                return e
            }
            i += 1
            return c
        }

        mutating func parseIdentifier() throws -> String {
            var out: [Character] = []
            while i < chars.count {
                let c = chars[i]
                if c.isLetter || c.isNumber || c == "-" || c == "_" {
                    out.append(c)
                    i += 1
                } else {
                    break
                }
            }
            guard !out.isEmpty else { throw GBNFError.parse("expected identifier at \(i)") }
            return String(out)
        }

        mutating func skipWs() {
            while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
        }

        /// GBNF permits only a fixed escape set; llama.cpp throws "unknown escape"
        /// on anything else (notably `\:` and `\,`, which are NOT special). This
        /// rejects unknown escapes so the recognizer is a real oracle for escape
        /// validity. `\x`/`\u`/`\U` hex escapes are valid GBNF but unused by this
        /// generator, so they are intentionally out of this subset.
        private func unescape(_ c: Character) throws -> Character {
            switch c {
            case "n": return "\n"
            case "t": return "\t"
            case "r": return "\r"
            case "\\", "\"", "[", "]": return c
            default: throw GBNFError.parse("unknown GBNF escape \\\(c)")
            }
        }
    }
}
