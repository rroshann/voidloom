import Foundation
import VoidloomAI
import VoidloomCore

/// Assembles the mediator brain for the current tier. Fast path always;
/// LLM fallback when the command model is ready, or while it is downloading
/// (unparseable utterances surface download progress). Engine loads lazily on
/// first real LLM use (cold Metal load ~0.66 s), then stays resident.
@MainActor
enum MediatorBrainFactory {
    static func makeBrain(assets: ModelAssetManager) -> MediatorBrain {
        let fast = FastPathBrain()
        let asset = LocalModelManifest.commandModel
        let state = assets.state(of: asset)
        let commandReady = state == .ready
        let fmPreferred = AppleTierAvailability.foundationModelsAvailable
            && AppleTierAvailability.preferAppleIntelligence
        let tier = MediatorTierResolver.resolve(
            capabilities: .init(
                commandModelReady: commandReady,
                foundationModelsAvailable: fmPreferred))
        let config = LlamaEngineConfig(contextLength: 2048)

        switch state {
        case .downloading(let progress):
            if fmPreferred, #available(macOS 26, *) {
                return TieredBrain(fast: fast, fallback: FoundationModelsBrain())
            }
            let message = "Local model downloading (\(Int(progress * 100))%) — try again shortly."
            let engine = LazyLoadingEngine(modelURL: nil, downloadingMessage: message, config: config)
            return TieredBrain(fast: fast, fallback: LlamaBrain(engine: engine))
        case .ready:
            switch tier {
            case .fastPathOnly:
                return fast
            case .appleFoundationModels:
                if #available(macOS 26, *) {
                    return TieredBrain(fast: fast, fallback: FoundationModelsBrain())
                }
                fallthrough
            case .fastPathWithLLM:
                let engine = LazyLoadingEngine(
                    modelURL: assets.localURL(of: asset),
                    config: config)
                return TieredBrain(fast: fast, fallback: LlamaBrain(engine: engine))
            }
        default:
            if fmPreferred, #available(macOS 26, *) {
                return TieredBrain(fast: fast, fallback: FoundationModelsBrain())
            }
            return fast
        }
    }
}

/// Loads the model on first `complete`/`stream`, throwing model-availability
/// `BrainError`s surfaced distinctly by the coordinator if the asset isn't ready.
/// Keeps the engine resident afterward. Model URL is resolved on the MainActor in
/// `makeBrain` — this type never touches `ModelAssetManager` off the main actor.
final class LazyLoadingEngine: LlamaEngine, @unchecked Sendable {
    private let underlying = CllamaEngine()
    private let modelURL: URL?
    private let downloadingMessage: String?
    private let config: LlamaEngineConfig
    private var loaded = false
    private let lock = NSLock()

    init(modelURL: URL?, downloadingMessage: String? = nil, config: LlamaEngineConfig) {
        self.modelURL = modelURL
        self.downloadingMessage = downloadingMessage
        self.config = config
    }

    func load(modelPath: URL, config: LlamaEngineConfig) throws {
        try underlying.load(modelPath: modelPath, config: config)
    }

    func unload() { underlying.unload(); loaded = false }

    private func ensureLoaded() throws {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return }
        if let downloadingMessage {
            throw BrainError.modelDownloading(downloadingMessage)
        }
        guard let url = modelURL else {
            throw BrainError.modelNotReady("Local model not downloaded — open Settings › Local AI.")
        }
        try underlying.load(modelPath: url, config: config)
        loaded = true
    }

    func complete(systemPrompt: String, userPrompt: String, grammar: String?, maxTokens: Int) throws -> String {
        try ensureLoaded()
        return try underlying.complete(systemPrompt: systemPrompt, userPrompt: userPrompt, grammar: grammar, maxTokens: maxTokens)
    }

    func stream(systemPrompt: String, userPrompt: String, onToken: @escaping (String) -> Bool) throws {
        try ensureLoaded()
        try underlying.stream(systemPrompt: systemPrompt, userPrompt: userPrompt, onToken: onToken)
    }
}
