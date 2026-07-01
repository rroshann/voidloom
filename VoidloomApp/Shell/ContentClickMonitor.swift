import AppKit
import SwiftUI

/// Reports left mouse-downs in the hosting window without consuming them, in
/// the monitor view's own top-left coordinate space, plus whether ⌘ was held.
/// Shells use it to select the card under a click even when the click lands on
/// AppKit-backed content (terminal PTY, web view) that SwiftUI gestures never
/// see. Mount it as a `.background` of the view whose coordinate space the
/// hit-testing uses.
struct ContentClickMonitor: NSViewRepresentable {
    let onClick: (CGPoint, _ commandHeld: Bool) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onClick = onClick
    }

    final class MonitorView: NSView {
        var onClick: ((CGPoint, Bool) -> Void)?
        private var monitor: Any?

        // Top-left origin so reported points match SwiftUI geometry.
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? removeMonitor() : installMonitor()
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    self.onClick?(point, event.modifierFlags.contains(.command))
                }
                return event   // observe only — never swallow the click
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}
