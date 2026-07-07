import XCTest
@testable import VoidloomCore

@MainActor
private final class FakeTranscriber: SpeechTranscribing {
    var onEvent: ((TranscriberEvent) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startUtterance() { startCount += 1 }
    func stopUtterance() { stopCount += 1 }

    func emit(_ event: TranscriberEvent) { onEvent?(event) }
}

@MainActor
final class MediatorVoiceTests: XCTestCase {
    private func makeStore() -> WorkspaceStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return WorkspaceStore(
            state: WorkspaceState(viewport: CanvasViewport(origin: .zero, scale: 1), cards: []),
            storageURL: url,
            persistenceDelay: 60
        )
    }

    private func makeCoordinator(
        _ store: WorkspaceStore,
        _ terminals: MockAgentTerminals,
        transcriber: FakeTranscriber
    ) -> MediatorSessionCoordinator {
        MediatorSessionCoordinator(
            brain: FastPathBrain(),
            executor: CommandExecutor(store: store, terminals: terminals, namePool: AgentNamePool()),
            transcriber: transcriber
        )
    }

    private func waitForIdle(_ c: MediatorSessionCoordinator) async {
        for _ in 0..<2000 {
            if c.state == .idle, !c.narration.isEmpty { return }
            await Task.yield()
        }
    }

    func testStartStopCalledOnCaptureEffects() {
        let transcriber = FakeTranscriber()
        let c = makeCoordinator(makeStore(), MockAgentTerminals(), transcriber: transcriber)

        c.pushToTalkPressed()
        XCTAssertEqual(transcriber.startCount, 1)
        XCTAssertEqual(transcriber.stopCount, 0)

        transcriber.emit(.final("start 1 claude agent"))
        XCTAssertEqual(transcriber.stopCount, 1)
    }

    func testPartialReplacesTranscript() {
        let transcriber = FakeTranscriber()
        let c = makeCoordinator(makeStore(), MockAgentTerminals(), transcriber: transcriber)

        c.pushToTalkPressed()
        transcriber.emit(.partial("start"))
        guard case .capturing(let t1) = c.state else { return XCTFail("expected capturing") }
        XCTAssertEqual(t1, "start")

        transcriber.emit(.partial("start two"))
        guard case .capturing(let t2) = c.state else { return XCTFail("expected capturing") }
        XCTAssertEqual(t2, "start two")
    }

    func testFinalFlowsThroughParsePipeline() async {
        let store = makeStore()
        let terminals = MockAgentTerminals()
        let transcriber = FakeTranscriber()
        let c = makeCoordinator(store, terminals, transcriber: transcriber)

        c.pushToTalkPressed()
        transcriber.emit(.final("start 2 claude agents"))
        await waitForIdle(c)

        XCTAssertEqual(store.state.cards.filter { $0.kind == .agent }.count, 2)
        XCTAssertEqual(terminals.spawned.count, 2)
        XCTAssertEqual(c.narration, "Spawned 2 claude agents: ember, slate")
        XCTAssertEqual(c.state, .idle)
    }

    func testFinalConfirmWhileAwaitingConfirmationUsesSharedPath() async {
        let store = makeStore()
        let terminals = MockAgentTerminals()
        let transcriber = FakeTranscriber()
        let c = makeCoordinator(store, terminals, transcriber: transcriber)
        let id = store.addTitledCard(kind: .agent, title: "ember")

        c.submitTyped("close ember")
        for _ in 0..<2000 {
            if case .awaitingConfirmation = c.state { break }
            await Task.yield()
        }
        guard case .awaitingConfirmation = c.state else {
            return XCTFail("expected awaitingConfirmation, got \(c.state)")
        }

        transcriber.emit(.final("confirm"))
        await waitForIdle(c)

        XCTAssertEqual(terminals.terminated, [id])
        XCTAssertFalse(store.state.cards.contains { $0.id == id })
        XCTAssertEqual(c.narration, "Closed ember")
    }

    func testUnavailableNarratesAndReturnsToIdle() {
        let transcriber = FakeTranscriber()
        let c = makeCoordinator(makeStore(), MockAgentTerminals(), transcriber: transcriber)

        c.pushToTalkPressed()
        guard case .capturing = c.state else { return XCTFail("expected capturing") }

        transcriber.emit(.unavailable("Voice model still preparing — try again shortly."))

        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.narration, "Voice model still preparing — try again shortly.")
        XCTAssertEqual(transcriber.stopCount, 1)
    }

    func testWakeDetectedStartsCapture() {
        let transcriber = FakeTranscriber()
        let c = makeCoordinator(makeStore(), MockAgentTerminals(), transcriber: transcriber)

        c.wakeDetected()
        XCTAssertEqual(transcriber.startCount, 1)
        guard case .capturing = c.state else { return XCTFail("expected capturing") }
    }

    func testPushToTalkReleasedStopsUtterance() {
        let transcriber = FakeTranscriber()
        let c = makeCoordinator(makeStore(), MockAgentTerminals(), transcriber: transcriber)

        c.pushToTalkPressed()
        XCTAssertEqual(transcriber.startCount, 1)
        c.pushToTalkReleased()
        XCTAssertEqual(transcriber.stopCount, 1)
    }

    func testSubmitTypedNeverStartsOrStopsCapture() async {
        let store = makeStore()
        let terminals = MockAgentTerminals()
        let transcriber = FakeTranscriber()
        let c = makeCoordinator(store, terminals, transcriber: transcriber)

        c.submitTyped("start 2 claude agents")
        await waitForIdle(c)

        XCTAssertEqual(transcriber.startCount, 0)
        XCTAssertEqual(transcriber.stopCount, 0)
        XCTAssertEqual(store.state.cards.filter { $0.kind == .agent }.count, 2)
    }
}
