import Foundation
import VoidloomCore

/// Chat responder backed by a LARGER local model (Qwen3-1.7B), never the 0.6B
/// command model. Inference hops off the main actor; stream/complete/error
/// callbacks marshal back to @MainActor per the `ResponseProvider` contract.
/// The App only constructs this when the chat model is verified-ready; otherwise
/// chat stays on `StubResponseProvider`.
public final class LocalResponseProvider: ResponseProvider, @unchecked Sendable {
    private let engine: LlamaEngine
    private let systemPrompt: String
    @MainActor private var activeGenerations: [UUID: Task<Void, Never>] = [:]
    @MainActor private var generationTokens: [UUID: UUID] = [:]

    public init(engine: LlamaEngine, systemPrompt: String = LocalResponseProvider.defaultSystemPrompt) {
        self.engine = engine
        self.systemPrompt = systemPrompt
    }

    @MainActor
    public func generateResponse(workspaceID: UUID, userMessage: String, context: String?,
                                 onStreamChunk: @escaping (String) -> Void,
                                 onComplete: @escaping (String) -> Void,
                                 onError: @escaping (String) -> Void) {
        activeGenerations[workspaceID]?.cancel()

        let prompt = context.flatMap { $0.isEmpty ? nil : "Context:\n\($0)\n\n\(userMessage)" } ?? userMessage
        let callbacks = StreamCallbacks(
            onStreamChunk: onStreamChunk, onComplete: onComplete, onError: onError)
        let engine = self.engine
        let system = self.systemPrompt
        let token = UUID()
        generationTokens[workspaceID] = token

        let task = Task.detached(priority: .userInitiated) { [self, workspaceID, token] in
            defer {
                Task { @MainActor in
                    if generationTokens[workspaceID] == token {
                        activeGenerations.removeValue(forKey: workspaceID)
                        generationTokens.removeValue(forKey: workspaceID)
                    }
                }
            }
            var full = ""
            do {
                try engine.stream(systemPrompt: system, userPrompt: prompt) { chunk in
                    guard !Task.isCancelled else { return false }
                    full += chunk
                    callbacks.deliverChunk(chunk)
                    return !Task.isCancelled
                }
                guard !Task.isCancelled else { return }
                let final = full
                await callbacks.deliverComplete(final)
            } catch {
                guard !Task.isCancelled else { return }
                await callbacks.deliverError("The local model failed to respond.")
            }
        }
        activeGenerations[workspaceID] = task
    }

    public static let defaultSystemPrompt =
        "You are a concise, helpful assistant embedded in a macOS canvas app. Answer directly."
}

/// Crosses the detached inference task boundary; each delivery hops to @MainActor.
private final class StreamCallbacks: @unchecked Sendable {
    private let onStreamChunk: (String) -> Void
    private let onComplete: (String) -> Void
    private let onError: (String) -> Void

    init(onStreamChunk: @escaping (String) -> Void,
         onComplete: @escaping (String) -> Void,
         onError: @escaping (String) -> Void) {
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
