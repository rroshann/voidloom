import AVFoundation
import VoidloomCore

/// On-device text-to-speech for Sunday's replies (opt-in). Speaks a trimmed
/// version of a narration, and is interruptible: any new utterance or a
/// barge-in (`stop()`) cancels the current speech immediately. Nothing leaves
/// the Mac — AVSpeechSynthesizer is fully local.
@MainActor
final class AssistantSpeaker: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    /// Chosen once: the highest-quality English voice installed (premium >
    /// enhanced > default), so Sunday sounds natural rather than robotic.
    private lazy var voice: AVSpeechSynthesisVoice? = Self.bestEnglishVoice()

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ text: String) {
        let spoken = AssistantSpeech.spoken(from: text)
        guard !spoken.isEmpty else { return }
        stop()
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = voice
        // A touch slower than the frantic default, with natural pitch — reads
        // as calm and considered.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.0
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
    }

    /// Best installed English voice by quality. Users can install higher-quality
    /// voices in System Settings › Accessibility › Spoken Content; this picks the
    /// best of whatever is present.
    private static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    /// Barge-in: stop talking at once (before capturing the user's voice, or on
    /// cancel) so Sunday never talks over the user or itself.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
