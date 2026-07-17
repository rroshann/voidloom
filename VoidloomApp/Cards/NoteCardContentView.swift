import SwiftUI
import VoidloomCore

struct NoteCardContentView: View {
    let cardID: UUID
    let content: String
    @ObservedObject var store: WorkspaceStore
    let isSelected: Bool

    @Environment(\.theme) private var theme

    @State private var draft: String
    @State private var persistTask: Task<Void, Never>?
    @FocusState private var isEditorFocused: Bool

    init(cardID: UUID, content: String, store: WorkspaceStore, isSelected: Bool) {
        self.cardID = cardID
        self.content = content
        self.store = store
        self.isSelected = isSelected
        _draft = State(initialValue: content)
    }

    var body: some View {
        TextEditor(text: $draft)
            .font(.system(size: 13 * theme.fontScale, weight: .semibold, design: .rounded))
            .foregroundStyle(theme.ink(0.78))
            .scrollContentBackground(.hidden)
            .padding(12)
            // TextEditor has no native placeholder; overlay a grayed prompt while
            // empty so a new note guides the user without pre-filling text they must
            // delete (and without that prompt leaking into Sunday's context as if it
            // were the note's real content).
            .overlay(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Capture spatial context here.")
                        .font(.system(size: 13 * theme.fontScale, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.ink(0.3))
                        .padding(.leading, 17)
                        .padding(.top, 20)
                        .allowsHitTesting(false)
                }
            }
            .focused($isEditorFocused)
            // Esc ends editing (resign focus + persist) and is consumed here, so
            // it never bubbles to the window — which in native full screen would
            // otherwise treat Esc as "exit full screen".
            .onExitCommand {
                isEditorFocused = false
                flushPersist()
            }
            .onChange(of: draft) { _, newValue in
                guard isSelected else { return }
                schedulePersist(newValue)
            }
            .onChange(of: content) { _, newValue in
                guard newValue != draft else { return }
                draft = newValue
            }
            .onChange(of: isSelected) { _, selected in
                if !selected {
                    flushPersist()
                }
            }
            .onDisappear {
                flushPersist()
            }
    }

    private func schedulePersist(_ value: String) {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                store.updateCardContent(id: cardID, to: value)
            }
        }
    }

    private func flushPersist() {
        persistTask?.cancel()
        persistTask = nil
        guard draft != content else { return }
        store.updateCardContent(id: cardID, to: draft)
    }
}
