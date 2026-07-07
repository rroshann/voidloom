import XCTest
@testable import VoidloomCore

@MainActor
final class MediatorCoordinatorTests: XCTestCase {
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

    private func makeCoordinator(_ store: WorkspaceStore, _ terminals: MockAgentTerminals,
                                 timeoutScale: Double = 1) -> MediatorSessionCoordinator {
        MediatorSessionCoordinator(
            brain: FastPathBrain(),
            executor: CommandExecutor(store: store, terminals: terminals, namePool: AgentNamePool()),
            timeoutScale: timeoutScale
        )
    }

    private func waitForIdle(_ c: MediatorSessionCoordinator) async {
        for _ in 0..<2000 {
            if c.state == .idle, !c.narration.isEmpty { return }
            await Task.yield()
        }
    }

    func testTypedSpawnFlowsThroughBrainExecutorAndNarrates() async {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let c = makeCoordinator(store, terminals)

        c.submitTyped("start 2 claude agents")
        await waitForIdle(c)

        XCTAssertEqual(store.state.cards.filter { $0.kind == .agent }.count, 2)
        XCTAssertEqual(terminals.spawned.count, 2)
        XCTAssertEqual(c.narration, "Spawned 2 claude agents: ember, slate")
        XCTAssertEqual(c.state, .idle)
    }

    func testUnparseableTypedInputNarratesRephrase() async {
        let c = makeCoordinator(makeStore(), MockAgentTerminals())
        c.submitTyped("do the thing")
        await waitForIdle(c)
        XCTAssertEqual(c.narration, "Didn't catch that — try rephrasing.")
    }

    func testDestructiveCommandAwaitsThenExecutesTypedConfirmation() async {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let c = makeCoordinator(store, terminals)
        let id = store.addTitledCard(kind: .agent, title: "ember")

        c.submitTyped("close ember")
        for _ in 0..<2000 {
            if case .awaitingConfirmation = c.state { break }
            await Task.yield()
        }
        guard case .awaitingConfirmation = c.state else {
            return XCTFail("expected awaitingConfirmation, got \(c.state)")
        }
        XCTAssertTrue(store.state.cards.contains { $0.id == id })

        c.submitTyped("confirm")
        await waitForIdle(c)
        XCTAssertEqual(terminals.terminated, [id])
        XCTAssertFalse(store.state.cards.contains { $0.id == id })
        XCTAssertEqual(c.narration, "Closed ember")
    }

    func testConfirmationTimesOutViaSingleReplaceableTimer() async {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let c = makeCoordinator(store, terminals, timeoutScale: 0.01) // 10s -> 100ms; generous enough that the parse watchdog can't race the instant brain
        store.addTitledCard(kind: .agent, title: "ember")

        c.submitTyped("close ember")
        for _ in 0..<4000 {
            if c.state == .idle, c.narration == "Cancelled" { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.narration, "Cancelled")
        XCTAssertTrue(terminals.terminated.isEmpty) // never executed
    }
}

private final class ControllableBrain: MediatorBrain, @unchecked Sendable {
    enum Outcome { case success(MediatorCommand), failure(BrainError), hang }
    var outcome: Outcome
    let started = AsyncStream<Void>.makeStream()
    private let lock = NSLock()
    private var release: CheckedContinuation<Void, Never>?
    private var released = false

    init(_ outcome: Outcome) { self.outcome = outcome }

    /// Safe to call before the brain reaches its suspension point: the release
    /// is latched, so the continuation resumes immediately when stored. Closes
    /// the lost-wakeup window that made the busy-queue test flaky on slow CI.
    func releaseNow() {
        lock.lock()
        released = true
        let pending = release
        release = nil
        lock.unlock()
        pending?.resume()
    }

    func command(for utterance: String) async throws -> MediatorCommand {
        started.continuation.yield(())
        if case .hang = outcome {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                lock.lock()
                if released {
                    released = false
                    lock.unlock()
                    cont.resume()
                } else {
                    release = cont
                    lock.unlock()
                }
            }
            try Task.checkCancellation()
        }
        switch outcome {
        case .success(let c): return c
        case .failure(let e): throw e
        case .hang: throw CancellationError()
        }
    }
}

extension MediatorCoordinatorTests {
    func testUnparseableFallsBackToChatWhenConfigured() async {
        let brain = ControllableBrain(.failure(.unparseable("hi")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.chatFallback = { utterance, _ in
            XCTAssertEqual(utterance, "hi")
            return "Hey — ready when you are."
        }
        c.submitTyped("hi")
        for _ in 0..<4000 where c.narration.isEmpty { await Task.yield() }
        XCTAssertEqual(c.narration, "Hey — ready when you are.")
        XCTAssertEqual(c.state, .idle)
    }

    func testChatReplyStreamsChunksIntoNarrationLive() async {
        let brain = ControllableBrain(.failure(.unparseable("tell me a joke")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.chatFallback = { _, onChunk in
            onChunk("Why did")
            onChunk("Why did the loom")
            return "Why did the loom cross the road?"
        }
        c.submitTyped("tell me a joke")
        for _ in 0..<4000 where c.narration != "Why did the loom cross the road?" { await Task.yield() }
        XCTAssertEqual(c.narration, "Why did the loom cross the road?")
        XCTAssertFalse(c.isStreamingReply)
        XCTAssertEqual(c.state, .idle)
    }

    func testSlowChatReplyOutlivesTheParseWatchdog() async {
        // The parse watchdog is sized for command parsing; a cold chat backend
        // can exceed it. Entering the chat leg must re-arm a longer window.
        let brain = ControllableBrain(.failure(.unparseable("hi")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()),
            timeoutScale: 0.001)   // parse watchdog ≈ 10ms, chat window ≈ 30ms
        c.chatFallback = { _, _ in
            try? await Task.sleep(nanoseconds: 20_000_000)   // 20ms: beyond parse, within chat
            return "Hey!"
        }
        c.submitTyped("hi")
        for _ in 0..<8000 where c.narration.isEmpty { await Task.yield(); try? await Task.sleep(nanoseconds: 100_000) }
        XCTAssertEqual(c.narration, "Hey!")
        XCTAssertEqual(c.state, .idle)
    }

    func testChatFallbackErrorFallsBackToRephrasePrompt() async {
        let brain = ControllableBrain(.failure(.unparseable("hi")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.chatFallback = { _, _ in throw BrainError.backendFailure("chat down") }
        c.submitTyped("hi")
        for _ in 0..<4000 where c.narration.isEmpty { await Task.yield() }
        XCTAssertEqual(c.narration, "Didn't catch that — try rephrasing.")
        XCTAssertEqual(c.state, .idle)
    }

    func testModelNotReadyNeverRoutesToChat() async {
        let brain = ControllableBrain(.failure(.modelNotReady("Local model not downloaded — open Settings › Local AI.")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.chatFallback = { _, _ in XCTFail("chat must not swallow model-availability errors"); return "" }
        c.submitTyped("start 2 claude agents")
        for _ in 0..<4000 where c.narration.isEmpty { await Task.yield() }
        XCTAssertEqual(c.narration, "Local model not downloaded — open Settings › Local AI.")
    }

    func testParseFailedSurfacesBrainSpecificMessage() async {
        let brain = ControllableBrain(.failure(.modelNotReady("Local model not downloaded — open Settings › Local AI.")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.submitTyped("start 2 claude agents")
        for _ in 0..<4000 where c.narration.isEmpty { await Task.yield() }
        XCTAssertEqual(c.narration, "Local model not downloaded — open Settings › Local AI.")
        XCTAssertEqual(c.state, .idle)
    }

    func testCancelDuringParsingCancelsBrainAndTimer() async {
        let brain = ControllableBrain(.hang)
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.submitTyped("start 2 claude agents")
        var it = brain.started.stream.makeAsyncIterator()
        _ = await it.next()                       // brain call is in flight
        guard case .parsing = c.state else { return XCTFail("expected parsing") }
        c.cancel()
        brain.releaseNow()                        // unblock the hung task so it can observe cancellation
        for _ in 0..<2000 where c.isBusy { await Task.yield() }
        XCTAssertEqual(c.state, .idle)
        XCTAssertFalse(c.isBusy)                   // timer + parse task both torn down
    }

    func testBusyInputQueuesExactlyOnePendingUtterance() async {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let brain = ControllableBrain(.hang)
        let c = MediatorSessionCoordinator(brain: brain, executor: CommandExecutor(store: store, terminals: terminals, namePool: AgentNamePool()))
        c.submitTyped("start 1 claude agent")
        var it = brain.started.stream.makeAsyncIterator(); _ = await it.next()
        XCTAssertTrue(c.isBusy)
        c.submitTyped("start 2 shell agents")     // queued, not dropped
        c.submitTyped("start 3 shell agents")     // replaces the queued one (queue depth 1)
        brain.outcome = .success(.spawnAgents(count: 1, kind: .claudeCode, names: nil))
        brain.releaseNow()
        for _ in 0..<6000 where store.state.cards.filter({ $0.kind == .agent }).count < 3 {
            await Task.yield(); try? await Task.sleep(nanoseconds: 500_000)
        }
        // First utterance spawns 1; the single queued "3 shell agents" runs next → 1 + ... = fast-path? No:
        // ControllableBrain always returns the same command, so the queued utterance re-runs it → +1 = 2 total.
        XCTAssertEqual(store.state.cards.filter { $0.kind == .agent }.count, 2)
    }
}
