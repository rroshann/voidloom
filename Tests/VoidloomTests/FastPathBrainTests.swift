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

    func testSendPromptPreservesPayloadCase() async throws {
        // Prompts route into real shells; case corruption breaks commands.
        let a = try await parse("ask ember to echo QA_ROUTE_OK")
        XCTAssertEqual(a, .sendPrompt(target: "ember", text: "echo QA_ROUTE_OK"))
        // Verb and target matching stay case-insensitive.
        let b = try await parse("Ask Ember to cat README.md")
        XCTAssertEqual(b, .sendPrompt(target: "ember", text: "cat README.md"))
    }

    func testCreateCardContentPreservesCase() async throws {
        let a = try await parse("note: Buy MILK on Monday")
        XCTAssertEqual(a, .createCard(kind: .note, content: "Buy MILK on Monday"))
        let b = try await parse("Todo: Review PR #8")
        XCTAssertEqual(b, .createCard(kind: .todo, content: "Review PR #8"))
    }

    // MARK: - Phase B: card CRUD verbs

    func testRenameCardPreservesNewNameCase() async throws {
        let a = try await parse("rename ember to Scout")
        XCTAssertEqual(a, .renameCard(target: "ember", newName: "Scout"))
        let b = try await parse("Rename New Note to Sprint Plan")
        XCTAssertEqual(b, .renameCard(target: "New Note", newName: "Sprint Plan"))
    }

    func testDeleteAndRemoveMapToDeleteCard() async throws {
        let a = try await parse("delete New Note")
        XCTAssertEqual(a, .deleteCard(target: "New Note"))
        let b = try await parse("remove chores")
        XCTAssertEqual(b, .deleteCard(target: "chores"))
    }

    func testAppendToNoteSetsAppendTrueAndPreservesCase() async throws {
        let a = try await parse("append Ship IT to standup")
        XCTAssertEqual(a, .editNote(target: "standup", content: "Ship IT", append: true))
    }

    func testAddToTodoMapsToAddTodoItem() async throws {
        let a = try await parse("add Buy Milk to chores")
        XCTAssertEqual(a, .addTodoItem(target: "chores", text: "Buy Milk"))
    }

    func testCheckAndUncheckMapToSetTodoItemDone() async throws {
        let checked = try await parse("check buy milk in chores")
        XCTAssertEqual(checked, .setTodoItemDone(target: "chores", text: "buy milk", done: true))
        let unchecked = try await parse("uncheck buy milk in chores")
        XCTAssertEqual(unchecked, .setTodoItemDone(target: "chores", text: "buy milk", done: false))
    }

    // MARK: - Phase C: delegation

    func testAskAboutDelegatesWhileAskToStillSendsPrompt() async throws {
        let deleg = try await parse("ask ember about how does persistence work")
        XCTAssertEqual(deleg, .delegate(question: "how does persistence work", target: "ember"))
        let prompt = try await parse("ask ember to fix the build")
        XCTAssertEqual(prompt, .sendPrompt(target: "ember", text: "fix the build"))
    }

    func testResearchAndDelegateVerbsDelegateWithoutATarget() async throws {
        let a = try await parse("research how the debounce works")
        XCTAssertEqual(a, .delegate(question: "how the debounce works", target: nil))
        let b = try await parse("delegate summarize the persistence layer")
        XCTAssertEqual(b, .delegate(question: "summarize the persistence layer", target: nil))
    }

    func testCrudVerbsNeedTheirConnectorsElseUnparseable() async {
        // No " to " / " in " → FastPath abstains and llama/chat handles it.
        for bad in ["rename ember", "append ship it", "add buy milk", "check buy milk"] {
            do { _ = try await parse(bad); XCTFail("\(bad) should be unparseable") }
            catch let e as BrainError { if case .unparseable = e {} else { XCTFail("\(bad) -> \(e)") } }
            catch { XCTFail("wrong error for \(bad)") }
        }
    }
}
