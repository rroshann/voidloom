import Foundation

/// Fast path first, LLM only on `.unparseable`. The spec's sanctioned layering:
/// deterministic `FastPathBrain` handles the common verb-first phrasings
/// instantly; anything it can't parse falls through to a grammar-constrained
/// LLM brain. Any non-`.unparseable` error from the fast path (there are none
/// today) propagates unchanged — only "I couldn't parse this" warrants the LLM.
public final class TieredBrain: MediatorBrain, @unchecked Sendable {
    private let fast: MediatorBrain
    private let fallback: MediatorBrain

    public init(fast: MediatorBrain, fallback: MediatorBrain) {
        self.fast = fast
        self.fallback = fallback
    }

    public func command(for utterance: String) async throws -> MediatorCommand {
        do {
            return try await fast.command(for: utterance)
        } catch BrainError.unparseable {
            return try await fallback.command(for: utterance)
        }
    }
}
