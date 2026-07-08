import AVFoundation
import VoidloomCore

/// On-device text-to-speech for Sunday's replies (opt-in). Speaks a trimmed
/// version of a narration, and is interruptible: any new utterance or a
/// barge-in (`stop()`) cancels the current speech immediately. Nothing leaves
/// the Mac — AVSpeechSynthesizer is fully local.
@MainActor
final class AssistantSpeaker: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    /// Chosen once: the highest-quality English voice installed (premium >
    /// enhanced > default), so Sunday sounds natural rather than robotic.
    private lazy var voice: AVSpeechSynthesisVoice? = Self.bestEnglishVoice()

    /// Published so the HUD can show a distinct "speaking" state while Sunday
    /// talks — driven by the synthesizer's start/finish/cancel callbacks.
    @Published private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

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
        utterance.volume = 1.0
        // Use our chosen voice/rate directly rather than tying playback to the
        // user's (often unset) assistive-tech settings, so speech is reliably
        // audible.
        utterance.prefersAssistiveTechnologySettings = false
        synthesizer.speak(utterance)
    }

    /// Best installed English voice by quality. Users can install higher-quality
    /// voices in System Settings › Accessibility › Spoken Content; this picks the
    /// best of whatever is present.
    private static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        // Rank installed English voices so Sunday sounds natural AND consistent:
        // quality dominates (premium > enhanced > default), then prefer US English
        // and a female voice — she's "Sunday", so this avoids landing on a random
        // installed accent or a male voice when a better-fitting one is present.
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            var s = v.quality.rawValue * 100
            if v.language == "en-US" { s += 10 }
            if v.gender == .female { s += 5 }
            return s
        }
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .max { score($0) < score($1) }
    }

    /// Barge-in: stop talking at once (before capturing the user's voice, or on
    /// cancel) so Sunday never talks over the user or itself.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}

extension AssistantSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
