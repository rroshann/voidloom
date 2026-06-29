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
                // Flip the cursor instantly on arming/disarming rather than
                // waiting for the next mouse-move, so the pen/eraser cursor
                // appears the moment a tool is selected — and the arrow returns
                // the moment a tool is disarmed.
                if mode.capturesCanvas {
                    CanvasToolCursor.cursor(for: mode).set()
                } else if previousMode.capturesCanvas {
                    NSCursor.arrow.set()
                }
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
                options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            guard mode.capturesCanvas else { return }
            addCursorRect(bounds, cursor: CanvasToolCursor.cursor(for: mode))
        }

        /// Re-asserts the per-mode cursor on every cursor-update event. This is
        /// hit-test independent, so the pen/eraser cursor survives pointer moves
        /// even though `hitTest` only claims left-mouse-down events. The decisive
        /// per-move re-assert lives in the SwiftUI `canvasToolCursor` modifier,
        /// which wins the race against `NSHostingView`'s arrow reset; this path
        /// is kept as a fast in-AppKit fallback.
        override func cursorUpdate(with event: NSEvent) {
            if mode.capturesCanvas {
                CanvasToolCursor.cursor(for: mode).set()
            } else {
                super.cursorUpdate(with: event)
            }
        }
    }
}
