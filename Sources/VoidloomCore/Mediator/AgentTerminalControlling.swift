import Foundation

/// Core-side seam for agent terminal sessions, keyed by card UUID.
/// The App layer's AgentSessionManager conforms (echo stub today; the
/// SwiftTerm PTY manager conforms identically when it lands).
@MainActor
public protocol AgentTerminalControlling: AnyObject {
    func spawn(cardID: UUID, kind: MediatorAgentKind)
    func send(text: String, to cardID: UUID)
    func recentOutput(of cardID: UUID, maxLines: Int) -> [String]
    func terminate(cardID: UUID)
}
