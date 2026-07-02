import Foundation

/// Which brain configuration to run, decided from runtime capability flags
/// (not per-OS at compile time). Pure decision logic — the App injects live
/// flags (model download state; later, Foundation Models availability).
/// v2b covers tier-2 only: FM resolution lands with the Apple-tier plan.
public enum MediatorTier: Equatable, Sendable {
    case fastPathOnly
    case fastPathWithLLM
}

public enum MediatorTierResolver {
    public struct Capabilities: Equatable, Sendable {
        public var commandModelReady: Bool
        public init(commandModelReady: Bool) { self.commandModelReady = commandModelReady }
    }

    public static func resolve(capabilities: Capabilities) -> MediatorTier {
        capabilities.commandModelReady ? .fastPathWithLLM : .fastPathOnly
    }
}
