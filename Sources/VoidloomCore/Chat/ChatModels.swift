// Sources/VoidloomCore/Chat/ChatModels.swift
import Foundation

public enum ChatRole: Sendable, Equatable { case user, assistant }

public enum MessageStatus: Sendable, Equatable {
    case sent, pending, streaming(String), complete, failed(String)
}

public struct ChatMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let role: ChatRole
    public let text: String
    public let status: MessageStatus
    public let timestamp: Date

    public init(id: UUID = UUID(), role: ChatRole, text: String,
                status: MessageStatus = .sent, timestamp: Date = Date()) {
        self.id = id; self.role = role; self.text = text
        self.status = status; self.timestamp = timestamp
    }

    public var isStreaming: Bool { if case .streaming = status { return true }; return false }
    public var isPending: Bool { role == .assistant && (status == .pending || isStreaming) }
    public var streamingText: String? { if case .streaming(let s) = status { return s }; return nil }
}

/// Pure transforms over a conversation thread. Deterministic — IDs passed in.
public enum ConversationReducer {
    public static func appendingUserAndPendingAssistant(_ thread: [ChatMessage], userText: String, assistantID: UUID) -> [ChatMessage] {
        var t = thread
        t.append(ChatMessage(role: .user, text: userText, status: .sent))
        t.append(ChatMessage(id: assistantID, role: .assistant, text: "", status: .pending))
        return t
    }
    public static func appendingStreamChunk(_ thread: [ChatMessage], messageID: UUID, chunk: String) -> [ChatMessage] {
        replace(thread, messageID) { m in
            let partial = (m.streamingText ?? "") + chunk
            return ChatMessage(id: m.id, role: m.role, text: partial, status: .streaming(partial), timestamp: m.timestamp)
        }
    }
    public static func completing(_ thread: [ChatMessage], messageID: UUID, text: String) -> [ChatMessage] {
        replace(thread, messageID) { m in
            ChatMessage(id: m.id, role: m.role, text: text, status: .complete, timestamp: m.timestamp)
        }
    }
    public static func failing(_ thread: [ChatMessage], messageID: UUID, error: String) -> [ChatMessage] {
        replace(thread, messageID) { m in
            ChatMessage(id: m.id, role: m.role, text: error, status: .failed(error), timestamp: m.timestamp)
        }
    }
    public static func resettingToPending(_ thread: [ChatMessage], messageID: UUID) -> [ChatMessage] {
        replace(thread, messageID) { m in
            ChatMessage(id: m.id, role: m.role, text: "", status: .pending, timestamp: m.timestamp)
        }
    }
    public static func userText(before messageID: UUID, in thread: [ChatMessage]) -> String? {
        guard let idx = thread.firstIndex(where: { $0.id == messageID }), idx > 0,
              thread[idx - 1].role == .user else { return nil }
        return thread[idx - 1].text
    }

    private static func replace(_ thread: [ChatMessage], _ id: UUID, _ transform: (ChatMessage) -> ChatMessage) -> [ChatMessage] {
        guard let idx = thread.firstIndex(where: { $0.id == id }) else { return thread }
        var t = thread; t[idx] = transform(t[idx]); return t
    }
}

/// Backend seam. A stub conforms today; a real LLM replaces it later — no view changes.
public protocol ResponseProvider: AnyObject, Sendable {
    @MainActor func generateResponse(
        workspaceID: UUID,
        userMessage: String,
        onStreamChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    )
}
