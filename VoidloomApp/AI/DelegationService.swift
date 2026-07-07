import Foundation
import VoidloomCore

/// Sunday's delegation: runs a repo-technical question through the user's agent
/// CLI (Claude/Codex, per the `agent.provider` setting) in the workspace's
/// project folder and returns the answer, attributed. The CLI does the real
/// work — Sunday's own brain stays local; delegation uses the user's account.
@MainActor
final class DelegationService {
    private let store: WorkspaceStore
    private let runner: AgentCommandRunning
    private let timeout: TimeInterval
    /// Relayed answers longer than this many lines are truncated with a pointer.
    private let maxAnswerLines = 30

    init(store: WorkspaceStore,
         runner: AgentCommandRunning = ProcessAgentCommandRunner(),
         timeout: TimeInterval = 120) {
        self.store = store
        self.runner = runner
        self.timeout = timeout
    }

    func delegate(question: String, target: String?,
                  onChunk: @escaping @MainActor (String) -> Void) async -> String {
        let provider = MediatorAgentKind.resolveProvider(UserDefaults.standard.string(forKey: "agent.provider"))
        let attribution = target.map { "\($0) (\(provider.displayName))" } ?? provider.displayName
        onChunk("\(attribution) is looking into it…")

        do {
            guard let printCommand = provider.printCommand(question: question) else {
                return "\(provider.displayName) can't answer questions directly."
            }
            let output = try await runner.run(printCommand, in: store.state.space?.folderPath, timeout: timeout)
            let answer = Self.clean(output, maxLines: maxAnswerLines)
            return answer.isEmpty ? "\(attribution) had nothing to add." : "\(attribution): \(answer)"
        } catch AgentCommandError.commandNotFound {
            return "The \(provider.displayName) CLI isn't installed or on your PATH — install it (or pick another provider in Settings) to delegate."
        } catch AgentCommandError.timedOut {
            return "\(attribution) is still working — the question is taking longer than \(Int(timeout))s. Try a narrower question."
        } catch AgentCommandError.failed(let message) {
            return "\(provider.displayName) couldn't answer: \(message)"
        } catch {
            return "\(provider.displayName) couldn't answer right now."
        }
    }

    /// Strips ANSI escapes and caps to `maxLines`, so a long CLI answer stays
    /// readable in the HUD without dropping the fact that more exists.
    static func clean(_ raw: String, maxLines: Int) -> String {
        let stripped = raw.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return trimmed }
        return lines.prefix(maxLines).joined(separator: "\n") + "\n… (full answer from the CLI)"
    }
}
