import Foundation

/// Builds the compact, LLM-facing snapshot of the current workspace that grounds
/// the assistant's answers. Pure and deterministic: the app layer gathers the
/// live inputs (names, cards, folder, git, running state) and calls `build`.
/// Hard-capped so it can never push a model past its context window.
public enum WorkspaceContextBuilder {
    /// One card, already reduced by the caller to what matters for context.
    public struct CardLine: Equatable, Sendable {
        public let title: String
        public let kind: String
        public let detail: String?
        public init(title: String, kind: String, detail: String? = nil) {
            self.title = title
            self.kind = kind
            self.detail = detail
        }
    }

    public struct Snapshot: Equatable, Sendable {
        public var workspaceName: String
        public var mode: String
        public var folderPath: String?
        public var gitSummary: String?
        public var brainTier: String?
        public var cards: [CardLine]
        public var recentActivity: String?
        public var selectedCardContext: String?

        public init(
            workspaceName: String,
            mode: String,
            folderPath: String? = nil,
            gitSummary: String? = nil,
            brainTier: String? = nil,
            cards: [CardLine] = [],
            recentActivity: String? = nil,
            selectedCardContext: String? = nil
        ) {
            self.workspaceName = workspaceName
            self.mode = mode
            self.folderPath = folderPath
            self.gitSummary = gitSummary
            self.brainTier = brainTier
            self.cards = cards
            self.recentActivity = recentActivity
            self.selectedCardContext = selectedCardContext
        }
    }

    /// Cards beyond this collapse into an "…and N more" line — enough to convey
    /// the workspace without unbounded growth.
    public static let maxCards = 20
    /// Per-card detail is trimmed to this many characters (first line only).
    public static let maxDetailCharacters = 80
    /// Absolute ceiling on the whole block. The header always survives.
    public static let maxCharacters = 1600

    public static func build(_ s: Snapshot) -> String {
        var lines: [String] = ["[Voidloom workspace context]"]
        lines.append("Workspace: \"\(s.workspaceName)\" (\(s.mode) mode)")

        if let folder = s.folderPath, !folder.isEmpty {
            if let git = s.gitSummary, !git.isEmpty {
                lines.append("Folder: \(folder) (git: \(git))")
            } else {
                lines.append("Folder: \(folder)")
            }
        }
        if let brain = s.brainTier, !brain.isEmpty {
            lines.append("Assistant: \(brain)")
        }

        if s.cards.isEmpty {
            lines.append("Cards: none")
        } else {
            lines.append("Cards (\(s.cards.count)):")
            for card in s.cards.prefix(maxCards) {
                lines.append("- \(cardLine(card))")
            }
            let remainder = s.cards.count - maxCards
            if remainder > 0 { lines.append("…and \(remainder) more") }
        }

        if let recent = s.recentActivity, !recent.isEmpty {
            lines.append("Recent: \(recent)")
        }
        if let selected = s.selectedCardContext?.trimmingCharacters(in: .whitespacesAndNewlines),
           !selected.isEmpty {
            lines.append("Selected card:")
            lines.append(selected)
        }

        return cap(lines.joined(separator: "\n"))
    }

    private static func cardLine(_ card: CardLine) -> String {
        let base = "\(card.title) — \(card.kind)"
        guard let detail = firstLine(card.detail), !detail.isEmpty else { return base }
        // A terminal's detail is a status ("running") → "…terminal, running".
        // Content cards' detail is their text → "…note: qa checklist".
        let separator = card.kind == "terminal" ? ", " : ": "
        return base + separator + detail
    }

    /// Detail collapses to its first non-empty line, trimmed to the detail cap.
    private static func firstLine(_ detail: String?) -> String? {
        guard let raw = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let first = raw.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? raw
        return first.count > maxDetailCharacters
            ? String(first.prefix(maxDetailCharacters)) + "…"
            : first
    }

    /// Truncate at a line boundary so the block stays well-formed, never cutting
    /// the header. Adds a marker so the model knows content was dropped.
    private static func cap(_ text: String) -> String {
        guard text.count > maxCharacters else { return text }
        let marker = "\n…[context truncated]"
        let budget = maxCharacters - marker.count
        var kept = String(text.prefix(max(0, budget)))
        if let lastNewline = kept.lastIndex(of: "\n") {
            kept = String(kept[..<lastNewline])
        }
        return kept + marker
    }
}
