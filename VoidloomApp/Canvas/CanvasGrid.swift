import SwiftUI
import VoidloomCore

/// Infinite, screen-space background grid. It draws directly into the visible
/// `size` using the live `viewport`, so it fills the whole viewport at every pan
/// position and zoom level — there is no fixed canvas frame to clip it. Lines/
/// dots are positioned in canvas units (`minorSpacing`/`majorSpacing`) but
/// projected to screen via `viewport.screenPoint`, so the grid aligns exactly
/// with the cards and connections drawn on the same viewport.
struct CanvasGrid: View {
    @Environment(\.theme) private var theme

    let viewport: CanvasViewport
    let size: CGSize

    private let minorSpacing: CGFloat = 40
    private let majorSpacing: CGFloat = 160

    var body: some View {
        if theme.canvasBackground == .solid {
            EmptyView()
        } else {
            Canvas { context, canvasSize in
                draw(in: &context, size: canvasSize)
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        switch theme.canvasBackground {
        case .solid:
            break

        case .grid:
            strokeLines(spacing: minorSpacing, color: theme.gridMinor, width: 1,
                        axes: .both, in: &context, size: size)
            strokeLines(spacing: majorSpacing, color: theme.gridMajor, width: 1,
                        axes: .both, in: &context, size: size)

        case .lines:
            strokeLines(spacing: minorSpacing, color: theme.gridMinor, width: 1,
                        axes: .horizontal, in: &context, size: size)

        case .blueprint:
            strokeLines(spacing: minorSpacing, color: theme.accent.opacity(0.12), width: 0.5,
                        axes: .both, in: &context, size: size)
            strokeLines(spacing: majorSpacing, color: theme.accent.opacity(0.45), width: 1,
                        axes: .both, in: &context, size: size)

        case .dots:
            drawDots(in: &context, size: size)
        }
    }

    private enum Axes { case both, horizontal }

    private func strokeLines(
        spacing: CGFloat,
        color: Color,
        width: CGFloat,
        axes: Axes,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let scale = CGFloat(viewport.scale)
        let ox = CGFloat(viewport.origin.x)
        let oy = CGFloat(viewport.origin.y)
        var path = Path()

        if axes == .both, let xs = visibleIndices(spacing: spacing, origin: ox, scale: scale, extent: size.width) {
            for i in xs {
                let x = (CGFloat(i) * spacing * scale) + ox
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }

        if let ys = visibleIndices(spacing: spacing, origin: oy, scale: scale, extent: size.height) {
            for j in ys {
                let y = (CGFloat(j) * spacing * scale) + oy
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }

        context.stroke(path, with: .color(color), lineWidth: width)
    }

    private func drawDots(in context: inout GraphicsContext, size: CGSize) {
        let scale = CGFloat(viewport.scale)
        let ox = CGFloat(viewport.origin.x)
        let oy = CGFloat(viewport.origin.y)
        guard let xs = visibleIndices(spacing: minorSpacing, origin: ox, scale: scale, extent: size.width),
              let ys = visibleIndices(spacing: minorSpacing, origin: oy, scale: scale, extent: size.height) else { return }

        let dotRadius: CGFloat = 1.0
        let ratio = Int((majorSpacing / minorSpacing).rounded())

        for i in xs {
            let x = (CGFloat(i) * minorSpacing * scale) + ox
            let columnMajor = i % ratio == 0
            for j in ys {
                let y = (CGFloat(j) * minorSpacing * scale) + oy
                let isMajor = columnMajor && (j % ratio == 0)
                let rect = CGRect(
                    x: x - dotRadius, y: y - dotRadius,
                    width: dotRadius * 2, height: dotRadius * 2
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(isMajor ? theme.gridMajor : theme.gridMinor)
                )
            }
        }
    }

    /// The inclusive range of canvas line indices (multiples of `spacing`) whose
    /// projected screen positions can fall within `[0, extent]`, padded by one on
    /// each side so partial lines at the edges still render.
    private func visibleIndices(
        spacing: CGFloat,
        origin: CGFloat,
        scale: CGFloat,
        extent: CGFloat
    ) -> ClosedRange<Int>? {
        guard scale > 0, spacing > 0, extent > 0 else { return nil }
        let canvasMin = (0 - origin) / scale
        let canvasMax = (extent - origin) / scale
        let iMin = Int((canvasMin / spacing).rounded(.down))
        let iMax = Int((canvasMax / spacing).rounded(.up))
        guard iMin <= iMax else { return nil }
        return iMin...iMax
    }
}
