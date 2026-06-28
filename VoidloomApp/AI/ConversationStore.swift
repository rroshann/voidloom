import Combine
import Foundation

/// One message in an AI conversation thread.
enum ChatRole {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let text: String

    init(id: UUID = UUID(), role: ChatRole, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// In-memory, per-workspace AI conversation state.
///
/// Conversations are session-only — they are keyed by workspace ID and are NOT
/// persisted, so they clear when the app restarts. No backend is wired yet:
/// `submit` echoes the user's message and appends a fixed placeholder reply.
@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var threads: [UUID: [ChatMessage]] = [:]

    private let placeholderReply = "✨ AI backend isn't connected yet — this is where responses will appear."

    func messages(for workspaceID: UUID) -> [ChatMessage] {
        threads[workspaceID] ?? []
    }

    func hasConversation(for workspaceID: UUID) -> Bool {
        !(threads[workspaceID]?.isEmpty ?? true)
    }

    func submit(workspaceID: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var thread = threads[workspaceID] ?? []
        thread.append(ChatMessage(role: .user, text: trimmed))
        thread.append(ChatMessage(role: .assistant, text: placeholderReply))
        threads[workspaceID] = thread
    }
}
