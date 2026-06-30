import XCTest
@testable import VoidloomCore

final class SpaceModelTests: XCTestCase {
    func testSpaceConfigRoundTripsAllBackgroundCases() throws {
        let configs = [
            SpaceConfig(background: .atmosphere),
            SpaceConfig(background: .solid(hex: "#102030FF")),
            SpaceConfig(
                background: .image(fileName: "abc.png"),
                tiling: SpaceTiling(mode: .fixedColumns, columns: 3, gap: 20, margin: 30, targetAspect: 1.4),
                backgroundDimming: 0.5,
                cardOrder: nil
            )
        ]

        for config in configs {
            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(SpaceConfig.self, from: data)
            XCTAssertEqual(decoded, config)
        }
    }

    func testSpaceConfigDefaults() {
        let config = SpaceConfig()
        XCTAssertEqual(config.background, .atmosphere)
        XCTAssertEqual(config.tiling.mode, .auto)
        XCTAssertEqual(config.backgroundDimming, 0.35, accuracy: 0.0001)
        XCTAssertNil(config.cardOrder)
    }
}

extension SpaceModelTests {
    func testWorkspaceStateDecodesLegacyJSONWithoutSpaceKey() throws {
        // A workspace JSON written before Spaces existed: no "space" key.
        let legacyJSON = """
        {
          "cards": [],
          "connections": [],
          "strokes": [],
          "textElements": [],
          "viewport": { "origin": { "x": 0, "y": 0 }, "scale": 1 }
        }
        """
        let data = Data(legacyJSON.utf8)
        let state = try JSONDecoder().decode(WorkspaceState.self, from: data)
        XCTAssertNil(state.space)
    }

    func testWorkspaceStateRoundTripsSpaceConfig() throws {
        var state = WorkspaceState(cards: [])
        state.space = SpaceConfig(background: .solid(hex: "#000000FF"), backgroundDimming: 0.42)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)
        XCTAssertEqual(decoded.space, state.space)
    }

    func testWorkspaceStateOmitsSpaceWhenNil() throws {
        let state = WorkspaceState(cards: [])
        let data = try JSONEncoder().encode(state)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("\"space\""))
    }
}
