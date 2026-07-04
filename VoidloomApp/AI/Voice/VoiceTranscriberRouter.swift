import Foundation
import Speech
import VoidloomCore

/// Routes voice capture to Parakeet (always-listening + fallback) or
/// `SpeechAnalyzerTranscriber` (PTT on macOS 26 when assets are ready).
@MainActor
final class VoiceTranscriberRouter: SpeechTranscribing {
    var onEvent: ((TranscriberEvent) -> Void)? {
        didSet { wireChildHandlers() }
    }

    var onWakePhraseMatched: (() -> Void)? {
        didSet { parakeet.onWakePhraseMatched = onWakePhraseMatched }
    }

    var onMicPermissionDeniedChanged: ((Bool) -> Void)? {
        didSet { wireChildHandlers() }
    }

    var isMicPermissionDenied: Bool { activeTranscriber.isMicDenied }

    private let parakeet: ParakeetTranscriber
    private let speechAnalyzer: SpeechTranscribing?
    private var voiceMode: VoiceInputMode = .pushToTalk

    init(parakeet: ParakeetTranscriber, speechAnalyzer: SpeechTranscribing?) {
        self.parakeet = parakeet
        self.speechAnalyzer = speechAnalyzer
        wireChildHandlers()
    }

    func applyConfiguration(mode: VoiceInputMode, wakePhrase: String) {
        voiceMode = mode
        parakeet.applyConfiguration(mode: mode, wakePhrase: wakePhrase)
    }

    func startUtterance() { activeTranscriber.transcriber.startUtterance() }
    func stopUtterance() { activeTranscriber.transcriber.stopUtterance() }

    static func speechAnalyzerIfAvailable() -> SpeechTranscribing? {
        guard #available(macOS 26, *), SpeechTranscriber.isAvailable else { return nil }
        return SpeechAnalyzerTranscriber()
    }

    private var activeTranscriber: ActiveVoiceEngine {
        switch voiceMode {
        case .alwaysListening:
            return ActiveVoiceEngine(transcriber: parakeet, isMicDenied: parakeet.isMicPermissionDenied)
        case .pushToTalk:
            if let speechAnalyzer {
                return ActiveVoiceEngine(
                    transcriber: speechAnalyzer,
                    isMicDenied: micDenied(for: speechAnalyzer))
            }
            return ActiveVoiceEngine(transcriber: parakeet, isMicDenied: parakeet.isMicPermissionDenied)
        case .off:
            return ActiveVoiceEngine(transcriber: parakeet, isMicDenied: parakeet.isMicPermissionDenied)
        }
    }

    private func wireChildHandlers() {
        let forward: (TranscriberEvent) -> Void = { [weak self] event in
            self?.onEvent?(event)
        }
        parakeet.onEvent = forward
        speechAnalyzer?.onEvent = forward
        parakeet.onWakePhraseMatched = onWakePhraseMatched

        let micHandler: (Bool) -> Void = { [weak self] denied in
            self?.onMicPermissionDeniedChanged?(denied)
        }
        parakeet.onMicPermissionDeniedChanged = micHandler
        if #available(macOS 26, *), let speech = speechAnalyzer as? SpeechAnalyzerTranscriber {
            speech.onMicPermissionDeniedChanged = micHandler
        }
    }

    private func micDenied(for transcriber: SpeechTranscribing) -> Bool {
        if let parakeet = transcriber as? ParakeetTranscriber {
            return parakeet.isMicPermissionDenied
        }
        if #available(macOS 26, *), let speech = transcriber as? SpeechAnalyzerTranscriber {
            return speech.isMicPermissionDenied
        }
        return false
    }

    private struct ActiveVoiceEngine {
        let transcriber: SpeechTranscribing
        let isMicDenied: Bool
    }
}
