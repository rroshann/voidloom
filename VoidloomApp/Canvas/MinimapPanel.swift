import SwiftUI
import VoidloomCore

/// A fixed ~200×150 overview panel showing all cards in canvas space and a
/// "you are here" viewport rect. Hosted bottom-right in RootView when the
/// minimap dock toggle is on. Non-interactive (`.allowsHitTesting(false)`)
/// for v1 — click-to-recenter is a deferred follow-on.
struct MinimapPanel: View {
    @ObservedObject var store: WorkspaceStore
    /// The on-screen viewport size (geometry.size from RootView).
    let viewportSize: CGSize

    @Environment(\.theme) private var theme

    private let panelWidth: CGFloat  = 200
    private let panelHeight: CGFloat = 150

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                // Build the current viewport region in canvas space.
                let vp = store.state.viewport
                let vpTL = vp.canvasPoint(forScreenPoint: ScreenPoint(x: 0, y: 0))
                let vpBR = vp.canvasPoint(
                    forScreenPoint: ScreenPoint(
                        x: Double(viewportSize.width),
                        y: Double(viewportSize.height)
                    )
                )
                let vpRect = CanvasRect(
                    origin: vpTL,
                    size: CardSize(width: vpBR.x - vpTL.x, height: vpBR.y - vpTL.y)
                )

                // Scale basis: the cards' bounding box unioned with the current
                // viewport CENTER (a point, not the full rect). Using the center
                // keeps the map scale STABLE while zooming — zoom changes the
                // viewport's size, not its center — so the map no longer zooms with
                // the canvas. Panning still shifts the basis, so the map follows you
                // into empty space. Falls back to the viewport rect when no cards.
                let vpCenter = vp.canvasPoint(
                    forScreenPoint: ScreenPoint(
                        x: Double(viewportSize.width) / 2,
                        y: Double(viewportSize.height) / 2
                    )
                )
                let displayBbox: CanvasRect = {
                    guard let cards = store.state.contentBoundingBox() else { return vpRect }
                    let minX = Swift.min(cards.origin.x, vpCenter.x)
                    let minY = Swift.min(cards.origin.y, vpCenter.y)
                    let maxX = Swift.max(cards.origin.x + cards.size.width, vpCenter.x)
                    let maxY = Swift.max(cards.origin.y + cards.size.height, vpCenter.y)
                    return CanvasRect(
                        origin: CanvasPoint(x: minX, y: minY),
                        size: CardSize(width: maxX - minX, height: maxY - minY)
                    )
                }()

                // Fit the entire display bbox inside the panel with ~10% margin.
                // Clamp each dimension to at least 1 to guard against NaN fitScale.
                let bboxW = max(displayBbox.size.width,  1.0)
                let bboxH = max(displayBbox.size.height, 1.0)
                let fitScale = min(Double(size.width) / bboxW,
                                   Double(size.height) / bboxH) * 0.90

                // Center the drawn content in the panel.
                let drawW   = bboxW * fitScale
                let drawH   = bboxH * fitScale
                let offsetX = (Double(size.width)  - drawW) / 2
                let offsetY = (Double(size.height) - drawH) / 2

                // --- Cards: faint rounded rects ---
                for card in store.state.cards {
                    let cx = (card.position.x - displayBbox.origin.x) * fitScale + offsetX
                    let cy = (card.position.y - displayBbox.origin.y) * fitScale + offsetY
                    let cw = max(card.size.width  * fitScale, 1.0)
                    let ch = max(card.size.height * fitScale, 1.0)
                    let cardPath = Path(
                        roundedRect: CGRect(x: cx, y: cy, width: cw, height: ch),
                        cornerRadius: 3
                    )
                    ctx.fill(cardPath, with: .color(theme.ink(0.22)))
                    ctx.stroke(cardPath, with: .color(theme.ink(0.32)), lineWidth: 0.5)
                }

                // --- Viewport "you are here" rect ---
                // Drawn at its true (zoom-dependent) size so it grows/shrinks LIVE
                // with zoom, then clamped to the panel so it stays visible (and never
                // overflows) when zoomed far out past the cards' scale basis.
                let vx = (vpTL.x - displayBbox.origin.x) * fitScale + offsetX
                let vy = (vpTL.y - displayBbox.origin.y) * fitScale + offsetY
                let vw = (vpBR.x - vpTL.x) * fitScale
                let vh = (vpBR.y - vpTL.y) * fitScale
                let left   = Swift.max(0, vx)
                let top    = Swift.max(0, vy)
                let right  = Swift.min(Double(size.width),  vx + vw)
                let bottom = Swift.min(Double(size.height), vy + vh)
                if right > left, bottom > top {
                    let vpPath = Path(
                        roundedRect: CGRect(x: left, y: top, width: right - left, height: bottom - top),
                        cornerRadius: 2
                    )
                    ctx.fill(vpPath, with: .color(theme.accent.opacity(0.10)))
                    ctx.stroke(
                        vpPath,
                        with: .color(theme.accent.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 1.5)
                    )
                }
            }
            if store.state.cards.isEmpty {
                Text("No cards yet")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.ink(0.35))
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.ink(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
        .allowsHitTesting(false)
    }
}
