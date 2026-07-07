import XCTest
@testable import VoidloomAI
@testable import VoidloomCore

private final class StreamingFakeEngine: LlamaEngine, @unchecked Sendable {
    let tokens: [String]
    init(tokens: [String]) { self.tokens = tokens }
    func load(modelPath: URL, config: LlamaEngineConfig) throws {}
    func unload() {}
    func complete(systemPrompt: String, userPrompt: String, grammar: String?, maxTokens: Int) throws -> String { tokens.joined() }
    func stream(systemPrompt: String, userPrompt: String, onToken: @escaping (String) -> Bool) throws {
        for t in tokens where onToken(t) {}
    }
}

/// Blocks mid-stream until released; polls `Task.isCancelled` while waiting.
private final class StallableFakeEngine: LlamaEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var stallGate: DispatchSemaphore?
    private var armStall = false
    private var stallTokens: [String] = []
    private var resumeTokens: [String] = []
    private var plainTokens: [String] = ["B1", "B2"]

    func armStall(tokens: [String], resumeWith tokensAfterRelease: [String]) {
        lock.lock()
        armStall = true
        stallTokens = tokens
        resumeTokens = tokensAfterRelease
        stallGate = DispatchSemaphore(value: 0)
        lock.unlock()
    }

    func releaseStall() {
        lock.lock()
        stallGate?.signal()
        lock.unlock()
    }

    func load(modelPath: URL, config: LlamaEngineConfig) throws {}
    func unload() {}

    func complete(systemPrompt: String, userPrompt: String, grammar: String?, maxTokens: Int) throws -> String {
        plainTokens.joined()
    }

    func stream(systemPrompt: String, userPrompt: String, onToken: @escaping (String) -> Bool) throws {
        lock.lock()
        let shouldStall = armStall
        let gate = stallGate
        let leading = stallTokens
        let trailing = resumeTokens
        let tokens = plainTokens
        if shouldStall {
            armStall = false
            stallTokens = []
            resumeTokens = []
            stallGate = nil
        }
        lock.unlock()

        if shouldStall {
            for token in leading {
                guard onToken(token) else { return }
            }
            guard waitForReleaseOrCancel(gate) else { return }
            for token in trailing {
                guard onToken(token) else { return }
            }
            return
        }

        for token in tokens where onToken(token) {}
    }

    private func waitForReleaseOrCancel(_ gate: DispatchSemaphore?) -> Bool {
        guard let gate else { return true }
        while true {
            if gate.wait(timeout: .now() + 0.02) == .success { return true }
            if Task.isCancelled { return false }
        }
    }
}

@MainActor
final class LocalResponseProviderTests: XCTestCase {
    func testStreamsChunksThenCompletes() async {
        let provider = LocalResponseProvider(engine: StreamingFakeEngine(tokens: ["Hel", "lo", "!"]), systemPrompt: "")
        var chunks: [String] = []; var final = ""
        let done = expectation(description: "done")
        provider.generateResponse(workspaceID: UUID(), userMessage: "hi", context: nil,
            onStreamChunk: { chunks.append($0) },
            onComplete: { final = $0; done.fulfill() },
            onError: { _ in XCTFail() })
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(chunks, ["Hel", "lo", "!"])
        XCTAssertEqual(final, "Hello!")
    }

    func testSupersededGenerationDeliversNoCompletion() async {
        let engine = StallableFakeEngine()
        engine.armStall(tokens: ["A1"], resumeWith: ["A2"])
        let provider = LocalResponseProvider(engine: engine, systemPrompt: "")
        let workspaceID = UUID()

        var aCompleted = false
        var aErrored = false
        let aStalled = expectation(description: "a stalled after first token")

        provider.generateResponse(workspaceID: workspaceID, userMessage: "first", context: nil,
            onStreamChunk: { _ in aStalled.fulfill() },
            onComplete: { _ in aCompleted = true },
            onError: { _ in aErrored = true })

        await fulfillment(of: [aStalled], timeout: 5)

        var bFinal = ""
        let bDone = expectation(description: "b done")
        provider.generateResponse(workspaceID: workspaceID, userMessage: "second", context: nil,
            onStreamChunk: { _ in },
            onComplete: { bFinal = $0; bDone.fulfill() },
            onError: { _ in XCTFail("B should not error") })

        engine.releaseStall()

        await fulfillment(of: [bDone], timeout: 5)
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(aCompleted, "superseded generation A must not complete")
        XCTAssertFalse(aErrored, "superseded generation A must not error")
        XCTAssertEqual(bFinal, "B1B2")
    }
}
