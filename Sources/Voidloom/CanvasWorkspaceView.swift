import SwiftUI
import VoidloomCore

struct CanvasWorkspaceView: View {
    @ObservedObject var store: WorkspaceStore

    @State private var lastPanTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1

    private let canvasSize = CGSize(width: 5_000, height: 3_400)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .simultaneousGesture(zoomGesture(in: geometry))

                ZStack(alignment: .topLeading) {
                    CanvasGrid()

                    ForEach(store.state.cards) { card in
                        DraggableWorkspaceCard(card: card, store: store)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
                .scaleEffect(CGFloat(store.state.viewport.scale), anchor: .topLeading)
                .offset(
                    x: CGFloat(store.state.viewport.origin.x),
                    y: CGFloat(store.state.viewport.origin.y)
                )
            }
            .clipped()
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastPanTranslation.width,
                    height: value.translation.height - lastPanTranslation.height
                )

                store.pan(by: CanvasVector(dx: delta.width, dy: delta.height))
                lastPanTranslation = value.translation
            }
            .onEnded { _ in
                lastPanTranslation = .zero
            }
    }

    private func zoomGesture(in geometry: GeometryProxy) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard value > 0 else { return }

                let delta = value / lastMagnification
                let anchor = ScreenPoint(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )

                store.zoom(by: delta, anchoredAt: anchor)
                lastMagnification = value
            }
            .onEnded { _ in
                lastMagnification = 1
            }
    }
}

private struct DraggableWorkspaceCard: View {
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

private struct CanvasGrid: View {
    private let minorSpacing: CGFloat = 40
    private let majorSpacing: CGFloat = 160

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                gridPath(in: geometry.size, spacing: minorSpacing)
                    .stroke(.white.opacity(0.035), lineWidth: 1)

                gridPath(in: geometry.size, spacing: majorSpacing)
                    .stroke(.white.opacity(0.085), lineWidth: 1)
            }
        }
    }

    private func gridPath(in size: CGSize, spacing: CGFloat) -> Path {
        var path = Path()

        for x in stride(from: CGFloat(0), through: size.width, by: spacing) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }

        for y in stride(from: CGFloat(0), through: size.height, by: spacing) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }

        return path
    }
}
