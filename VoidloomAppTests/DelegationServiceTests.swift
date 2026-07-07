import XCTest
import VoidloomCore
@testable import Voidloom

private struct FakeRunner: AgentCommandRunning {
    let result: Result<String, Error>
    func run(_ command: String, in directory: String?, timeout: TimeInterval) async throws -> String {
        try result.get()
    }
}

@MainActor
final class DelegationServiceTests: XCTestCase {
    private func makeStore() -> WorkspaceStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return WorkspaceStore(state: WorkspaceState(), storageURL: url, persistenceDelay: 60)
    }

    override func setUp() { UserDefaults.standard.removeObject(forKey: "agent.provider") }

    func testSuccessfulAnswerIsAttributedToTheTarget() async {
        let service = DelegationService(store: makeStore(),
            runner: FakeRunner(result: .success("Persistence is debounced per workspace.")))
        let answer = await service.delegate(question: "how does persistence work", target: "ember") { _ in }
        XCTAssertEqual(answer, "ember (Claude): Persistence is debounced per workspace.")
    }

    func testNoTargetAttributesToTheProviderName() async {
        let service = DelegationService(store: makeStore(),
            runner: FakeRunner(result: .success("Answer.")))
        let answer = await service.delegate(question: "q", target: nil) { _ in }
        XCTAssertEqual(answer, "Claude: Answer.")
    }

    func testMissingCLIExplainsHowToFixInsteadOfCrashing() async {
        let service = DelegationService(store: makeStore(),
            runner: FakeRunner(result: .failure(AgentCommandError.commandNotFound)))
        let answer = await service.delegate(question: "q", target: nil) { _ in }
        XCTAssertTrue(answer.contains("isn't installed"), answer)
    }

    func testTimeoutIsSurfacedNotSwallowed() async {
        let service = DelegationService(store: makeStore(),
            runner: FakeRunner(result: .failure(AgentCommandError.timedOut)), timeout: 5)
        let answer = await service.delegate(question: "q", target: "ember") { _ in }
        XCTAssertTrue(answer.contains("still working"), answer)
    }

    func testCodexProviderSettingChangesAttribution() async {
        UserDefaults.standard.set("codex", forKey: "agent.provider")
        let service = DelegationService(store: makeStore(),
            runner: FakeRunner(result: .success("Done.")))
        let answer = await service.delegate(question: "q", target: nil) { _ in }
        XCTAssertEqual(answer, "Codex: Done.")
    }

    func testLongAnswerIsCappedWithPointer() {
        let long = (1...50).map { "line \($0)" }.joined(separator: "\n")
        let cleaned = DelegationService.clean(long, maxLines: 30)
        XCTAssertTrue(cleaned.contains("line 30"))
        XCTAssertFalse(cleaned.contains("line 31"))
        XCTAssertTrue(cleaned.contains("full answer from the CLI"))
    }

    func testAnsiEscapesAreStripped() {
        let ansi = "\u{1B}[1mBold\u{1B}[0m and \u{1B}[31mred\u{1B}[0m"
        XCTAssertEqual(DelegationService.clean(ansi, maxLines: 30), "Bold and red")
    }
}
