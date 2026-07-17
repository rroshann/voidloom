import Foundation
import VoidloomCore

/// Decorates any `ResponseProvider` with mechanical reply validation against
/// live card titles. Invalid replies get one retry, then a grounded fallback;
/// `onComplete` always fires exactly once with a grounded string so persisted
/// history never stores hallucinated card names.
///
/// Streaming trade-off: invalid first-pass text may flash in the UI before
/// completion swaps in the retry/fallback — accepted for UI liveness.
@MainActor
final class ValidatingResponseProvider: ResponseProvider {
    private let underlying: ResponseProvider

    /// The wrapped provider — command phrasing uses this so it can apply its own
    /// sanitize → validate → fact path without receiving GroundedReplies fallbacks.
    var wrapped: ResponseProvider { underlying }

    /// Live card titles from `WorkspaceStore` — injected by RootView.
    var titles: () -> [String]
    var workspaceName: () -> String

    init(
        underlying: ResponseProvider,
        titles: @escaping () -> [String] = { [] },
        workspaceName: @escaping () -> String = { "Workspace" }
    ) {
        self.underlying = underlying
        self.titles = titles
        self.workspaceName = workspaceName
    }

    func generateResponse(
        workspaceID: UUID,
        userMessage: String,
        context: String?,
        onStreamChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        var finished = false
        let finish: (String) -> Void = { reply in
            guard !finished else { return }
            finished = true
            onComplete(reply)
        }
        let fail: (String) -> Void = { message in
            guard !finished else { return }
            finished = true
            onError(message)
        }

        underlying.generateResponse(
            workspaceID: workspaceID,
            userMessage: userMessage,
            context: context,
            onStreamChunk: onStreamChunk,
            onComplete: { [weak self] reply in
                guard let self else { return }
                let known = self.titles()
                if ReplyValidator.validate(reply: reply, knownTitles: known).isGrounded {
                    finish(reply)
                    return
                }

                // ONE retry — no streaming; earlier streamed text is replaced at completion.
                let list = known.isEmpty ? "none" : known.joined(separator: ", ")
                let reminder =
                    "\nReminder: the ONLY cards that exist are: \(list). Do not mention anything else."
                let retryContext = (context ?? "") + reminder
                self.underlying.generateResponse(
                    workspaceID: workspaceID,
                    userMessage: userMessage,
                    context: retryContext,
                    onStreamChunk: { _ in },
                    onComplete: { retryReply in
                        let knownAgain = self.titles()
                        if ReplyValidator.validate(reply: retryReply, knownTitles: knownAgain).isGrounded {
                            finish(retryReply)
                        } else {
                            self.underlying.resetConversation(workspaceID: workspaceID)
                            finish(
                                GroundedReplies.fallback(
                                    cardTitles: knownAgain,
                                    workspaceName: self.workspaceName()
                                )
                            )
                        }
                    },
                    onError: fail
                )
            },
            onError: fail
        )
    }

    func resetConversation(workspaceID: UUID) {
        underlying.resetConversation(workspaceID: workspaceID)
    }
}
