import SwiftUI
import VoidloomCore

/// Render-only layer drawing persisted card connections. It is hosted in SCREEN
/// space (a sibling of the transformed card group, not inside it), drawing into
/// a `Canvas` that fills the whole viewport so an edge between far-apart cards is
/// never clipped by a fixed canvas frame. Each endpoint is computed in canvas
/// coordinates (border-anchored on the two cards) and projected to the screen via
/// `viewport.screenPoint`, so edges line up exactly with the cards. Line widths
/// and anchor dots scale with `viewport.scale` to match the on-screen card size.
/// Edges render as a NON-DIRECTIONAL chain: a plain line capped by a symmetric
/// dot at BOTH endpoints, with no arrowhead. The selected edge is drawn brighter
/// and thicker.
struct ConnectionsLayer: View, Equatable {
    let connections: [CardConnection]
    let cards: [WorkspaceCard]
    let viewport: CanvasViewport
    var selectedConnectionID: UUID? = nil

    var body: some View {
        Canvas { context, _ in
            let scale = CGFloat(viewport.scale)
            for connection in connections {
                guard let fromCard = cards.first(where: { $0.id == connection.from }),
                      let toCard = cards.first(where: { $0.id == connection.to }) else { continue }

                let endpoints = connectionEndpoints(
                    from: CanvasRect(origin: fromCard.position, size: fromCard.size),
                    to: CanvasRect(origin: toCard.position, size: toCard.size)
                )
                let start = screenPoint(endpoints.start)
                let end = screenPoint(endpoints.end)
                let accent = CardPalette(kind: fromCard.kind).accent
                let isSelected = connection.id == selectedConnectionID
                let lineWidth: CGFloat = (isSelected ? 4 : 2.5) * scale
                let lineColor = accent.opacity(isSelected ? 1 : 0.85)
                let dotColor = accent.opacity(isSelected ? 1 : 0.95)
                let dotRadius: CGFloat = (isSelected ? 4 : 3) * scale

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
        .allowsHitTesting(false)
    }

    private func screenPoint(_ point: CanvasPoint) -> CGPoint {
        let screen = viewport.screenPoint(forCanvasPoint: point)
        return CGPoint(x: screen.x, y: screen.y)
    }
}
