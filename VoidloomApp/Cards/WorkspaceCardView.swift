import SwiftUI
import VoidloomCore

struct WorkspaceCardView: View {
    let card: WorkspaceCard
    @ObservedObject var store: WorkspaceStore
    var isSelected: Bool = false
    var isCardFocused: Bool = false
    var onToggleCardFocus: () -> Void = {}
    var onClose: () -> Void = {}
    @Binding var isEditingTitle: Bool
    @Binding var editingCardTitleID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    @State private var isHeaderHovered = false
    @State private var editingTitle = ""
    @FocusState private var isTitleFieldFocused: Bool

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(theme.ink(0.12))

            content
                .allowsHitTesting(isSelected)
        }
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: 18)
        .animation(selectionAnimation, value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHeaderHovered)
        .animation(.easeOut(duration: 0.15), value: isEditingTitle)
        .onChange(of: isSelected) { _, selected in
            if !selected {
                cancelTitleEdit()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.18))

                Image(systemName: palette.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                titleView

                Text(palette.eyebrow)
                    .font(.system(size: 10, weight: .bold, design: theme.monospacedMetadata ? .monospaced : .default))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(palette.accent.opacity(0.78))
            }

            Spacer(minLength: 0)

            if isSelected, isHeaderHovered, !isEditingTitle {
                headerActions
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .onHover { isHeaderHovered = $0 }
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditingTitle {
            TextField("Title", text: $editingTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14 * theme.fontScale, weight: .black, design: .rounded))
                .foregroundStyle(theme.ink(0.92))
                .focused($isTitleFieldFocused)
                .onSubmit {
                    commitTitle()
                }
                .onChange(of: isTitleFieldFocused) { _, focused in
                    if !focused {
                        commitTitle()
                    }
                }
                .onExitCommand {
                    cancelTitleEdit()
                }
                .onAppear {
                    editingTitle = card.title
                    isTitleFieldFocused = true
                }
        } else {
            Text(card.title)
                .font(.system(size: 14 * theme.fontScale, weight: .black, design: .rounded))
                .foregroundStyle(theme.ink(0.92))
                .lineLimit(1)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    beginTitleEdit()
                }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 4) {
            headerIconButton(
                systemName: "pencil",
                label: "Edit title",
                action: beginTitleEdit
            )

            headerIconButton(
                systemName: isCardFocused
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                label: isCardFocused ? "Exit card focus" : "Focus card",
                action: {
                    store.selectCard(id: card.id)
                    onToggleCardFocus()
                }
            )

            headerIconButton(
                systemName: "xmark",
                label: "Close card",
                action: onClose
            )
        }
    }

    private func headerIconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .foregroundStyle(theme.ink(0.84))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.surface(0.08))
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(label)
        .highPriorityGesture(
            TapGesture().onEnded {
                action()
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .agent:
            AgentTerminalView(cardID: card.id, accent: palette.accent, isSelected: isSelected)
        case .browser:
            BrowserCardContentView(cardID: card.id, content: card.content, store: store, isSelected: isSelected)
        case .note:
            NoteCardContentView(cardID: card.id, content: card.content, store: store, isSelected: isSelected)
        case .todo:
            TodoCardContentView(cardID: card.id, content: card.content, store: store, isSelected: isSelected)
        }
    }

    private func beginTitleEdit() {
        editingTitle = card.title
        isEditingTitle = true
        editingCardTitleID = card.id
        isTitleFieldFocused = true
    }

    private func commitTitle() {
        let trimmed = editingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelTitleEdit()
            return
        }

        store.updateCardTitle(id: card.id, to: trimmed)
        isEditingTitle = false
        editingCardTitleID = nil
        isTitleFieldFocused = false
    }

    private func cancelTitleEdit() {
        editingTitle = card.title
        isEditingTitle = false
        editingCardTitleID = nil
        isTitleFieldFocused = false
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    colors: [
                        palette.accent.opacity(isSelected ? 0.22 : 0.16),
                        theme.surface(0.045),
                        .black.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: isSelected
                        ? [
                            palette.accent.opacity(0.72),
                            palette.accent.opacity(0.42),
                            theme.ink(0.18)
                        ]
                        : [
                            theme.ink(0.22),
                            palette.accent.opacity(0.18),
                            theme.ink(0.06)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isSelected ? 2 : 1
            )
    }

    private var cardShadowColor: Color {
        isSelected ? palette.accent.opacity(0.35) : palette.shadow
    }

    private var cardShadowRadius: CGFloat {
        isSelected ? 30 : 24
    }

    private var palette: CardPalette {
        CardPalette(kind: card.kind)
    }
}

#Preview("Workspace Cards") {
    struct PreviewContainer: View {
        @State private var isEditingTitle = false
        @State private var editingCardTitleID: UUID?

        var body: some View {
            let cards = PreviewSupport.cards
            HStack(spacing: 20) {
                if let unselected = cards.first {
                    WorkspaceCardView(
                        card: unselected,
                        store: PreviewSupport.makeStore(),
                        isSelected: false,
                        isEditingTitle: $isEditingTitle,
                        editingCardTitleID: $editingCardTitleID
                    )
                    .frame(width: CGFloat(unselected.size.width), height: CGFloat(unselected.size.height))
                }
                if let selected = cards.dropFirst().first {
                    WorkspaceCardView(
                        card: selected,
                        store: PreviewSupport.makeStore(),
                        isSelected: true,
                        isEditingTitle: $isEditingTitle,
                        editingCardTitleID: $editingCardTitleID
                    )
                    .frame(width: CGFloat(selected.size.width), height: CGFloat(selected.size.height))
                }
            }
            .padding(28)
            .background(Color(red: 0.04, green: 0.05, blue: 0.07))
            .environmentObject(AgentSessionManager())
        }
    }

    return PreviewContainer()
}
