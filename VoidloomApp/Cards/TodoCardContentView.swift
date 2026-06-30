import SwiftUI
import VoidloomCore

struct TodoItem: Identifiable, Equatable {
    let id: Int
    var isComplete: Bool
    var text: String
}

enum TodoContentParser {
    static func parse(_ content: String) -> [TodoItem] {
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

    static func serialize(_ items: [TodoItem]) -> String {
        items
            .map { item in
                let marker = item.isComplete ? "[x]" : "[ ]"
                return "\(marker) \(item.text)"
            }
            .joined(separator: "\n")
    }
}

struct TodoCardContentView: View {
    let cardID: UUID
    let content: String
    @ObservedObject var store: WorkspaceStore
    let isSelected: Bool

    @Environment(\.theme) private var theme

    @State private var items: [TodoItem]
    @State private var newItemText = ""
    @FocusState private var isNewItemFocused: Bool

    init(cardID: UUID, content: String, store: WorkspaceStore, isSelected: Bool) {
        self.cardID = cardID
        self.content = content
        self.store = store
        self.isSelected = isSelected
        _items = State(initialValue: TodoContentParser.parse(content))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($items) { $item in
                    Toggle(isOn: $item.isComplete) {
                        Text(item.text)
                            .font(.system(size: 13 * theme.fontScale, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.ink(item.isComplete ? 0.45 : 0.78))
                            .strikethrough(item.isComplete, color: theme.ink(0.35))
                    }
                    .toggleStyle(TodoCheckboxToggleStyle())
                    .onChange(of: item.isComplete) { _, _ in
                        persistItems()
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(theme.ink(0.45))

                    TextField("New item", text: $newItemText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12 * theme.fontScale, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.ink(0.72))
                        .focused($isNewItemFocused)
                        .onSubmit(addItem)
                        // Esc ends editing and is consumed here so it never
                        // bubbles to the window and exits native full screen.
                        .onExitCommand { isNewItemFocused = false }
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .allowsHitTesting(isSelected)
        .onChange(of: content) { _, newValue in
            let parsed = TodoContentParser.parse(newValue)
            guard parsed != items else { return }
            items = parsed
        }
        .onChange(of: isSelected) { _, selected in
            if !selected {
                newItemText = ""
            }
        }
    }

    private func addItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        items.append(TodoItem(id: items.count, isComplete: false, text: trimmed))
        newItemText = ""
        persistItems()
    }

    private func persistItems() {
        store.updateCardContent(id: cardID, to: TodoContentParser.serialize(items))
    }
}

private struct TodoCheckboxToggleStyle: ToggleStyle {
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(configuration.isOn ? .green.opacity(0.85) : theme.ink(0.45))

                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}
