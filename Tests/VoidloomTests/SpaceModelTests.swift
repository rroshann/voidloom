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

    func testSpaceTilingDefaultsMaxRowsToNil() {
        XCTAssertNil(SpaceTiling().maxRows)
    }

    func testSpaceTilingRoundTripsMaxRows() throws {
        let tiling = SpaceTiling(mode: .fixedColumns, columns: 3, maxRows: 2)
        let decoded = try JSONDecoder().decode(SpaceTiling.self, from: JSONEncoder().encode(tiling))
        XCTAssertEqual(decoded, tiling)
        XCTAssertEqual(decoded.maxRows, 2)
    }

    func testSpaceTilingDecodesLegacyJSONWithoutMaxRows() throws {
        let legacy = #"{"mode":"fixedColumns","columns":3,"gap":18,"margin":28,"targetAspect":1.6}"#
        let decoded = try JSONDecoder().decode(SpaceTiling.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.maxRows)
        XCTAssertEqual(decoded.columns, 3)
        XCTAssertEqual(decoded.mode, .fixedColumns)
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

    func testReorderSpaceCardWritesCardOrderLeavingCardsUntouched() {
        var state = stateWithCards(3)
        let originalCardsOrder = state.cards.map(\.id)
        state.reorderSpaceCard(fromIndex: 0, toIndex: 2)
        // The canonical cards array is never mutated.
        XCTAssertEqual(state.cards.map(\.id), originalCardsOrder)
        // cardOrder is written so orderedCardIDsForSpace reflects the new order.
        XCTAssertNotNil(state.space?.cardOrder)
        XCTAssertEqual(
            state.orderedCardIDsForSpace,
            [originalCardsOrder[1], originalCardsOrder[2], originalCardsOrder[0]]
        )
    }

    func testReorderSpaceCardOutOfRangeFromIndexIsNoOp() {
        var state = stateWithCards(3)
        let originalCardsOrder = state.cards.map(\.id)
        state.reorderSpaceCard(fromIndex: 5, toIndex: 0)   // fromIndex out of range → no-op
        XCTAssertNil(state.space?.cardOrder)
        XCTAssertEqual(state.orderedCardIDsForSpace, originalCardsOrder)
    }

    func testReorderSpaceCardEqualIndicesIsNoOp() {
        var state = stateWithCards(3)
        state.reorderSpaceCard(fromIndex: 1, toIndex: 1)
        XCTAssertNil(state.space?.cardOrder)
    }

    // (a) equal indices: orderedCardIDsForSpace must be identical to the original.
    func testReorderSpaceCardEqualIndicesLeavesOrderUnchanged() {
        var state = stateWithCards(3)
        let original = state.orderedCardIDsForSpace
        state.reorderSpaceCard(fromIndex: 1, toIndex: 1)
        XCTAssertEqual(state.orderedCardIDsForSpace, original)
    }

    // (b) out-of-range toIndex clamps: item from index 0 should land last.
    func testReorderSpaceCardOutOfRangeToIndexClampsToLast() {
        var state = stateWithCards(3)
        let ids = state.cards.map(\.id)
        state.reorderSpaceCard(fromIndex: 0, toIndex: 99)
        XCTAssertEqual(state.orderedCardIDsForSpace, [ids[1], ids[2], ids[0]])
    }

    func testResetSpaceCardOrderClearsCardOrder() {
        var state = stateWithCards(3)
        state.reorderSpaceCard(fromIndex: 0, toIndex: 2)
        XCTAssertNotNil(state.space?.cardOrder)
        state.resetSpaceCardOrder()
        XCTAssertNil(state.space?.cardOrder)
        XCTAssertEqual(state.orderedCardIDsForSpace, state.cards.map(\.id))
    }

    func testOrderedCardIDsReflectsNewCardOrder() {
        var state = stateWithCards(4)
        let ids = state.cards.map(\.id)
        state.reorderSpaceCard(fromIndex: 3, toIndex: 0)
        XCTAssertEqual(state.orderedCardIDsForSpace, [ids[3], ids[0], ids[1], ids[2]])
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

extension SpaceModelTests {
    @MainActor
    func testSetSpaceBackgroundPersistsImmediately() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(cards: []), storageURL: url, persistenceDelay: 0)
        store.setSpaceBackground(.solid(hex: "#123456FF"))

        let reloaded = try WorkspaceStore.load(from: url)   // synchronous immediate write
        XCTAssertEqual(reloaded.space?.background, .solid(hex: "#123456FF"))
    }

    @MainActor
    func testImportBackgroundImageCopiesAndReferences() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)   // dummy PNG header bytes
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: source)
        }

        let store = WorkspaceStore(state: WorkspaceState(cards: []), storageURL: url, persistenceDelay: 0)
        let fileName = try XCTUnwrap(store.importBackgroundImage(from: source))

        let copied = store.backgroundsDirectoryURL().appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertEqual(store.state.space?.background, .image(fileName: fileName))
        try? FileManager.default.removeItem(at: copied)
    }

    // (e) importBackgroundImage also persists the background choice to the workspace
    // file immediately so a reload sees the same value.
    @MainActor
    func testImportBackgroundImagePersistsToWorkspaceFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: source)
        }

        let store = WorkspaceStore(state: WorkspaceState(cards: []), storageURL: url, persistenceDelay: 0)
        let fileName = try XCTUnwrap(store.importBackgroundImage(from: source))

        // Reload from disk — the workspace file must already carry the background.
        let reloaded = try WorkspaceStore.load(from: url)
        XCTAssertEqual(reloaded.space?.background, .image(fileName: fileName))

        // Clean up the copied image so the temp directory stays tidy.
        try? FileManager.default.removeItem(
            at: store.backgroundsDirectoryURL().appendingPathComponent(fileName)
        )
    }

    func testSelectCardsInSpaceWithOneIDMirrorsSelectedCardID() {
        var state = stateWithCards(3)
        let id = state.cards[1].id
        state.selectCardsInSpace(ids: [id])
        XCTAssertEqual(state.marqueeSelectedCardIDs, [id])
        XCTAssertEqual(state.selectedCardID, id)
        XCTAssertNil(state.selectedTextID)
    }

    func testSelectCardsInSpaceWithManyIDsLeavesSelectedCardIDNil() {
        var state = stateWithCards(3)
        let ids = Set(state.cards.prefix(2).map(\.id))
        state.selectCardsInSpace(ids: ids)
        XCTAssertEqual(state.marqueeSelectedCardIDs, ids)
        XCTAssertNil(state.selectedCardID)
    }

    func testSelectCardsInSpaceWithEmptyClears() {
        var state = stateWithCards(3)
        state.selectCardsInSpace(ids: [state.cards[0].id])
        state.selectCardsInSpace(ids: [])
        XCTAssertTrue(state.marqueeSelectedCardIDs.isEmpty)
        XCTAssertNil(state.selectedCardID)
    }
}
