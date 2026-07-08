import Combine
import Foundation

/// Severity of a mediator narration, so the HUD can give success, failure, and
/// ordinary replies visually distinct signatures.
public enum NarrationKind: Sendable, Equatable {
    case info, success, error
}

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
    /// True when mic permission was denied; HUD disables the hold-to-talk control.
    @Published public private(set) var isMicPermissionDenied: Bool = false

    /// When set, an utterance NO brain tier can parse as a command is answered
    /// by the chat backend and the reply narrated in the HUD — the pill talks
    /// back instead of shrugging. Only `.unparseable` routes here; model-
    /// availability errors keep their specific messages. The `onChunk` callback
    /// streams partial text into the HUD live; the returned string is the final.
    public typealias ChatFallback =
        @MainActor (_ utterance: String, _ onChunk: @escaping @MainActor (String) -> Void) async throws -> String
    public var chatFallback: ChatFallback?

    /// True while a chat reply is streaming into the HUD — drives the thinking
    /// affordance. Set when the chat leg begins, cleared when it resolves.
    @Published public private(set) var isStreamingReply: Bool = false

    /// True while a delegation is in flight (an agent CLI is working), so the HUD
    /// can show a distinct "consulting an agent" state rather than plain thinking.
    @Published public private(set) var isDelegating: Bool = false

    /// Whether the most recent request arrived by voice (vs typed). Drives the
    /// "speak only when spoken to" preference and pure-voice reply display.
    @Published public private(set) var lastInputWasVoice: Bool = false

    /// Severity of the current narration, so the HUD can give success and failure
    /// distinct signatures instead of one identical bubble.
    @Published public private(set) var narrationKind: NarrationKind = .info

    /// Live mic input level (0…1) while capturing — lets the HUD visibly react to
    /// the user's voice. Zero when not listening.
    @Published public private(set) var inputLevel: Float = 0

    /// Runs a delegated question through an agent CLI and relays the answer.
    /// Always returns user-facing text (owns its own errors + timeout); streams
    /// progress via `onChunk`. Set by the app; nil disables delegation.
    public typealias DelegateHandler =
        @MainActor (_ question: String, _ target: String?, _ onChunk: @escaping @MainActor (String) -> Void) async -> String
    public var delegateHandler: DelegateHandler?

    private var machine = MediatorSessionMachine()
    private let brain: MediatorBrain
    private let executor: CommandExecutor
    private let transcriber: SpeechTranscribing?
    private let timeoutScale: Double
    private var timeoutTask: Task<Void, Never>?
    private var parseTask: Task<Void, Never>?
    private var delegateTask: Task<Void, Never>?
    /// Published so the HUD can show a "next up" chip — a command typed while busy
    /// is queued (depth-1, newest wins) instead of silently vanishing.
    @Published public private(set) var queuedUtterance: String?

    public init(
        brain: MediatorBrain,
        executor: CommandExecutor,
        transcriber: SpeechTranscribing? = nil,
        timeoutScale: Double = 1
    ) {
        self.brain = brain
        self.executor = executor
        self.transcriber = transcriber
        self.timeoutScale = timeoutScale
        transcriber?.onEvent = { [weak self] event in
            self?.handleTranscriberEvent(event)
        }
    }

    public func submitTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if handleConfirmationUtterance(trimmed) { return }
        lastInputWasVoice = false
        if isBusy {
            queuedUtterance = trimmed   // depth-1 queue: newest wins, per carry-over #2
            return
        }
        send(.typedUtterance(trimmed))
    }

    public func pushToTalkPressed() { send(.pushToTalkPressed) }
    /// Ends the current utterance capture; the transcriber emits `.final` when ready.
    public func pushToTalkReleased() { transcriber?.stopUtterance() }
    public func wakeDetected() { send(.wakeDetected) }
    public func setMicPermissionDenied(_ denied: Bool) { isMicPermissionDenied = denied }
    public func confirm(_ accepted: Bool) { send(.confirmReceived(accepted)) }
    public func cancel() { send(.cancelRequested) }

    private func send(_ event: MediatorEvent) {
        classifyNarration(for: event)
        let effects = machine.handle(event)
        state = machine.state
        // Any return to idle tears down in-flight async work (carry-over #1):
        // a hung LlamaBrain call and the parse watchdog must not outlive the state.
        if state == .idle {
            parseTask?.cancel(); parseTask = nil
            delegateTask?.cancel(); delegateTask = nil
            timeoutTask?.cancel(); timeoutTask = nil
            isStreamingReply = false
            isDelegating = false
        }
        isBusy = !(state == .idle) && !isAwaitingConfirmation
        for effect in effects { perform(effect) }
        drainQueueIfIdle()
    }

    private var isAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = state { return true }
        return false
    }

    /// Tags the upcoming narration with a severity so the HUD can distinguish a
    /// completed command (success), a failure (error), and an ordinary reply (info).
    private func classifyNarration(for event: MediatorEvent) {
        switch event {
        case .typedUtterance, .transcriptFinal, .pushToTalkPressed, .wakeDetected:
            narrationKind = .info   // a fresh turn starts neutral
        case .parseFailed, .timeout:
            narrationKind = .error
        case .executionFinished(let result):
            switch result {
            case .success: narrationKind = .success
            case .refused: narrationKind = .error
            case .needsClarification, .needsConfirmation: narrationKind = .info
            }
        default:
            break
        }
    }

    /// Runs a delegation while the machine sits in `.executing`: streams the
    /// agent's progress into the HUD, then narrates the final answer. The
    /// handler owns its own timeout and never throws; a `cancel()` returns the
    /// machine to idle, which cancels this task.
    private func runDelegation(question: String, target: String?, handler: @escaping DelegateHandler) {
        isStreamingReply = true
        isDelegating = true
        narration = target.map { "Asking \($0)…" } ?? "Delegating…"
        delegateTask?.cancel()
        delegateTask = Task { [weak self] in
            guard let self else { return }
            let onChunk: @MainActor (String) -> Void = { [weak self] partial in
                guard let self, !Task.isCancelled, self.isStreamingReply else { return }
                self.narration = partial
            }
            let answer = await handler(question, target, onChunk)
            guard !Task.isCancelled else { return }
            self.isStreamingReply = false
            self.isDelegating = false
            self.send(.executionFinished(.success(narration: answer)))
            self.narrationKind = .info   // a relayed answer is content, not a command-success flash
        }
    }

    private func drainQueueIfIdle() {
        guard state == .idle, let next = queuedUtterance else { return }
        queuedUtterance = nil
        send(.typedUtterance(next))
    }

    /// Typed input and voice finals share this branch while awaiting confirmation.
    @discardableResult
    private func handleConfirmationUtterance(_ text: String) -> Bool {
        guard case .awaitingConfirmation = machine.state else { return false }
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["confirm", "yes", "cancel", "no"].contains(word) else { return false }
        send(.confirmReceived(word == "confirm" || word == "yes"))
        return true
    }

    private func handleTranscriberEvent(_ event: TranscriberEvent) {
        switch event {
        case .partial(let text):
            send(.transcriptDelta(text))
        case .final(let text):
            inputLevel = 0
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if handleConfirmationUtterance(trimmed) { return }
            lastInputWasVoice = true
            send(.transcriptFinal(trimmed))
        case .unavailable(let message):
            inputLevel = 0
            if case .capturing = state { send(.cancelRequested) }
            perform(.narrate(message))
        case .level(let level):
            // Only meaningful while capturing; ignore stray levels otherwise.
            if case .capturing = state { inputLevel = level } else { inputLevel = 0 }
        }
    }

    private func perform(_ effect: MediatorEffect) {
        switch effect {
        case .startCapture:
            transcriber?.startUtterance()
        case .stopCapture:
            transcriber?.stopUtterance()

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
                    if case BrainError.unparseable = error, let chat = self.chatFallback {
                        self.isStreamingReply = true
                        self.perform(.scheduleTimeout(seconds: MediatorSessionMachine.chatTimeout))
                        let onChunk: @MainActor (String) -> Void = { [weak self] partial in
                            guard let self, !Task.isCancelled, self.isStreamingReply else { return }
                            // Live typing into the HUD while still .parsing; steady
                            // progress keeps the window open, a stalled stream doesn't.
                            self.narration = partial
                            self.perform(.scheduleTimeout(seconds: MediatorSessionMachine.chatTimeout))
                        }
                        let reply = try? await chat(transcript, onChunk)
                        self.isStreamingReply = false
                        guard !Task.isCancelled else { return }
                        if let reply, !reply.isEmpty {
                            self.send(.chatReply(reply))
                        } else {
                            self.send(.parseFailed(""))
                        }
                        return
                    }
                    self.send(.parseFailed(Self.message(for: error)))
                }
            }

        case .execute(let command, let confirmed):
            if case .delegate(let question, let target) = command, let handler = delegateHandler {
                runDelegation(question: question, target: target, handler: handler)
            } else {
                send(.executionFinished(executor.execute(command, confirmed: confirmed)))
            }

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
