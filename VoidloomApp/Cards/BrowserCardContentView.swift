import SwiftUI
import VoidloomCore

struct BrowserCardContentView: View {
    let cardID: UUID
    let content: String
    @ObservedObject var store: WorkspaceStore
    let isSelected: Bool

    @StateObject private var loadModel = BrowserLoadModel()
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
                            .foregroundStyle(urlDraft.isEmpty || BrowserURLResolver.isValid(urlDraft)
                                             ? .white.opacity(0.55) : .red.opacity(0.8))
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

            ZStack {
                BrowserWebView(urlString: content, model: loadModel)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(isSelected)

                if loadModel.isLoading {
                    VStack {
                        ProgressView(value: loadModel.progress)
                            .progressViewStyle(.linear)
                            .tint(.white.opacity(0.7))
                        Spacer()
                    }
                    .padding(8)
                    .allowsHitTesting(false)
                }

                if let error = loadModel.lastError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2).foregroundStyle(.orange)
                        Text("Couldn't load page").font(.headline).foregroundStyle(.white.opacity(0.9))
                        Text(error).font(.caption).foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center).lineLimit(3)
                        Button("Retry") { loadModel.reload() }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
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
        guard BrowserURLResolver.isValid(trimmed) else {
            // keep editing; the red tint (below) signals invalid; do not persist garbage.
            return
        }
        isEditingURL = false
        isURLFieldFocused = false
        store.updateCardContent(id: cardID, to: trimmed)
    }

    private func cancelURLEdit() {
        urlDraft = content
        isEditingURL = false
        isURLFieldFocused = false
    }
}
