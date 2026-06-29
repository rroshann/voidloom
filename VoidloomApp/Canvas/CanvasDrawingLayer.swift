import SwiftUI
import VoidloomCore

/// Render-only layer drawing persisted brush strokes plus the in-progress live
/// stroke. It lives INSIDE the scaled/offset canvas ZStack (right after the
/// grid and beneath the cards), so strokes are expressed in canvas coordinates,
/// pan/zoom with everything else, and — by render order alone — always sit
/// BENEATH the cards. Never hit-tested.
struct CanvasDrawingLayer: View, Equatable {
    let strokes: [DrawingStroke]
    let liveStroke: DrawingStroke?
    let canvasSize: CGSize

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                Self.draw(stroke, in: &context)
            }
            if let liveStroke {
                Self.draw(liveStroke, in: &context)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
    }

    private static func draw(_ stroke: DrawingStroke, in context: inout GraphicsContext) {
        guard let first = stroke.points.first else { return }

        let color = Color(
            .sRGB,
            red: stroke.color.red,
            green: stroke.color.green,
            blue: stroke.color.blue,
            opacity: stroke.color.opacity
        )

        // A single point has no line geometry — render it as a round dot so the
        // brush shows feedback the instant the press lands.
        guard stroke.points.count > 1 else {
            let radius = stroke.thickness / 2
            let dot = Path(
                ellipseIn: CGRect(
                    x: first.x - radius,
                    y: first.y - radius,
                    width: stroke.thickness,
                    height: stroke.thickness
                )
            )
            context.fill(dot, with: .color(color))
            return
        }

        let path = smoothPath(through: stroke.points)

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: max(0.5, stroke.thickness),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    /// Builds a smooth curve through the sampled points using a Catmull-Rom
    /// spline (converted to cubic Béziers). Fast drags sample the pointer
    /// sparsely; joining those samples with straight lines makes the stroke look
    /// polygonal, so the curve follows the intended path instead. Assumes at
    /// least two points (callers guard the single-point case as a dot).
    private static func smoothPath(through points: [CanvasPoint]) -> Path {
        let pts = points.map { CGPoint(x: $0.x, y: $0.y) }
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
