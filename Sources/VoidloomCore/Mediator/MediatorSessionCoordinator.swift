import Combine
import Foundation

/// Performs `MediatorEffect`s around the pure `MediatorSessionMachine`:
/// runs the brain, dispatches the executor synchronously, and keeps AT MOST
/// ONE timeout task — every `scheduleTimeout` REPLACES the previous timer
/// (the machine's effects assume this; independent timers would misfire
/// across states). Capture effects are no-ops until the voice plan lands.
@MainActor
public final class MediatorSessionCoordinator: ObservableObject {
    @Published public private(set) var state: MediatorState = .idle
    @Published public private(set) var narration: String = ""

    private var machine = MediatorSessionMachine()
    private let brain: MediatorBrain
    private let executor: CommandExecutor
    private let timeoutScale: Double
    private var timeoutTask: Task<Void, Never>?
    private var parseTask: Task<Void, Never>?

    public init(brain: MediatorBrain, executor: CommandExecutor, timeoutScale: Double = 1) {
        self.brain = brain
        self.executor = executor
        self.timeoutScale = timeoutScale
    }

    /// Typed input: drives the machine through capture instantly. While a
    /// confirmation is pending, "confirm"/"yes"/"cancel"/"no" resolve it.
    public func submitTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if case .awaitingConfirmation = machine.state {
            let word = trimmed.lowercased()
            if ["confirm", "yes", "cancel", "no"].contains(word) {
                send(.confirmReceived(word == "confirm" || word == "yes"))
                return
            }
        }
        send(.pushToTalkPressed)
        send(.transcriptFinal(trimmed))
    }

    public func confirm(_ accepted: Bool) { send(.confirmReceived(accepted)) }
    public func cancel() { send(.cancelRequested) }

    private func send(_ event: MediatorEvent) {
        let effects = machine.handle(event)
        state = machine.state
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: MediatorEffect) {
        switch effect {
        case .startCapture, .stopCapture:
            break // audio capture arrives with the voice plan

        case .parse(let transcript):
            parseTask?.cancel()
            parseTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let command = try await self.brain.command(for: transcript)
                    guard !Task.isCancelled else { return }
                    self.send(.commandProduced(command))
                } catch {
                    guard !Task.isCancelled else { return }
                    self.send(.parseFailed(String(describing: error)))
                }
            }

        case .execute(let command, let confirmed):
            send(.executionFinished(executor.execute(command, confirmed: confirmed)))

        case .scheduleTimeout(let seconds):
            timeoutTask?.cancel()
            let delay = UInt64(seconds * timeoutScale * 1_000_000_000)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                self?.send(.timeout)
            }

        case .narrate(let text):
            timeoutTask?.cancel()
            narration = text
        }
    }
}
