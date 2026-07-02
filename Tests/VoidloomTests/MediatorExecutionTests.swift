import XCTest
@testable import VoidloomCore

@MainActor
final class MockAgentTerminals: AgentTerminalControlling {
    var spawned: [(cardID: UUID, kind: MediatorAgentKind)] = []
    var sent: [(text: String, cardID: UUID)] = []
    var terminated: [UUID] = []
    var outputByCard: [UUID: [String]] = [:]

    func spawn(cardID: UUID, kind: MediatorAgentKind) { spawned.append((cardID, kind)) }
    func send(text: String, to cardID: UUID) { sent.append((text, cardID)) }
    func recentOutput(of cardID: UUID, maxLines: Int) -> [String] {
        Array((outputByCard[cardID] ?? []).suffix(maxLines))
    }
    func terminate(cardID: UUID) { terminated.append(cardID) }
}

@MainActor
final class AgentTerminalControllingTests: XCTestCase {
    func testMockRecordsInteractionsAndClampsOutput() {
        let mock = MockAgentTerminals()
        let id = UUID()
        mock.outputByCard[id] = ["a", "b", "c", "d"]

        mock.spawn(cardID: id, kind: .claudeCode)
        mock.send(text: "hello", to: id)

        XCTAssertEqual(mock.spawned.first?.kind, .claudeCode)
        XCTAssertEqual(mock.sent.first?.text, "hello")
        XCTAssertEqual(mock.recentOutput(of: id, maxLines: 2), ["c", "d"])
    }
}

final class AgentNamePoolTests: XCTestCase {
    func testAssignsFirstUnusedNamesCaseInsensitively() {
        let pool = AgentNamePool()
        let names = pool.nextNames(count: 2, existing: ["Ember", "SLATE"])
        XCTAssertEqual(names, ["nova", "drift"])
    }

    func testExhaustedPoolAppendsNumericSuffixes() {
        let pool = AgentNamePool(names: ["fox", "owl"])
        let names = pool.nextNames(count: 3, existing: ["fox"])
        XCTAssertEqual(names, ["owl", "fox-2", "owl-2"])
    }

    func testCustomPackReplacesDefaults() {
        let pool = AgentNamePool(names: ["maple", "fox"])
        XCTAssertEqual(pool.nextNames(count: 1, existing: []), ["maple"])
    }

    func testEmptyCustomPackFallsBackToDefaults() {
        let pool = AgentNamePool(names: [])
        XCTAssertEqual(pool.nextNames(count: 1, existing: []), ["ember"])
    }
}

@MainActor
final class AddTitledCardTests: XCTestCase {
    func testAddTitledCardSetsTitleContentAndReturnsID() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkspaceStore(
            state: WorkspaceState(viewport: CanvasViewport(origin: .zero, scale: 1), cards: []),
            storageURL: url,
            persistenceDelay: 60
        )

        let id = store.addTitledCard(kind: .agent, title: "viper")
        let noteID = store.addTitledCard(kind: .note, content: "standup notes")

        let agent = store.state.cards.first { $0.id == id }
        XCTAssertEqual(agent?.title, "viper")
        XCTAssertEqual(agent?.kind, .agent)
        let note = store.state.cards.first { $0.id == noteID }
        XCTAssertEqual(note?.content, "standup notes")
        XCTAssertNotEqual(agent?.position, note?.position) // cascade, no stacking
    }

    func testAddTitledCardPreservesDefaultContentWhenOmitted() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkspaceStore(
            state: WorkspaceState(viewport: CanvasViewport(origin: .zero, scale: 1), cards: []),
            storageURL: url,
            persistenceDelay: 60
        )

        let id = store.addTitledCard(kind: .todo, title: "chores")

        let todo = store.state.cards.first { $0.id == id }
        XCTAssertEqual(todo?.title, "chores")
        XCTAssertFalse(todo?.content.isEmpty ?? true)
    }
}

final class MediatorTargetResolverTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testExactCaseInsensitiveMatchWins() {
        let r = MediatorTargetResolver.resolve("Jerry", in: [(a, "jerry"), (b, "sage")])
        XCTAssertEqual(r, .match(a))
    }

    func testDuplicateNamesAreAmbiguous() {
        let r = MediatorTargetResolver.resolve("untitled", in: [(a, "Untitled"), (b, "Untitled")])
        XCTAssertEqual(r, .ambiguous(["Untitled", "Untitled"]))
    }

    func testUniquePrefixMatches() {
        let r = MediatorTargetResolver.resolve("phoe", in: [(a, "phoenix"), (b, "sage")])
        XCTAssertEqual(r, .match(a))
    }

    func testCloseMisspellingMatchesWithinDistanceTwo() {
        // ASR often drops/mangles a character or two.
        let r = MediatorTargetResolver.resolve("jery", in: [(a, "jerry"), (b, "sage")])
        XCTAssertEqual(r, .match(a))
    }

    func testFarMissReturnsNoneWithNearestSuggestion() {
        // "jasper" is edit-distance 5 from "jerry" — far beyond the match
        // threshold, but the mediator still offers the nearest name as a
        // question rather than silently failing (spec flow example).
        let r = MediatorTargetResolver.resolve("jasper", in: [(a, "jerry")])
        XCTAssertEqual(r, TargetResolution.none(suggestion: "jerry"))
    }

    func testEmptyCandidatesReturnsNoneWithoutSuggestion() {
        let r = MediatorTargetResolver.resolve("jerry", in: [])
        XCTAssertEqual(r, TargetResolution.none(suggestion: nil))
    }
}

@MainActor
final class CommandExecutorTests: XCTestCase {
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

    private func makeExecutor(_ store: WorkspaceStore, _ terminals: MockAgentTerminals) -> CommandExecutor {
        CommandExecutor(store: store, terminals: terminals, namePool: AgentNamePool())
    }

    func testSpawnAgentsCreatesTitledCardsAndSessions() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let result = makeExecutor(store, terminals).execute(.spawnAgents(count: 2, kind: .claudeCode, names: nil))

        let agents = store.state.cards.filter { $0.kind == .agent }
        XCTAssertEqual(agents.map(\.title), ["ember", "slate"])
        XCTAssertEqual(terminals.spawned.count, 2)
        XCTAssertEqual(result, .success(narration: "Spawned 2 claude agents: ember, slate"))
    }

    func testSpawnCountOutsideLimitsIsRefused() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let result = makeExecutor(store, terminals).execute(.spawnAgents(count: 9, kind: .claudeCode, names: nil))
        XCTAssertEqual(result, .refused(reason: "I can spawn between 1 and 8 agents at once."))
        XCTAssertTrue(store.state.cards.isEmpty)
    }

    func testSpawnDedupesCallerProvidedNames() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let result = makeExecutor(store, terminals).execute(.spawnAgents(count: 2, kind: .claudeCode, names: ["Ember", "ember"]))
        let titles = store.state.cards.filter { $0.kind == .agent }.map(\.title)
        XCTAssertEqual(titles, ["ember", "slate"])
        XCTAssertEqual(result, .success(narration: "Spawned 2 claude agents: ember, slate"))
    }

    func testSpawnRefusesNameCollidingWithExistingAgent() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        store.addTitledCard(kind: .agent, title: "ember")
        let result = makeExecutor(store, terminals).execute(.spawnAgents(count: 1, kind: .claudeCode, names: ["Ember"]))
        XCTAssertEqual(result, .needsClarification(question: "An agent named ember already exists — pick a different name."))
        XCTAssertEqual(store.state.cards.filter { $0.kind == .agent }.count, 1)
    }

    func testSendPromptRoutesToResolvedAgentCard() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let id = store.addTitledCard(kind: .agent, title: "jerry")
        let result = makeExecutor(store, terminals).execute(.sendPrompt(target: "jery", text: "look into the API errors"))

        XCTAssertEqual(terminals.sent.first?.cardID, id)
        XCTAssertEqual(terminals.sent.first?.text, "look into the API errors")
        XCTAssertEqual(result, .success(narration: "→ jerry"))
    }

    func testSendPromptToUnknownTargetAsksForClarification() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        store.addTitledCard(kind: .agent, title: "jerry")
        let result = makeExecutor(store, terminals).execute(.sendPrompt(target: "jasper", text: "hi"))
        XCTAssertEqual(result, .needsClarification(question: "I don't see a jasper — did you mean jerry?"))
        XCTAssertTrue(terminals.sent.isEmpty)
    }

    func testCloseTerminalRequiresConfirmationThenDeletes() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let id = store.addTitledCard(kind: .agent, title: "omen")
        let executor = makeExecutor(store, terminals)

        let first = executor.execute(.closeTerminal(target: "omen"))
        XCTAssertEqual(first, .needsConfirmation(
            prompt: "Close omen and its session?",
            pending: .closeTerminal(target: "omen")
        ))
        XCTAssertTrue(store.state.cards.contains { $0.id == id })

        let second = executor.execute(.closeTerminal(target: "omen"), confirmed: true)
        XCTAssertEqual(second, .success(narration: "Closed omen"))
        XCTAssertEqual(terminals.terminated, [id])
        XCTAssertFalse(store.state.cards.contains { $0.id == id })
    }

    func testReadOutputReturnsRecentLinesInNarration() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let id = store.addTitledCard(kind: .agent, title: "viper")
        terminals.outputByCard[id] = (1...30).map { "line \($0)" }
        let result = makeExecutor(store, terminals).execute(.readOutput(target: "viper"))
        guard case .success(let narration) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertTrue(narration.contains("line 30"))
        XCTAssertFalse(narration.contains("line 5")) // clamped to last 25
    }

    func testCreateCardAndSetBackgroundAndArrange() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let executor = makeExecutor(store, terminals)

        XCTAssertEqual(
            executor.execute(.createCard(kind: .note, content: "standup notes")),
            .success(narration: "Created a note")
        )
        XCTAssertEqual(store.state.cards.first?.content, "standup notes")

        XCTAssertEqual(
            executor.execute(.setBackground(spec: .solid(hex: "#102030FF"))),
            .success(narration: "Background updated")
        )
        XCTAssertEqual(store.state.space?.background, .solid(hex: "#102030FF"))

        XCTAssertEqual(executor.execute(.arrange(style: .retile)), .success(narration: "Re-tiled the space"))
    }

    func testCreateAgentCardRoutesThroughSpawnMachinery() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let result = makeExecutor(store, terminals).execute(.createCard(kind: .agent, content: nil))
        XCTAssertEqual(result, .success(narration: "Spawned 1 claude agent: ember"))
        XCTAssertEqual(terminals.spawned.count, 1)
        XCTAssertEqual(store.state.cards.first?.title, "ember")
    }

    func testSwitchSpaceWithDuplicateNamesAsksForClarification() {
        // createWorkspace only mutates the library in library mode, so this
        // test needs a library-backed store (unlike makeStore()'s legacy
        // single-file store, where createWorkspace is a no-op).
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: baseDirectory) }
        let store = WorkspaceStore(
            libraryURL: baseDirectory.appendingPathComponent("library.json"),
            workspacesDirectoryURL: baseDirectory.appendingPathComponent("workspaces", isDirectory: true),
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json"),
            persistenceDelay: 60
        )
        let terminals = MockAgentTerminals()
        // Two workspaces named identically → never guess (spec finding 13).
        store.createWorkspace(named: "research")
        store.createWorkspace(named: "research")
        let result = makeExecutor(store, terminals).execute(.switchSpace(name: "research"))
        XCTAssertEqual(result, .needsClarification(
            question: "There are 2 spaces named research — rename one to switch by voice."
        ))
    }

    func testSwitchSpaceVerifiesTheSwitchHappened() {
        // library-backed store, same reasoning as
        // testSwitchSpaceWithDuplicateNamesAsksForClarification: createWorkspace
        // only mutates the library in library mode.
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: baseDirectory) }
        let store = WorkspaceStore(
            libraryURL: baseDirectory.appendingPathComponent("library.json"),
            workspacesDirectoryURL: baseDirectory.appendingPathComponent("workspaces", isDirectory: true),
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json"),
            persistenceDelay: 60
        )
        let terminals = MockAgentTerminals()
        store.createWorkspace(named: "research")
        let result = makeExecutor(store, terminals).execute(.switchSpace(name: "research"))
        XCTAssertEqual(result, .success(narration: "Switched to research"))
        let selected = store.library.workspaces.first { $0.id == store.library.selectedWorkspaceID }
        XCTAssertEqual(selected?.name, "research")
    }

    func testSpawnCollisionCheckIsCaseInsensitiveAgainstRenamedCards() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        store.addTitledCard(kind: .agent, title: "Ember") // user renamed via UI
        let result = makeExecutor(store, terminals).execute(.spawnAgents(count: 1, kind: .claudeCode, names: ["ember"]))
        XCTAssertEqual(result, .needsClarification(question: "An agent named ember already exists — pick a different name."))
    }
}

final class PreworkCleanupTests: XCTestCase {
    func testWhitespaceOnlyPackFallsBackToDefaultsAndEntriesAreTrimmed() {
        XCTAssertEqual(AgentNamePool(names: ["  ", ""]).nextNames(count: 1, existing: []), ["ember"])
        XCTAssertEqual(AgentNamePool(names: [" Fox "]).nextNames(count: 1, existing: []), ["fox"])
    }

    func testResolverTrimsNewlinesFromTypedInput() {
        let id = UUID()
        let r = MediatorTargetResolver.resolve("ember\n", in: [(id, "ember")])
        XCTAssertEqual(r, .match(id))
    }
}
