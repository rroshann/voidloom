import XCTest
@testable import VoidloomCore

final class MediatorAgentKindTests: XCTestCase {
    func testAIKindsExcludeShell() {
        XCTAssertFalse(MediatorAgentKind.aiKinds.contains(.shell))
        XCTAssertTrue(MediatorAgentKind.aiKinds.contains(.claudeCode))
        XCTAssertTrue(MediatorAgentKind.aiKinds.contains(.cursor))
        XCTAssertTrue(MediatorAgentKind.shell.defaultLaunchCommand == nil)
        XCTAssertEqual(MediatorAgentKind.claudeCode.defaultLaunchCommand, "claude")
        XCTAssertEqual(MediatorAgentKind.cursor.defaultLaunchCommand, "cursor-agent")
    }

    func testPrintCommandIsShellSafeAndNilForShell() {
        XCTAssertEqual(MediatorAgentKind.claudeCode.printCommand(question: "how does X work"),
                       "claude -p 'how does X work'")
        XCTAssertEqual(MediatorAgentKind.codex.printCommand(question: "explain Y"),
                       "codex exec 'explain Y'")
        XCTAssertEqual(MediatorAgentKind.claudeCode.printCommand(question: "what's this"),
                       "claude -p 'what'\\''s this'")
        XCTAssertNil(MediatorAgentKind.shell.printCommand(question: "q"))
    }

    func testResolveProviderDefaultsToClaudeForBadOrShellValues() {
        XCTAssertEqual(MediatorAgentKind.resolveProvider(nil), .claudeCode)
        XCTAssertEqual(MediatorAgentKind.resolveProvider("nonsense"), .claudeCode)
        XCTAssertEqual(MediatorAgentKind.resolveProvider("shell"), .claudeCode)
        XCTAssertEqual(MediatorAgentKind.resolveProvider("codex"), .codex)
        XCTAssertEqual(MediatorAgentKind.resolveProvider("grok"), .grok)
    }
}
