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

extension SpaceModelTests {
    private func stateWithCards(_ n: Int) -> WorkspaceState {
        WorkspaceState(cards: (0..<n).map { i in
            WorkspaceCard(kind: .note,
                          position: CanvasPoint(x: Double(i), y: 0),
                          size: CardSize(width: 240, height: 160),
                          title: "C\(i)", content: "")
        })
    }

    func testEnsureSpaceConfigMaterializesDefaultsOnce() {
        var state = stateWithCards(0)
        XCTAssertNil(state.space)
        state.ensureSpaceConfig()
        XCTAssertEqual(state.space, SpaceConfig())
        state.space?.backgroundDimming = 0.9
        state.ensureSpaceConfig()                       // must not overwrite
        XCTAssertEqual(state.space!.backgroundDimming, 0.9, accuracy: 0.0001)
    }

    func testOrderedCardIDsFollowArrayWhenNoCardOrder() {
        let state = stateWithCards(3)
        XCTAssertEqual(state.orderedCardIDsForSpace, state.cards.map(\.id))
    }

    func testMoveCardReordersArray() {
        var state = stateWithCards(3)
        let ids = state.cards.map(\.id)
        state.moveCard(fromIndex: 0, toIndex: 2)
        XCTAssertEqual(state.cards.map(\.id), [ids[1], ids[2], ids[0]])
    }

    func testMoveCardIgnoresOutOfRangeIndices() {
        var state = stateWithCards(2)
        let ids = state.cards.map(\.id)
        state.moveCard(fromIndex: 0, toIndex: 9)        // out of range → no-op
        XCTAssertEqual(state.cards.map(\.id), ids)
    }

    func testSettersMaterializeAndUpdateConfig() {
        var state = stateWithCards(1)
        state.setSpaceBackground(.solid(hex: "#ABCDEFFF"))
        state.setSpaceTiling(SpaceTiling(mode: .fixedColumns, columns: 4))
        state.setBackgroundDimming(0.6)
        XCTAssertEqual(state.space?.background, .solid(hex: "#ABCDEFFF"))
        XCTAssertEqual(state.space?.tiling.columns, 4)
        XCTAssertEqual(state.space!.backgroundDimming, 0.6, accuracy: 0.0001)
    }

    func testBackgroundDimmingIsClamped() {
        var state = stateWithCards(1)
        state.setBackgroundDimming(1.7)
        XCTAssertEqual(state.space!.backgroundDimming, 1.0, accuracy: 0.0001)
        state.setBackgroundDimming(-0.3)
        XCTAssertEqual(state.space!.backgroundDimming, 0.0, accuracy: 0.0001)
    }
}
