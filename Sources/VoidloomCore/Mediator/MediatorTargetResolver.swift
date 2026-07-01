// Sources/VoidloomCore/Mediator/MediatorTargetResolver.swift
import Foundation

public enum TargetResolution: Equatable, Sendable {
    case match(UUID)
    case ambiguous([String])
    case none(suggestion: String?)
}

/// Resolves a spoken/typed name against candidate (id, name) pairs.
/// Ladder: exact (case-insensitive) → unique prefix → unique small
/// misspelling (edit distance ≤ 2) → no match with nearest suggestion.
/// Never guesses on ties: duplicates are surfaced as ambiguous.
public enum MediatorTargetResolver {
    public static func resolve(
        _ spoken: String,
        in candidates: [(id: UUID, name: String)]
    ) -> TargetResolution {
        let query = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        guard !candidates.isEmpty, !query.isEmpty else { return .none(suggestion: nil) }

        let exact = candidates.filter { $0.name.lowercased() == query }
        if exact.count == 1 { return .match(exact[0].id) }
        if exact.count > 1 { return .ambiguous(exact.map(\.name)) }

        let prefixed = candidates.filter { $0.name.lowercased().hasPrefix(query) }
        if prefixed.count == 1 { return .match(prefixed[0].id) }
        if prefixed.count > 1 { return .ambiguous(prefixed.map(\.name)) }

        let scored = candidates
            .map { (candidate: $0, distance: editDistance(query, $0.name.lowercased())) }
            .sorted { $0.distance < $1.distance }
        let best = scored[0]
        if best.distance <= 2 {
            let ties = scored.filter { $0.distance == best.distance }
            if ties.count == 1 { return .match(best.candidate.id) }
            return .ambiguous(ties.map(\.candidate.name))
        }
        // Too far to auto-match, but always offer the nearest name as a
        // question — "did you mean X?" beats a dead-end for voice input.
        return .none(suggestion: best.candidate.name)
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
