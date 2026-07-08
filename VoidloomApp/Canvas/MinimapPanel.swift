import SwiftUI
import VoidloomCore

/// A fixed ~200×150 overview panel showing all cards in canvas space and a
/// "you are here" viewport rect. Hosted bottom-right in CanvasShellView when
/// the minimap dock toggle is on. Clicking the map recenters the viewport on
/// the clicked canvas point (pan only — zoom is preserved).
struct MinimapPanel: View {
    @ObservedObject var store: WorkspaceStore
    /// The on-screen viewport size (geometry.size from the shell).
    let viewportSize: CGSize
    /// The pan/zoom the map depicts — the Canvas viewport in the Canvas shell,
    /// the Board (space) viewport in Spaces.
    let viewport: CanvasViewport
    /// Recenters that viewport on a clicked canvas point (pan only, zoom kept).
    let onRecenter: (CanvasPoint) -> Void

    @Environment(\.theme) private var theme

    private let panelWidth: CGFloat  = 200
    private let panelHeight: CGFloat = 150

    /// The world→panel mapping, shared by drawing and click-to-recenter so the
    /// two can never disagree.
    private struct Projection {
        let displayBbox: CanvasRect
        let fitScale: Double
        let offsetX: Double
        let offsetY: Double

        func panelPoint(forCanvasX x: Double, y: Double) -> CGPoint {
            CGPoint(x: (x - displayBbox.origin.x) * fitScale + offsetX,
                    y: (y - displayBbox.origin.y) * fitScale + offsetY)
        }

        func canvasPoint(forPanelPoint p: CGPoint) -> CanvasPoint {
            CanvasPoint(x: (Double(p.x) - offsetX) / fitScale + displayBbox.origin.x,
                        y: (Double(p.y) - offsetY) / fitScale + displayBbox.origin.y)
        }
    }

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let vp = viewport
                let vpTL = vp.canvasPoint(forScreenPoint: ScreenPoint(x: 0, y: 0))
                let vpBR = vp.canvasPoint(
                    forScreenPoint: ScreenPoint(
                        x: Double(viewportSize.width),
                        y: Double(viewportSize.height)
                    )
                )
                let proj = projection(panelSize: size)

                // --- Cards: faint rounded rects ---
                for card in store.state.cards {
                    let tl = proj.panelPoint(forCanvasX: card.position.x, y: card.position.y)
                    let cw = max(card.size.width  * proj.fitScale, 1.0)
                    let ch = max(card.size.height * proj.fitScale, 1.0)
                    let cardPath = Path(
                        roundedRect: CGRect(x: tl.x, y: tl.y, width: cw, height: ch),
                        cornerRadius: 3
                    )
                    ctx.fill(cardPath, with: .color(theme.ink(0.22)))
                    ctx.stroke(cardPath, with: .color(theme.ink(0.32)), lineWidth: 0.5)
                }

                // --- Viewport "you are here" rect ---
                // Drawn at its true (zoom-dependent) size so it grows/shrinks LIVE
                // with zoom, then clamped to the panel so it stays visible (and never
                // overflows) when zoomed far out past the cards' scale basis.
                let vtl = proj.panelPoint(forCanvasX: vpTL.x, y: vpTL.y)
                let vw = (vpBR.x - vpTL.x) * proj.fitScale
                let vh = (vpBR.y - vpTL.y) * proj.fitScale
                let left   = Swift.max(0, Double(vtl.x))
                let top    = Swift.max(0, Double(vtl.y))
                let right  = Swift.min(Double(size.width),  Double(vtl.x) + vw)
                let bottom = Swift.min(Double(size.height), Double(vtl.y) + vh)
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
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { location in
            let proj = projection(panelSize: CGSize(width: panelWidth, height: panelHeight))
            onRecenter(proj.canvasPoint(forPanelPoint: location))
        }
    }

    /// Builds the world region the panel depicts and its fit into the panel.
    ///
    /// Scale basis: the cards' extent unioned with the viewport CENTER point,
    /// then expanded to at least "one screenful" (the window size in canvas
    /// units at 100%). Two properties fall out of this:
    ///  • STABLE ON ZOOM — the extent depends on card positions, the viewport
    ///    center, and the constant minimum; none of those is the viewport's
    ///    zoom-dependent SIZE, so zooming doesn't rescale the map (only the
    ///    "you are here" rect resizes).
    ///  • NO BLOW-UP ON SMALL CONTENT — a single small card sits in a full
    ///    screenful of space instead of filling the whole panel.
    /// Panning moves the viewport center, so the map follows into empty space.
    private func projection(panelSize size: CGSize) -> Projection {
        let vp = viewport
        let vpCenter = vp.canvasPoint(
            forScreenPoint: ScreenPoint(
                x: Double(viewportSize.width) / 2,
                y: Double(viewportSize.height) / 2
            )
        )
        let cards = store.state.contentBoundingBox()
        let cMinX = cards.map { Swift.min($0.origin.x, vpCenter.x) } ?? vpCenter.x
        let cMinY = cards.map { Swift.min($0.origin.y, vpCenter.y) } ?? vpCenter.y
        let cMaxX = cards.map { Swift.max($0.origin.x + $0.size.width, vpCenter.x) } ?? vpCenter.x
        let cMaxY = cards.map { Swift.max($0.origin.y + $0.size.height, vpCenter.y) } ?? vpCenter.y
        let minWorldW = Swift.max(Double(viewportSize.width), 1)
        let minWorldH = Swift.max(Double(viewportSize.height), 1)
        let worldW = Swift.max(cMaxX - cMinX, minWorldW)
        let worldH = Swift.max(cMaxY - cMinY, minWorldH)
        let worldCX = (cMinX + cMaxX) / 2
        let worldCY = (cMinY + cMaxY) / 2
        let displayBbox = CanvasRect(
            origin: CanvasPoint(x: worldCX - worldW / 2, y: worldCY - worldH / 2),
            size: CardSize(width: worldW, height: worldH)
        )

        // Fit the entire display bbox inside the panel with ~10% margin.
        // Clamp each dimension to at least 1 to guard against NaN fitScale.
        let bboxW = max(displayBbox.size.width,  1.0)
        let bboxH = max(displayBbox.size.height, 1.0)
        let fitScale = min(Double(size.width) / bboxW,
                           Double(size.height) / bboxH) * 0.90
        let drawW   = bboxW * fitScale
        let drawH   = bboxH * fitScale
        return Projection(
            displayBbox: displayBbox,
            fitScale: fitScale,
            offsetX: (Double(size.width)  - drawW) / 2,
            offsetY: (Double(size.height) - drawH) / 2
        )
    }
}
