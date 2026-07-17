import XCTest
import VoidloomCore
@testable import Voidloom

/// Records the `context` argument of each `generateResponse` call without
/// completing — keeps ConversationStore off the disk persist path.
@MainActor
private final class RecordingResponseProvider: ResponseProvider {
    private(set) var lastContext: String?
    private(set) var callCount = 0

    func generateResponse(
        workspaceID: UUID,
        userMessage: String,
        context: String?,
        onStreamChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        callCount += 1
        lastContext = context
    }
}

@MainActor
final class ConversationStoreTests: XCTestCase {
    func testRetryPassesFreshlyDerivedContextWhenProviderIsSet() throws {
        let provider = RecordingResponseProvider()
        let store = ConversationStore(provider: provider)
        let workspaceID = UUID()

        store.submit(workspaceID: workspaceID, text: "hello", context: "stale-original")
        let assistantID = try XCTUnwrap(
            store.messages(for: workspaceID).first(where: { $0.role == .assistant })?.id)

        var derivationCount = 0
        store.contextProvider = {
            derivationCount += 1
            return "fresh-context-\(derivationCount)"
        }

        store.retry(workspaceID: workspaceID, messageID: assistantID)

        XCTAssertEqual(provider.lastContext, "fresh-context-1")
        XCTAssertEqual(derivationCount, 1)

        // A second retry must re-derive, not reuse a cached snapshot.
        store.retry(workspaceID: workspaceID, messageID: assistantID)
        XCTAssertEqual(provider.lastContext, "fresh-context-2")
        XCTAssertEqual(derivationCount, 2)
    }
}
