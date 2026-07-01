import Foundation

/// Deterministic agent-card naming. The built-in pack is generic tactical
/// callsigns (ordinary dictionary words only — never game-branded, no coined
/// names). Users can substitute any custom pack.
public struct AgentNamePool: Equatable, Sendable {
    public static let defaultCallsigns = [
        "viper", "omen", "phoenix", "sage", "echo", "harbor",
        "breach", "cipher", "nova", "drift", "ember", "slate",
    ]

    private let names: [String]

    public init(names: [String] = AgentNamePool.defaultCallsigns) {
        self.names = names.map { $0.lowercased() }
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
