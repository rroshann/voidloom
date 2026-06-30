import SwiftUI
import VoidloomCore

/// One Spaces grid tile: the existing card chrome at a grid-assigned frame,
/// with no resize handles and no free dragging (the grid owns position in v0).
struct SpaceTileCard: View {
    let card: WorkspaceCard
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager

    @State private var isEditingTitle = false
    @State private var editingCardTitleID: UUID?

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
