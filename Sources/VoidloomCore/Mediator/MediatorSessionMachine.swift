import Foundation

public enum MediatorState: Equatable, Sendable {
    case idle
    case capturing(transcript: String)
    case parsing(transcript: String)
    /// No watchdog or cancel here by design: CommandExecutor runs synchronously
    /// on the main actor. Revisit if execution ever becomes async.
    case executing(MediatorCommand)
    case awaitingConfirmation(prompt: String, pending: MediatorCommand)
}

public enum MediatorEvent: Equatable, Sendable {
    case wakeDetected
    case pushToTalkPressed
    case transcriptDelta(String)
    case transcriptFinal(String)
    case commandProduced(MediatorCommand)
    case parseFailed(String)
    case executionFinished(ExecutionResult)
    case confirmReceived(Bool)
    case timeout
    case cancelRequested
}

public enum MediatorEffect: Equatable, Sendable {
    case startCapture
    case stopCapture
    case parse(transcript: String)
    case execute(MediatorCommand, confirmed: Bool)
    /// Replaces any previously scheduled timeout — the coordinator keeps at most one timer.
    case scheduleTimeout(seconds: Double)
    case narrate(String)
}

/// Pure reducer for the mediator pipeline. Owns every lifecycle rule from
/// the spec: capture windows and timeouts, single pending command,
/// confirmation without a wake word, overlapping-trigger semantics.
/// An @MainActor coordinator (Plan 2) performs effects and feeds events back.
public struct MediatorSessionMachine: Equatable, Sendable {
    public static let captureTimeout: Double = 15
    public static let confirmationTimeout: Double = 10
    public static let parseTimeout: Double = 10
    static let rephrasePrompt = "Didn't catch that — try rephrasing."

    public private(set) var state: MediatorState = .idle

    public init() {}
    /// Test/coordination conveniences for entering mid-pipeline states.
    static func parsing(_ transcript: String) -> Self {
        var m = Self(); m.state = .parsing(transcript: transcript); return m
    }
    static func executing(_ command: MediatorCommand) -> Self {
        var m = Self(); m.state = .executing(command); return m
    }

    public mutating func handle(_ event: MediatorEvent) -> [MediatorEffect] {
        switch (state, event) {
        case (.idle, .wakeDetected), (.idle, .pushToTalkPressed):
            state = .capturing(transcript: "")
            return [.startCapture, .scheduleTimeout(seconds: Self.captureTimeout)]

        case (.capturing, .wakeDetected), (.capturing, .pushToTalkPressed):
            state = .capturing(transcript: "")
            return [.stopCapture, .startCapture, .scheduleTimeout(seconds: Self.captureTimeout)]

        case (.capturing, .transcriptDelta(let text)):
            state = .capturing(transcript: text)
            return []

        case (.capturing, .transcriptFinal(let text)):
            state = .parsing(transcript: text)
            // The parse watchdog frees the machine if a brain call hangs.
            return [.stopCapture, .parse(transcript: text), .scheduleTimeout(seconds: Self.parseTimeout)]

        case (.capturing, .timeout):
            state = .idle
            return [.stopCapture, .narrate(Self.rephrasePrompt)]

        case (.capturing, .cancelRequested):
            state = .idle
            return [.stopCapture]

        case (.parsing, .commandProduced(let command)):
            state = .executing(command)
            return [.execute(command, confirmed: false)]

        case (.parsing, .parseFailed(let message)):
            state = .idle
            return [.narrate(message.isEmpty ? Self.rephrasePrompt : message)]

        case (.parsing, .timeout):
            state = .idle
            return [.narrate(Self.rephrasePrompt)]

        case (.parsing, .cancelRequested):
            state = .idle
            return []

        case (.executing, .executionFinished(let result)):
            return finish(result)

        case (.awaitingConfirmation(_, let pending), .confirmReceived(true)):
            state = .executing(pending)
            return [.execute(pending, confirmed: true)]

        case (.awaitingConfirmation, .confirmReceived(false)),
             (.awaitingConfirmation, .timeout),
             (.awaitingConfirmation, .cancelRequested):
            state = .idle
            return [.narrate("Cancelled")]

        default:
            return [] // stale or irrelevant events never disturb the pipeline
        }
    }

    private mutating func finish(_ result: ExecutionResult) -> [MediatorEffect] {
        switch result {
        case .success(let narration):
            state = .idle
            return [.narrate(narration)]
        case .needsClarification(let question):
            state = .idle
            return [.narrate(question)]
        case .needsConfirmation(let prompt, let pending):
            state = .awaitingConfirmation(prompt: prompt, pending: pending)
            return [.scheduleTimeout(seconds: Self.confirmationTimeout)]
        case .refused(let reason):
            state = .idle
            return [.narrate(reason)]
        }
    }
}
