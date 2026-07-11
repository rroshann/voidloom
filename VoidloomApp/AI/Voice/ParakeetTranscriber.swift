import AVFoundation
import FluidAudio
import Foundation
import VoidloomCore

/// App-target Parakeet transcriber.
///
/// Push-to-talk is utterance-level: the whole recording is buffered while the
/// key is held, then transcribed ONCE on release by the batch Parakeet Unified
/// 0.6B model (full-attention offline encoder — far more accurate than the
/// 120M realtime model, with punctuation and casing). Always-listening keeps
/// the small streaming EOU model, whose realtime wake-word scanning is the
/// point. Until the batch models finish their first download, push-to-talk
/// falls back to the streaming path so voice is never dead.
@MainActor
final class ParakeetTranscriber: SpeechTranscribing {
    var onEvent: ((TranscriberEvent) -> Void)?

    /// Invoked when the wake phrase is matched in always-listening mode (before command audio).
    var onWakePhraseMatched: (() -> Void)?

    private let capture = AudioCaptureService()
    private let manager = StreamingEouAsrManager(chunkSize: .ms160)
    private let batchManager = UnifiedAsrManager()
    private var modelsReady = false
    private var batchReady = false
    private var isPTTSession = false
    private var pttUsesBatch = false
    private var pttSamples: [Float] = []
    private var isContinuousSession = false
    private var isCommandArmed = false
    private var didEmitFinalForUtterance = false
    private var prepareTask: Task<Void, Never>?
    private var batchPrepareTask: Task<Void, Never>?
    private var voiceMode: VoiceInputMode = .pushToTalk
    private var wakeMatcher = WakePhraseMatcher(phrase: "hey sunday")
    private var wakeScanBuffer = ""

    private static let modelUnavailableMessage =
        "Voice model still preparing — try again shortly."
    private static let transcriptionFailedMessage =
        "Transcription failed — try again."
    private static let micDeniedMessage =
        "Microphone access denied — voice is off; typing still works."

    /// App wiring (RootView) observes this to keep the HUD mic button in sync.
    var onMicPermissionDeniedChanged: ((Bool) -> Void)?

    var isMicPermissionDenied: Bool { capture.permissionState == .denied }

    init() {
        prepareTask = Task { await prepareModels() }
        batchPrepareTask = Task { await prepareBatchModels() }
        // Forward mic loudness to the HUD (fires only while capture runs). Hops to
        // the main actor since onEvent is main-isolated; ~12/sec, cheap.
        capture.onLevel = { [weak self] level in
            Task { @MainActor in self?.onEvent?(.level(level)) }
        }
    }

    deinit {
        prepareTask?.cancel()
        batchPrepareTask?.cancel()
        capture.stop()
    }

    func applyConfiguration(mode: VoiceInputMode, wakePhrase: String) {
        let previousMode = voiceMode
        voiceMode = mode
        wakeMatcher = WakePhraseMatcher(phrase: wakePhrase)
        wakeScanBuffer = ""

        switch mode {
        case .off:
            stopAllCapture()
        case .pushToTalk:
            if previousMode == .alwaysListening {
                stopContinuousSession()
            }
        case .alwaysListening:
            if previousMode != .alwaysListening {
                Task { await startAlwaysListeningIfPossible() }
            }
        }
    }

    func startUtterance() {
        guard voiceMode != .off else { return }
        guard modelsReady || batchReady else {
            onEvent?(.unavailable(Self.modelUnavailableMessage))
            return
        }

        if voiceMode == .alwaysListening {
            isCommandArmed = true
            didEmitFinalForUtterance = false
            return
        }

        Task {
            let granted = await capture.requestPermissionIfNeeded()
            guard granted else {
                onEvent?(.unavailable(Self.micDeniedMessage))
                publishMicPermissionDenied()
                return
            }

            publishMicPermissionDenied()
            await beginPTTSession()
        }
    }

    func stopUtterance() {
        if voiceMode == .alwaysListening {
            isCommandArmed = false
            didEmitFinalForUtterance = false
            wakeScanBuffer = ""
            Task { await manager.reset() }
            return
        }

        guard isPTTSession else { return }
        isPTTSession = false
        capture.onPCMBuffer = nil
        capture.stop()

        if pttUsesBatch {
            let samples = pttSamples
            pttSamples = []
            Task { await transcribeBatchUtterance(samples: samples) }
        } else {
            Task { await finalizeUtterance(trigger: .manualStop) }
        }
    }

    // MARK: - Model prep

    private func prepareModels() async {
        await manager.setPartialTranscriptCallback { [weak self] text in
            Task { @MainActor in
                self?.handlePartial(text)
            }
        }

        await manager.setEouCallback { [weak self] text in
            Task { @MainActor in
                self?.handleEndOfUtterance(text)
            }
        }

        do {
            try await manager.loadModels()
            modelsReady = true
            if voiceMode == .alwaysListening {
                await startAlwaysListeningIfPossible()
            }
        } catch {
            onEvent?(.unavailable(Self.modelUnavailableMessage))
        }
    }

    /// Downloads/loads the batch Parakeet Unified 0.6B models (first run pulls
    /// them from Hugging Face into Application Support). Independent of the
    /// streaming prep: push-to-talk upgrades to batch whenever this lands.
    private func prepareBatchModels() async {
        do {
            try await batchManager.loadModels()
            batchReady = true
        } catch {
            // Batch stays unavailable; push-to-talk keeps the streaming fallback.
            batchReady = false
        }
    }

    /// Transcribes a fully buffered push-to-talk utterance in one pass and
    /// ALWAYS emits `.final` — an empty transcript included, so the session
    /// coordinator can settle (it cancels an empty capture) instead of waiting
    /// on its watchdog.
    private func transcribeBatchUtterance(samples: [Float]) async {
        guard !didEmitFinalForUtterance else { return }
        do {
            let transcript = samples.isEmpty ? "" : try await batchManager.transcribe(samples)
            didEmitFinalForUtterance = true
            onEvent?(.final(transcript))
        } catch {
            onEvent?(.unavailable(Self.transcriptionFailedMessage))
        }
    }

    // MARK: - Always listening

    private func startAlwaysListeningIfPossible() async {
        guard voiceMode == .alwaysListening, modelsReady, !isContinuousSession else { return }

        let granted = await capture.requestPermissionIfNeeded()
        guard granted else {
            onEvent?(.unavailable(Self.micDeniedMessage))
            publishMicPermissionDenied()
            return
        }

        publishMicPermissionDenied()
        await beginContinuousSession()
    }

    private func beginContinuousSession() async {
        isCommandArmed = false
        didEmitFinalForUtterance = false
        wakeScanBuffer = ""
        await manager.reset()

        capture.onPCMBuffer = { [weak self] buffer in
            guard let self, let samples = Self.copySamples(from: buffer) else { return }
            Task { @MainActor in
                await self.feedAudio(samples: samples)
            }
        }

        do {
            try capture.start()
            isContinuousSession = true
        } catch {
            onEvent?(.unavailable(Self.modelUnavailableMessage))
        }
    }

    private func stopContinuousSession() {
        guard isContinuousSession else { return }
        isContinuousSession = false
        isCommandArmed = false
        didEmitFinalForUtterance = false
        wakeScanBuffer = ""
        capture.onPCMBuffer = nil
        capture.stop()
        Task { await manager.reset() }
    }

    private func stopAllCapture() {
        isPTTSession = false
        pttSamples = []
        isCommandArmed = false
        didEmitFinalForUtterance = false
        wakeScanBuffer = ""
        capture.onPCMBuffer = nil
        capture.stop()
        isContinuousSession = false
        Task { await manager.reset() }
    }

    // MARK: - PTT capture

    private func beginPTTSession() async {
        didEmitFinalForUtterance = false
        pttUsesBatch = batchReady
        pttSamples = []

        if pttUsesBatch {
            // Batch path: buffer the whole utterance; transcription happens
            // once, on release. Levels still flow via capture.onLevel.
            capture.onPCMBuffer = { [weak self] buffer in
                guard let self, let samples = Self.copySamples(from: buffer) else { return }
                Task { @MainActor in
                    guard self.isPTTSession else { return }
                    self.pttSamples.append(contentsOf: samples)
                }
            }
        } else {
            // Streaming fallback while the batch models download.
            await manager.reset()
            capture.onPCMBuffer = { [weak self] buffer in
                guard let self, let samples = Self.copySamples(from: buffer) else { return }
                Task { @MainActor in
                    await self.feedAudio(samples: samples)
                }
            }
        }

        do {
            try capture.start()
            isPTTSession = true
        } catch {
            onEvent?(.unavailable(Self.modelUnavailableMessage))
        }
    }

    // MARK: - Transcript routing

    private func handlePartial(_ text: String) {
        if voiceMode == .alwaysListening {
            if isCommandArmed {
                guard !didEmitFinalForUtterance else { return }
                onEvent?(.partial(text))
            } else {
                handleWakeScan(fragment: text, isFinal: false)
            }
            return
        }

        guard isPTTSession, !didEmitFinalForUtterance else { return }
        onEvent?(.partial(text))
    }

    private func handleEndOfUtterance(_ text: String) {
        if voiceMode == .alwaysListening {
            if isCommandArmed {
                emitFinal(text, trigger: .endOfUtterance, endSession: false)
                Task { await manager.reset() }
            } else {
                handleWakeScan(fragment: text, isFinal: true)
                Task { await manager.reset() }
            }
            return
        }

        guard isPTTSession else { return }
        emitFinal(text, trigger: .endOfUtterance, endSession: true)
    }

    private func handleWakeScan(fragment: String, isFinal: Bool) {
        guard let command = wakeMatcher.scanRolling(buffer: &wakeScanBuffer, appending: fragment) else {
            if isFinal { wakeScanBuffer = "" }
            return
        }

        onWakePhraseMatched?()
        isCommandArmed = true
        didEmitFinalForUtterance = false
        wakeScanBuffer = ""

        guard !command.isEmpty else { return }
        if isFinal {
            emitFinal(command, trigger: .endOfUtterance, endSession: false)
        } else {
            onEvent?(.partial(command))
        }
    }

    private func feedAudio(samples: [Float]) async {
        let isActive = isPTTSession || isContinuousSession
        guard isActive, !didEmitFinalForUtterance else { return }
        guard let buffer = Self.makePCMBuffer(from: samples) else { return }
        do {
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
        } catch {
            if isPTTSession {
                isPTTSession = false
            }
            if isContinuousSession {
                isContinuousSession = false
            }
            capture.stop()
            onEvent?(.unavailable(Self.transcriptionFailedMessage))
        }
    }

    private nonisolated static func copySamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: channelData[0], count: count))
    }

    private nonisolated static func makePCMBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let destination = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { source in
            destination.update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }

    private enum FinalTrigger {
        case endOfUtterance
        case manualStop
    }

    private func finalizeUtterance(trigger: FinalTrigger) async {
        do {
            try await manager.processBufferedAudio()
            let transcript = try await manager.finish()
            if trigger == .manualStop {
                emitFinal(transcript, trigger: trigger, endSession: true)
            }
            await manager.reset()
        } catch {
            onEvent?(.unavailable(Self.transcriptionFailedMessage))
        }
    }

    private func publishMicPermissionDenied() {
        onMicPermissionDeniedChanged?(isMicPermissionDenied)
    }

    private func emitFinal(_ text: String, trigger: FinalTrigger, endSession: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !didEmitFinalForUtterance else { return }
        didEmitFinalForUtterance = true
        onEvent?(.final(trimmed))
        if trigger == .endOfUtterance, endSession {
            isPTTSession = false
            capture.onPCMBuffer = nil
            capture.stop()
        }
    }
}
