import Foundation

/// User-selected voice input mode (persisted in app settings).
public enum VoiceInputMode: String, Sendable, CaseIterable, Identifiable {
    case off
    case pushToTalk
    case alwaysListening

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .pushToTalk: "Push-to-talk"
        case .alwaysListening: "Always listening"
        }
    }
}

/// When Sunday reads replies aloud. `whenSpokenTo` speaks only if the request
/// came in by voice (a natural spoken back-and-forth); `always` also reads typed
/// replies aloud; `off` is silent.
public enum AssistantSpeechMode: String, Sendable, CaseIterable, Identifiable {
    case off
    case whenSpokenTo
    case always

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .whenSpokenTo: "When spoken to"
        case .always: "Always"
        }
    }

    /// Whether to speak given how the request arrived.
    public func shouldSpeak(inputWasVoice: Bool) -> Bool {
        switch self {
        case .off: false
        case .whenSpokenTo: inputWasVoice
        case .always: true
        }
    }
}
