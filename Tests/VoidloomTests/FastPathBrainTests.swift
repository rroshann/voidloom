import XCTest
@testable import VoidloomCore

final class FastPathBrainTests: XCTestCase {
    private func parse(_ utterance: String) async throws -> MediatorCommand {
        try await FastPathBrain().command(for: utterance)
    }

    func testSpawnPhrasings() async throws {
        let a = try await parse("start 4 claude agents")
        XCTAssertEqual(a, .spawnAgents(count: 4, kind: .claudeCode, names: nil))
        let b = try await parse("spawn two shell terminals named fox and owl")
        XCTAssertEqual(b, .spawnAgents(count: 2, kind: .shell, names: ["fox", "owl"]))
        let c = try await parse("open a claude agent")
        XCTAssertEqual(c, .spawnAgents(count: 1, kind: .claudeCode, names: nil))
    }

    func testPromptRoutingPhrasings() async throws {
        let a = try await parse("ask ember to look into the api errors")
        XCTAssertEqual(a, .sendPrompt(target: "ember", text: "look into the api errors"))
        let b = try await parse("tell slate run the tests")
        XCTAssertEqual(b, .sendPrompt(target: "slate", text: "run the tests"))
    }

    func testReadCloseAndFocus() async throws {
        let read = try await parse("show ember's output")
        XCTAssertEqual(read, .readOutput(target: "ember"))
        let close = try await parse("close ember")
        XCTAssertEqual(close, .closeTerminal(target: "ember"))
        let focus = try await parse("focus on slate")
        XCTAssertEqual(focus, .arrange(style: .focus(target: "slate")))
    }

    func testArrangeSwitchBackgroundAndCards() async throws {
        let retile = try await parse("re-tile")
        XCTAssertEqual(retile, .arrange(style: .retile))
        let grid = try await parse("arrange in a grid")
        XCTAssertEqual(grid, .arrange(style: .grid))
        let sw = try await parse("switch to research")
        XCTAssertEqual(sw, .switchSpace(name: "research"))
        let solid = try await parse("background #102030FF")
        XCTAssertEqual(solid, .setBackground(spec: .solid(hex: "#102030FF")))
        let atmo = try await parse("background atmosphere")
        XCTAssertEqual(atmo, .setBackground(spec: .atmosphere))
        let note = try await parse("note: buy milk")
        XCTAssertEqual(note, .createCard(kind: .note, content: "buy milk"))
        let todo = try await parse("todo")
        XCTAssertEqual(todo, .createCard(kind: .todo, content: nil))
    }

    func testUnparseableUtterancesThrow() async {
        for bad in ["", "do the thing", "spawn zero agents", "ask", "switch"] {
            do {
                _ = try await parse(bad)
                XCTFail("expected unparseable for: \(bad)")
            } catch let error as BrainError {
                if case .unparseable = error { continue }
                XCTFail("wrong error for: \(bad)")
            } catch {
                XCTFail("unexpected error type for: \(bad)")
            }
        }
    }

    func testAgentLiterallyNamedShellStaysClaudeKind() async throws {
        // "shell" as a NAME must not flip the process kind (carry-over #5).
        let a = try await FastPathBrain().command(for: "spawn a claude agent named shell")
        XCTAssertEqual(a, .spawnAgents(count: 1, kind: .claudeCode, names: ["shell"]))
        // "shell" as the KIND word still selects a shell terminal.
        let b = try await FastPathBrain().command(for: "spawn 2 shell terminals")
        XCTAssertEqual(b, .spawnAgents(count: 2, kind: .shell, names: nil))
        // Explicit shell kind AND a shell name together: kind shell, name preserved.
        let c = try await FastPathBrain().command(for: "spawn a shell named shell")
        XCTAssertEqual(c, .spawnAgents(count: 1, kind: .shell, names: ["shell"]))
    }
}
