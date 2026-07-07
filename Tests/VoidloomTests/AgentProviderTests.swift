import XCTest
@testable import VoidloomCore

final class AgentProviderTests: XCTestCase {
    func testDefaultIsClaude() {
        XCTAssertEqual(AgentProvider.default, .claude)
        XCTAssertEqual(AgentProvider.resolve(nil), .claude)
        XCTAssertEqual(AgentProvider.resolve("nonsense"), .claude)
        XCTAssertEqual(AgentProvider.resolve("codex"), .codex)
    }

    func testPrintCommandIsShellSafe() {
        XCTAssertEqual(AgentProvider.claude.printCommand(question: "how does X work"),
                       "claude -p 'how does X work'")
        XCTAssertEqual(AgentProvider.codex.printCommand(question: "explain Y"),
                       "codex exec 'explain Y'")
        // Embedded single quote is escaped, so the shell can't break out.
        XCTAssertEqual(AgentProvider.claude.printCommand(question: "what's this"),
                       "claude -p 'what'\\''s this'")
    }

    func testLaunchCommands() {
        XCTAssertEqual(AgentProvider.claude.launchCommand, "claude")
        XCTAssertEqual(AgentProvider.codex.launchCommand, "codex")
    }
}
