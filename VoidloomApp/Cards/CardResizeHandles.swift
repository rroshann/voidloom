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

/// Self-balancing diagonal-resize cursor for the corner hot zone. Uses an
/// `NSTrackingArea` with `.cursorUpdate` (not `NSCursor.push/pop`) so AppKit
/// owns enter/exit and the cursor can never get stuck — even across the
/// per-frame re-renders of a live resize. `hitTest` returns nil so it never
/// consumes the SwiftUI resize gesture underneath it.
private struct ResizeCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView { CursorView() }
    func updateNSView(_ nsView: CursorView, context: Context) {}

    final class CursorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [.cursorUpdate, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                )
            )
        }

        override func cursorUpdate(with event: NSEvent) {
            DiagonalResizeCursor.nwse().set()
        }
    }
}

struct CardResizeHandles: View {
    let cardSize: CardSize
    let cardPosition: CanvasPoint
    let viewportScale: Double
    let accentColor: Color
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
                    .overlay(ResizeCursorView().allowsHitTesting(false))
                    .contentShape(
                        ResizeHitRegion(cornerRadius: cornerRadius, edgeLength: edgeLength, hitWidth: hitWidth)
                    )
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
                // No manual cursor revert: AppKit re-evaluates the tracking area
                // on mouse-up and restores the arrow automatically.
                isDragging = false
                onResizeEnd()
            }
    }

    private func resizedFrame(
        startSize: CardSize,
        startPosition: CanvasPoint,
        totalCanvasDelta: CanvasVector
    ) -> (size: CardSize, position: CanvasPoint) {
        let width = startSize.width + totalCanvasDelta.dx
        let height = startSize.height + totalCanvasDelta.dy
        let clampedSize = CardSize(width: width, height: height).clampedToMinimums()
        return (clampedSize, startPosition)
    }
}
