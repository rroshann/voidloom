import Foundation

/// A logical grouping for palette commands, shown as a section header.
enum PaletteSection: String, CaseIterable {
    case create = "Create"
    case workspaces = "Workspaces"
    case view = "View"
    case app = "App"
}

/// A single runnable action in the command palette.
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let section: PaletteSection
    let systemImage: String
    /// Extra terms (beyond the title) that should match this command when typed.
    let keywords: [String]
    let action: () -> Void

    init(
        id: String,
        title: String,
        section: PaletteSection,
        systemImage: String,
        keywords: [String] = [],
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.section = section
        self.systemImage = systemImage
        self.keywords = keywords
        self.action = action
    }
}

enum CommandPaletteFilter {
    /// Case-insensitive token match against title + keywords. Every whitespace
    /// token in the query must appear somewhere in the command's haystack.
    /// An empty query returns everything (original order preserved).
    static func filter(_ commands: [PaletteCommand], query: String) -> [PaletteCommand] {
        let tokens = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard !tokens.isEmpty else { return commands }

        return commands.filter { command in
            let haystack = ([command.title] + command.keywords)
                .joined(separator: " ")
                .lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
}
