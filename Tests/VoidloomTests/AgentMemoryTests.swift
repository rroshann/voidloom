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

    func testBriefingPrefixGivesCrossAgentContextOnceThenStopsRepeating() {
        let memory = AgentMemory()
        let ember = UUID(), nova = UUID()
        memory.record(cardID: nova, action: .received("fix auth"))
        let agents = [(ember, "ember"), (nova, "nova")]
        // First task to ember auto-briefs it on nova; second task does not repeat.
        let first = memory.briefingPrefix(for: ember, amongst: agents)
        XCTAssertTrue(first.contains("nova: asked to fix auth"))
        XCTAssertFalse(first.contains("ember:"))
        XCTAssertEqual(memory.briefingPrefix(for: ember, amongst: agents), "")
    }

    func testBriefingPrefixIsEmptyWhenSoleThenBriefsOnceOthersExist() {
        let memory = AgentMemory()
        let ember = UUID()
        // Sole agent: nothing to brief, and NOT yet marked briefed.
        XCTAssertEqual(memory.briefingPrefix(for: ember, amongst: [(ember, "ember")]), "")
        // Once nova exists, ember's next task briefs it once.
        let nova = UUID()
        memory.record(cardID: nova, action: .spawned)
        let prefix = memory.briefingPrefix(for: ember, amongst: [(ember, "ember"), (nova, "nova")])
        XCTAssertTrue(prefix.contains("nova"))
    }

    func testForgetLetsAnAgentBeReBriefed() {
        let memory = AgentMemory()
        let ember = UUID(), nova = UUID()
        memory.record(cardID: nova, action: .spawned)
        let agents = [(ember, "ember"), (nova, "nova")]
        _ = memory.briefingPrefix(for: ember, amongst: agents)   // brief once
        memory.forget(cardID: ember)                              // ember removed
        // A brand-new agent reusing nothing should brief again.
        XCTAssertFalse(memory.briefingPrefix(for: ember, amongst: agents).isEmpty)
    }
}
