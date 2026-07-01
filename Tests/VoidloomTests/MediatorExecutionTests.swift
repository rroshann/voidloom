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
        let names = pool.nextNames(count: 2, existing: ["Viper", "OMEN"])
        XCTAssertEqual(names, ["phoenix", "sage"])
    }

    func testExhaustedPoolAppendsNumericSuffixes() {
        let pool = AgentNamePool(names: ["viper", "omen"])
        let names = pool.nextNames(count: 3, existing: ["viper"])
        XCTAssertEqual(names, ["omen", "viper-2", "omen-2"])
    }

    func testCustomPackReplacesDefaults() {
        let pool = AgentNamePool(names: ["jett", "sage"])
        XCTAssertEqual(pool.nextNames(count: 1, existing: []), ["jett"])
    }
}
