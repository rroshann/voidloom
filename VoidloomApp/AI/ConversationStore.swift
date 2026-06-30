import Combine
import Foundation
import VoidloomCore

/// In-memory, per-workspace AI conversation state.
///
/// Conversations are session-only — they are keyed by workspace ID and are NOT
/// persisted, so they clear when the app restarts. The provider drives all
/// loading/streaming/error state transitions via `ConversationReducer`.
@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var threads: [UUID: [ChatMessage]] = [:]
    private let provider: ResponseProvider

    init(provider: ResponseProvider = StubResponseProvider()) { self.provider = provider }

    func messages(for workspaceID: UUID) -> [ChatMessage] { threads[workspaceID] ?? [] }
    func hasConversation(for workspaceID: UUID) -> Bool { !(threads[workspaceID]?.isEmpty ?? true) }

    func submit(workspaceID: UUID, text: String, context: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let assistantID = UUID()
        threads[workspaceID] = ConversationReducer.appendingUserAndPendingAssistant(
            threads[workspaceID] ?? [], userText: trimmed, assistantID: assistantID)
        request(workspaceID: workspaceID, userMessage: trimmed, assistantID: assistantID, context: context)
    }

    func retry(workspaceID: UUID, messageID: UUID) {
        let thread = threads[workspaceID] ?? []
        guard let userText = ConversationReducer.userText(before: messageID, in: thread) else { return }
        threads[workspaceID] = ConversationReducer.resettingToPending(thread, messageID: messageID)
        // NOTE: retry passes nil context (v1 — context is not re-derived on retry)
        request(workspaceID: workspaceID, userMessage: userText, assistantID: messageID, context: nil)
    }

    private func request(workspaceID: UUID, userMessage: String, assistantID: UUID, context: String? = nil) {
        provider.generateResponse(
            workspaceID: workspaceID, userMessage: userMessage,
            context: context,
            onStreamChunk: { [weak self] chunk in
                guard let self else { return }
                self.threads[workspaceID] = ConversationReducer.appendingStreamChunk(
                    self.threads[workspaceID] ?? [], messageID: assistantID, chunk: chunk)
            },
            onComplete: { [weak self] text in
                guard let self else { return }
                self.threads[workspaceID] = ConversationReducer.completing(
                    self.threads[workspaceID] ?? [], messageID: assistantID, text: text)
            },
            onError: { [weak self] err in
                guard let self else { return }
                self.threads[workspaceID] = ConversationReducer.failing(
                    self.threads[workspaceID] ?? [], messageID: assistantID, error: err)
            })
    }
}
