import SwiftUI
import VoidloomCore

struct DraggableWorkspaceCard: View {
    let card: WorkspaceCard
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    let viewportScale: Double
    var isCardFocused: Bool = false
    var onToggleCardFocus: () -> Void

    @State private var lastDragTranslation: CGSize = .zero
    @State private var isEditingTitle = false
    @State private var isResizing = false

    private var isSelected: Bool {
        store.state.selectedCardID == card.id
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
                isEditingTitle: $isEditingTitle
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
            store.selectCard(id: card.id)
        }
        .gesture(cardDragGesture, isEnabled: dragEnabled)
    }

    private var cardDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                store.selectCard(id: card.id)

                let delta = CGSize(
                    width: value.translation.width - lastDragTranslation.width,
                    height: value.translation.height - lastDragTranslation.height
                )

                store.moveCard(
                    id: card.id,
                    screenTranslation: CanvasVector(dx: delta.width, dy: delta.height)
                )
                lastDragTranslation = value.translation
            }
            .onEnded { _ in
                lastDragTranslation = .zero
            }
    }

    private func closeCard() {
        if card.kind == .agent {
            sessionManager.terminateSession(cardID: card.id)
        }
        store.deleteCard(id: card.id)
    }
}
