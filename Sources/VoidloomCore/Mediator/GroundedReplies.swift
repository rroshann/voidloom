import Foundation

/// Deterministic warm replies built only from real workspace state — used when
/// a model reply fails validation twice. Pool-based like `AssistantAcks`
/// (no immediate repeat).
@MainActor
public enum GroundedReplies {
    private static var lastReturned: String?

    /// Mentions real card titles (up to 3) or the empty state, and offers one
    /// concrete next step. Never invents cards.
    public static func fallback(cardTitles: [String], workspaceName: String) -> String {
        let pool = cardTitles.isEmpty
            ? emptyPool(workspaceName: workspaceName)
            : populatedPool(cardTitles: cardTitles, workspaceName: workspaceName)
        var candidates = pool
        if let last = lastReturned, pool.count > 1 {
            candidates = pool.filter { $0 != last }
        }
        let pick = candidates.randomElement() ?? pool[0]
        lastReturned = pick
        return pick
    }

    private static func emptyPool(workspaceName: String) -> [String] {
        [
            "\(workspaceName) is empty right now — want me to drop a note or spin up a terminal?",
            "Nothing on the canvas in \(workspaceName) yet. I can add a note or open a terminal whenever you're ready.",
            "Quiet workspace — \(workspaceName) has no cards. Say the word and I'll set one up.",
            "\(workspaceName)'s blank. A note or a terminal would get us started.",
        ]
    }

    private static func populatedPool(cardTitles: [String], workspaceName: String) -> [String] {
        let listed = listTitles(Array(cardTitles.prefix(3)))
        let extra = cardTitles.count > 3 ? " (and \(cardTitles.count - 3) more)" : ""
        return [
            "In \(workspaceName) you've got \(listed)\(extra). Want to open one, or add something new?",
            "Here's what's on the canvas: \(listed)\(extra). I can rearrange, rename, or add another card.",
            "Looking at \(workspaceName) — \(listed)\(extra). What should we do next?",
            "You've got \(listed)\(extra) in \(workspaceName). Tell me if you want a new note or terminal.",
        ]
    }

    private static func listTitles(_ titles: [String]) -> String {
        switch titles.count {
        case 0: return "nothing"
        case 1: return titles[0]
        case 2: return "\(titles[0]) and \(titles[1])"
        default:
            let head = titles.dropLast().joined(separator: ", ")
            return "\(head), and \(titles.last!)"
        }
    }
}
