import AppKit
import SwiftUI
import VoidloomCore

struct WorkspaceCardView: View {
    /// Approximate height of the card header (20pt icon/button row + 7pt
    /// vertical padding ×2), used by the Spaces click monitor to split header
    /// clicks (→ select) from content clicks (→ activate). Keep in sync with
    /// `header`'s layout.
    static let approximateHeaderHeight: CGFloat = 34

    let card: WorkspaceCard
    @ObservedObject var store: WorkspaceStore
    var isSelected: Bool = false
    /// Content focus (typing lands in this card) — renders a neutral focus
    /// ring, distinct from the accent `isSelected` border that arms Delete.
    var isActive: Bool = false
    var isCardFocused: Bool = false
    var onToggleCardFocus: () -> Void = {}
    var onClose: () -> Void = {}
    /// Header drag handle. When set, the header (and only the header) becomes the
    /// card's move handle — forwarding the drag's cumulative global `translation`
    /// and cursor `location` up, without owning any move math. Nil leaves the
    /// header inert (e.g. the dead Canvas shell, which drags the whole card).
    var onHeaderDragChanged: ((CGSize, CGPoint) -> Void)? = nil
    var onHeaderDragEnded: ((CGPoint) -> Void)? = nil
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
        }
        .background(cardBackground)
        // The shadow is cast by a plain shape BEHIND the card, never by the
        // composited card content: live-repainting content (terminal PTY, web
        // view) would otherwise force this 24–30px blur to be recomputed on
        // every frame, which made terminal cards visibly laggy.
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardShadowColor)
                .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: 18)
        )
        .overlay(cardBorder)
        .animation(selectionAnimation, value: isSelected)
        .animation(selectionAnimation, value: isActive)
        .animation(.easeOut(duration: 0.15), value: isHeaderHovered)
        .animation(.easeOut(duration: 0.15), value: isEditingTitle)
        .onChange(of: isSelected) { _, selected in
            if !selected {
                cancelTitleEdit()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.18))

                Image(systemName: palette.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.accent)
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                titleView

                if !isEditingTitle {
                    Text(palette.eyebrow)
                        .font(.system(size: 8.5, weight: .bold, design: theme.monospacedMetadata ? .monospaced : .default))
                        .textCase(.uppercase)
                        .tracking(0.9)
                        .foregroundStyle(palette.accent.opacity(0.7))
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }

            Spacer(minLength: 0)

            if isSelected || isActive, isHeaderHovered, !isEditingTitle {
                headerActions
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        // The header is the card's drag handle (reorder in grid, free move in
        // free-arrange). Show a grab cursor so that's discoverable — re-set on
        // every move since AppKit resets cursor rects per event.
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHeaderHovered = true
                if !isEditingTitle { NSCursor.openHand.set() }
            case .ended:
                isHeaderHovered = false
                NSCursor.arrow.set()
            }
        }
        // The header is the card's drag handle. Global coordinate space so the
        // translation tracks the cursor at every zoom level; minimumDistance 1 so
        // a click still selects. Masked to `.subviews` (off on the header itself,
        // but title-field editing and header buttons stay live) while a title is
        // being edited or no handler is wired.
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in onHeaderDragChanged?(value.translation, value.location) }
                .onEnded { value in onHeaderDragEnded?(value.location) },
            including: (onHeaderDragChanged != nil && !isEditingTitle) ? .all : .subviews
        )
    }

    @ViewBuilder
    private var titleView: some View {
        if isEditingTitle {
            TextField("Title", text: $editingTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13 * theme.fontScale, weight: .heavy, design: .rounded))
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
                .font(.system(size: 13 * theme.fontScale, weight: .heavy, design: .rounded))
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
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .foregroundStyle(theme.ink(0.84))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.surface(0.08))
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(label)
        .accessibilityLabel(label)
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
            AgentTerminalView(
                cardID: card.id,
                accent: palette.accent,
                isSelected: isSelected,
                workingDirectory: store.state.space?.folderPath
            )
        case .browser:
            BrowserCardContentView(cardID: card.id, content: card.content, store: store, isSelected: isSelected)
        case .note:
            NoteCardContentView(cardID: card.id, content: card.content, store: store, isSelected: isSelected)
        case .todo:
            TodoCardContentView(cardID: card.id, content: card.content, store: store, isSelected: isSelected)
        case .fileBrowser:
            FileBrowserCardContentView(store: store, accent: palette.accent)
        case .git:
            GitCardContentView(store: store, accent: palette.accent)
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
                    colors: borderColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isSelected || isActive ? 2 : 1
            )
    }

    /// Selected = accent (armed for keyboard commands). Active = neutral bright
    /// focus ring (typing lands here). Idle = faint outline.
    private var borderColors: [Color] {
        if isSelected {
            return [
                palette.accent.opacity(0.72),
                palette.accent.opacity(0.42),
                theme.ink(0.18)
            ]
        }
        if isActive {
            return [
                theme.ink(0.9),
                theme.ink(0.55),
                theme.ink(0.3)
            ]
        }
        return [
            theme.ink(0.22),
            palette.accent.opacity(0.18),
            theme.ink(0.06)
        ]
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
