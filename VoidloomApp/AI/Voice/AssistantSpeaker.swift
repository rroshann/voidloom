import AVFoundation
import VoidloomCore

/// On-device text-to-speech for Sunday's replies (opt-in). Speaks a trimmed
/// version of a narration, and is interruptible: any new utterance or a
/// barge-in (`stop()`) cancels the current speech immediately. Nothing leaves
/// the Mac — AVSpeechSynthesizer is fully local.
@MainActor
final class AssistantSpeaker: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ text: String) {
        let spoken = AssistantSpeech.spoken(from: text)
        guard !spoken.isEmpty else { return }
        stop()
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.prefersAssistiveTechnologySettings = true
        synthesizer.speak(utterance)
    }

    /// Barge-in: stop talking at once (before capturing the user's voice, or on
    /// cancel) so Sunday never talks over the user or itself.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
