import Foundation

/// One line of a todo card. Items are stored in `WorkspaceCard.content` as
/// `[ ] text` / `[x] text` lines; this is the single parse/serialize authority
/// shared by the todo card view and the mediator's todo commands.
public struct TodoItem: Identifiable, Equatable, Sendable {
    public let id: Int
    public var isComplete: Bool
    public var text: String

    public init(id: Int, isComplete: Bool, text: String) {
        self.id = id
        self.isComplete = isComplete
        self.text = text
    }
}

public enum TodoContentParser {
    public static func parse(_ content: String) -> [TodoItem] {
        content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, rawLine in
                var line = String(rawLine)
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

                var isComplete = false

                if line.hasPrefix("- ") {
                    line = String(line.dropFirst(2))
                }

                if line.hasPrefix("[x]") || line.hasPrefix("[X]") {
                    isComplete = true
                    line = String(line.dropFirst(3))
                } else if line.hasPrefix("[ ]") {
                    line = String(line.dropFirst(3))
                }

                let text = line.trimmingCharacters(in: .whitespaces)
                return TodoItem(id: index, isComplete: isComplete, text: text.isEmpty ? "Item" : text)
            }
    }

    public static func serialize(_ items: [TodoItem]) -> String {
        items
            .map { item in
                let marker = item.isComplete ? "[x]" : "[ ]"
                return "\(marker) \(item.text)"
            }
            .joined(separator: "\n")
    }
}
