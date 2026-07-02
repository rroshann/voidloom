import Combine
import Foundation

/// Performs `MediatorEffect`s around the pure `MediatorSessionMachine`:
/// runs the brain, dispatches the executor synchronously, and keeps AT MOST
/// ONE timeout task — every `scheduleTimeout` REPLACES the previous timer.
/// With a slow `LlamaBrain` behind the fast path, three lifecycle rules become
/// load-bearing (prework carry-overs #1–#3): any return to idle cancels BOTH
/// the parse task and the timer; a `parseFailed` payload is narrated verbatim
/// (distinct "model not downloaded" vs generic rephrase); and typed input while
/// busy queues exactly one pending utterance instead of being dropped.
@MainActor
public final class MediatorSessionCoordinator: ObservableObject {
    @Published public private(set) var state: MediatorState = .idle
    @Published public private(set) var narration: String = ""
    /// True whenever the pipeline is mid-command (capturing/parsing/executing);
    /// false at idle and while awaiting a confirmation (the HUD accepts input then).
    @Published public private(set) var isBusy: Bool = false

    private var machine = MediatorSessionMachine()
    private let brain: MediatorBrain
    private let executor: CommandExecutor
    private let timeoutScale: Double
    private var timeoutTask: Task<Void, Never>?
    private var parseTask: Task<Void, Never>?
    private var queuedUtterance: String?

    public init(brain: MediatorBrain, executor: CommandExecutor, timeoutScale: Double = 1) {
        self.brain = brain
        self.executor = executor
        self.timeoutScale = timeoutScale
    }

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
        if isBusy {
            queuedUtterance = trimmed   // depth-1 queue: newest wins, per carry-over #2
            return
        }
        send(.pushToTalkPressed)
        send(.transcriptFinal(trimmed))
    }

    public func confirm(_ accepted: Bool) { send(.confirmReceived(accepted)) }
    public func cancel() { send(.cancelRequested) }

    private func send(_ event: MediatorEvent) {
        let effects = machine.handle(event)
        state = machine.state
        // Any return to idle tears down in-flight async work (carry-over #1):
        // a hung LlamaBrain call and the parse watchdog must not outlive the state.
        if state == .idle {
            parseTask?.cancel(); parseTask = nil
            timeoutTask?.cancel(); timeoutTask = nil
        }
        isBusy = !(state == .idle) && !isAwaitingConfirmation
        for effect in effects { perform(effect) }
        drainQueueIfIdle()
    }

    private var isAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = state { return true }
        return false
    }

    private func drainQueueIfIdle() {
        guard state == .idle, let next = queuedUtterance else { return }
        queuedUtterance = nil
        send(.pushToTalkPressed)
        send(.transcriptFinal(next))
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
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self.send(.parseFailed(Self.message(for: error)))
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
            timeoutTask?.cancel(); timeoutTask = nil
            narration = text
        }
    }

    /// Maps brain errors to the exact HUD text (carry-over #3). `.unparseable`
    /// yields empty so the machine falls back to its generic rephrase prompt.
    private static func message(for error: Error) -> String {
        switch error {
        case BrainError.unparseable: return ""
        case BrainError.modelNotReady(let m),
             BrainError.modelDownloading(let m),
             BrainError.backendFailure(let m): return m
        default: return ""
        }
    }
}
