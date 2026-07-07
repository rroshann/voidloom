import AVFoundation
import Foundation

/// Mic permission state surfaced for voice UI (Task 3) without SwiftUI.
enum MicPermissionState: Equatable, Sendable {
    case undetermined
    case authorized
    case denied
}

/// Sole owner of `AVAudioEngine` microphone input. Converts tap buffers to 16 kHz
/// mono Float32 via `AVAudioConverter` before handing them to consumers.
final class AudioCaptureService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let targetFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private let stateLock = NSLock()
    private var isRunning = false

    /// Invoked on the realtime audio thread with converted PCM buffers.
    var onPCMBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    init() {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    }

    var permissionState: MicPermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .undetermined
        @unknown default:
            return .denied
        }
    }

    func requestPermissionIfNeeded() async -> Bool {
        switch permissionState {
        case .authorized:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func start() throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard let audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterInitFailed
        }
        converter = audioConverter

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard isRunning else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine.reset()
        converter = nil
        isRunning = false
    }

    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let onPCMBuffer else { return }
        guard let converted = convert(buffer, using: converter) else { return }
        onPCMBuffer(converted)
    }

    private func convert(_ input: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let frameCapacity = AVAudioFrameCount(ceil(Double(input.frameLength) * ratio)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        var suppliedInput = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return input
        }

        guard error == nil, status != .error else { return nil }
        return output.frameLength > 0 ? output : nil
    }
}

enum AudioCaptureError: Error {
    case converterInitFailed
}
