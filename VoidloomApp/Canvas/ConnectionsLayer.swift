import SwiftUI
import VoidloomCore

/// Render-only layer drawing persisted card connections. It lives INSIDE the
/// scaled/offset canvas ZStack (beneath the cards) so edges are expressed in
/// canvas coordinates and pan/zoom with everything else. Each edge anchors on
/// the two cards' borders and renders as a NON-DIRECTIONAL chain: a plain line
/// capped by a symmetric dot at BOTH endpoints, with no arrowhead. The selected
/// edge is drawn brighter and thicker.
struct ConnectionsLayer: View, Equatable {
    let connections: [CardConnection]
    let cards: [WorkspaceCard]
    let canvasSize: CGSize
    var selectedConnectionID: UUID? = nil

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
                let isSelected = connection.id == selectedConnectionID
                let lineWidth: CGFloat = isSelected ? 4 : 2.5
                let lineColor = accent.opacity(isSelected ? 1 : 0.85)
                let dotColor = accent.opacity(isSelected ? 1 : 0.95)
                let dotRadius: CGFloat = isSelected ? 4 : 3

                var line = Path()
                line.move(to: start)
                line.addLine(to: end)
                context.stroke(
                    line,
                    with: .color(lineColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

                // Symmetric dots at BOTH endpoints — the edge is undirected, so
                // neither end is privileged with an arrowhead.
                for anchor in [start, end] {
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: anchor.x - dotRadius,
                            y: anchor.y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )),
                        with: .color(dotColor)
                    )
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
    }
}
