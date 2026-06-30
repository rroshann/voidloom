import SwiftUI
import VoidloomCore

/// Render-only layer drawing persisted brush strokes plus the in-progress live
/// stroke. It is hosted in SCREEN space (a sibling of the transformed card group,
/// not inside it), drawing into a `Canvas` that fills the whole viewport so a
/// stroke is never clipped by a fixed canvas frame. Each stroke point is stored
/// in canvas coordinates and projected to the screen via `viewport.screenPoint`,
/// and the thickness scales with `viewport.scale`, so strokes pan/zoom in lockstep
/// with the cards. By render order alone they always sit BENEATH the cards.
/// Never hit-tested.
struct CanvasDrawingLayer: View, Equatable {
    let strokes: [DrawingStroke]
    let liveStroke: DrawingStroke?
    let viewport: CanvasViewport

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                Self.draw(stroke, viewport: viewport, in: &context)
            }
            if let liveStroke {
                Self.draw(liveStroke, viewport: viewport, in: &context)
            }
        }
        .allowsHitTesting(false)
    }

    private static func draw(_ stroke: DrawingStroke, viewport: CanvasViewport, in context: inout GraphicsContext) {
        guard !stroke.points.isEmpty else { return }

        let scale = CGFloat(viewport.scale)
        let color = Color(
            .sRGB,
            red: stroke.color.red,
            green: stroke.color.green,
            blue: stroke.color.blue,
            opacity: stroke.color.opacity
        )

        let screenPoints = stroke.points.map { point -> CGPoint in
            let screen = viewport.screenPoint(forCanvasPoint: point)
            return CGPoint(x: screen.x, y: screen.y)
        }

        // A single point has no line geometry — render it as a round dot so the
        // brush shows feedback the instant the press lands.
        guard screenPoints.count > 1 else {
            let radius = (CGFloat(stroke.thickness) * scale) / 2
            let first = screenPoints[0]
            let dot = Path(
                ellipseIn: CGRect(
                    x: first.x - radius,
                    y: first.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            context.fill(dot, with: .color(color))
            return
        }

        let path = smoothPath(through: screenPoints)

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: max(0.5, CGFloat(stroke.thickness) * scale),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    /// Builds a smooth curve through the (screen-space) sampled points using a
    /// Catmull-Rom spline (converted to cubic Béziers). Fast drags sample the
    /// pointer sparsely; joining those samples with straight lines makes the
    /// stroke look polygonal, so the curve follows the intended path instead.
    /// Assumes at least two points (callers guard the single-point case as a dot).
    private static func smoothPath(through pts: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: pts[0])

        guard pts.count > 2 else {
            path.addLine(to: pts[1])
            return path
        }

        for index in 0..<(pts.count - 1) {
            let p0 = pts[max(index - 1, 0)]
            let p1 = pts[index]
            let p2 = pts[index + 1]
            let p3 = pts[min(index + 2, pts.count - 1)]
            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }
}
