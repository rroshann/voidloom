import Foundation

public enum TranscriberEvent: Equatable, Sendable {
    case partial(String)
    case final(String)
    case unavailable(String)
    /// Normalized mic input level (0…1) while capturing, so the HUD can react to
    /// the user's voice and show it's genuinely listening.
    case level(Float)
}

/// App-layer speech engines (e.g. Parakeet) conform; Core stays headless.
public protocol SpeechTranscribing: AnyObject {
    @MainActor func startUtterance()
    @MainActor func stopUtterance()
    @MainActor var onEvent: ((TranscriberEvent) -> Void)? { get set }
}
