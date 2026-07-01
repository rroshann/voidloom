import SwiftUI
import VoidloomCore

/// One Spaces grid tile: the existing card chrome at a grid-assigned frame,
/// with no resize handles and no free dragging (the grid owns position in v0).
struct SpaceTileCard: View {
    let card: WorkspaceCard
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    let onDragChanged: (CGSize) -> Void
    /// Returns `true` iff a reorder was committed, so the caller can skip
    /// the snap-back animation and let the grid spring do the work alone.
    let onDropped: (CGPoint) -> Bool

    @State private var isEditingTitle = false
    @State private var editingCardTitleID: UUID?
    @State private var translation: CGSize = .zero

    var body: some View {
        WorkspaceCardView(
            card: card,
            store: store,
            isSelected: store.state.selectedCardID == card.id,
            isCardFocused: false,
            onToggleCardFocus: {},
            onClose: closeCard,
            isEditingTitle: $isEditingTitle,
            editingCardTitleID: $editingCardTitleID
        )
        .contentShape(Rectangle())
        .offset(translation)
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    translation = value.translation
                    onDragChanged(value.translation)
                }
                .onEnded { value in
                    let didReorder = onDropped(value.location)
                    if didReorder {
                        // Grid spring handles the visual move; reset without
                        // animation so the two springs don't compound into a
                        // visible double-move.
                        translation = .zero
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            translation = .zero
                        }
                    }
                },
            // While the title field is being edited, disable the tile's own drag
            // so typing/selection isn't stolen and a stray move can't reorder.
            including: isEditingTitle ? .subviews : .all
        )
        .onTapGesture {
            store.selectCard(id: card.id)
        }
    }

    private func closeCard() {
        if card.kind == .agent {
            sessionManager.terminateSession(cardID: card.id)
        }
        store.deleteCard(id: card.id)
    }
}
