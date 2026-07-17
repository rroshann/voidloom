import XCTest
@testable import VoidloomAI
@testable import VoidloomCore

private final class FakeEngine: LlamaEngine, @unchecked Sendable {
    var completion: Result<String, Error>
    var lastGrammar: String?
    init(_ completion: Result<String, Error>) { self.completion = completion }
    func load(modelPath: URL, config: LlamaEngineConfig) throws {}
    func unload() {}
    func complete(systemPrompt: String, userPrompt: String, grammar: String?, maxTokens: Int) throws -> String {
        lastGrammar = grammar
        return try completion.get()
    }
    func stream(systemPrompt: String, userPrompt: String, onToken: @escaping (String) -> Bool) throws {}
}

final class LlamaBrainTests: XCTestCase {
    func testDecodesGrammarConstrainedJSONIntoCommand() async throws {
        let engine = FakeEngine(.success(#"{"spawnAgents":{"count":2,"kind":"claude"}}"#))
        let brain = LlamaBrain(engine: engine)
        let cmd = try await brain.command(for: "spin up a couple agents")
        XCTAssertEqual(cmd, .spawnAgents(count: 2, kind: .claudeCode, names: nil))
        XCTAssertEqual(engine.lastGrammar, MediatorGrammar.rootGrammar)
    }

    func testNonJSONOutputThrowsUnparseable() async {
        let brain = LlamaBrain(engine: FakeEngine(.success("I think you meant to spawn agents")))
        await XCTAssertThrowsBrainError(.unparseable("")) { try await brain.command(for: "x") }
    }

    func testAbstainSentinelThrowsUnparseableSoChatCanAnswer() async {
        // The grammar can emit {"none":{}} for non-commands; it has no command
        // case, so it surfaces as .unparseable and the utterance goes to chat.
        let brain = LlamaBrain(engine: FakeEngine(.success(#"{"none":{}}"#)))
        await XCTAssertThrowsBrainError(.unparseable("")) { try await brain.command(for: "what cards are open") }
    }

    func testEngineFailureMapsToBackendFailure() async {
        let brain = LlamaBrain(engine: FakeEngine(.failure(LlamaBrainStubError.boom)))
        do { _ = try await brain.command(for: "x"); XCTFail() }
        catch let e as BrainError { if case .backendFailure = e {} else { XCTFail("got \(e)") } }
        catch { XCTFail("wrong type") }
    }

    func testEngineBrainErrorPassesThroughUnchanged() async {
        let brain = LlamaBrain(engine: FakeEngine(.failure(BrainError.modelNotReady("not on disk"))))
        await XCTAssertThrowsBrainError(.modelNotReady("")) { try await brain.command(for: "x") }
    }
}

enum LlamaBrainStubError: Error { case boom }

func XCTAssertThrowsBrainError(
    _ expected: BrainError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        XCTFail("expected BrainError", file: file, line: line)
    } catch let error as BrainError {
        switch (expected, error) {
        case (.unparseable, .unparseable),
             (.backendFailure, .backendFailure),
             (.modelNotReady, .modelNotReady),
             (.modelDownloading, .modelDownloading):
            return
        default:
            XCTFail("got \(error), expected \(expected)", file: file, line: line)
        }
    } catch {
        XCTFail("wrong type: \(error)", file: file, line: line)
    }
}
