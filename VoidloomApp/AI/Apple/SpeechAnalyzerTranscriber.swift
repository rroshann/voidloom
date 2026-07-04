import AVFoundation
import Foundation
import Speech
import VoidloomCore

/// macOS 26 on-device speech via `SpeechAnalyzer` + `SpeechTranscriber`.
/// Push-to-talk only — always-listening / wake-phrase stays on Parakeet.
///
/// SDK contract (`Speech.swiftinterface`): attach modules at `SpeechAnalyzer`
/// init, call `prepareToAnalyze(in:)` exactly once per analyzer instance, then
/// `start(inputSequence:)`. Do not overlap `prepareToAnalyze` calls — serialize
/// session setup. Create a fresh `SpeechTranscriber` module per PTT session.
@available(macOS 26, *)
@MainActor
final class SpeechAnalyzerTranscriber: SpeechTranscribing {
    var onEvent: ((TranscriberEvent) -> Void)?

    var onMicPermissionDeniedChanged: ((Bool) -> Void)?
    var isMicPermissionDenied: Bool { capture.permissionState == .denied }

    private let capture = AudioCaptureService()
    private var sessionModule: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var analyzerFormat: AVAudioFormat?
    private var pcmConverter: AVAudioConverter?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analysisTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    private var isPTTSession = false
    private var modelsReady = false
    private var prepareTask: Task<Void, Never>?
    /// Serializes PTT session setup so `prepareToAnalyze` never runs concurrently.
    private var sessionSetupTask: Task<Void, Never>?

    private static let modelUnavailableMessage =
        "Speech model still preparing — try again shortly."
    private static let micDeniedMessage =
        "Microphone access denied — voice is off; typing still works."
    private static let transcriptionFailedMessage =
        "Transcription failed — try again."

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

        sessionSetupTask?.cancel()
        sessionSetupTask = Task {
            if let prepareTask { await prepareTask.value }

            let granted = await capture.requestPermissionIfNeeded()
            guard !Task.isCancelled else { return }
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
        guard isPTTSession else { return }
        isPTTSession = false
        capture.onPCMBuffer = nil
        capture.stop()
        inputContinuation?.finish()

        Task {
            if let analyzer {
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
                await analyzer.cancelAndFinishNow()
            }
            tearDownSession()
        }
    }

    // MARK: - Model prep

    private func prepareModels() async {
        guard SpeechTranscriber.isAvailable else { return }

        let locale = Locale(identifier: "en-US")
        let probe = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [])

        let status = await AssetInventory.status(forModules: [probe])
        switch status {
        case .installed, .supported:
            modelsReady = true
        case .downloading:
            onEvent?(.unavailable("Speech assets downloading — try again shortly."))
        default:
            if let request = try? await AssetInventory.assetInstallationRequest(supporting: [probe]) {
                Task {
                    do {
                        try await request.downloadAndInstall()
                        modelsReady = true
                    } catch {
                        self.onEvent?(.unavailable(Self.modelUnavailableMessage))
                    }
                }
            } else {
                onEvent?(.unavailable(Self.modelUnavailableMessage))
            }
        }
    }

    // MARK: - PTT session

    private func beginPTTSession() async {
        guard modelsReady else {
            onEvent?(.unavailable(Self.modelUnavailableMessage))
            return
        }

        tearDownSession()

        do {
            let locale = Locale(identifier: "en-US")
            let module = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [.volatileResults],
                attributeOptions: [])
            sessionModule = module

            // Module must be attached at analyzer init before the single prepare call.
            let analyzer = SpeechAnalyzer(modules: [module])
            self.analyzer = analyzer
            let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
            guard let format else {
                onEvent?(.unavailable(Self.transcriptionFailedMessage))
                tearDownSession()
                return
            }
            try await analyzer.prepareToAnalyze(in: format)
            analyzerFormat = format
            if let captureFormat = AVAudioFormat(
                   commonFormat: .pcmFormatFloat32,
                   sampleRate: 16_000,
                   channels: 1,
                   interleaved: false),
               format != captureFormat {
                pcmConverter = AVAudioConverter(from: captureFormat, to: format)
            } else {
                pcmConverter = nil
            }

            let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
            inputContinuation = continuation

            resultsTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await result in module.results {
                        handleTranscriptionResult(result)
                    }
                } catch {
                    handleAnalysisFailure()
                }
            }

            analysisTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await analyzer.start(inputSequence: stream)
                } catch {
                    handleAnalysisFailure()
                }
            }

            capture.onPCMBuffer = { [weak self] buffer in
                guard let self, let samples = Self.copySamples(from: buffer) else { return }
                Task { @MainActor in
                    self.feedAudio(samples: samples)
                }
            }

            try capture.start()
            isPTTSession = true
        } catch {
            onEvent?(.unavailable(Self.transcriptionFailedMessage))
            tearDownSession()
        }
    }

    private func feedAudio(samples: [Float]) {
        guard isPTTSession else { return }
        guard let buffer = Self.makePCMBuffer(from: samples) else { return }
        guard let converted = convertedBuffer(for: buffer) else { return }
        inputContinuation?.yield(AnalyzerInput(buffer: converted))
    }

    private func convertedBuffer(for buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let analyzerFormat else { return buffer }
        if buffer.format == analyzerFormat { return buffer }
        guard let pcmConverter else { return nil }

        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        var suppliedInput = false
        var error: NSError?
        let status = pcmConverter.convert(to: output, error: &error) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil, status != .error, output.frameLength > 0 else { return nil }
        return output
    }

    private func handleTranscriptionResult(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if result.isFinal {
            onEvent?(.final(text))
        } else {
            onEvent?(.partial(text))
        }
    }

    private func handleAnalysisFailure() {
        guard isPTTSession else { return }
        isPTTSession = false
        capture.stop()
        onEvent?(.unavailable(Self.transcriptionFailedMessage))
        tearDownSession()
    }

    private func tearDownSession() {
        analysisTask?.cancel()
        analysisTask = nil
        resultsTask?.cancel()
        resultsTask = nil
        inputContinuation = nil
        analyzer = nil
        sessionModule = nil
        analyzerFormat = nil
        pcmConverter = nil
    }

    private func publishMicPermissionDenied() {
        onMicPermissionDeniedChanged?(isMicPermissionDenied)
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
}
