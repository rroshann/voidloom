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
        private var onMouseDown: (CGPoint) -> Void = { _ in }
        private var onMouseDragged: (CGPoint) -> Void = { _ in }
        private var onMouseMoved: (CGPoint) -> Void = { _ in }
        private var onMouseUp: (CGPoint) -> Void = { _ in }

        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool { true }

        func apply(_ representable: CanvasInteractionOverlay) {
            let previousMode = mode
            mode = representable.mode
            onMouseDown = representable.onMouseDown
            onMouseDragged = representable.onMouseDragged
            onMouseMoved = representable.onMouseMoved
            onMouseUp = representable.onMouseUp
            if previousMode != mode {
                window?.invalidateCursorRects(for: self)
            }
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
            onMouseDragged(localPoint(event))
        }

        override func mouseUp(with event: NSEvent) {
            guard mode.capturesCanvas else { return }
            onMouseUp(localPoint(event))
        }

        override func mouseMoved(with event: NSEvent) {
            guard mode.capturesCanvas else { return }
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

        private func cursor(for mode: CanvasInteractionModel.Mode) -> NSCursor {
            switch mode {
            case .erasing:
                // The round eraser footprint is drawn as a SwiftUI overlay that
                // tracks the pointer, so the system cursor is hidden (a fully
                // transparent cursor) over the canvas while erasing.
                return Self.transparentCursor
            case .idle:
                return .arrow
            default:
                return .crosshair
            }
        }

        /// A fully transparent cursor used to hide the system pointer over the
        /// canvas while the SwiftUI eraser footprint indicator is shown.
        private static let transparentCursor: NSCursor = {
            let image = NSImage(size: NSSize(width: 1, height: 1))
            return NSCursor(image: image, hotSpot: NSPoint(x: 0, y: 0))
        }()
    }
}
