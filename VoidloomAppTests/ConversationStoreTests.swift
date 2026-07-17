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

    func testRecentRecap_keepsNewestFourWithEarlierLabelsAndCharCap() throws {
        // Recording provider never completes — submit adds a settled user + pending
        // assistant, so we can seed an odd settled count.
        let provider = RecordingResponseProvider()
        let store = ConversationStore(provider: provider)
        let workspaceID = UUID()

        let long = String(repeating: "x", count: 200)
        store.record(workspaceID: workspaceID, userText: "user-0", assistantText: "asst-0-\(long)")
        store.record(workspaceID: workspaceID, userText: "user-1", assistantText: "asst-1-\(long)")
        // 4 settled so far; submit adds user-2 (settled) + pending assistant → 5 settled.
        store.submit(workspaceID: workspaceID, text: "user-2")

        let recap = try XCTUnwrap(store.recentRecap(for: workspaceID))
        let lines = recap.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        XCTAssertEqual(lines.count, 4, "only newest 4 settled messages appear")
        XCTAssertFalse(recap.contains("user-0"), "oldest settled message must be dropped")
        XCTAssertTrue(recap.contains("user-1"))
        XCTAssertTrue(recap.contains("asst-1"))
        XCTAssertTrue(recap.contains("user-2"))

        for line in lines {
            XCTAssertTrue(line.contains("(earlier)"), "each line labeled as earlier: \(line)")
            // Speaker label + ": " + body; body capped at 120 (+ optional ellipsis).
            let body = line.split(separator: ":", maxSplits: 1).last.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let withoutEllipsis = body.hasSuffix("…") ? String(body.dropLast()) : body
            XCTAssertLessThanOrEqual(withoutEllipsis.count, 120, "body ≤120 chars: \(body)")
        }
        XCTAssertTrue(lines.contains { $0.hasPrefix("User (earlier):") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("\(AssistantIdentity.name) (earlier):") })
    }
}
