import Foundation

/// Which brain configuration to run, decided from runtime capability flags
/// (not per-OS at compile time). Pure decision logic — the App injects live
/// flags (model download state; later, Foundation Models availability).
public enum MediatorTier: Equatable, Sendable {
    case fastPathOnly
    case fastPathWithLLM
    case appleFoundationModels
}

public enum MediatorTierResolver {
    public struct Capabilities: Equatable, Sendable {
        public var commandModelReady: Bool
        public var foundationModelsAvailable: Bool

        public init(commandModelReady: Bool) {
            self.commandModelReady = commandModelReady
            self.foundationModelsAvailable = false
        }

        public init(commandModelReady: Bool, foundationModelsAvailable: Bool = false) {
            self.commandModelReady = commandModelReady
            self.foundationModelsAvailable = foundationModelsAvailable
        }
    }

    public static func resolve(capabilities: Capabilities) -> MediatorTier {
        if capabilities.foundationModelsAvailable {
            return .appleFoundationModels
        }
        return capabilities.commandModelReady ? .fastPathWithLLM : .fastPathOnly
    }
}
