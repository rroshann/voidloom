import SwiftUI
import VoidloomCore

/// Render-only layer drawing persisted brush strokes plus the in-progress live
/// stroke. It lives INSIDE the scaled/offset canvas ZStack (right after the
/// grid and beneath the cards), so strokes are expressed in canvas coordinates,
/// pan/zoom with everything else, and — by render order alone — always sit
/// BENEATH the cards. Never hit-tested.
struct CanvasDrawingLayer: View {
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

        var path = Path()
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in stroke.points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }

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
}
