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
            [.stopCapture, .parse(transcript: "ask jerry to fix the build")]
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
            [.scheduleTimeout(seconds: 10)]
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

    func testParseFailureNarratesRephrasePrompt() {
        var machine = MediatorSessionMachine.parsing("mumble mumble")
        XCTAssertEqual(machine.handle(.parseFailed("no valid command")),
                       [.narrate("Didn't catch that — try rephrasing.")])
        XCTAssertEqual(machine.state, .idle)
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
        XCTAssertEqual(machine.handle(.timeout), [.stopCapture, .narrate("Didn't catch that — try rephrasing.")])
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
}
