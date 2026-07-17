import Combine
import Foundation
import VoidloomCore

/// Per-workspace AI conversation state, persisted to disk.
///
/// Threads are keyed by workspace ID and saved as JSON under Application Support,
/// so a workspace's chat history — from BOTH the pill and the sidebar — survives
/// relaunches and is the same history the sidebar shows. Only settled messages
/// (user + completed assistant) are persisted; transient streaming/pending/failed
/// states are not. Each thread is capped so long-lived workspaces don't grow
/// unbounded in memory or on disk.
@MainActor
final class ConversationStore: ObservableObject {
    @Published private(set) var threads: [UUID: [ChatMessage]] = [:]
    private let provider: ResponseProvider

    /// Fresh workspace snapshot for retries — injected by RootView so a retry
    /// is grounded in the live canvas, not the (possibly stale) original turn.
    var contextProvider: (@MainActor () -> String?)?

    /// Keeps memory/disk bounded — the newest N messages per workspace are kept.
    private static let maxMessagesPerWorkspace = 300

    init(provider: ResponseProvider = StubResponseProvider()) {
        self.provider = provider
        threads = Self.loadFromDisk()
    }

    func messages(for workspaceID: UUID) -> [ChatMessage] { threads[workspaceID] ?? [] }
    func hasConversation(for workspaceID: UUID) -> Bool { !(threads[workspaceID]?.isEmpty ?? true) }

    /// A compact recap of the last few settled exchanges, for grounding the model
    /// so it recalls recent conversation — including across app launches, since
    /// history is persisted. Deliberately BOUNDED (few turns, each truncated) and
    /// labeled `(earlier)` so small models treat it as PAST, not live workspace
    /// state. Token/RAM cost stays small and fixed regardless of log length.
    func recentRecap(for workspaceID: UUID, maxMessages: Int = 4, perMessageChars: Int = 120) -> String? {
        let settled = (threads[workspaceID] ?? []).filter { $0.status == .sent || $0.status == .complete }
        guard !settled.isEmpty else { return nil }
        let recent = settled.suffix(maxMessages)
        let lines = recent.map { msg -> String in
            let who = msg.role == .user
                ? "User (earlier)"
                : "\(AssistantIdentity.name) (earlier)"
            let text = msg.text.count > perMessageChars
                ? String(msg.text.prefix(perMessageChars)) + "…"
                : msg.text
            return "\(who): \(text)"
        }
        return lines.joined(separator: "\n")
    }

    func submit(workspaceID: UUID, text: String, context: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let assistantID = UUID()
        threads[workspaceID] = ConversationReducer.appendingUserAndPendingAssistant(
            threads[workspaceID] ?? [], userText: trimmed, assistantID: assistantID)
        request(workspaceID: workspaceID, userMessage: trimmed, assistantID: assistantID, context: context)
    }

    /// Records an exchange that was answered elsewhere (the pill's chat fallback
    /// already streamed the reply into the HUD) so it joins the sidebar history.
    func record(workspaceID: UUID, userText: String, assistantText: String) {
        let user = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reply = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !reply.isEmpty else { return }
        var thread = threads[workspaceID] ?? []
        thread.append(ChatMessage(role: .user, text: user, status: .sent))
        thread.append(ChatMessage(role: .assistant, text: reply, status: .complete))
        threads[workspaceID] = thread
        persist()
    }

    /// Wipes a workspace's history AND tells the backend to forget it, so after a
    /// clear Sunday no longer references the prior conversation.
    func clear(workspaceID: UUID) {
        threads[workspaceID] = []
        provider.resetConversation(workspaceID: workspaceID)
        persist()
    }

    func retry(workspaceID: UUID, messageID: UUID) {
        let thread = threads[workspaceID] ?? []
        guard let userText = ConversationReducer.userText(before: messageID, in: thread) else { return }
        threads[workspaceID] = ConversationReducer.resettingToPending(thread, messageID: messageID)
        request(workspaceID: workspaceID, userMessage: userText, assistantID: messageID,
                context: contextProvider?())
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
                self.persist()
            },
            onError: { [weak self] err in
                guard let self else { return }
                self.threads[workspaceID] = ConversationReducer.failing(
                    self.threads[workspaceID] ?? [], messageID: assistantID, error: err)
            })
    }

    // MARK: - Persistence

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voidloom", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("conversations.json")
    }

    /// Only settled messages are worth persisting; transient states are dropped.
    private struct PersistedMessage: Codable {
        var id: UUID
        var role: String
        var text: String
        var timestamp: Date
    }

    /// Honors the Settings toggle "Persist conversations to disk" (default on).
    private static var persistenceEnabled: Bool {
        UserDefaults.standard.object(forKey: "conversations.persist") as? Bool ?? true
    }

    private func persist() {
        guard Self.persistenceEnabled else {
            // Respect an opt-out: stop writing and remove any prior on-disk copy.
            let url = Self.storeURL
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: url) }
            return
        }
        // Snapshot the persistable subset on the main actor, then write off-thread.
        let snapshot: [UUID: [PersistedMessage]] = threads.reduce(into: [:]) { acc, entry in
            let settled = entry.value.compactMap { msg -> PersistedMessage? in
                switch msg.status {
                case .sent, .complete:
                    return PersistedMessage(id: msg.id, role: msg.role == .user ? "user" : "assistant",
                                            text: msg.text, timestamp: msg.timestamp)
                default:
                    return nil   // pending / streaming / failed are transient
                }
            }
            guard !settled.isEmpty else { return }
            acc[entry.key] = Array(settled.suffix(Self.maxMessagesPerWorkspace))
        }
        let url = Self.storeURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func loadFromDisk() -> [UUID: [ChatMessage]] {
        guard persistenceEnabled,
              let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([UUID: [PersistedMessage]].self, from: data)
        else { return [:] }
        return decoded.mapValues { msgs in
            msgs.map { m in
                let role: ChatRole = m.role == "user" ? .user : .assistant
                return ChatMessage(id: m.id, role: role, text: m.text,
                                   status: role == .user ? .sent : .complete, timestamp: m.timestamp)
            }
        }
    }
}
