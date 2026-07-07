import XCTest
import VoidloomAI
import VoidloomCore

/// Real inference against the vendored llama + Qwen3-0.6B. Skipped (not failed)
/// when the model isn't downloaded, so CI without the 397 MB asset stays green.
final class LlamaBrainIntegrationTests: XCTestCase {
    private func modelURLOrSkip() throws -> URL {
        let url = MainActor.assumeIsolated {
            let assets = ModelAssetManager()
            return assets.localURL(of: LocalModelManifest.commandModel)
        }
        guard let url else {
            throw XCTSkip("Command model not downloaded — run the app's Settings › Local AI download, then re-run.")
        }
        return url
    }

    func testGoldenUtterancesProduceSchemaValidCommands() throws {
        let url = try modelURLOrSkip()
        let engine = CllamaEngine()
        try engine.load(modelPath: url, config: LlamaEngineConfig(contextLength: 2048))
        defer { engine.unload() }
        let brain = LlamaBrain(engine: engine)

        let golden: [(String, (MediatorCommand) -> Bool)] = [
            ("start 4 claude agents", { if case .spawnAgents(4, .claudeCode, _) = $0 { return true }; return false }),
            ("switch to research", { $0 == .switchSpace(name: "research") }),
            ("close ember", { $0 == .closeTerminal(target: "ember") }),
            ("tile the windows in a grid", { $0 == .arrange(style: .grid) }),
        ]
        let exp = expectation(description: "golden")
        Task {
            for (utterance, check) in golden {
                let cmd = try await brain.command(for: utterance)
                XCTAssertTrue(check(cmd), "\(utterance) -> \(cmd)")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
    }

    /// Warm end-of-utterance -> command-dispatch latency against the spec's
    /// ≤1s bar (spike-measured warm: 0.15-0.26s). The first call pays the cold
    /// Metal-load + first-eval cost (spike: ~0.66s + ~0.35s) and is discarded;
    /// only the second call is measured.
    func testWarmDispatchMeetsTheOneSecondBar() throws {
        let url = try modelURLOrSkip()
        let engine = CllamaEngine()
        try engine.load(modelPath: url, config: LlamaEngineConfig(contextLength: 2048))
        defer { engine.unload() }
        let brain = LlamaBrain(engine: engine)

        let warmUp = expectation(description: "warm-up")
        Task { _ = try? await brain.command(for: "start 2 claude agents"); warmUp.fulfill() }
        wait(for: [warmUp], timeout: 30)

        let start = DispatchTime.now()
        let measured = expectation(description: "measured")
        Task { _ = try? await brain.command(for: "ask ember to fix the build"); measured.fulfill() }
        wait(for: [measured], timeout: 10)
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        print("LlamaBrain warm dispatch: \(elapsedSeconds)s")
        XCTAssertLessThan(elapsedSeconds, 1.0, "warm end-of-speech->dispatch exceeded the spec's ≤1s bar")
    }
}
