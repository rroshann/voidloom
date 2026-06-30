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

                // displayBbox = union of cards bbox (if any) and viewport region,
                // so the "you are here" rect is always within the scaled bbox and
                // never flies off the panel when panning into empty space.
                let displayBbox = store.state.contentBoundingBox().map { $0.union(vpRect) } ?? vpRect

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
                    ctx.fill(cardPath, with: .color(.white.opacity(0.22)))
                    ctx.stroke(cardPath, with: .color(.white.opacity(0.32)), lineWidth: 0.5)
                }

                // --- Viewport "you are here" rect ---
                // Because displayBbox already includes vpRect, vx/vy/vw/vh are
                // guaranteed to land inside the panel bounds.
                let vx = (vpTL.x - displayBbox.origin.x) * fitScale + offsetX
                let vy = (vpTL.y - displayBbox.origin.y) * fitScale + offsetY
                let vw = (vpBR.x - vpTL.x) * fitScale
                let vh = (vpBR.y - vpTL.y) * fitScale
                if vw > 0, vh > 0 {
                    let vpPath = Path(
                        roundedRect: CGRect(x: vx, y: vy, width: vw, height: vh),
                        cornerRadius: 2
                    )
                    ctx.fill(vpPath, with: .color(Color.teal.opacity(0.10)))
                    ctx.stroke(
                        vpPath,
                        with: .color(Color.teal.opacity(0.85)),
                        style: StrokeStyle(lineWidth: 1.5)
                    )
                }
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 8)
        .allowsHitTesting(false)
    }
}
