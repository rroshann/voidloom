import SwiftUI
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
            isActive: store.state.activeCardID == card.id,
            isCardFocused: false,
            onToggleCardFocus: {},
            onClose: closeCard,
            // The header is the only drag handle: the body stays inert so a drag
            // over terminal/browser content moves the card instead of being
            // swallowed (grid reorder + free move both ride this one gesture).
            onHeaderDragChanged: { translation, location in onDragChanged(translation, location) },
            onHeaderDragEnded: { location in onDragEnded(location) },
            isEditingTitle: $isEditingTitle,
            editingCardTitleID: $editingCardTitleID
        )
        // No tap gesture here: selection-on-click (including ⌘-toggle) is owned
        // by SpacesShellView's ContentClickMonitor, which also sees clicks on
        // AppKit-backed content a SwiftUI gesture never would. A second handler
        // here would double-toggle ⌘-clicks.
    }

    private func closeCard() {
        if card.kind == .agent {
            sessionManager.terminateSession(cardID: card.id)
        }
        store.deleteCard(id: card.id)
    }
}
