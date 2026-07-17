import Foundation

/// Brief acknowledgments shown while a command is being parsed.
@MainActor
public enum AssistantAcks {
    public static let pool: [String] = [
        "On it…",
        "Sure —",
        "One sec…",
        "Looking at that…",
        "Mm-hm, working on it…",
    ]

    private static var lastReturned: String?

    /// Rotating pool; never returns the same ack twice in a row.
    public static func next() -> String {
        var candidates = pool
        if let last = lastReturned, pool.count > 1 {
            candidates = pool.filter { $0 != last }
        }
        let pick = candidates.randomElement() ?? pool[0]
        lastReturned = pick
        return pick
    }
}
