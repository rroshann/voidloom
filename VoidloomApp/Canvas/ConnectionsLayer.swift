import SwiftUI
import VoidloomCore

/// Render-only layer drawing persisted card connections. It lives INSIDE the
/// scaled/offset canvas ZStack (beneath the cards) so edges are expressed in
/// canvas coordinates and pan/zoom with everything else. Each edge anchors on
/// the two cards' borders and is tinted with the source card's accent.
struct ConnectionsLayer: View {
    let connections: [CardConnection]
    let cards: [WorkspaceCard]
    let canvasSize: CGSize

    var body: some View {
        Canvas { context, _ in
            for connection in connections {
                guard let fromCard = cards.first(where: { $0.id == connection.from }),
                      let toCard = cards.first(where: { $0.id == connection.to }) else { continue }

                let endpoints = connectionEndpoints(
                    from: CanvasRect(origin: fromCard.position, size: fromCard.size),
                    to: CanvasRect(origin: toCard.position, size: toCard.size)
                )
                let start = CGPoint(x: endpoints.start.x, y: endpoints.start.y)
                let end = CGPoint(x: endpoints.end.x, y: endpoints.end.y)
                let accent = CardPalette(kind: fromCard.kind).accent

                var line = Path()
                line.move(to: start)
                line.addLine(to: end)
                context.stroke(
                    line,
                    with: .color(accent.opacity(0.85)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )

                context.fill(
                    Self.arrowHead(at: end, from: start, length: 14, width: 9),
                    with: .color(accent.opacity(0.95))
                )

                // Small dot at the source anchor to read as a directed edge.
                context.fill(
                    Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)),
                    with: .color(accent.opacity(0.95))
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
    }

    static func arrowHead(at tip: CGPoint, from origin: CGPoint, length: CGFloat, width: CGFloat) -> Path {
        let angle = atan2(tip.y - origin.y, tip.x - origin.x)
        let base = CGPoint(x: tip.x - length * cos(angle), y: tip.y - length * sin(angle))
        let left = CGPoint(
            x: base.x + width * cos(angle + .pi / 2),
            y: base.y + width * sin(angle + .pi / 2)
        )
        let right = CGPoint(
            x: base.x - width * cos(angle + .pi / 2),
            y: base.y - width * sin(angle + .pi / 2)
        )

        var path = Path()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }
}
