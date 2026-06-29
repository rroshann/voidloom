import SwiftUI
import VoidloomCore

/// Transient thin lines shown while dragging when edges/centers align with other cards.
/// Coordinates are canvas-space; converted to screen via the viewport. Never persisted.
struct AlignmentGuidesLayer: View {
    let guides: [AlignmentGuide]
    let viewport: CanvasViewport
    let canvasSize: CGSize

    var body: some View {
        Canvas { context, _ in
            for guide in guides {
                var path = Path()
                switch guide.axis {
                case .vertical:
                    let x = viewport.screenPoint(forCanvasPoint: .init(x: guide.canvasCoordinate, y: 0)).x
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                case .horizontal:
                    let y = viewport.screenPoint(forCanvasPoint: .init(x: 0, y: guide.canvasCoordinate)).y
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                }
                context.stroke(path, with: .color(Color(red: 0.34, green: 0.93, blue: 0.82).opacity(0.9)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .allowsHitTesting(false)
    }
}
