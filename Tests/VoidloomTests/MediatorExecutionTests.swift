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
