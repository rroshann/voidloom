import SwiftUI
import VoidloomCore

struct BrowserCardContentView: View {
    let cardID: UUID
    let content: String
    @ObservedObject var store: WorkspaceStore
    let isSelected: Bool

    @Environment(\.theme) private var theme

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
            // ── Toolbar row ───────────────────────────────────────────────
            HStack(spacing: 6) {
                Circle().fill(.red.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(.yellow.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(.green.opacity(0.75)).frame(width: 8, height: 8)

                // URL bar
                Group {
                    if isEditingURL {
                        TextField("https://example.com", text: $urlDraft)
                            .textFieldStyle(.plain)
                            .focused($isURLFieldFocused)
                            .onSubmit(commitURL)
                            .onExitCommand { cancelURLEdit() }
                            .foregroundStyle(urlDraft.isEmpty || BrowserURLResolver.isValid(urlDraft)
                                             ? theme.ink(0.55) : Color.red.opacity(0.8))
                    } else {
                        Text(displayURL)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard isSelected else { return }
                                // Pre-populate draft with the live URL so the user edits what they see
                                urlDraft = loadModel.currentURL?.absoluteString ?? content
                                isEditingURL = true
                                isURLFieldFocused = true
                            }
                    }
                }
                .font(.system(size: 10, weight: .semibold, design: theme.monospacedMetadata ? .monospaced : .default))
                .foregroundStyle(theme.ink(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.surface(0.08))
                )

                // Navigation controls
                HStack(spacing: 4) {
                    Button { loadModel.goBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .disabled(!loadModel.canGoBack)

                    Button { loadModel.goForward() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .disabled(!loadModel.canGoForward)

                    Button {
                        if loadModel.isLoading { loadModel.stop() } else { loadModel.reload() }
                    } label: {
                        Image(systemName: loadModel.isLoading ? "xmark" : "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.ink(0.55))
            }

            // ── Page title (secondary, truncated) ─────────────────────────
            if let title = loadModel.pageTitle, !title.isEmpty {
                Text(title)
                    .font(.system(size: 9 * theme.fontScale, weight: .regular))
                    .foregroundStyle(theme.ink(0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 4)
                    .allowsHitTesting(false)
            }

            // ── Web view + overlays ───────────────────────────────────────
            ZStack {
                BrowserWebView(urlString: content, model: loadModel)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if loadModel.isLoading {
                    VStack {
                        ProgressView(value: loadModel.progress)
                            .progressViewStyle(.linear)
                            .tint(theme.ink(0.7))
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
            if !focused, isEditingURL { commitURL() }
        }
        .onChange(of: content) { _, newValue in
            guard !isEditingURL else { return }
            urlDraft = newValue
        }
        .onChange(of: isSelected) { _, selected in
            if !selected { cancelURLEdit() }
        }
    }

    // Shows the live in-page URL while not editing; falls back to the persisted content
    private var displayURL: String {
        if let liveURL = loadModel.currentURL {
            return liveURL.absoluteString
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://voidloom.local" : trimmed
    }

    private func commitURL() {
        let trimmed = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard BrowserURLResolver.isValid(trimmed) else {
            // Red tint already signals invalid; do not persist garbage
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
