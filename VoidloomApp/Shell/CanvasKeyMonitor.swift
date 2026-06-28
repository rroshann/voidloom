import AppKit
import SwiftUI

/// A window-scoped `.keyDown` monitor that forwards each event to `onKeyDown`,
/// which returns `true` when it consumed the event (so the key is swallowed) or
/// `false` to let it fall through. Mirrors the `.scrollWheel` monitor pattern in
/// `CanvasWorkspaceView`.
///
/// This exists because the canvas Delete shortcut must fire for a single
/// tap-selected card and a marquee group, yet still let a focused text editor
/// keep Backspace — behavior a hidden disabled `.keyboardShortcut` button can't
/// deliver reliably (a disabled button never fires its key equivalent, and a
/// bare Backspace equivalent loses to any first-responder text control).
struct CanvasKeyMonitor: NSViewRepresentable {
    /// Returns whether the event was handled (and should be consumed).
    let onKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
        context.coordinator.hostView = nsView
    }

    static func dismantleNSView(_ nsView: HostView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onKeyDown: (NSEvent) -> Bool
        weak var hostView: HostView?

        private var monitor: Any?

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                // Only act on key events in this view's own window, so other
                // windows (e.g. Settings) keep their normal key handling.
                guard let hostWindow = self.hostView?.window, event.window === hostWindow else {
                    return event
                }
                return self.onKeyDown(event) ? nil : event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }

            monitor = nil
        }

        deinit {
            uninstall()
        }
    }

    final class HostView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }
}
