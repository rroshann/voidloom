import Foundation
import VoidloomAI
import llama

/// Concrete `LlamaEngine` backed by the vendored llama.xcframework (pinned
/// llama.cpp b9850). Lives in the app target only — the sole place that links
/// libllama. Caps n_ctx per `Config` (mandatory). Model + context load once
/// and stay resident across calls, but each `complete`/`stream` is stateless:
/// `evaluate` clears the KV memory and re-tokenizes the full prompt, so repeated
/// calls cannot accumulate KV until n_ctx overflows. (A persistent system-prompt
/// KV-cache optimization is possible later but deliberately not done here.)
final class CllamaEngine: LlamaEngine, @unchecked Sendable {
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private let lock = NSLock()
    private static let backendInit: Void = { llama_backend_init() }()

    init() { _ = Self.backendInit }

    /// Uncontended at dealloc — no other reference can exist — so the lock-free
    /// core teardown is called directly to release the resident model/context.
    deinit { unloadLocked() }

    func load(modelPath: URL, config: LlamaEngineConfig) throws {
        lock.lock(); defer { lock.unlock() }
        unloadLocked()

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = Int32(config.gpuLayers)
        guard let m = llama_model_load_from_file(modelPath.path, mparams) else {
            throw LlamaEngineError.modelLoadFailed(modelPath.lastPathComponent)
        }
        model = m
        vocab = llama_model_get_vocab(m)

        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(config.contextLength)   // MANDATORY cap
        cparams.n_batch = UInt32(min(config.contextLength, 512))
        guard let c = llama_init_from_model(m, cparams) else {
            llama_model_free(m); model = nil
            throw LlamaEngineError.contextInitFailed
        }
        ctx = c
    }

    func unload() { lock.lock(); defer { lock.unlock() }; unloadLocked() }

    private func unloadLocked() {
        if let c = ctx { llama_free(c); ctx = nil }
        if let m = model { llama_model_free(m); model = nil }
        vocab = nil
    }

    func complete(systemPrompt: String, userPrompt: String,
                  grammar: String?, maxTokens: Int) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard let ctx, let vocab else { throw LlamaEngineError.notLoaded }

        let prompt = Self.chatMLPrompt(system: systemPrompt, user: userPrompt)
        try evaluate(prompt: prompt, ctx: ctx, vocab: vocab)

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(sampler) }
        if let grammar {
            let grammarSampler = grammar.withCString { g in
                "root".withCString { r in
                    llama_sampler_init_grammar(vocab, g, r)
                }
            }
            // NULL means the GBNF failed to parse; adding it would crash at sample
            // time. Throw instead — `defer` frees the partially-built chain.
            guard let grammarSampler else { throw LlamaEngineError.grammarLoadFailed }
            llama_sampler_chain_add(sampler, grammarSampler)
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        var output = ""
        for _ in 0..<maxTokens {
            let token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            output += Self.piece(token, vocab: vocab)
            var next = token
            let batch = llama_batch_get_one(&next, 1)
            if llama_decode(ctx, batch) != 0 { throw LlamaEngineError.decodeFailed }
        }
        return output
    }

    func stream(systemPrompt: String, userPrompt: String,
                onToken: @escaping (String) -> Bool) throws {
        lock.lock(); defer { lock.unlock() }
        guard let ctx, let vocab else { throw LlamaEngineError.notLoaded }
        // Qwen3 emits <think> unless suppressed; append /no_think for chat (spike risk #3).
        let prompt = Self.chatMLPrompt(system: systemPrompt, user: userPrompt + " /no_think")
        try evaluate(prompt: prompt, ctx: ctx, vocab: vocab)

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(0xFFFFFFFF))

        for _ in 0..<1024 {
            let token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            if !onToken(Self.piece(token, vocab: vocab)) { break }
            var next = token
            let batch = llama_batch_get_one(&next, 1)
            if llama_decode(ctx, batch) != 0 { throw LlamaEngineError.decodeFailed }
        }
    }

    // MARK: helpers

    private func evaluate(prompt: String, ctx: OpaquePointer, vocab: OpaquePointer) throws {
        // Stateless per call: drop any KV from a prior call so re-tokenizing the
        // full prompt (with BOS) starts from an empty context instead of growing
        // past n_ctx across calls.
        llama_memory_clear(llama_get_memory(ctx), true)
        var tokens = Self.tokenize(prompt, vocab: vocab, addBos: true)
        let status = tokens.withUnsafeMutableBufferPointer { buf -> Int32 in
            let batch = llama_batch_get_one(buf.baseAddress, Int32(buf.count))
            return llama_decode(ctx, batch)
        }
        // Nonzero means the prompt exceeded n_ctx (or decode failed) — fail loudly
        // rather than sampling from a bad state and emitting garbage.
        if status != 0 { throw LlamaEngineError.decodeFailed }
    }

    private static func tokenize(_ text: String, vocab: OpaquePointer, addBos: Bool) -> [llama_token] {
        let utf8 = Array(text.utf8)
        let capacity = utf8.count + 8
        var tokens = [llama_token](repeating: 0, count: capacity)
        let n = text.withCString { cstr in
            llama_tokenize(vocab, cstr, Int32(utf8.count), &tokens, Int32(capacity), addBos, true)
        }
        return Array(tokens.prefix(Int(max(0, n))))
    }

    private static func piece(_ token: llama_token, vocab: OpaquePointer) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        let n = llama_token_to_piece(vocab, token, &buf, 128, 0, true)
        guard n > 0 else { return "" }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Qwen3 ChatML template.
    private static func chatMLPrompt(system: String, user: String) -> String {
        "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
    }
}

enum LlamaEngineError: Error {
    case modelLoadFailed(String), contextInitFailed, notLoaded, decodeFailed, grammarLoadFailed
}
