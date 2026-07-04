import XCTest
@testable import VoidloomCore

final class MediatorTierResolverTests: XCTestCase {
    func testCommandModelReadyEnablesLLMFallbackTier() {
        let tier = MediatorTierResolver.resolve(capabilities: .init(commandModelReady: true))
        XCTAssertEqual(tier, .fastPathWithLLM)
    }

    func testCommandModelMissingFallsBackToFastPathOnly() {
        let tier = MediatorTierResolver.resolve(capabilities: .init(commandModelReady: false))
        XCTAssertEqual(tier, .fastPathOnly)
    }

    func testFoundationModelsAvailableSelectsAppleTierRegardlessOfCommandModel() {
        let withCommandModel = MediatorTierResolver.resolve(
            capabilities: .init(commandModelReady: true, foundationModelsAvailable: true))
        let withoutCommandModel = MediatorTierResolver.resolve(
            capabilities: .init(commandModelReady: false, foundationModelsAvailable: true))
        XCTAssertEqual(withCommandModel, .appleFoundationModels)
        XCTAssertEqual(withoutCommandModel, .appleFoundationModels)
    }

    func testFoundationModelsUnavailableCommandModelReadyUsesLLMTier() {
        let tier = MediatorTierResolver.resolve(
            capabilities: .init(commandModelReady: true, foundationModelsAvailable: false))
        XCTAssertEqual(tier, .fastPathWithLLM)
    }

    func testFoundationModelsUnavailableCommandModelMissingUsesFastPathOnly() {
        let tier = MediatorTierResolver.resolve(
            capabilities: .init(commandModelReady: false, foundationModelsAvailable: false))
        XCTAssertEqual(tier, .fastPathOnly)
    }
}
