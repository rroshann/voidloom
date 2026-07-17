import Foundation
import FoundationModels
import VoidloomCore

/// Chat responder backed by Apple Intelligence. One `LanguageModelSession` per
/// workspace; inference runs off the main actor with the same per-workspace
/// cancellation semantics as `LocalResponseProvider`.
@available(macOS 26, *)
final class FoundationModelsResponseProvider: ResponseProvider, @unchecked Sendable {
    private let systemPrompt: String
    @MainActor private var activeGenerations: [UUID: Task<Void, Never>] = [:]
    @MainActor private var generationTokens: [UUID: UUID] = [:]
    @MainActor private var sessions: [UUID: LanguageModelSession] = [:]

    init(systemPrompt: String = FoundationModelsResponseProvider.defaultSystemPrompt) {
        self.systemPrompt = systemPrompt
    }

    @MainActor
    func generateResponse(
        workspaceID: UUID,
        userMessage: String,
        context: String?,
        onStreamChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        guard AppleTierAvailability.foundationModelsAvailable else {
            onError("Apple Intelligence isn't available right now.")
            return
        }

        activeGenerations[workspaceID]?.cancel()

        let prompt = context.flatMap { $0.isEmpty ? nil : "Context:\n\($0)\n\n\(userMessage)" } ?? userMessage
        let callbacks = FMStreamCallbacks(
            onStreamChunk: onStreamChunk, onComplete: onComplete, onError: onError)
        let session = session(for: workspaceID)
        let token = UUID()
        generationTokens[workspaceID] = token

        let task = Task.detached(priority: .userInitiated) { [self, session, token, workspaceID] in
            defer {
                Task { @MainActor in
                    if self.generationTokens[workspaceID] == token {
                        self.activeGenerations.removeValue(forKey: workspaceID)
                        self.generationTokens.removeValue(forKey: workspaceID)
                    }
                }
            }
            do {
                let stream = session.streamResponse(to: prompt)
                var previous = ""
                for try await snapshot in stream {
                    guard !Task.isCancelled else { return }
                    let current = snapshot.content
                    guard current.count >= previous.count else { continue }
                    let delta = String(current.dropFirst(previous.count))
                    previous = current
                    if !delta.isEmpty { callbacks.deliverChunk(delta) }
                }
                guard !Task.isCancelled else { return }
                await callbacks.deliverComplete(previous)
            } catch {
                guard !Task.isCancelled else { return }
                await callbacks.deliverError("Apple Intelligence failed to respond.")
            }
        }
        activeGenerations[workspaceID] = task
    }

    /// Drops the per-workspace session so its accumulated turn history is gone —
    /// the next message starts a fresh conversation. Backs "clear history".
    @MainActor
    func resetConversation(workspaceID: UUID) {
        sessions[workspaceID] = nil
    }

    @MainActor
    private func session(for workspaceID: UUID) -> LanguageModelSession {
        if let existing = sessions[workspaceID] { return existing }
        let created = LanguageModelSession(instructions: systemPrompt)
        if case .available = SystemLanguageModel.default.availability {
            created.prewarm()
        }
        sessions[workspaceID] = created
        return created
    }

    static let defaultSystemPrompt =
        "You are a concise, helpful assistant embedded in a macOS canvas app. Answer directly."
}

@available(macOS 26, *)
private final class FMStreamCallbacks: @unchecked Sendable {
    private let onStreamChunk: (String) -> Void
    private let onComplete: (String) -> Void
    private let onError: (String) -> Void

    init(
        onStreamChunk: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.onStreamChunk = onStreamChunk
        self.onComplete = onComplete
        self.onError = onError
    }

    func deliverChunk(_ token: String) {
        Task { @MainActor in onStreamChunk(token) }
    }

    func deliverComplete(_ text: String) async {
        await MainActor.run { onComplete(text) }
    }

    func deliverError(_ message: String) async {
        await MainActor.run { onError(message) }
    }
}
