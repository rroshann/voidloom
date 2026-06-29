import Foundation
import VoidloomCore

/// Simulates latency + word-by-word streaming so the sidebar's loading/streaming/error
/// states are visible without a real backend.
///
/// - Parameters:
///   - simulateStreaming: When true (default), streams the reply word-by-word.
///     When false, calls `onComplete` immediately after the initial delay.
///   - failEvery: When non-nil, every N-th call to `generateResponse` (where
///     `counter % failEvery == 0`) calls `onError("Simulated failure (QA)")` and
///     returns early. Defaults to nil (never fail), preserving normal behaviour.
@MainActor
final class StubResponseProvider: ResponseProvider {
    private let reply = "✨ AI backend isn't connected yet — this is where responses will appear."
    private let simulateStreaming: Bool
    private let failEvery: Int?
    private var counter = 0

    init(simulateStreaming: Bool = true, failEvery: Int? = nil) {
        self.simulateStreaming = simulateStreaming
        self.failEvery = failEvery
    }

    func generateResponse(workspaceID: UUID, userMessage: String,
                          onStreamChunk: @escaping (String) -> Void,
                          onComplete: @escaping (String) -> Void,
                          onError: @escaping (String) -> Void) {
        counter += 1
        if let every = failEvery, counter % every == 0 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                onError("Simulated failure (QA)")
            }
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)   // pending state visible
            guard simulateStreaming else { onComplete(reply); return }
            for word in reply.split(separator: " ") {
                try? await Task.sleep(nanoseconds: 60_000_000)
                onStreamChunk(String(word) + " ")
            }
            onComplete(reply)
        }
    }
}
