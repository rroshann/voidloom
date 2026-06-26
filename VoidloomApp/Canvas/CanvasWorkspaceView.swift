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

#Preview("Canvas Workspace") {
    CanvasWorkspaceView(store: PreviewSupport.makeStore())
        .frame(width: 900, height: 580)
        .background(.black)
}
