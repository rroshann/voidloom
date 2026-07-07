import AppKit
import SwiftUI

/// In-app hold-to-talk for ⌥Space. Uses a local (not global) key monitor so no
/// Accessibility permission is required — events are only seen while Voidloom is active.
struct VoicePushToTalkKeyMonitor: NSViewRepresentable {
    let onPress: () -> Void
    let onRelease: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPress: onPress, onRelease: onRelease)
    }

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        context.coordinator.onPress = onPress
        context.coordinator.onRelease = onRelease
        context.coordinator.hostView = nsView
    }

    static func dismantleNSView(_ nsView: HostView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onPress: () -> Void
        var onRelease: () -> Void
        weak var hostView: HostView?

        private var monitor: Any?
        private var keyboardPTTActive = false

        init(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
            self.onPress = onPress
            self.onRelease = onRelease
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) {
                [weak self] event in
                guard let self else { return event }
                guard let hostWindow = self.hostView?.window, event.window === hostWindow else {
                    return event
                }
                return self.handle(event) ? nil : event
            }
        }

        func uninstall() {
            if keyboardPTTActive {
                keyboardPTTActive = false
                onRelease()
            }
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            uninstall()
        }

        private func handle(_ event: NSEvent) -> Bool {
            switch event.type {
            case .keyDown:
                guard event.keyCode == 49, event.modifierFlags.contains(.option), !event.isARepeat else {
                    return false
                }
                guard !keyboardPTTActive else { return true }
                keyboardPTTActive = true
                onPress()
                return true

            case .keyUp:
                guard event.keyCode == 49, keyboardPTTActive else { return false }
                keyboardPTTActive = false
                onRelease()
                return true

            case .flagsChanged:
                guard keyboardPTTActive, !event.modifierFlags.contains(.option) else { return false }
                keyboardPTTActive = false
                onRelease()
                return true

            default:
                return false
            }
        }
    }

    final class HostView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
