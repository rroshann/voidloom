import AVFoundation
import FluidAudio
import VoidloomCore

/// Sunday's voice: two natural American neural voices (Kokoro, fully on-device).
enum AssistantVoice: String, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        }
    }
    /// Kokoro voice pack ids: af_heart is the flagship American female voice;
    /// am_puck is the best-rated American male.
    var kokoroVoice: String {
        switch self {
        case .female: "af_heart"
        case .male: "am_puck"
        }
    }

    static let defaultsKey = "voice.assistantVoice"

    static var selected: AssistantVoice {
        AssistantVoice(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .female
    }
}

/// On-device text-to-speech for Sunday's replies (opt-in). Speaks a trimmed
/// version of a narration, and is interruptible: any new utterance or a
/// barge-in (`stop()`) cancels the current speech immediately.
///
/// Primary engine is Kokoro on the Neural Engine (natural American voices,
/// male/female per Settings). Until its models finish their first download —
/// or if synthesis fails — the best installed system voice fills in, so
/// speech is never silently missing. Nothing leaves the Mac either way.
@MainActor
final class AssistantSpeaker: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    /// The noise stage stays off the GPU: on this OS the MPSGraph compile of
    /// KokoroNoise_v2 can hit "shape for TensorData is not static" and abort
    /// the process (seen live switching voices). CPU noise costs ~100 ms per
    /// utterance — a fair trade for never crashing mid-sentence.
    private let kokoro = KokoroAneManager(
        computeUnits: KokoroAneComputeUnits(noise: .cpuOnly)
    )
    private var kokoroReady = false
    private var prepareTask: Task<Void, Never>?
    private var synthesisTask: Task<Void, Never>?
    private var player: AVAudioPlayer?

    /// Chosen once: the highest-quality English voice installed (premium >
    /// enhanced > default) — the fallback while Kokoro prepares.
    private lazy var fallbackVoice: AVSpeechSynthesisVoice? = Self.bestEnglishVoice()

    /// Published so the HUD can show a distinct "speaking" state while Sunday
    /// talks — driven by playback start/finish/cancel for both engines.
    @Published private(set) var isSpeaking = false

    /// Which voice a Settings preview is currently playing (nil when none), so
    /// each preview button can flip between play and stop.
    @Published private(set) var previewingVoice: AssistantVoice?

    /// Sunday's introduction line, used by the Settings voice previews.
    static var previewLine: String {
        "Hi, I'm \(AssistantIdentity.name) — I'm here to help. Let's build something great together."
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        prepareTask = Task { [weak self] in
            // The CoreML repo only ships af_heart.bin; other Kokoro voice packs
            // exist as JSON. Materialize any missing packs as .bin in the
            // package's cache (validated byte-identical to the shipped pack)
            // BEFORE initialize, so male synthesis can load them locally.
            for voice in AssistantVoice.allCases {
                await Self.ensureVoicePackAvailable(voice.kokoroVoice)
            }
            do {
                try await self?.kokoro.initialize()
                self?.kokoroReady = true
            } catch {
                NSLog("Voidloom Kokoro init failed: \(error)")
                self?.kokoroReady = false
            }
        }
    }

    deinit {
        prepareTask?.cancel()
        synthesisTask?.cancel()
    }

    func speak(_ text: String) {
        speak(text, as: AssistantVoice.selected, preview: nil)
    }

    /// Plays (or stops) the Settings preview for a voice, independent of the
    /// currently selected one.
    func togglePreview(_ voice: AssistantVoice) {
        if previewingVoice == voice {
            stop()
            return
        }
        speak(Self.previewLine, as: voice, preview: voice)
    }

    private func speak(_ text: String, as voiceChoice: AssistantVoice, preview: AssistantVoice?) {
        let spoken = AssistantSpeech.spoken(from: text)
        guard !spoken.isEmpty else { return }
        stop()
        previewingVoice = preview
        guard kokoroReady else {
            speakWithSystemVoice(spoken)
            return
        }
        let voice = voiceChoice.kokoroVoice
        synthesisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let wav = try await self.kokoro.synthesize(text: spoken, voice: voice)
                guard !Task.isCancelled else { return }
                self.play(wav)
            } catch {
                guard !Task.isCancelled else { return }
                NSLog("Voidloom Kokoro synthesis failed: \(error)")
                self.speakWithSystemVoice(spoken)
            }
        }
    }

    private func play(_ wav: Data) {
        guard let player = try? AVAudioPlayer(data: wav) else { return }
        self.player = player
        player.delegate = self
        isSpeaking = true
        player.play()
    }

    private func speakWithSystemVoice(_ spoken: String) {
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = fallbackVoice
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

    // MARK: - Voice pack conversion

    /// The Kokoro CoreML repo stores extra voices as `voices/<voice>.json`
    /// (keys "1"…"510", each a 256-float row) while the ANE loader wants a
    /// flat fp32 `<voice>.bin`. If the .bin is missing from the package cache,
    /// fetch the JSON and write the .bin (verified byte-identical to the
    /// repo's own af_heart.bin for the same rows). Best-effort: on failure the
    /// voice simply falls back to the system engine at synthesis time.
    private nonisolated static func ensureVoicePackAvailable(_ voice: String) async {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/fluidaudio/Models/kokoro-82m-coreml/ANE", isDirectory: true)
        let binURL = cacheDir.appendingPathComponent("\(voice).bin")
        guard !FileManager.default.fileExists(atPath: binURL.path) else { return }

        guard let jsonURL = URL(
            string: "https://huggingface.co/FluidInference/kokoro-82m-coreml/resolve/main/voices/\(voice).json"
        ) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: jsonURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let rows = try JSONDecoder().decode([String: [Float]].self, from: data)
            var flat: [Float] = []
            flat.reserveCapacity(510 * 256)
            for index in 1...510 {
                guard let row = rows[String(index)], row.count == 256 else { return }
                flat.append(contentsOf: row)
            }
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
            let bin = flat.withUnsafeBufferPointer { Data(buffer: $0) }
            try bin.write(to: binURL, options: .atomic)
            NSLog("Voidloom converted Kokoro voice pack \(voice) (\(bin.count) bytes)")
        } catch {
            NSLog("Voidloom voice pack conversion failed for \(voice): \(error)")
        }
    }

    /// Best installed English voice by quality — the pre-Kokoro fallback.
    private static func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
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

    /// Whether a natural-sounding (Enhanced or Premium) English voice is installed.
    /// Only relevant to the fallback tier — Kokoro replaces it once ready.
    static var hasEnhancedEnglishVoice: Bool {
        AVSpeechSynthesisVoice.speechVoices().contains {
            $0.language.hasPrefix("en")
                && $0.quality.rawValue > AVSpeechSynthesisVoiceQuality.default.rawValue
        }
    }

    /// Barge-in: stop talking at once (before capturing the user's voice, or on
    /// cancel) so Sunday never talks over the user or itself.
    func stop() {
        synthesisTask?.cancel()
        synthesisTask = nil
        previewingVoice = nil
        if let player {
            player.stop()
            self.player = nil
            isSpeaking = false
        }
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
        Task { @MainActor in
            self.isSpeaking = false
            self.previewingVoice = nil
        }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.previewingVoice = nil
        }
    }
}

extension AssistantSpeaker: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isSpeaking = false
            self.previewingVoice = nil
            self.player = nil
        }
    }
}
