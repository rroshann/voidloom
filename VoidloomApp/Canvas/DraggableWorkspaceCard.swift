import AppKit
import SwiftUI
import VoidloomCore

struct DraggableWorkspaceCard: View {
    let card: WorkspaceCard
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    let viewportScale: Double
    var isCardFocused: Bool = false
    var onToggleCardFocus: () -> Void
    @Binding var editingCardTitleID: UUID?

    @State private var lastDragTranslation: CGSize = .zero
    @State private var isEditingTitle = false
    @State private var isResizing = false
    /// The marquee group captured on the first move of a drag, so the choice of
    /// group-move vs single-move is decided once and held for the whole drag
    /// (mirrors the idle-drag "decide once" pattern). Nil between drags.
    @State private var draggingGroup: Set<UUID>?

    private var isSelected: Bool {
        store.state.selectedCardID == card.id
            || store.state.marqueeSelectedCardIDs.contains(card.id)
    }

    private var dragEnabled: Bool {
        !isEditingTitle && !isResizing
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorkspaceCardView(
                card: card,
                store: store,
                isSelected: isSelected,
                isCardFocused: isCardFocused,
                onToggleCardFocus: onToggleCardFocus,
                onClose: closeCard,
                isEditingTitle: $isEditingTitle,
                editingCardTitleID: $editingCardTitleID
            )
            .frame(width: CGFloat(card.size.width), height: CGFloat(card.size.height))

            CardResizeHandles(
                cardSize: card.size,
                cardPosition: card.position,
                viewportScale: viewportScale,
                accentColor: CardPalette(kind: card.kind).accent,
                onResizeStart: {
                    store.selectCard(id: card.id)
                    isResizing = true
                },
                onResize: { size, position in
                    store.resizeCard(id: card.id, to: size, position: position)
                },
                onResizeEnd: {
                    isResizing = false
                }
            )
            .frame(width: CGFloat(card.size.width), height: CGFloat(card.size.height))
        }
        .offset(x: CGFloat(card.position.x), y: CGFloat(card.position.y))
        .onTapGesture {
            // ⌘-click toggles this card in/out of the multi-selection. Evaluated
            // before the marquee no-op below so ⌘-clicking an existing group
            // member is honored instead of being swallowed by it.
            if NSEvent.modifierFlags.contains(.command) {
                store.toggleCardInSelection(id: card.id)
                return
            }
            // A tap on a marquee member is a no-op so the group stays selected for
            // a subsequent group drag. macOS can fire this co-located tap eagerly
            // on press; calling selectCard here would collapse the marquee set to
            // one card before cardDragGesture.onChanged reads it. A tap on a lone
            // or non-member card still selects normally.
            let marquee = store.state.marqueeSelectedCardIDs
            if marquee.count > 1 && marquee.contains(card.id) { return }
            store.selectCard(id: card.id)
        }
        .gesture(cardDragGesture, isEnabled: dragEnabled)
    }

    private var cardDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                // Decide once, on the first move, whether this drag moves the
                // whole marquee group or just this card. A group only counts when
                // it has >1 member and includes this card.
                let group: Set<UUID>
                if let captured = draggingGroup {
                    group = captured
                } else {
                    let marquee = store.state.marqueeSelectedCardIDs
                    group = (marquee.count > 1 && marquee.contains(card.id)) ? marquee : []
                    draggingGroup = group
                }

                let delta = CGSize(
                    width: value.translation.width - lastDragTranslation.width,
                    height: value.translation.height - lastDragTranslation.height
                )
                let translation = CanvasVector(dx: delta.width, dy: delta.height)

                if group.count > 1 {
                    // Group drag: move every member together. Do NOT call
                    // selectCard — that would collapse the marquee set to one.
                    store.moveCards(ids: group, screenTranslation: translation)
                } else {
                    store.selectCard(id: card.id)
                    store.moveCard(id: card.id, screenTranslation: translation)
                }
                lastDragTranslation = value.translation
            }
            .onEnded { _ in
                lastDragTranslation = .zero
                draggingGroup = nil
            }
    }

    private func closeCard() {
        if card.kind == .agent {
            sessionManager.terminateSession(cardID: card.id)
        }
        store.deleteCard(id: card.id)
    }
}
