import Foundation

/// Deterministic agent-card naming. The built-in pack is ordinary dictionary
/// words (nature, mineral, and bird names); users can substitute any custom
/// pack. An empty pack falls back to the defaults.
public struct AgentNamePool: Equatable, Sendable {
    public static let defaultCallsigns = [
        "ember", "slate", "nova", "drift", "ridge", "quartz",
        "wren", "vale", "flint", "cove", "sage", "echo",
    ]

    private let names: [String]

    public init(names: [String] = AgentNamePool.defaultCallsigns) {
        let cleaned = names.map { $0.lowercased() }
        self.names = cleaned.isEmpty ? Self.defaultCallsigns : cleaned
    }

    /// First `count` names not present in `existing` (case-insensitive),
    /// wrapping with "-2", "-3", … suffixes once the pack is exhausted.
    public func nextNames(count: Int, existing: Set<String>) -> [String] {
        let taken = Set(existing.map { $0.lowercased() })
        var result: [String] = []
        var round = 1
        while result.count < count {
            for base in names where result.count < count {
                let candidate = round == 1 ? base : "\(base)-\(round)"
                if !taken.contains(candidate) && !result.contains(candidate) {
                    result.append(candidate)
                }
            }
            round += 1
        }
        return result
    }
}
