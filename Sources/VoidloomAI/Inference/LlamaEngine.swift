import Foundation

/// Pure-Swift seam over a llama.cpp context. The concrete `CllamaEngine`
/// (app target) links the vendored xcframework and conforms; `VoidloomAI`
/// never imports llama, so `swift test` stays headless. Grammar-constrained
/// `complete` powers `LlamaBrain`; streaming `stream` powers the chat
/// `LocalResponseProvider`.
public protocol LlamaEngine: AnyObject, Sendable {
    /// Loads a GGUF model and holds it resident. Caps context per `config`
    /// (mandatory — default n_ctx blows RSS to ~4.9 GB, spike risk #2).
    func load(modelPath: URL, config: LlamaEngineConfig) throws
    func unload()

    /// One grammar-constrained completion. Greedy decoding; returns the raw
    /// generated string (expected to be schema-valid JSON when a grammar is set).
    func complete(systemPrompt: String, userPrompt: String,
                  grammar: String?, maxTokens: Int) throws -> String

    /// Streamed, unconstrained generation for chat. `onToken` returns false to stop.
    func stream(systemPrompt: String, userPrompt: String,
                onToken: @escaping (String) -> Bool) throws
}

/// Load-time configuration for a `LlamaEngine`. Top-level rather than nested in
/// the protocol: Swift forbids concrete types nested inside a protocol, so the
/// spike-plan's `LlamaEngine.Config` spelling is expressed as `LlamaEngineConfig`.
public struct LlamaEngineConfig: Sendable, Equatable {
    /// Hard context cap. 2048 keeps RSS ~0.3–0.7 GB (spike-measured).
    public var contextLength: Int
    /// GPU layers offloaded to Metal (-1/large = all).
    public var gpuLayers: Int
    public var seed: UInt32

    public init(contextLength: Int = 2048, gpuLayers: Int = 999, seed: UInt32 = 0xFFFFFFFF) {
        self.contextLength = contextLength
        self.gpuLayers = gpuLayers
        self.seed = seed
    }
}
