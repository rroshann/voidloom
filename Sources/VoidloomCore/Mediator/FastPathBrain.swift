import Foundation

public enum BrainError: Error, Equatable {
    case unparseable(String)
}

/// Deterministic command parser — the instant, zero-model fast path the spec
/// reserves in front of the LLM brains, and the only brain in the typed-input
/// build. Grammar is intentionally narrow: on any doubt it throws and the HUD
/// asks to rephrase, per the no-guess rule. Word order: verb first.
public final class FastPathBrain: MediatorBrain {
    public init() {}

    public func command(for utterance: String) async throws -> MediatorCommand {
        guard let command = Self.parse(utterance) else {
            throw BrainError.unparseable(utterance)
        }
        return command
    }

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8,
    ]

    static func parse(_ utterance: String) -> MediatorCommand? {
        let text = utterance.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = text.split(separator: " ").map(String.init)
        guard let rawHead = words.first else { return nil }
        // `note: buy milk` tokenizes to a `note:` head; the colon belongs to the
        // card grammar, not the verb, so strip it before dispatch.
        let head = rawHead.hasSuffix(":") ? String(rawHead.dropLast()) : rawHead

        switch head {
        case "spawn", "start", "open", "launch":
            return parseSpawn(Array(words.dropFirst()))
        case "ask", "tell", "prompt":
            return parseSendPrompt(Array(words.dropFirst()))
        case "read", "show":
            guard words.count >= 2 else { return nil }
            return .readOutput(target: strippedName(words[1]))
        case "close", "kill", "terminate":
            guard words.count >= 2 else { return nil }
            return .closeTerminal(target: strippedName(words[1]))
        case "focus":
            let rest = words.dropFirst().filter { $0 != "on" }
            guard let name = rest.first else { return nil }
            return .arrange(style: .focus(target: strippedName(name)))
        case "retile", "re-tile", "tile":
            return .arrange(style: .retile)
        case "grid":
            return .arrange(style: .grid)
        case "arrange":
            return text.contains("grid") ? .arrange(style: .grid) : .arrange(style: .retile)
        case "switch", "go":
            let rest = words.dropFirst().filter { $0 != "to" }
            guard !rest.isEmpty else { return nil }
            return .switchSpace(name: rest.joined(separator: " "))
        case "background":
            return parseBackground(Array(words.dropFirst()))
        case "note", "todo", "browser":
            let kind: CardKind = head == "note" ? .note : (head == "todo" ? .todo : .browser)
            let content = text.dropFirst(head.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            return .createCard(kind: kind, content: content.isEmpty ? nil : content)
        default:
            return nil
        }
    }

    private static func parseSpawn(_ words: [String]) -> MediatorCommand? {
        guard let first = words.first else { return nil }
        let count = Int(first) ?? numberWords[first] ?? 0
        guard count > 0 else { return nil }

        let nameMarker = words.firstIndex { $0 == "named" || $0 == "called" }
        // Only words up to the name marker can name the process kind, so an
        // agent NAMED "shell" no longer flips a claude agent to a shell (carry-over #5).
        let kindScan = nameMarker.map { Array(words[..<$0]) } ?? words
        let kind: MediatorAgentKind = kindScan.contains("shell") ? .shell : .claudeCode

        var names: [String]? = nil
        if let namedIdx = nameMarker {
            let raw = words[(namedIdx + 1)...]
                .flatMap { $0.split(separator: ",").map(String.init) }
                .filter { $0 != "and" && !$0.isEmpty }
            if !raw.isEmpty { names = raw }
        }
        return .spawnAgents(count: count, kind: kind, names: names)
    }

    private static func parseSendPrompt(_ words: [String]) -> MediatorCommand? {
        guard words.count >= 2 else { return nil }
        let target = strippedName(words[0])
        var rest = Array(words.dropFirst())
        if rest.first == "to" { rest.removeFirst() }
        guard !rest.isEmpty else { return nil }
        return .sendPrompt(target: target, text: rest.joined(separator: " "))
    }

    private static func parseBackground(_ words: [String]) -> MediatorCommand? {
        if let hex = words.first(where: { $0.hasPrefix("#") }) {
            return .setBackground(spec: .solid(hex: hex.uppercased()))
        }
        if words.contains("atmosphere") {
            return .setBackground(spec: .atmosphere)
        }
        return nil
    }

    private static func strippedName(_ word: String) -> String {
        var name = word
        if name.hasSuffix("'s") { name.removeLast(2) }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
    }
}
