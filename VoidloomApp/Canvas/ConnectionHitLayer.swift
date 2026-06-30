import SwiftUI
import VoidloomCore

/// A thick, invisible hit region tracing a connection edge, used so a thin
/// rendered line is comfortably clickable. Expressed in SCREEN coordinates
/// (the layer is hosted in screen space alongside the rendered edges).
struct EdgeHitShape: Shape {
    let start: CGPoint
    let end: CGPoint
    var hitWidth: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var line = Path()
        line.move(to: start)
        line.addLine(to: end)
        return line.strokedPath(StrokeStyle(lineWidth: hitWidth, lineCap: .round))
    }
}

/// Transparent hit-testing layer for connection edges. Hosted in SCREEN space,
/// AFTER `ConnectionsLayer` and BEFORE the cards, so cards win hit priority.
/// Endpoints are projected through `viewport.screenPoint` and the hit width
/// scales with zoom so the clickable band tracks the rendered line thickness.
/// Tapping an edge selects it (revealing its screen-space delete control); the
/// visible highlight is drawn by `ConnectionsLayer`. Uses `onTapGesture` (not a
/// drag) and a modest hit width so a left-drag marquee starting over an edge
/// falls through to the canvas. Inert unless the canvas is idle.
struct ConnectionHitLayer: View {
    @ObservedObject var interaction: CanvasInteractionModel
    let connections: [CardConnection]
    let cards: [WorkspaceCard]
    let viewport: CanvasViewport
    let onSelect: (UUID) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(connections) { connection in
                if let endpoints = endpoints(for: connection) {
                    Color.clear
                        .contentShape(
                            EdgeHitShape(
                                start: endpoints.start,
                                end: endpoints.end,
                                hitWidth: 16 * CGFloat(viewport.scale)
                            )
                        )
                        .onTapGesture { onSelect(connection.id) }
                }
            }
        }
        .allowsHitTesting(interaction.mode == .idle)
    }

    private func endpoints(for connection: CardConnection) -> (start: CGPoint, end: CGPoint)? {
        guard let fromCard = cards.first(where: { $0.id == connection.from }),
              let toCard = cards.first(where: { $0.id == connection.to }) else { return nil }

        let resolved = connectionEndpoints(
            from: CanvasRect(origin: fromCard.position, size: fromCard.size),
            to: CanvasRect(origin: toCard.position, size: toCard.size)
        )
        return (screenPoint(resolved.start), screenPoint(resolved.end))
    }

    private func screenPoint(_ point: CanvasPoint) -> CGPoint {
        let screen = viewport.screenPoint(forCanvasPoint: point)
        return CGPoint(x: screen.x, y: screen.y)
    }
}

/// A small circular delete control for the selected connection edge, rendered
/// in SCREEN space at the edge midpoint so it stays a constant size regardless
/// of zoom (mirrors the card close-button styling).
struct ConnectionDeleteButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(Color.red.opacity(0.92))
                )
                .overlay(
                    Circle().stroke(.white.opacity(0.55), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help("Delete connection")
    }
}
