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
