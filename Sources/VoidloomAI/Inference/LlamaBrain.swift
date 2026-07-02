import Foundation
import VoidloomCore

/// Tier-2 grammar-constrained brain. Runs the model with GBNF from
/// `MediatorCommandSchema`, so raw output is (structurally) always
/// schema-valid JSON; a decode failure means the model produced something
/// off-grammar and we throw `.unparseable` (fast path / rephrase handles it).
/// Field extraction is validated downstream by `MediatorTargetResolver`.
public final class LlamaBrain: MediatorBrain, @unchecked Sendable {
    private let engine: LlamaEngine
    private let systemPrompt: String
    private let maxTokens: Int

    public init(engine: LlamaEngine,
                systemPrompt: String = LlamaBrain.defaultSystemPrompt,
                maxTokens: Int = 96) {
        self.engine = engine
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
    }

    public func command(for utterance: String) async throws -> MediatorCommand {
        let raw: String
        do {
            raw = try engine.complete(systemPrompt: systemPrompt, userPrompt: utterance,
                                      grammar: MediatorGrammar.rootGrammar, maxTokens: maxTokens)
        } catch {
            throw BrainError.backendFailure("The local model failed to respond.")
        }
        guard let data = Self.firstJSONObject(in: raw)?.data(using: .utf8),
              let command = try? JSONDecoder().decode(MediatorCommand.self, from: data) else {
            throw BrainError.unparseable(utterance)
        }
        return command
    }

    /// Trims any stray text around the JSON object (grammar makes this rare).
    static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        return String(text[start...end])
    }

    /// Lowercase, realistic few-shot examples (spike: uppercase placeholders made
    /// the tiny model uppercase targets). Keep short.
    public static let defaultSystemPrompt = """
    You translate a single spoken workspace command into one JSON object matching the schema. \
    Output ONLY the JSON. Examples:
    ask ember to fix the build -> {"sendPrompt":{"target":"ember","text":"fix the build"}}
    start 4 claude agents -> {"spawnAgents":{"count":4,"kind":"claude"}}
    switch to research -> {"switchSpace":{"name":"research"}}
    close ember -> {"closeTerminal":{"target":"ember"}}
    read what slate is saying -> {"readOutput":{"target":"slate"}}
    tile the windows in a grid -> {"arrange":{"style":{"grid":{}}}}
    make a todo that says buy milk -> {"createCard":{"kind":"todo","content":"buy milk"}}
    """
}
