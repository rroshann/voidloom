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
            if let bbox = store.state.contentBoundingBox() {
                Canvas { ctx, size in
                    // Fit the entire bounding box inside the panel with 8% margin.
                    // Clamp each dimension to at least 1 so a single card (which
                    // may have zero-width bbox) never produces a NaN fitScale.
                    let bboxW = max(bbox.size.width,  1.0)
                    let bboxH = max(bbox.size.height, 1.0)
                    let fitScale = min(Double(size.width) / bboxW,
                                      Double(size.height) / bboxH) * 0.92

                    // Center the drawn content in the panel.
                    let drawW   = bboxW * fitScale
                    let drawH   = bboxH * fitScale
                    let offsetX = (Double(size.width)  - drawW) / 2
                    let offsetY = (Double(size.height) - drawH) / 2

                    // --- Cards: faint rounded rects ---
                    for card in store.state.cards {
                        let cx = (card.position.x - bbox.origin.x) * fitScale + offsetX
                        let cy = (card.position.y - bbox.origin.y) * fitScale + offsetY
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
                    // The visible region in canvas coords spans from the canvas
                    // point at screen (0, 0) to the point at (viewportW, viewportH).
                    // This is robust to any origin/scale convention: it uses the
                    // same canvasPoint(forScreenPoint:) transform the canvas itself uses.
                    let vp = store.state.viewport
                    let tl = vp.canvasPoint(forScreenPoint: ScreenPoint(x: 0, y: 0))
                    let br = vp.canvasPoint(
                        forScreenPoint: ScreenPoint(
                            x: Double(viewportSize.width),
                            y: Double(viewportSize.height)
                        )
                    )
                    let vx = (tl.x - bbox.origin.x) * fitScale + offsetX
                    let vy = (tl.y - bbox.origin.y) * fitScale + offsetY
                    let vw = (br.x - tl.x) * fitScale
                    let vh = (br.y - tl.y) * fitScale
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
            } else {
                Text("No cards yet")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
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
