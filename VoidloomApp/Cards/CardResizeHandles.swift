import AppKit
import SwiftUI
import VoidloomCore

private enum DiagonalResizeCursor {
    /// The system NW–SE diagonal resize cursor (private API, with a graceful
    /// fallback). Resolved fresh each call; cheap and avoids caching surprises.
    @MainActor
    static func nwse() -> NSCursor {
        let selector = NSSelectorFromString("_windowResizeNorthWestSouthEastCursor")
        guard NSCursor.responds(to: selector),
              let cursor = (NSCursor.self as AnyObject).perform(selector)?.takeUnretainedValue() as? NSCursor else {
            return NSCursor.crosshair
        }
        return cursor
    }
}

private struct BottomRightResizeGuide: Shape {
    let cornerRadius: CGFloat
    let edgeLength: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.maxX - radius - edgeLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius - edgeLength))

        return path
    }
}

private struct ResizeHitRegion: Shape {
    let cornerRadius: CGFloat
    let edgeLength: CGFloat
    let hitWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.addRect(
            CGRect(
                x: rect.maxX - radius - edgeLength - hitWidth,
                y: rect.maxY - hitWidth,
                width: edgeLength + radius + hitWidth,
                height: hitWidth
            )
        )
        path.addRect(
            CGRect(
                x: rect.maxX - hitWidth,
                y: rect.maxY - radius - edgeLength - hitWidth,
                width: hitWidth,
                height: edgeLength + radius + hitWidth
            )
        )
        path.addRect(
            CGRect(
                x: rect.maxX - radius - hitWidth,
                y: rect.maxY - radius - hitWidth,
                width: radius + hitWidth,
                height: radius + hitWidth
            )
        )

        return path
    }
}

struct CardResizeHandles: View {
    let cardSize: CardSize
    let cardPosition: CanvasPoint
    let viewportScale: Double
    let accentColor: Color
    /// Minimum size the drag is allowed to shrink to. Defaults to the card
    /// minimums; text elements pass their smaller 60x28 minimums.
    var minWidth: Double = CardSize.minimumWidth
    var minHeight: Double = CardSize.minimumHeight
    let onResizeStart: () -> Void
    let onResize: (CardSize, CanvasPoint) -> Void
    let onResizeEnd: () -> Void

    @State private var isDragging = false
    @State private var startSize = CardSize(width: 0, height: 0)
    @State private var startPosition = CanvasPoint.zero

    private let cornerRadius: CGFloat = 24
    private let edgeLength: CGFloat = 36
    private let strokeWidth: CGFloat = 3.5
    private let hitWidth: CGFloat = 14

    /// Side of the square hot zone pinned to the card's bottom-right corner.
    /// Confining hover + gesture to this box (instead of the full card frame)
    /// keeps the resize cursor at the corner and stops it occluding the header.
    private var hotZoneSide: CGFloat {
        cornerRadius + edgeLength + hitWidth
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                BottomRightResizeGuide(cornerRadius: cornerRadius, edgeLength: edgeLength)
                    .stroke(
                        accentColor.opacity(0.92),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                    )
                    .allowsHitTesting(false)

                Color.clear
                    .frame(width: hotZoneSide, height: hotZoneSide)
                    .contentShape(
                        ResizeHitRegion(cornerRadius: cornerRadius, edgeLength: edgeLength, hitWidth: hitWidth)
                    )
                    // Re-apply the cursor on every move (a one-shot set gets
                    // overridden by AppKit's per-move reset). Gate on the actual
                    // L-shaped hit path so the diagonal cursor shows ONLY where a
                    // resize drag would start — not over the inner corner box.
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            if isInResizeRegion(location) {
                                DiagonalResizeCursor.nwse().set()
                            } else if !isDragging {
                                NSCursor.arrow.set()
                            }
                        case .ended:
                            if !isDragging { NSCursor.arrow.set() }
                        }
                    }
                    .highPriorityGesture(resizeGesture)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                // Keep the diagonal cursor pinned for the whole drag even when
                // the pointer leaves the corner box. `.set()` is idempotent and
                // AppKit suppresses cursor-rect resets while a button is down.
                DiagonalResizeCursor.nwse().set()

                if !isDragging {
                    isDragging = true
                    startSize = cardSize
                    startPosition = cardPosition
                    onResizeStart()
                }

                let canvasDelta = CanvasVector(
                    dx: value.translation.width / viewportScale,
                    dy: value.translation.height / viewportScale
                )
                let result = resizedFrame(
                    startSize: startSize,
                    startPosition: startPosition,
                    totalCanvasDelta: canvasDelta
                )
                onResize(result.size, result.position)
            }
            .onEnded { _ in
                isDragging = false
                NSCursor.arrow.set()
                onResizeEnd()
            }
    }

    /// Whether a point in the corner box falls on the L-shaped resize hit path —
    /// the same shape that scopes the resize gesture, so cursor and drag agree.
    private func isInResizeRegion(_ point: CGPoint) -> Bool {
        let rect = CGRect(x: 0, y: 0, width: hotZoneSide, height: hotZoneSide)
        return ResizeHitRegion(cornerRadius: cornerRadius, edgeLength: edgeLength, hitWidth: hitWidth)
            .path(in: rect)
            .contains(point)
    }

    private func resizedFrame(
        startSize: CardSize,
        startPosition: CanvasPoint,
        totalCanvasDelta: CanvasVector
    ) -> (size: CardSize, position: CanvasPoint) {
        let width = startSize.width + totalCanvasDelta.dx
        let height = startSize.height + totalCanvasDelta.dy
        let clampedSize = CardSize(width: width, height: height)
            .clamped(minWidth: minWidth, minHeight: minHeight)
        return (clampedSize, startPosition)
    }
}
