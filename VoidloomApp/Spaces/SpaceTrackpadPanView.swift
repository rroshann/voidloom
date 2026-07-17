import AppKit
import SwiftUI
import VoidloomCore

/// A single window-scoped `.scrollWheel` monitor that turns two-finger trackpad
/// scrolls into Board pans. Mounted ONLY in Board mode (exactly one instance);
/// it installs on appear and removes on `dismantleNSView`, so grid mode never
/// pans and the monitor is never double-installed. A faithful port of the
/// Canvas shell's trackpad-pan bridge, kept in Spaces so the dead Canvas copy
/// can be deleted with the rest of that shell.
struct SpaceTrackpadPanView: NSViewRepresentable {
    /// `cursorInView` is the pointer in this view's top-left space (nil if it
    /// can't be resolved); the closure returns whether it consumed the scroll
    /// (pan) or let it fall through (so a card's own scroll view scrolls).
    let onPan: (CanvasVector, CGPoint?) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onPan: onPan)
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.onScreenFrameChange = { screenFrame in
            context.coordinator.screenFrame = screenFrame
        }
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        context.coordinator.onPan = onPan
        context.coordinator.hostView = nsView
        nsView.onScreenFrameChange = { screenFrame in
            context.coordinator.screenFrame = screenFrame
        }
        nsView.updateScreenFrame()
    }

    static func dismantleNSView(_ nsView: HostView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onPan: (CanvasVector, CGPoint?) -> Bool
        var screenFrame: CGRect?
        weak var hostView: HostView?

        private var monitor: Any?

        init(onPan: @escaping (CanvasVector, CGPoint?) -> Bool) {
            self.onPan = onPan
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return self.handle(event) ? nil : event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> Bool {
            // Only pan when no mouse button is held — a trackpad click+drag can
            // emit spurious scrollWheel events; consuming them would break the
            // SwiftUI drag used for marquee/pan.
            guard NSEvent.pressedMouseButtons == 0 else { return false }
            // Only pan when the scroll targets this view's own window.
            guard let hostWindow = hostView?.window, event.window === hostWindow else { return false }
            guard let screenFrame, screenFrame.contains(NSEvent.mouseLocation) else { return false }

            let translation = CanvasVector(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
            guard translation != .zero else { return false }

            // Map the global cursor into the view's top-left space (screenFrame is
            // Cocoa bottom-left origin, so flip Y).
            let mouse = NSEvent.mouseLocation
            let cursorInView = CGPoint(x: mouse.x - screenFrame.minX, y: screenFrame.maxY - mouse.y)
            return onPan(translation, cursorInView)
        }

        deinit { uninstall() }
    }

    final class HostView: NSView {
        var onScreenFrameChange: (CGRect?) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateScreenFrame()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            updateScreenFrame()
        }

        func updateScreenFrame() {
            guard let window else {
                onScreenFrameChange(nil)
                return
            }
            let windowFrame = convert(bounds, to: nil)
            onScreenFrameChange(window.convertToScreen(windowFrame))
        }
    }
}
