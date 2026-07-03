import SwiftUI
import VoidloomCore

/// The content of an agent card: a real PTY-backed terminal (SwiftTerm) owned
/// by `AgentSessionManager`. When the shell exits, a restart affordance
/// replaces the dead session.
struct AgentTerminalView: View {
    let cardID: UUID
    let accent: Color
    let isSelected: Bool
    let workingDirectory: String?

    @Environment(\.theme) private var theme
    @EnvironmentObject private var agentSessionManager: AgentSessionManager

    var body: some View {
        ZStack {
            if let session = agentSessionManager.session(for: cardID) {
                TerminalHostView(terminal: session.terminal)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)

                if !session.isRunning {
                    sessionEndedOverlay
                }
            } else {
                Text("Starting shell…")
                    .font(.system(size: 12 * theme.fontScale, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.ink(0.5))
            }
        }
        .onAppear {
            agentSessionManager.startSession(cardID: cardID, workingDirectory: workingDirectory)
        }
    }

    private var sessionEndedOverlay: some View {
        VStack(spacing: 10) {
            Text("Session ended")
                .font(.system(size: 13 * theme.fontScale, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.ink(0.75))
            Button {
                agentSessionManager.restartSession(cardID: cardID, workingDirectory: workingDirectory)
            } label: {
                Label("New Shell", systemImage: "arrow.clockwise")
                    .font(.system(size: 12 * theme.fontScale, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.55))
    }
}
