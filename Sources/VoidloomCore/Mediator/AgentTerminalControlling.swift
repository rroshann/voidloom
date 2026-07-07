import Foundation

/// Core-side seam for agent terminal sessions, keyed by card UUID.
/// The App layer's SwiftTerm PTY AgentSessionManager conforms.
@MainActor
public protocol AgentTerminalControlling: AnyObject {
    /// `workingDirectory` is the workspace's project folder when set; sessions
    /// fall back to the user's home directory when nil.
    func spawn(cardID: UUID, kind: MediatorAgentKind, workingDirectory: String?)
    func send(text: String, to cardID: UUID)
    func recentOutput(of cardID: UUID, maxLines: Int) -> [String]
    func terminate(cardID: UUID)
}
