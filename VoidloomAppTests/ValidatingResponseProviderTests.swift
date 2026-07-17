import XCTest
import VoidloomCore
@testable import Voidloom

/// Scripted underlying provider: returns replies in order, records call counts.
@MainActor
private final class ScriptedResponseProvider: ResponseProvider {
    private var replies: [String]
    private var index = 0
    private(set) var generateCallCount = 0
    private(set) var resetCallCount = 0
    private(set) var lastContexts: [String?] = []
    /// When true, streams a single chunk before completing (first call only).
    var streamOnFirstCall = false

    init(replies: [String]) {
        self.replies = replies
    }

    func generateResponse(
        workspaceID: UUID,
        userMessage: String,
        context: String?,
        onStreamChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        generateCallCount += 1
        lastContexts.append(context)
        let reply = replies[min(index, replies.count - 1)]
        index += 1
        if streamOnFirstCall && generateCallCount == 1 {
            onStreamChunk(reply)
        }
        onComplete(reply)
    }

    func resetConversation(workspaceID: UUID) {
        resetCallCount += 1
    }
}

@MainActor
final class ValidatingResponseProviderTests: XCTestCase {
    private let workspaceID = UUID()

    func testInvalidThenValid_completesOnceWithRetryReply() {
        let invalid = "I can run the ember or nova terminals."
        let valid = "Your my ideas note looks good."
        let underlying = ScriptedResponseProvider(replies: [invalid, valid])
        underlying.streamOnFirstCall = true
        let provider = ValidatingResponseProvider(
            underlying: underlying,
            titles: { ["my ideas"] },
            workspaceName: { "QA" }
        )

        var completions: [String] = []
        var chunks: [String] = []
        provider.generateResponse(
            workspaceID: workspaceID,
            userMessage: "hi",
            context: "ctx",
            onStreamChunk: { chunks.append($0) },
            onComplete: { completions.append($0) },
            onError: { XCTFail("unexpected error: \($0)") }
        )

        XCTAssertEqual(completions, [valid], "exactly one completion with the valid retry reply")
        XCTAssertEqual(underlying.generateCallCount, 2)
        XCTAssertEqual(underlying.resetCallCount, 0)
        XCTAssertFalse(chunks.isEmpty, "first attempt still streams for UI liveness")
        // Retry context carries the reminder suffix.
        XCTAssertEqual(underlying.lastContexts.count, 2)
        if underlying.lastContexts.count >= 2 {
            let retryContext = underlying.lastContexts[1] ?? ""
            XCTAssertTrue(
                retryContext.contains("Reminder: the ONLY cards that exist are: my ideas")
            )
        }
    }

    func testInvalidThenInvalid_fallsBackAndResetsConversation() {
        let invalid = "Look at the Juno note."
        let underlying = ScriptedResponseProvider(replies: [invalid, invalid])
        let provider = ValidatingResponseProvider(
            underlying: underlying,
            titles: { [] },
            workspaceName: { "QA" }
        )

        var completions: [String] = []
        provider.generateResponse(
            workspaceID: workspaceID,
            userMessage: "hi",
            context: nil,
            onStreamChunk: { _ in },
            onComplete: { completions.append($0) },
            onError: { XCTFail("unexpected error: \($0)") }
        )

        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(underlying.resetCallCount, 1)
        XCTAssertEqual(underlying.generateCallCount, 2)
        let reply = completions[0]
        XCTAssertTrue(
            ReplyValidator.validate(reply: reply, knownTitles: []).isGrounded,
            "fallback must be grounded"
        )
        XCTAssertFalse(reply.localizedCaseInsensitiveContains("Juno"))
        // Reminder uses 'none' when there are no live titles.
        XCTAssertEqual(underlying.lastContexts.count, 2)
        if underlying.lastContexts.count >= 2 {
            let retryContext = underlying.lastContexts[1] ?? ""
            XCTAssertTrue(
                retryContext.contains("Reminder: the ONLY cards that exist are: none")
            )
        }
    }

    func testValidImmediately_noRetry() {
        let valid = "I made a note for you. The note is on page 2."
        let underlying = ScriptedResponseProvider(replies: [valid])
        let provider = ValidatingResponseProvider(
            underlying: underlying,
            titles: { ["my ideas"] },
            workspaceName: { "QA" }
        )

        var completions: [String] = []
        provider.generateResponse(
            workspaceID: workspaceID,
            userMessage: "hi",
            context: "ctx",
            onStreamChunk: { _ in },
            onComplete: { completions.append($0) },
            onError: { XCTFail("unexpected error: \($0)") }
        )

        XCTAssertEqual(completions, [valid])
        XCTAssertEqual(underlying.generateCallCount, 1, "no retry call on the underlying provider")
        XCTAssertEqual(underlying.resetCallCount, 0)
    }
}
