import XCTest
import FoundationModels
import VoidloomAI
import VoidloomCore
@testable import Voidloom

/// Warm end-of-utterance → command latency: Apple Intelligence vs local llama.
/// Skips when FM or the command model isn't present on this machine.
final class AppleTierBenchmarkTests: XCTestCase {
    func testWarmCommandLatencyFoundationModelsVsLlama() async throws {
        guard #available(macOS 26, *) else {
            throw XCTSkip("Requires macOS 26")
        }
        try requireFoundationModelsOrSkip()

        let fmBrain = FoundationModelsBrain()
        _ = try? await fmBrain.command(for: "start 2 claude agents")

        let fmStart = DispatchTime.now()
        _ = try await fmBrain.command(for: "ask ember to fix the build")
        let fmElapsed = elapsedSeconds(since: fmStart)
        print("FoundationModelsBrain warm dispatch: \(fmElapsed)s")
        if fmElapsed > 1.0 {
            print("NOTE: FM guided generation exceeded the spec's ≤1s bar on this machine.")
        }
        XCTAssertLessThan(fmElapsed, 10.0, "FM command did not complete in reasonable time")

        guard let url = await llamaModelURLIfPresent() else {
            print("Llama benchmark skipped — command model not downloaded")
            return
        }

        let engine = CllamaEngine()
        try engine.load(modelPath: url, config: LlamaEngineConfig(contextLength: 2048))
        defer { engine.unload() }
        let llamaBrain = LlamaBrain(engine: engine)
        _ = try? await llamaBrain.command(for: "start 2 claude agents")

        let llamaStart = DispatchTime.now()
        _ = try await llamaBrain.command(for: "ask ember to fix the build")
        let llamaElapsed = elapsedSeconds(since: llamaStart)
        print("LlamaBrain warm dispatch: \(llamaElapsed)s")
        XCTAssertLessThan(llamaElapsed, 1.0, "Llama warm dispatch exceeded ≤1s bar")
    }

    @available(macOS 26, *)
    private func requireFoundationModelsOrSkip() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(let reason):
            throw XCTSkip("Foundation Models unavailable: \(reason)")
        }
    }

    private func llamaModelURLIfPresent() async -> URL? {
        await MainActor.run {
            ModelAssetManager().localURL(of: LocalModelManifest.commandModel)
        }
    }

    private func elapsedSeconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }
}
