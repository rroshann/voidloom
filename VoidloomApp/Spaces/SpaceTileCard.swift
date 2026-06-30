import SwiftUI
import VoidloomCore

/// One Spaces grid tile: the existing card chrome at a grid-assigned frame,
/// with no resize handles and no free dragging (the grid owns position in v0).
struct SpaceTileCard: View {
    let card: WorkspaceCard
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    let onDragChanged: (CGSize) -> Void
    let onDropped: (CGPoint) -> Void

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
                    onDropped(value.location)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        translation = .zero
                    }
                }
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
