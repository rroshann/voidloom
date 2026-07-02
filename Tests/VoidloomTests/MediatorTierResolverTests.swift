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
}
