import AVFoundation
import FluidAudio
import Foundation
import VoidloomCore

/// App-target Parakeet EOU streaming transcriber. Feeds `StreamingEouAsrManager` from
/// `AudioCaptureService`; hypothesis updates become `.partial`, EOU / stop become `.final`.
@MainActor
final class ParakeetTranscriber: SpeechTranscribing {
    var onEvent: ((TranscriberEvent) -> Void)?

    private let capture = AudioCaptureService()
    private let manager = StreamingEouAsrManager(chunkSize: .ms160)
    private var modelsReady = false
    private var isCapturing = false
    private var didEmitFinalForUtterance = false
    private var prepareTask: Task<Void, Never>?

    private static let modelUnavailableMessage =
        "Voice model still preparing — try again shortly."
    private static let micDeniedMessage =
        "Microphone access denied — voice is off; typing still works."

    /// App wiring (RootView) observes this to keep the HUD mic button in sync.
    var onMicPermissionDeniedChanged: ((Bool) -> Void)?

    var isMicPermissionDenied: Bool { capture.permissionState == .denied }

    init() {
        prepareTask = Task { await prepareModels() }
    }

    deinit {
        prepareTask?.cancel()
        capture.stop()
    }

    func startUtterance() {
        guard modelsReady else {
            onEvent?(.unavailable(Self.modelUnavailableMessage))
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
            await beginCapture()
        }
    }

    func stopUtterance() {
        guard isCapturing else { return }
        isCapturing = false
        capture.onPCMBuffer = nil
        capture.stop()

        Task {
            await finalizeUtterance(trigger: .manualStop)
        }
    }

    // MARK: - Model prep

    private func prepareModels() async {
        await manager.setPartialTranscriptCallback { [weak self] text in
            Task { @MainActor in
                guard let self, self.isCapturing, !self.didEmitFinalForUtterance else { return }
                self.onEvent?(.partial(text))
            }
        }

        await manager.setEouCallback { [weak self] text in
            Task { @MainActor in
                guard let self, self.isCapturing else { return }
                self.emitFinal(text, trigger: .endOfUtterance)
            }
        }

        do {
            try await manager.loadModels()
            modelsReady = true
        } catch {
            onEvent?(.unavailable(Self.modelUnavailableMessage))
        }
    }

    // MARK: - Capture loop

    private func beginCapture() async {
        didEmitFinalForUtterance = false

        await manager.reset()

        capture.onPCMBuffer = { [weak self] buffer in
            guard let self, let samples = Self.copySamples(from: buffer) else { return }
            Task { @MainActor in
                await self.feedAudio(samples: samples)
            }
        }

        do {
            try capture.start()
            isCapturing = true
        } catch {
            onEvent?(.unavailable(Self.modelUnavailableMessage))
        }
    }

    private func feedAudio(samples: [Float]) async {
        guard isCapturing, !didEmitFinalForUtterance else { return }
        guard let buffer = Self.makePCMBuffer(from: samples) else { return }
        do {
            try await manager.appendAudio(buffer)
            try await manager.processBufferedAudio()
        } catch {
            isCapturing = false
            capture.stop()
            onEvent?(.unavailable(Self.modelUnavailableMessage))
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
                emitFinal(transcript, trigger: trigger)
            }
            await manager.reset()
        } catch {
            onEvent?(.unavailable(Self.modelUnavailableMessage))
        }
    }

    private func publishMicPermissionDenied() {
        onMicPermissionDeniedChanged?(isMicPermissionDenied)
    }

    private func emitFinal(_ text: String, trigger: FinalTrigger) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !didEmitFinalForUtterance else { return }
        didEmitFinalForUtterance = true
        onEvent?(.final(trimmed))
        if trigger == .endOfUtterance {
            isCapturing = false
            capture.onPCMBuffer = nil
            capture.stop()
        }
    }
}
