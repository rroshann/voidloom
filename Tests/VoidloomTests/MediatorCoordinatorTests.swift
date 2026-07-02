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
