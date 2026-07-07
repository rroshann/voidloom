import AppKit
import SwiftTerm
import SwiftUI

/// Thin AppKit bridge hosting a SwiftTerm `LocalProcessTerminalView` that
/// `AgentSessionManager` owns. The session manager keeps the NSView alive
/// across SwiftUI re-renders so terminal state survives card churn; this
/// wrapper only mounts it.
struct TerminalHostView: NSViewRepresentable {
    let terminal: LocalProcessTerminalView

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

/// True when `responder` is a text-input target (an editable text view or a
/// terminal), so window-level key handlers (Delete, Escape, arrows) stay inert
/// while the user is typing.
func isTypingResponder(_ responder: NSResponder?) -> Bool {
    responder is NSText || responder is SwiftTerm.TerminalView
}
