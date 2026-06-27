import SwiftUI
import VoidloomCore

struct BrowserCardContentView: View {
    let cardID: UUID
    let content: String
    @ObservedObject var store: WorkspaceStore
    let isSelected: Bool

    @State private var urlDraft: String
    @State private var isEditingURL = false
    @FocusState private var isURLFieldFocused: Bool

    init(cardID: UUID, content: String, store: WorkspaceStore, isSelected: Bool) {
        self.cardID = cardID
        self.content = content
        self.store = store
        self.isSelected = isSelected
        _urlDraft = State(initialValue: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(.red.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(.yellow.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(.green.opacity(0.75)).frame(width: 8, height: 8)

                Group {
                    if isEditingURL {
                        TextField("https://example.com", text: $urlDraft)
                            .textFieldStyle(.plain)
                            .focused($isURLFieldFocused)
                            .onSubmit(commitURL)
                            .onExitCommand { cancelURLEdit() }
                    } else {
                        Text(displayURL)
                            .lineLimit(1)
                            .onTapGesture {
                                guard isSelected else { return }
                                isEditingURL = true
                                isURLFieldFocused = true
                            }
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
            }
            .allowsHitTesting(isSelected)

            BrowserWebView(urlString: content)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(isSelected)
        }
        .padding(12)
        .onChange(of: isURLFieldFocused) { _, focused in
            if !focused, isEditingURL {
                commitURL()
            }
        }
        .onChange(of: content) { _, newValue in
            guard !isEditingURL else { return }
            urlDraft = newValue
        }
        .onChange(of: isSelected) { _, selected in
            if !selected {
                cancelURLEdit()
            }
        }
    }

    private var displayURL: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://voidloom.local" : trimmed
    }

    private func commitURL() {
        let trimmed = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingURL = false
        isURLFieldFocused = false
        store.updateCardContent(id: cardID, to: trimmed.isEmpty ? "https://voidloom.local" : trimmed)
    }

    private func cancelURLEdit() {
        urlDraft = content
        isEditingURL = false
        isURLFieldFocused = false
    }
}
