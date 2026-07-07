import XCTest
@testable import VoidloomCore

@MainActor
final class AgentMemoryTests: XCTestCase {
    func testRecordsAndReportsLatestActivity() {
        let memory = AgentMemory()
        let id = UUID()
        memory.record(cardID: id, action: .spawned)
        XCTAssertEqual(memory.activity(for: id), "just started")
        memory.record(cardID: id, action: .received("fix the build"))
        XCTAssertEqual(memory.activity(for: id), "asked to fix the build")
    }

    func testRosterExcludesTheRecipientAndMarksIdleAgents() {
        let memory = AgentMemory()
        let ember = UUID(), slate = UUID(), nova = UUID()
        memory.record(cardID: ember, action: .received("fix the build"))
        memory.record(cardID: slate, action: .delegated("how does persistence work"))
        let roster = memory.roster(
            for: [(ember, "ember"), (slate, "slate"), (nova, "nova")], excluding: ember)
        XCTAssertFalse(roster.contains("ember:"))
        XCTAssertTrue(roster.contains("slate: looking into how does persistence work"))
        XCTAssertTrue(roster.contains("nova: idle"))
    }

    func testLongTextIsTrimmed() {
        let memory = AgentMemory()
        let id = UUID()
        memory.record(cardID: id, action: .received(String(repeating: "x", count: 200)))
        XCTAssertTrue(memory.activity(for: id)?.hasSuffix("…") == true)
        XCTAssertLessThan(memory.activity(for: id)?.count ?? 999, 80)
    }

    func testForgetRemovesAnAgent() {
        let memory = AgentMemory()
        let id = UUID()
        memory.record(cardID: id, action: .spawned)
        memory.forget(cardID: id)
        XCTAssertNil(memory.activity(for: id))
    }
}
