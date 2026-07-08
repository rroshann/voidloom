import AppKit
import SwiftUI
import VoidloomCore

/// Lets free-arrange cards be moved by dragging ANYWHERE on them — including over
/// terminal/browser content that swallows SwiftUI drag gestures. It watches the
/// window's mouse events (which the content can't intercept first): a click still
/// passes through to select/interact, but a drag past a small threshold moves the
/// card the press began on and is consumed, so the content (e.g. terminal text
/// selection) doesn't also react. Mounted only in free-arrange, as a `.background`.
struct FreeArrangeDragCatcher: NSViewRepresentable {
    /// Card frames in this view's local (top-left) space — same space the shell's
    /// `ContentClickMonitor` reports clicks in.
    let frames: [UUID: SpaceFreeFrame]
    /// Space order; later entries render on top, so the last match wins a hit-test.
    let orderedIDs: [UUID]
    let viewportSize: CGSize
    /// Reports a new top-left origin for the dragged card (already clamped).
    let onMove: (UUID, ScreenPoint) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.apply(frames: frames, orderedIDs: orderedIDs, viewport: viewportSize, onMove: onMove)
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.apply(frames: frames, orderedIDs: orderedIDs, viewport: viewportSize, onMove: onMove)
    }

    final class MonitorView: NSView {
        private var frames: [UUID: SpaceFreeFrame] = [:]
        private var orderedIDs: [UUID] = []
        private var viewport: CGSize = .zero
        private var onMove: ((UUID, ScreenPoint) -> Void)?
        private var monitor: Any?

        // Drag state, captured on mouse-down and applied on subsequent drags.
        private var pressedCard: UUID?
        private var startOrigin: ScreenPoint?
        private var startPoint: CGPoint?
        private var isMoving = false

        /// A card must move at least this far before a press becomes a drag, so a
        /// plain click still passes through to the card content.
        private static let dragThreshold: CGFloat = 5
        /// Bottom-right corner reserved for the SwiftUI resize handle.
        private static let resizeCorner: CGFloat = 30
        /// Minimum visible strip kept on screen, matching `SpaceFreeArrangeLayer`.
        private static let minVisibleEdge: Double = 60

        override var isFlipped: Bool { true }   // top-left origin, matches SpaceFreeFrame

        func apply(frames: [UUID: SpaceFreeFrame], orderedIDs: [UUID], viewport: CGSize,
                   onMove: @escaping (UUID, ScreenPoint) -> Void) {
            self.frames = frames
            self.orderedIDs = orderedIDs
            self.viewport = viewport
            self.onMove = onMove
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? removeMonitor() : installMonitor()
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }

        deinit { removeMonitor() }

        private func localPoint(_ event: NSEvent) -> CGPoint? {
            guard let window = self.window, event.window === window else { return nil }
            return convert(event.locationInWindow, from: nil)
        }

        /// Topmost card under the point, excluding its resize corner so the corner
        /// still starts a resize (owned by the SwiftUI handle) rather than a move.
        private func card(at point: CGPoint) -> UUID? {
            for id in orderedIDs.reversed() {
                guard let frame = frames[id] else { continue }
                let rect = CGRect(x: frame.origin.x, y: frame.origin.y,
                                  width: frame.size.x, height: frame.size.y)
                guard rect.contains(point) else { continue }
                let inResizeCorner = point.x > rect.maxX - Self.resizeCorner
                    && point.y > rect.maxY - Self.resizeCorner
                return inResizeCorner ? nil : id
            }
            return nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let point = localPoint(event) else { return event }
            switch event.type {
            case .leftMouseDown:
                if let id = card(at: point), let frame = frames[id] {
                    pressedCard = id
                    startOrigin = frame.origin
                    startPoint = point
                    isMoving = false
                }
                return event   // never swallow the click — select/interact still work
            case .leftMouseDragged:
                guard let id = pressedCard, let start = startPoint, let origin = startOrigin,
                      let size = frames[id]?.size else { return event }
                let dx = point.x - start.x
                let dy = point.y - start.y
                if !isMoving, abs(dx) + abs(dy) < Self.dragThreshold { return event }
                isMoving = true
                let proposed = ScreenPoint(x: origin.x + Double(dx), y: origin.y + Double(dy))
                onMove?(id, clamp(proposed, size: size))
                return nil     // consume so the content doesn't also drag-select
            case .leftMouseUp:
                let wasMoving = isMoving
                pressedCard = nil; startOrigin = nil; startPoint = nil; isMoving = false
                return wasMoving ? nil : event   // swallow the up that ended a move
            default:
                return event
            }
        }

        private func clamp(_ origin: ScreenPoint, size: ScreenPoint) -> ScreenPoint {
            let e = Self.minVisibleEdge
            let x = min(max(origin.x, e - size.x), Double(viewport.width) - e)
            let y = min(max(origin.y, 0), Double(viewport.height) - e)
            return ScreenPoint(x: x, y: y)
        }
    }
}
