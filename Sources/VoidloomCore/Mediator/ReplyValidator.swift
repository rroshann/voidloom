import Foundation

/// Mechanical string checks that a model reply only names live cards.
/// Pure string mechanics — never a second LLM call.
public enum ReplyValidator {
    public struct Verdict: Equatable, Sendable {
        public let isGrounded: Bool
        public let offendingNames: [String]

        public init(isGrounded: Bool, offendingNames: [String]) {
            self.isGrounded = isGrounded
            self.offendingNames = offendingNames
        }
    }

    /// AgentNamePool names + schema example names: ember, slate, nova, drift,
    /// ridge, quartz, scout, juno. Exposed for tests.
    public static let defaultForbidden: Set<String> = [
        "ember", "slate", "nova", "drift", "ridge", "quartz", "scout", "juno",
    ]

    private static let kindNouns = ["terminal", "note", "card", "todo", "agent"]

    /// Articles / possessives that may be capitalized at sentence start
    /// ("The note", "Your My Ideas note") and must not count as card names.
    private static let leadingDeterminers: Set<String> = [
        "a", "an", "the", "this", "that", "these", "those",
        "my", "your", "our", "their", "its", "his", "her",
        "some", "any", "each", "every", "one", "another",
        "new", "old", "other", "same",
    ]

    /// knownTitles = live card titles (case-insensitive match).
    /// Checks: (1) any default-forbidden example/pool name appearing in the reply
    /// while NOT a live title; (2) "<Name> terminal|note|card|todo|agent" and
    /// "terminal|note|card named|called <Name>" patterns where Name is not a
    /// live title. Plain words ("a note", "the note") never flag.
    public static func validate(reply: String, knownTitles: [String]) -> Verdict {
        let live = Set(knownTitles.map { $0.lowercased() })
        var offenders: [String] = []
        var seenLower: Set<String> = []

        func record(_ raw: String) {
            let key = raw.lowercased()
            guard !seenLower.contains(key) else { return }
            seenLower.insert(key)
            offenders.append(raw)
        }

        // (1) Forbidden pool/schema names present as whole words, not live titles.
        for name in defaultForbidden {
            guard !live.contains(name) else { continue }
            if containsWholeWord(name, in: reply) {
                record(surfaceForm(of: name, in: reply) ?? name)
            }
        }

        // (2a) Capitalized name sequence before a kind noun ("Juno note", "My Ideas note").
        // Leading determiners are stripped so "The note" never flags; a live-title
        // suffix ("Your My Ideas note" with live "my ideas") is accepted.
        let kindAlternation = kindNouns.joined(separator: "|")
        let beforeKind = try! NSRegularExpression(
            pattern: #"\b([A-Z][A-Za-z0-9-]*(?:\s+[A-Z][A-Za-z0-9-]*)*)\s+(?:\#(kindAlternation))s?\b"#
        )
        for match in matches(of: beforeKind, in: reply) {
            guard match.numberOfRanges >= 2,
                  let nameRange = Range(match.range(at: 1), in: reply) else { continue }
            let candidate = String(reply[nameRange])
            if let offender = properNameOffender(candidate, live: live) {
                record(offender)
            }
        }

        // (2b) "terminal|note|card named|called <Name>"
        let namedKind = try! NSRegularExpression(
            pattern: #"(?i)\b(?:terminal|note|card)s?\s+(?:named|called)\s+([A-Za-z][\w-]*)\b"#
        )
        for match in matches(of: namedKind, in: reply) {
            guard match.numberOfRanges >= 2,
                  let nameRange = Range(match.range(at: 1), in: reply) else { continue }
            let candidate = String(reply[nameRange])
            if live.contains(candidate.lowercased()) { continue }
            if leadingDeterminers.contains(candidate.lowercased()) { continue }
            record(candidate)
        }

        return Verdict(isGrounded: offenders.isEmpty, offendingNames: offenders)
    }

    /// Returns the offending surface name, or nil when the candidate is generic
    /// phrasing or matches a live title (including a multi-word title suffix).
    /// Live-title suffixes are checked before stripping determiners so a title
    /// like "my ideas" still matches inside "Your My Ideas note".
    private static func properNameOffender(_ candidate: String, live: Set<String>) -> String? {
        let words = candidate.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        for length in stride(from: words.count, through: 1, by: -1) {
            let suffix = words.suffix(length).joined(separator: " ")
            if live.contains(suffix.lowercased()) { return nil }
        }

        var remainder = words
        while let first = remainder.first, leadingDeterminers.contains(first.lowercased()) {
            remainder.removeFirst()
        }
        guard !remainder.isEmpty else { return nil }

        for length in stride(from: remainder.count, through: 1, by: -1) {
            let suffix = remainder.suffix(length).joined(separator: " ")
            if live.contains(suffix.lowercased()) { return nil }
        }

        return remainder.joined(separator: " ")
    }

    private static func containsWholeWord(_ word: String, in text: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func surfaceForm(of word: String, in text: String) -> String? {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func matches(of regex: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range)
    }
}
