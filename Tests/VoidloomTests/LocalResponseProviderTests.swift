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
}
