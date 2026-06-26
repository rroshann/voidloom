import SwiftUI
import VoidloomCore

struct DraggableWorkspaceCard: View {
    let card: WorkspaceCard
    @ObservedObject var store: WorkspaceStore

    @State private var lastDragTranslation: CGSize = .zero

    var body: some View {
        WorkspaceCardView(card: card)
            .frame(width: CGFloat(card.size.width), height: CGFloat(card.size.height))
            .offset(x: CGFloat(card.position.x), y: CGFloat(card.position.y))
            .highPriorityGesture(cardDragGesture)
    }

    private var cardDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
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
}
