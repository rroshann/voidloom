import SwiftUI
import AppKit
import VoidloomCore

/// One Spaces grid tile: the existing card chrome at a grid-assigned frame. The
/// grid (`SpacesShellView`) owns position and drag state — this view renders the
/// card, forwards its drag to the shell (which live-previews the reorder and
/// positions the tile under the cursor), and handles tap selection.
struct SpaceTileCard: View {
    let card: WorkspaceCard
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    /// Reports an in-progress drag: cumulative `translation` plus the cursor's
    /// global `location`, so the shell can offset the tile and hit-test the slot.
    let onDragChanged: (CGSize, CGPoint) -> Void
    /// Reports the drag ending at the cursor's global `location`.
    let onDragEnded: (CGPoint) -> Void

    @State private var isEditingTitle = false
    @State private var editingCardTitleID: UUID?

    var body: some View {
        WorkspaceCardView(
            card: card,
            store: store,
            isSelected: store.state.selectedCardID == card.id
                || store.state.marqueeSelectedCardIDs.contains(card.id),
            isCardFocused: false,
            onToggleCardFocus: {},
            onClose: closeCard,
            isEditingTitle: $isEditingTitle,
            editingCardTitleID: $editingCardTitleID
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in onDragChanged(value.translation, value.location) }
                .onEnded { value in onDragEnded(value.location) },
            // While the title field is being edited, disable the tile's own drag
            // so typing/selection isn't stolen and a stray move can't reorder.
            including: isEditingTitle ? .subviews : .all
        )
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                store.toggleCardInSelection(id: card.id)
            } else {
                store.selectCard(id: card.id)
            }
        }
    }

    private func closeCard() {
        if card.kind == .agent {
            sessionManager.terminateSession(cardID: card.id)
        }
        store.deleteCard(id: card.id)
    }
}
