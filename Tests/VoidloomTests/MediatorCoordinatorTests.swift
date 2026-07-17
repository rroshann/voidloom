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
            if c.state == .idle { return }
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
        XCTAssertEqual(c.narration, MediatorSessionMachine.rephrasePrompt)
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
    private var release: CheckedContinuation<Outcome, Never>?
    private var released = false
    private var latchedOutcome: Outcome?

    init(_ outcome: Outcome) { self.outcome = outcome }

    /// Safe to call before the brain reaches its suspension point: the release
    /// is latched, so the continuation resumes immediately when stored. Closes
    /// the lost-wakeup window that made the busy-queue test flaky on slow CI.
    /// Snapshots `outcome` at release so a waiter isn't poisoned if the test
    /// re-arms `.hang` for the next turn before this call resumes on MainActor.
    /// When a waiter is already pending, resume it without latching — same as
    /// `ControllablePhraser.releaseNow` — so the next hang still waits.
    func releaseNow() {
        lock.lock()
        let pending = release
        release = nil
        let value = outcome
        if pending == nil {
            released = true
            latchedOutcome = value
        }
        lock.unlock()
        pending?.resume(returning: value)
    }

    func command(for utterance: String) async throws -> MediatorCommand {
        started.continuation.yield(())
        let resolved: Outcome
        if case .hang = outcome {
            resolved = await withCheckedContinuation { (cont: CheckedContinuation<Outcome, Never>) in
                lock.lock()
                if released {
                    released = false
                    let result = latchedOutcome ?? outcome
                    latchedOutcome = nil
                    lock.unlock()
                    cont.resume(returning: result)
                } else {
                    release = cont
                    lock.unlock()
                }
            }
            try Task.checkCancellation()
        } else {
            resolved = outcome
        }
        switch resolved {
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
        await waitForIdle(c)
        XCTAssertEqual(c.narration, "Hey — ready when you are.")
        XCTAssertEqual(c.state, .idle)
    }

    func testDelegateCommandRoutesToHandlerAndNarratesAnswer() async {
        let brain = ControllableBrain(.success(.delegate(question: "how does persistence work", target: "ember")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.delegateHandler = { question, target, onChunk in
            XCTAssertEqual(question, "how does persistence work")
            XCTAssertEqual(target, "ember")
            onChunk("ember is thinking…")
            return "ember: persistence is debounced per workspace."
        }
        c.submitTyped("ask ember about how does persistence work")
        for _ in 0..<4000 where c.narration != "ember: persistence is debounced per workspace." { await Task.yield() }
        XCTAssertEqual(c.narration, "ember: persistence is debounced per workspace.")
        XCTAssertFalse(c.isStreamingReply)
        XCTAssertEqual(c.state, .idle)
    }

    func testDelegationWithoutHandlerIsRefusedNotCrashed() async {
        let brain = ControllableBrain(.success(.delegate(question: "q", target: nil)))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        // No delegateHandler set → falls through to the executor's safety refusal.
        c.submitTyped("research something")
        await waitForIdle(c)
        XCTAssertEqual(c.narration, "Delegation isn't available right now.")
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
        for _ in 0..<8000 where c.state != .idle { await Task.yield(); try? await Task.sleep(nanoseconds: 100_000) }
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
        await waitForIdle(c)
        XCTAssertEqual(c.narration, MediatorSessionMachine.rephrasePrompt)
        XCTAssertEqual(c.state, .idle)
    }

    func testModelNotReadyNeverRoutesToChat() async {
        let brain = ControllableBrain(.failure(.modelNotReady("Local model not downloaded — open Settings › Local AI.")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.chatFallback = { _, _ in XCTFail("chat must not swallow model-availability errors"); return "" }
        c.submitTyped("start 2 claude agents")
        await waitForIdle(c)
        XCTAssertEqual(c.narration, "Local model not downloaded — open Settings › Local AI.")
    }

    func testParseFailedSurfacesBrainSpecificMessage() async {
        let brain = ControllableBrain(.failure(.modelNotReady("Local model not downloaded — open Settings › Local AI.")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.submitTyped("start 2 claude agents")
        await waitForIdle(c)
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

// MARK: - Task 2: spokenReply + phrasing pipeline

private final class ControllablePhraser: @unchecked Sendable {
    enum Mode { case hang, returnValue(String?), hangFirstOnly }
    var mode: Mode = .hang
    let started = AsyncStream<String>.makeStream()
    private let lock = NSLock()
    private var release: CheckedContinuation<String?, Never>?
    private var released = false
    private var latchedResult: String??
    @MainActor private var callCount = 0

    func releaseNow(_ value: String?) {
        lock.lock()
        let pending = release
        release = nil
        if pending == nil {
            released = true
            latchedResult = value
        }
        lock.unlock()
        pending?.resume(returning: value)
    }

    @MainActor
    func phrase(_ fact: String) async -> String? {
        callCount += 1
        let call = callCount
        started.continuation.yield(fact)
        switch mode {
        case .returnValue(let v):
            return v
        case .hangFirstOnly where call > 1:
            return nil
        case .hang, .hangFirstOnly:
            break
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            lock.lock()
            if released {
                released = false
                let result = latchedResult ?? nil
                latchedResult = nil
                lock.unlock()
                cont.resume(returning: result)
            } else {
                release = cont
                lock.unlock()
            }
        }
    }
}

extension MediatorCoordinatorTests {
    func testParseStartSetsAckNarration() async {
        let brain = ControllableBrain(.hang)
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.submitTyped("add a note")
        var it = brain.started.stream.makeAsyncIterator()
        _ = await it.next()
        guard case .parsing = c.state else {
            return XCTFail("expected parsing, got \(c.state)")
        }
        XCTAssertTrue(AssistantAcks.pool.contains(c.narration))
        XCTAssertNil(c.spokenReply)
    }

    func testPhraserSoftensSuccessNarration() async {
        let phraser = ControllablePhraser()
        let brain = ControllableBrain(.success(.createCard(kind: .note, content: nil)))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.phraser = { fact in await phraser.phrase(fact) }
        c.submitTyped("note")
        var it = brain.started.stream.makeAsyncIterator()
        _ = await it.next()
        brain.releaseNow()
        for _ in 0..<4000 where c.narration != "Created a note" { await Task.yield() }
        XCTAssertEqual(c.narration, "Created a note")
        XCTAssertNil(c.spokenReply)
        phraser.releaseNow("Note's up!")
        for _ in 0..<4000 where c.spokenReply?.text != "Note's up!" { await Task.yield() }
        XCTAssertEqual(c.narration, "Note's up!")
        XCTAssertEqual(c.spokenReply?.text, "Note's up!")
    }

    func testPhraserReturningNilKeepsFact() async {
        let phraser = ControllablePhraser()
        phraser.mode = .returnValue(nil)
        let brain = ControllableBrain(.success(.createCard(kind: .note, content: nil)))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.phraser = { fact in await phraser.phrase(fact) }
        c.submitTyped("note")
        var it = brain.started.stream.makeAsyncIterator()
        _ = await it.next()
        brain.releaseNow()
        for _ in 0..<4000 where c.spokenReply == nil { await Task.yield() }
        await waitForIdle(c)
        XCTAssertEqual(c.narration, "Created a note")
        XCTAssertEqual(c.spokenReply?.text, "Created a note")
    }

    func testSuccessWithoutPhraserPublishesSpokenReplyImmediately() async {
        let c = makeCoordinator(makeStore(), MockAgentTerminals())
        c.submitTyped("note")
        await waitForIdle(c)
        XCTAssertEqual(c.narration, "Created a note")
        XCTAssertEqual(c.spokenReply?.text, "Created a note")
    }

    func testStalePhraseDroppedWhenNewTurnStarts() async {
        let phraser = ControllablePhraser()
        phraser.mode = .hangFirstOnly
        let brain = ControllableBrain(.success(.createCard(kind: .note, content: nil)))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.phraser = { fact in await phraser.phrase(fact) }
        c.submitTyped("note")
        var it = brain.started.stream.makeAsyncIterator()
        _ = await it.next()
        brain.releaseNow()
        for _ in 0..<4000 where c.narration != "Created a note" { await Task.yield() }
        var phraserIt = phraser.started.stream.makeAsyncIterator()
        _ = await phraserIt.next()
        brain.outcome = .success(.createCard(kind: .todo, content: nil))
        c.submitTyped("todo")
        _ = await it.next()
        brain.releaseNow()
        for _ in 0..<4000 where c.narration != "Created a todo" { await Task.yield() }
        phraser.releaseNow("Note's up!")
        for _ in 0..<2000 { await Task.yield() }
        XCTAssertEqual(c.narration, "Created a todo")
        XCTAssertNotEqual(c.narration, "Note's up!")
        for _ in 0..<4000 where c.spokenReply?.text != "Created a todo" { await Task.yield() }
        XCTAssertEqual(c.spokenReply?.text, "Created a todo")
    }

    func testStaleSpokenReplyDroppedWhenQueuedUtteranceDrains() async {
        let phraser = ControllablePhraser()
        phraser.mode = .hangFirstOnly
        let store = makeStore()
        let terminals = MockAgentTerminals()
        let brain = ControllableBrain(.hang)
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: store, terminals: terminals, namePool: AgentNamePool()))
        c.phraser = { fact in await phraser.phrase(fact) }
        c.submitTyped("note")
        var it = brain.started.stream.makeAsyncIterator()
        _ = await it.next()
        c.submitTyped("todo")
        XCTAssertEqual(c.queuedUtterance, "todo")
        brain.outcome = .success(.createCard(kind: .note, content: nil))
        brain.releaseNow()
        brain.outcome = .hang
        var phraserIt = phraser.started.stream.makeAsyncIterator()
        let firstFact = await phraserIt.next()
        XCTAssertEqual(firstFact, "Created a note")
        XCTAssertNil(c.queuedUtterance)
        phraser.releaseNow("Stale note phrase!")
        for _ in 0..<2000 { await Task.yield() }
        XCTAssertNotEqual(c.spokenReply?.text, "Stale note phrase!")
        brain.outcome = .success(.createCard(kind: .todo, content: nil))
        brain.releaseNow()
        for _ in 0..<4000 where c.narration != "Created a todo" { await Task.yield() }
        for _ in 0..<4000 where c.spokenReply?.text != "Created a todo" { await Task.yield() }
        XCTAssertEqual(c.spokenReply?.text, "Created a todo")
    }

    func testParseFailedPublishesSpokenReply() async {
        let brain = ControllableBrain(.failure(.modelNotReady("Local model not downloaded — open Settings › Local AI.")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.submitTyped("start 2 claude agents")
        await waitForIdle(c)
        XCTAssertEqual(c.narration, "Local model not downloaded — open Settings › Local AI.")
        XCTAssertEqual(c.spokenReply?.text, "Local model not downloaded — open Settings › Local AI.")
    }
}
