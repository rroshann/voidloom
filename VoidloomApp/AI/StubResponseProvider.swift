import Foundation
import VoidloomCore

/// Simulates latency + word-by-word streaming so the sidebar's loading/streaming/error
/// states are visible without a real backend. `failEvery` injects periodic failures for QA.
@MainActor
final class StubResponseProvider: ResponseProvider {
    private let reply = "✨ AI backend isn't connected yet — this is where responses will appear."
    private let simulateStreaming: Bool
    private var counter = 0

    init(simulateStreaming: Bool = true) { self.simulateStreaming = simulateStreaming }

    func generateResponse(workspaceID: UUID, userMessage: String,
                          onStreamChunk: @escaping (String) -> Void,
                          onComplete: @escaping (String) -> Void,
                          onError: @escaping (String) -> Void) {
        counter += 1
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
