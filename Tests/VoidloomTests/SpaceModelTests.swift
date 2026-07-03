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

    @MainActor
    func testSetSpaceTilingPersistsImmediately() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(cards: []), storageURL: url, persistenceDelay: 0)
        store.setSpaceTiling(SpaceTiling(mode: .fixedColumns, columns: 3, maxRows: 2))

        let reloaded = try WorkspaceStore.load(from: url)   // synchronous immediate write
        XCTAssertEqual(reloaded.space?.tiling.columns, 3)
        XCTAssertEqual(reloaded.space?.tiling.maxRows, 2)
        XCTAssertEqual(reloaded.space?.tiling.mode, .fixedColumns)
    }

    func testSpaceConfigLayoutDefaults() {
        let config = SpaceConfig()
        XCTAssertEqual(config.layoutMode, .pagedGrid)
        XCTAssertTrue(config.freeFrames.isEmpty)
    }

    func testSpaceConfigDecodesLegacyJSONWithoutLayoutKeys() throws {
        // Simulate a pre-free-arrange file: encode a current config, then strip
        // the new keys so decoding must fall back to defaults.
        let data = try JSONEncoder().encode(SpaceConfig(backgroundDimming: 0.5))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "layoutMode")
        object.removeValue(forKey: "freeFrames")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SpaceConfig.self, from: legacy)
        XCTAssertEqual(decoded.layoutMode, .pagedGrid)
        XCTAssertTrue(decoded.freeFrames.isEmpty)
        XCTAssertEqual(decoded.backgroundDimming, 0.5, accuracy: 0.0001)
    }

    func testSpaceConfigRoundTripsLayoutModeAndFreeFrames() throws {
        var config = SpaceConfig()
        let id = UUID()
        config.layoutMode = .freeArrange
        config.freeFrames = [id: SpaceFreeFrame(origin: ScreenPoint(x: 40, y: 60),
                                                size: ScreenPoint(x: 320, y: 220))]
        let decoded = try JSONDecoder().decode(SpaceConfig.self, from: JSONEncoder().encode(config))
        XCTAssertEqual(decoded, config)
    }

    func testSetSpaceLayoutModeMaterializesAndSets() {
        var state = stateWithCards(1)
        state.setSpaceLayoutMode(.freeArrange)
        XCTAssertEqual(state.space?.layoutMode, .freeArrange)
        state.setSpaceLayoutMode(.pagedGrid)
        XCTAssertEqual(state.space?.layoutMode, .pagedGrid)
    }

    func testSeedMissingFreeFramesOnlyFillsAbsentEntries() {
        var state = stateWithCards(2)
        let (a, b) = (state.cards[0].id, state.cards[1].id)
        let existing = SpaceFreeFrame(origin: ScreenPoint(x: 5, y: 5), size: ScreenPoint(x: 100, y: 80))
        state.setSpaceLayoutMode(.freeArrange)
        state.space?.freeFrames[a] = existing

        let seedA = SpaceFreeFrame(origin: ScreenPoint(x: 900, y: 900), size: ScreenPoint(x: 1, y: 1))
        let seedB = SpaceFreeFrame(origin: ScreenPoint(x: 50, y: 60), size: ScreenPoint(x: 300, y: 200))
        state.seedMissingFreeFrames([a: seedA, b: seedB])

        XCTAssertEqual(state.space?.freeFrames[a], existing)   // never overwritten
        XCTAssertEqual(state.space?.freeFrames[b], seedB)
    }

    func testMoveSpaceCardFreelyUpdatesOriginKeepingSize() {
        var state = stateWithCards(1)
        let id = state.cards[0].id
        state.setSpaceLayoutMode(.freeArrange)
        state.seedMissingFreeFrames([id: SpaceFreeFrame(origin: ScreenPoint(x: 10, y: 10),
                                                        size: ScreenPoint(x: 300, y: 200))])
        state.moveSpaceCardFreely(id: id, to: ScreenPoint(x: 120, y: 140))
        XCTAssertEqual(state.space?.freeFrames[id]?.origin, ScreenPoint(x: 120, y: 140))
        XCTAssertEqual(state.space?.freeFrames[id]?.size, ScreenPoint(x: 300, y: 200))
    }

    func testResizeSpaceCardFreelyUpdatesSizeKeepingOrigin() {
        var state = stateWithCards(1)
        let id = state.cards[0].id
        state.setSpaceLayoutMode(.freeArrange)
        state.seedMissingFreeFrames([id: SpaceFreeFrame(origin: ScreenPoint(x: 40, y: 50),
                                                        size: ScreenPoint(x: 300, y: 200))])
        state.resizeSpaceCardFreely(id: id, to: ScreenPoint(x: 500, y: 380))
        XCTAssertEqual(state.space?.freeFrames[id]?.size, ScreenPoint(x: 500, y: 380))
        XCTAssertEqual(state.space?.freeFrames[id]?.origin, ScreenPoint(x: 40, y: 50))
    }

    func testResizeSpaceCardFreelyClampsToCardMinimums() {
        var state = stateWithCards(1)
        let id = state.cards[0].id
        state.setSpaceLayoutMode(.freeArrange)
        state.seedMissingFreeFrames([id: SpaceFreeFrame(origin: ScreenPoint(x: 0, y: 0),
                                                        size: ScreenPoint(x: 300, y: 200))])
        state.resizeSpaceCardFreely(id: id, to: ScreenPoint(x: 10, y: 10))
        XCTAssertEqual(state.space?.freeFrames[id]?.size.x ?? 0, CardSize.minimumWidth)
        XCTAssertEqual(state.space?.freeFrames[id]?.size.y ?? 0, CardSize.minimumHeight)
    }

    func testResizeSpaceCardFreelyUnknownIDIsNoOp() {
        var state = stateWithCards(1)
        state.setSpaceLayoutMode(.freeArrange)
        state.resizeSpaceCardFreely(id: UUID(), to: ScreenPoint(x: 400, y: 300))
        XCTAssertTrue(state.space?.freeFrames.isEmpty ?? false)
    }

    func testMoveSpaceCardFreelyUnknownIDIsNoOp() {
        var state = stateWithCards(1)
        state.setSpaceLayoutMode(.freeArrange)
        state.moveSpaceCardFreely(id: UUID(), to: ScreenPoint(x: 1, y: 1))
        XCTAssertTrue(state.space?.freeFrames.isEmpty ?? false)
    }

    func testDeleteCardPrunesItsFreeFrame() {
        var state = stateWithCards(2)
        let (a, b) = (state.cards[0].id, state.cards[1].id)
        state.setSpaceLayoutMode(.freeArrange)
        let frame = SpaceFreeFrame(origin: ScreenPoint(x: 0, y: 0), size: ScreenPoint(x: 10, y: 10))
        state.seedMissingFreeFrames([a: frame, b: frame])

        state.deleteCard(id: a)
        XCTAssertNil(state.space?.freeFrames[a])
        XCTAssertNotNil(state.space?.freeFrames[b])

        state.deleteCards(ids: [b])
        XCTAssertTrue(state.space?.freeFrames.isEmpty ?? false)
    }

    func testActivateCardSetsActiveAndClearsSelection() {
        var state = stateWithCards(2)
        let (a, b) = (state.cards[0].id, state.cards[1].id)
        state.selectCard(id: a)
        state.activateCard(id: b)
        XCTAssertEqual(state.activeCardID, b)
        XCTAssertNil(state.selectedCardID)
        XCTAssertTrue(state.marqueeSelectedCardIDs.isEmpty)
    }

    func testActivateUnknownCardIsNoOp() {
        var state = stateWithCards(1)
        state.selectCard(id: state.cards[0].id)
        state.activateCard(id: UUID())
        XCTAssertNil(state.activeCardID)
        XCTAssertEqual(state.selectedCardID, state.cards[0].id)
    }

    func testSelectionMutationsClearActiveCard() {
        var state = stateWithCards(2)
        let (a, b) = (state.cards[0].id, state.cards[1].id)

        state.activateCard(id: a)
        state.selectCard(id: b)
        XCTAssertNil(state.activeCardID)

        state.activateCard(id: a)
        state.toggleCardInSelection(id: b)
        XCTAssertNil(state.activeCardID)

        state.activateCard(id: a)
        state.selectCardsInSpace(ids: [b])
        XCTAssertNil(state.activeCardID)

        state.activateCard(id: a)
        state.clearSelection()
        XCTAssertNil(state.activeCardID)
    }

    func testDeleteClearsActiveCardOnlyWhenDeleted() {
        var state = stateWithCards(2)
        let (a, b) = (state.cards[0].id, state.cards[1].id)
        state.activateCard(id: a)
        state.deleteCard(id: b)
        XCTAssertEqual(state.activeCardID, a)
        state.deleteCards(ids: [a])
        XCTAssertNil(state.activeCardID)
    }

    func testActiveCardIDIsNotPersisted() throws {
        var state = stateWithCards(1)
        state.activateCard(id: state.cards[0].id)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: JSONEncoder().encode(state))
        XCTAssertNil(decoded.activeCardID)
    }

    func testSetSpaceFreeFramesReplacesAll() {
        var state = stateWithCards(2)
        let (a, b) = (state.cards[0].id, state.cards[1].id)
        let f1 = SpaceFreeFrame(origin: ScreenPoint(x: 1, y: 1), size: ScreenPoint(x: 10, y: 10))
        let f2 = SpaceFreeFrame(origin: ScreenPoint(x: 2, y: 2), size: ScreenPoint(x: 20, y: 20))
        state.seedMissingFreeFrames([a: f1])
        state.setSpaceFreeFrames([b: f2])
        XCTAssertNil(state.space?.freeFrames[a])
        XCTAssertEqual(state.space?.freeFrames[b], f2)
    }

    func testFreeFrameHitTestOverlapsAndMisses() {
        let a = UUID(), b = UUID()
        let frames = [
            a: SpaceFreeFrame(origin: ScreenPoint(x: 0, y: 0), size: ScreenPoint(x: 100, y: 100)),
            b: SpaceFreeFrame(origin: ScreenPoint(x: 300, y: 300), size: ScreenPoint(x: 50, y: 50))
        ]
        // Box covering only frame a (order-independent corners).
        let hitA = SpaceGrid.cardIDs(fromCorner: ScreenPoint(x: 90, y: 90),
                                     toCorner: ScreenPoint(x: 10, y: 10), frames: frames)
        XCTAssertEqual(hitA, [a])
        // Box grazing both.
        let hitBoth = SpaceGrid.cardIDs(fromCorner: ScreenPoint(x: 50, y: 50),
                                        toCorner: ScreenPoint(x: 310, y: 310), frames: frames)
        XCTAssertEqual(Set(hitBoth), [a, b])
        // Box touching neither (edge-exclusive, like tileIndices).
        let miss = SpaceGrid.cardIDs(fromCorner: ScreenPoint(x: 110, y: 110),
                                     toCorner: ScreenPoint(x: 290, y: 290), frames: frames)
        XCTAssertTrue(miss.isEmpty)
    }

    @MainActor
    func testResetAllDataWipesDiskAndRecreatesFreshLibrary() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let workspacesDir = base.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: base.appendingPathComponent("library.json"),
            workspacesDirectoryURL: workspacesDir,
            legacyStorageURL: base.appendingPathComponent("workspace.json"),
            persistenceDelay: 0
        )
        store.addCard(kind: .note)
        store.createWorkspace(named: "Second")
        store.addCard(kind: .todo)
        XCTAssertEqual(store.library.workspaces.count, 2)

        store.resetAllData()

        XCTAssertEqual(store.library.workspaces.count, 1)
        XCTAssertTrue(store.state.cards.isEmpty)
        // Disk holds exactly the one fresh workspace file, and the persisted
        // library points at it.
        let files = try fm.contentsOfDirectory(at: workspacesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(
            files.first?.lastPathComponent,
            "\(store.library.selectedWorkspaceID.uuidString).json"
        )
        let reloaded = try WorkspaceStore.load(
            from: WorkspaceStore.workspaceURL(for: store.library.selectedWorkspaceID, in: workspacesDir)
        )
        XCTAssertTrue(reloaded.cards.isEmpty)
    }

    @MainActor
    func testCenterViewportPutsCanvasPointAtScreenCenter() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(cards: []), storageURL: url, persistenceDelay: 0)
        let target = CanvasPoint(x: 500, y: -300)
        let viewport = ScreenPoint(x: 1200, y: 800)
        store.centerViewport(on: target, viewportSize: viewport)

        let screen = store.state.viewport.screenPoint(forCanvasPoint: target)
        XCTAssertEqual(screen.x, 600, accuracy: 0.0001)
        XCTAssertEqual(screen.y, 400, accuracy: 0.0001)
        // Scale must be untouched — recenter is a pan, not a zoom.
        XCTAssertEqual(store.state.viewport.scale, 1, accuracy: 0.0001)
    }

    @MainActor
    func testSetSpaceLayoutModePersistsImmediately() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(cards: []), storageURL: url, persistenceDelay: 0)
        store.setSpaceLayoutMode(.freeArrange)

        let reloaded = try WorkspaceStore.load(from: url)
        XCTAssertEqual(reloaded.space?.layoutMode, .freeArrange)
    }

    @MainActor
    func testStoreSelectCardsInSpaceUpdatesSelection() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: stateWithCards(3), storageURL: url, persistenceDelay: 0)
        let ids = Set(store.state.cards.prefix(2).map(\.id))
        store.selectCardsInSpace(ids: ids)

        XCTAssertEqual(store.state.marqueeSelectedCardIDs, ids)
        XCTAssertNil(store.state.selectedCardID)
    }
}
