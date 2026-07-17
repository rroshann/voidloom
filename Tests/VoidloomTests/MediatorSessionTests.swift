import XCTest
@testable import VoidloomCore

final class MediatorSessionTests: XCTestCase {
    func testWakeStartsCaptureAndTranscriptFlowsToParse() {
        var machine = MediatorSessionMachine()
        XCTAssertEqual(machine.handle(.wakeDetected), [.startCapture, .scheduleTimeout(seconds: 15)])
        XCTAssertEqual(machine.state, .capturing(transcript: ""))

        XCTAssertEqual(machine.handle(.transcriptDelta("ask jerry")), [])
        XCTAssertEqual(machine.state, .capturing(transcript: "ask jerry"))

        XCTAssertEqual(
            machine.handle(.transcriptFinal("ask jerry to fix the build")),
            [.stopCapture, .parse(transcript: "ask jerry to fix the build"), .scheduleTimeout(seconds: 10)]
        )
        XCTAssertEqual(machine.state, .parsing(transcript: "ask jerry to fix the build"))
    }

    func testCommandProducedExecutesAndResultNarrates() {
        var machine = MediatorSessionMachine.parsing("ask jerry to fix the build")
        let command = MediatorCommand.sendPrompt(target: "jerry", text: "fix the build")

        XCTAssertEqual(machine.handle(.commandProduced(command)), [.execute(command, confirmed: false)])
        XCTAssertEqual(machine.state, .executing(command))

        XCTAssertEqual(
            machine.handle(.executionFinished(.success(narration: "→ jerry"))),
            [.narrate("→ jerry")]
        )
        XCTAssertEqual(machine.state, .idle)
    }

    func testConfirmationFlowConfirmAndCancelAndTimeout() {
        let pending = MediatorCommand.closeTerminal(target: "omen")

        var machine = MediatorSessionMachine.executing(pending)
        XCTAssertEqual(
            machine.handle(.executionFinished(.needsConfirmation(prompt: "Close omen?", pending: pending))),
            [.scheduleTimeout(seconds: 30)]
        )
        XCTAssertEqual(machine.state, .awaitingConfirmation(prompt: "Close omen?", pending: pending))

        // confirm → re-execute confirmed, no wake word needed
        var confirmed = machine
        XCTAssertEqual(confirmed.handle(.confirmReceived(true)), [.execute(pending, confirmed: true)])
        XCTAssertEqual(confirmed.state, .executing(pending))

        // cancel → idle
        var cancelled = machine
        XCTAssertEqual(cancelled.handle(.confirmReceived(false)), [.narrate("Cancelled")])
        XCTAssertEqual(cancelled.state, .idle)

        // timeout → idle
        var timedOut = machine
        XCTAssertEqual(timedOut.handle(.timeout), [.narrate("Cancelled")])
        XCTAssertEqual(timedOut.state, .idle)
    }

    func testParseFailureNarratesPayloadVerbatimAndFallsBackWhenEmpty() {
        // A non-empty payload is surfaced verbatim (carry-over #3): the coordinator
        // maps availability errors like "model not downloaded" to real sentences.
        var withMessage = MediatorSessionMachine.parsing("mumble mumble")
        XCTAssertEqual(withMessage.handle(.parseFailed("no valid command")),
                       [.narrate("no valid command")])
        XCTAssertEqual(withMessage.state, .idle)

        // An empty payload (e.g. `.unparseable`) falls back to the generic prompt.
        var empty = MediatorSessionMachine.parsing("mumble mumble")
        XCTAssertEqual(empty.handle(.parseFailed("")),
                       [.narrate(MediatorSessionMachine.rephrasePrompt)])
        XCTAssertEqual(empty.state, .idle)
    }

    func testParsingTimesOutAndCanBeCancelled() {
        var timedOut = MediatorSessionMachine.parsing("slow brain")
        XCTAssertEqual(timedOut.handle(.timeout), [.narrate(MediatorSessionMachine.rephrasePrompt)])
        XCTAssertEqual(timedOut.state, .idle)

        var cancelled = MediatorSessionMachine.parsing("slow brain")
        XCTAssertEqual(cancelled.handle(.cancelRequested), [])
        XCTAssertEqual(cancelled.state, .idle)
    }

    func testOverlappingTriggerRestartsCaptureButNeverInterruptsExecution() {
        // during capture: push-to-talk restarts the capture window
        var capturing = MediatorSessionMachine()
        _ = capturing.handle(.wakeDetected)
        _ = capturing.handle(.transcriptDelta("half a command"))
        XCTAssertEqual(capturing.handle(.pushToTalkPressed),
                       [.stopCapture, .startCapture, .scheduleTimeout(seconds: 15)])
        XCTAssertEqual(capturing.state, .capturing(transcript: ""))

        // during execution: triggers are ignored (single pending command)
        let command = MediatorCommand.arrange(style: .grid)
        var executing = MediatorSessionMachine.executing(command)
        XCTAssertEqual(executing.handle(.wakeDetected), [])
        XCTAssertEqual(executing.state, .executing(command))
    }

    func testCaptureTimeoutAndCancelReturnToIdle() {
        var machine = MediatorSessionMachine()
        _ = machine.handle(.wakeDetected)
        XCTAssertEqual(machine.handle(.timeout), [.stopCapture, .narrate(MediatorSessionMachine.rephrasePrompt)])
        XCTAssertEqual(machine.state, .idle)

        var cancelled = MediatorSessionMachine()
        _ = cancelled.handle(.wakeDetected)
        XCTAssertEqual(cancelled.handle(.cancelRequested), [.stopCapture])
        XCTAssertEqual(cancelled.state, .idle)
    }

    func testStaleEventsInIdleAreIgnored() {
        var machine = MediatorSessionMachine()
        XCTAssertEqual(machine.handle(.transcriptFinal("late transcript")), [])
        XCTAssertEqual(machine.handle(.timeout), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testTypedUtteranceFromIdleParsesWithoutCapture() {
        var machine = MediatorSessionMachine()
        XCTAssertEqual(
            machine.handle(.typedUtterance("start 2 claude agents")),
            [.parse(transcript: "start 2 claude agents"), .scheduleTimeout(seconds: 10)]
        )
        XCTAssertEqual(machine.state, .parsing(transcript: "start 2 claude agents"))
    }

    func testTypedUtteranceIgnoredWhileCapturing() {
        var machine = MediatorSessionMachine()
        _ = machine.handle(.wakeDetected)
        XCTAssertEqual(machine.handle(.typedUtterance("typed while mic open")), [])
        XCTAssertEqual(machine.state, .capturing(transcript: ""))
    }

    func testNonConfirmUtteranceWhileAwaitingConfirmationRepromptsAndRearmsTimeout() {
        let pending = MediatorCommand.closeTerminal(target: "omen")
        var machine = MediatorSessionMachine.executing(pending)
        _ = machine.handle(.executionFinished(.needsConfirmation(prompt: "Close omen?", pending: pending)))

        XCTAssertEqual(
            machine.handle(.typedUtterance("start 2 claude agents")),
            [.narrate("Waiting on a confirmation — say \"confirm\" or \"cancel\". Close omen?"),
             .scheduleTimeout(seconds: MediatorSessionMachine.confirmationTimeout)]
        )
        XCTAssertEqual(machine.state, .awaitingConfirmation(prompt: "Close omen?", pending: pending))

        XCTAssertEqual(
            machine.handle(.transcriptFinal("what about the build")),
            [.narrate("Waiting on a confirmation — say \"confirm\" or \"cancel\". Close omen?"),
             .scheduleTimeout(seconds: MediatorSessionMachine.confirmationTimeout)]
        )
        XCTAssertEqual(machine.state, .awaitingConfirmation(prompt: "Close omen?", pending: pending))
    }

    func testStrayConfirmWordsAtIdleNarrateInsteadOfParsing() {
        var machine = MediatorSessionMachine()
        for word in ["confirm", "Cancel", "yes", "NO"] {
            XCTAssertEqual(machine.handle(.typedUtterance(word)), [.narrate("Nothing to confirm.")],
                           "stray \(word) should not reach the parser")
            XCTAssertEqual(machine.state, .idle)
        }
    }

    func testConfirmationWindowIsThirtySeconds() {
        XCTAssertEqual(MediatorSessionMachine.confirmationTimeout, 30)
    }

    func testCancelDuringExecutingAbortsDelegation() {
        var machine = MediatorSessionMachine.executing(.delegate(question: "how does X work", target: nil))
        XCTAssertEqual(machine.handle(.cancelRequested), [.narrate("Cancelled")])
        XCTAssertEqual(machine.state, .idle)
    }

    func testChatReplyWhileParsingNarratesAndReturnsToIdle() {
        var machine = MediatorSessionMachine()
        _ = machine.handle(.typedUtterance("hi"))
        XCTAssertEqual(machine.handle(.chatReply("Hey — ready when you are.")),
                       [.narrate("Hey — ready when you are.")])
        XCTAssertEqual(machine.state, .idle)
        // Stale replies after the pipeline moved on never disturb it.
        XCTAssertEqual(machine.handle(.chatReply("stale")), [])
    }
}
