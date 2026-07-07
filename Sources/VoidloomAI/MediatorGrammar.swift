import Foundation
import VoidloomCore

/// Generates the llama.cpp GBNF grammar for `MediatorCommand` FROM the frozen
/// `MediatorCommandSchema`. Hand-written GBNF (not json-schema-to-grammar):
/// the Swift enum-with-associated-value Codable encoding does not map cleanly
/// from JSON Schema (spike finding). The generated string is frozen against
/// `Resources/mediator.gbnf`, which the spike validated end-to-end with
/// Qwen3-0.6B (8/8 utterances → schema-valid JSON).
public enum MediatorGrammar {
    /// The complete root grammar, built deterministically from the schema.
    public static let rootGrammar: String = gbnf(from: MediatorCommandSchema.cases)

    public static func gbnf(from cases: [MediatorCommandSchema.Case]) -> String {
        var lines: [String] = []
        // `cmd-none` is the abstain option: the model emits {"none":{}} when the
        // utterance isn't a workspace command (a question, greeting, chit-chat).
        // It has no `MediatorCommand` case, so it fails to decode and surfaces as
        // `.unparseable` — which routes the utterance to the conversational path.
        let ruleNames = ["cmd-none"] + cases.map { "cmd-\($0.name)" }
        // Each `cmd-<name>` is a COMPLETE command object `{"name":{…}}` (see
        // `caseBody`), so root only alternates over them plus optional surrounding
        // whitespace — it must NOT add a second pair of object braces.
        lines.append("root ::= ws ( \(ruleNames.joined(separator: " | ")) ) ws")
        lines.append(#"cmd-none ::= "{" ws "\"none\"" ws ":" ws "{" ws "}" ws "}""#)

        for c in cases {
            lines.append("cmd-\(c.name) ::= \(caseBody(c))")
        }

        // Shared primitives (mirrors the spike's mediator.gbnf).
        lines.append(#"string ::= "\"" char* "\"""#)
        lines.append(#"char ::= [^"\\] | "\\" ( ["\\/bfnrt] | "u" hex hex hex hex )"#)
        lines.append("hex ::= [0-9a-fA-F]")
        lines.append("integer ::= [1-9] [0-9]*")
        lines.append(#"string-array ::= "[" ws string ( ws "," ws string )* ws "]""#)
        lines.append("ws ::= [ \\t\\n]*")
        return lines.joined(separator: "\n")
    }

    private static func caseBody(_ c: MediatorGrammar.SchemaCase) -> String {
        // {"name": { <params> }}
        let key = "\"\\\"\(c.name)\\\"\""
        let params = c.parameters
        var objectParts: [String] = []
        for (i, p) in params.enumerated() {
            let sep = i == 0 ? "" : "\",\" ws "
            let keyLit = "\"\\\"\(p.name)\\\"\" ws \":\" ws"
            let valueRule = valueGrammar(for: p.kind)
            let fragment = "\(sep)\(keyLit) \(valueRule)"
            if p.required {
                objectParts.append(fragment)
            } else {
                // Optional param is omitted when nil (spike risk #5 — Swift omits the key).
                objectParts.append("( \(fragment) )?")
            }
        }
        let inner = objectParts.joined(separator: " ")
        return "\"{\" ws \(key) ws \":\" ws \"{\" ws \(inner) ws \"}\" ws \"}\""
    }

    private static func valueGrammar(for kind: MediatorCommandSchema.Parameter.Kind) -> String {
        switch kind {
        case .string: return "string"
        case .integer: return "integer"
        case .stringArray: return "string-array"
        case .agentKind:
            let alts = MediatorCommandSchema.agentKindValues.map { "\"\\\"\($0)\\\"\"" }
            return "( \(alts.joined(separator: " | ")) )"
        case .cardKind:
            let alts = CardKind.allCases.map { "\"\\\"\($0.rawValue)\\\"\"" }
            return "( \(alts.joined(separator: " | ")) )"
        case .arrangeStyle:
            // {"grid":{}} | {"retile":{}} | {"focus":{"target": string}}
            return #"( "{" ws "\"grid\"" ws ":" ws "{" ws "}" ws "}" | "{" ws "\"retile\"" ws ":" ws "{" ws "}" ws "}" | "{" ws "\"focus\"" ws ":" ws "{" ws "\"target\"" ws ":" ws string ws "}" ws "}" )"#
        case .backgroundSpec:
            // {"atmosphere":{}} | {"solid":{"hex": string}}
            return #"( "{" ws "\"atmosphere\"" ws ":" ws "{" ws "}" ws "}" | "{" ws "\"solid\"" ws ":" ws "{" ws "\"hex\"" ws ":" ws string ws "}" ws "}" )"#
        }
    }
}

// Local alias so the generator reads cleanly; `SchemaCase` == `MediatorCommandSchema.Case`.
extension MediatorGrammar { typealias SchemaCase = MediatorCommandSchema.Case }
