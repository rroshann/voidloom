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

    /// Invoked on the realtime audio thread with a normalized (0…1) input level
    /// (loudness) per buffer — drives the "it's listening" visual reaction.
    var onLevel: (@Sendable (Float) -> Void)?

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
        guard let converter else { return }
        guard let converted = convert(buffer, using: converter) else { return }
        onPCMBuffer?(converted)
        if let onLevel { onLevel(Self.normalizedLevel(of: converted)) }
    }

    /// RMS of the buffer mapped to a perceptual 0…1 range. Cheap enough for the
    /// realtime thread; the ~‑50 dB floor keeps quiet-room noise near zero.
    private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sumSquares: Float = 0
        for i in 0..<n { let s = data[i]; sumSquares += s * s }
        let rms = (sumSquares / Float(n)).squareRoot()
        let db = 20 * log10(max(rms, 1e-7))          // ~‑140…0 dB
        let floor: Float = -50
        return max(0, min(1, (db - floor) / -floor))  // ‑50 dB→0, 0 dB→1
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
