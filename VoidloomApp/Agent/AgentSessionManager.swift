import Combine
import Foundation
import VoidloomCore

@MainActor
final class AgentSessionManager: ObservableObject {
    struct Session {
        var outputLines: [String]
    }

    @Published private(set) var sessions: [UUID: Session] = [:]

    func startSession(cardID: UUID) {
        guard sessions[cardID] == nil else { return }

        sessions[cardID] = Session(outputLines: [
            "Voidloom agent session (stub)",
            "No PTY attached yet — input is echoed locally."
        ])
    }

    func terminateSession(cardID: UUID) {
        sessions.removeValue(forKey: cardID)
    }

    func terminateAllSessions() {
        sessions.removeAll()
    }

    func session(for cardID: UUID) -> Session? {
        sessions[cardID]
    }

    func submitInput(cardID: UUID, input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if sessions[cardID] == nil {
            startSession(cardID: cardID)
        }

        guard var session = sessions[cardID] else { return }

        session.outputLines.append("$ \(trimmed)")
        session.outputLines.append("session stub: \(trimmed)")
        sessions[cardID] = session
    }
}

extension AgentSessionManager: AgentTerminalControlling {
    func spawn(cardID: UUID, kind: MediatorAgentKind) {
        // Stub sessions have no process; kind becomes meaningful when PTY lands.
        startSession(cardID: cardID)
    }

    func send(text: String, to cardID: UUID) {
        submitInput(cardID: cardID, input: text)
    }

    func recentOutput(of cardID: UUID, maxLines: Int) -> [String] {
        Array((session(for: cardID)?.outputLines ?? []).suffix(maxLines))
    }

    func terminate(cardID: UUID) {
        terminateSession(cardID: cardID)
    }
}
