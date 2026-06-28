import AppKit
import SwiftUI
import VoidloomCore

/// Transparent AppKit input-capture overlay for armed canvas tools. Like
/// `CanvasRightClickCatcher`, `hitTest` claims the view ONLY when a tool is
/// armed (`capturesCanvas`) and the current event is a left mouse-down, so
/// pinch-zoom, scroll-pan, right-click, and (when idle) all card hover/drag
/// flow straight through untouched.
///
/// Emits press-drag-release callbacks in local, top-left (flipped) view
/// coordinates and owns the per-mode cursor via an always-active tracking area.
struct CanvasInteractionOverlay: NSViewRepresentable {
    var mode: CanvasInteractionModel.Mode
    /// Eraser disc diameter in SCREEN points (canvas thickness × viewport scale)
    /// used to size the hollow-circle erase cursor.
    var eraserScreenDiameter: CGFloat

    var onMouseDown: (CGPoint) -> Void
    var onMouseDragged: (CGPoint) -> Void
    var onMouseMoved: (CGPoint) -> Void
    var onMouseUp: (CGPoint) -> Void

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.apply(self)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.apply(self)
    }

    final class InteractionView: NSView {
        private var mode: CanvasInteractionModel.Mode = .idle
        private var eraserScreenDiameter: CGFloat = 28
        private var onMouseDown: (CGPoint) -> Void = { _ in }
        private var onMouseDragged: (CGPoint) -> Void = { _ in }
        private var onMouseMoved: (CGPoint) -> Void = { _ in }
        private var onMouseUp: (CGPoint) -> Void = { _ in }

        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool { true }

        func apply(_ representable: CanvasInteractionOverlay) {
            mode = representable.mode
            eraserScreenDiameter = representable.eraserScreenDiameter
            onMouseDown = representable.onMouseDown
            onMouseDragged = representable.onMouseDragged
            onMouseMoved = representable.onMouseMoved
            onMouseUp = representable.onMouseUp
            // Refresh cursor immediately so arming/disarming updates it even
            // without a mouse move.
            window?.invalidateCursorRects(for: self)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard mode.capturesCanvas else { return nil }
            // Claim only the initial left mouse-down; subsequent dragged/up
            // events route to us because we became first responder for the drag.
            if NSApp.currentEvent?.type == .leftMouseDown {
                return self
            }
            return nil
        }

        private func localPoint(_ event: NSEvent) -> CGPoint {
            let local = convert(event.locationInWindow, from: nil)
            return CGPoint(x: local.x, y: local.y)
        }

        override func mouseDown(with event: NSEvent) {
            guard mode.capturesCanvas else { return }
            onMouseDown(localPoint(event))
        }

        override func mouseDragged(with event: NSEvent) {
            guard mode.capturesCanvas else { return }
            applyCursor()
            onMouseDragged(localPoint(event))
        }

        override func mouseUp(with event: NSEvent) {
            guard mode.capturesCanvas else { return }
            onMouseUp(localPoint(event))
        }

        override func mouseMoved(with event: NSEvent) {
            guard mode.capturesCanvas else { return }
            applyCursor()
            onMouseMoved(localPoint(event))
        }

        // MARK: - Cursor

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseMoved, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard mode.capturesCanvas else { return }
            addCursorRect(bounds, cursor: cursor(for: mode))
        }

        private func applyCursor() {
            cursor(for: mode).set()
        }

        private func cursor(for mode: CanvasInteractionModel.Mode) -> NSCursor {
            switch mode {
            case .erasing:
                return Self.eraserCursor(diameter: eraserScreenDiameter)
            case .idle:
                return .arrow
            default:
                return .crosshair
            }
        }

        /// A hollow-circle cursor sized to the live eraser diameter so the user
        /// sees exactly what the eraser will touch.
        private static func eraserCursor(diameter: CGFloat) -> NSCursor {
            let clamped = max(10, min(diameter, 160))
            let padding: CGFloat = 2
            let side = clamped + padding * 2
            let size = NSSize(width: side, height: side)
            let image = NSImage(size: size)
            image.lockFocus()
            let rect = NSRect(x: padding, y: padding, width: clamped, height: clamped)
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = 1.5
            NSColor.white.withAlphaComponent(0.9).setStroke()
            path.stroke()
            NSColor.black.withAlphaComponent(0.45).setStroke()
            let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 1.2, dy: 1.2))
            inner.lineWidth = 1
            inner.stroke()
            image.unlockFocus()
            return NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
        }
    }
}
