import Foundation

public enum TranscriberEvent: Equatable, Sendable {
    case partial(String)
    case final(String)
    case unavailable(String)
}

/// App-layer speech engines (e.g. Parakeet) conform; Core stays headless.
public protocol SpeechTranscribing: AnyObject {
    @MainActor func startUtterance()
    @MainActor func stopUtterance()
    @MainActor var onEvent: ((TranscriberEvent) -> Void)? { get set }
}
