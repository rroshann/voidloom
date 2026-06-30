import XCTest
@testable import VoidloomCore

final class WorkspaceModelTests: XCTestCase {
    func testViewportRoundTripsScreenAndCanvasPoints() {
        let viewport = CanvasViewport(origin: CanvasPoint(x: -120, y: 45), scale: 1.75)
        let screenPoint = ScreenPoint(x: 260, y: 150)

        let canvasPoint = viewport.canvasPoint(forScreenPoint: screenPoint)
        let roundTrippedPoint = viewport.screenPoint(forCanvasPoint: canvasPoint)

        XCTAssertEqual(roundTrippedPoint.x, screenPoint.x, accuracy: 0.0001)
        XCTAssertEqual(roundTrippedPoint.y, screenPoint.y, accuracy: 0.0001)
    }

    func testViewportFocusCentersCardWithPadding() {
        var viewport = CanvasViewport()
        let cardOrigin = CanvasPoint(x: 100, y: 100)
        let cardSize = CardSize(width: 320, height: 220)
        let viewportSize = ScreenPoint(x: 900, y: 600)
        let padding = 48.0

        viewport.focus(
            onCanvasRect: cardOrigin,
            size: cardSize,
            padding: padding,
            viewportSize: viewportSize
        )

        let cardCenter = CanvasPoint(
            x: cardOrigin.x + (cardSize.width / 2),
            y: cardOrigin.y + (cardSize.height / 2)
        )
        let screenCenter = viewport.screenPoint(forCanvasPoint: cardCenter)

        XCTAssertEqual(screenCenter.x, viewportSize.x / 2, accuracy: 0.0001)
        XCTAssertEqual(screenCenter.y, viewportSize.y / 2, accuracy: 0.0001)

        let expectedScale = min(
            (viewportSize.x - (padding * 2)) / cardSize.width,
            (viewportSize.y - (padding * 2)) / cardSize.height
        )
        XCTAssertEqual(viewport.scale, expectedScale, accuracy: 0.0001)
    }

    func testMovingCardUsesCanvasCoordinatesWhenZoomed() throws {
        let cardID = try XCTUnwrap(UUID(uuidString: "9C664805-A57C-45B4-A4FE-2F46B6B3FD15"))
        var state = WorkspaceState(
            viewport: CanvasViewport(origin: .zero, scale: 2),
            cards: [
                WorkspaceCard(
                    id: cardID,
                    kind: .agent,
                    position: CanvasPoint(x: 10, y: 20),
                    size: CardSize(width: 320, height: 220),
                    title: "Scout",
                    content: "Mapping the codebase."
                )
            ]
        )

        state.moveCard(id: cardID, screenTranslation: CanvasVector(dx: 40, dy: -20))

        let card = try XCTUnwrap(state.cards.first)
        XCTAssertEqual(card.position.x, 30, accuracy: 0.0001)
        XCTAssertEqual(card.position.y, 10, accuracy: 0.0001)
    }

    func testWorkspaceSelectionStartsEmptyAndCanBeCleared() throws {
        let cardID = try XCTUnwrap(UUID(uuidString: "B232D327-344C-446B-B577-53C326856252"))
        var state = WorkspaceState(
            cards: [
                WorkspaceCard(
                    id: cardID,
                    kind: .browser,
                    position: CanvasPoint(x: 120, y: 160),
                    size: CardSize(width: 380, height: 240),
                    title: "Preview",
                    content: "Canvas selection target."
                )
            ]
        )

        XCTAssertNil(state.selectedCardID)

        state.selectCard(id: cardID)
        XCTAssertEqual(state.selectedCardID, cardID)

        state.clearSelection()
        XCTAssertNil(state.selectedCardID)
    }

    func testSelectingUnknownCardDoesNotReplaceCurrentSelection() throws {
        let cardID = try XCTUnwrap(UUID(uuidString: "2E870590-D9B4-49ED-A77D-6823D3C89DDE"))
        let missingCardID = try XCTUnwrap(UUID(uuidString: "E9B47781-7987-419F-AEC6-4763C6817E78"))
        var state = WorkspaceState(
            cards: [
                WorkspaceCard(
                    id: cardID,
                    kind: .agent,
                    position: CanvasPoint(x: 80, y: 110),
                    size: CardSize(width: 360, height: 240),
                    title: "Agent",
                    content: "Existing selection."
                )
            ]
        )

        state.selectCard(id: cardID)
        state.selectCard(id: missingCardID)

        XCTAssertEqual(state.selectedCardID, cardID)
    }

    func testWorkspaceStateEncodesAndDecodesCards() throws {
        let state = WorkspaceState(
            viewport: CanvasViewport(origin: CanvasPoint(x: 12, y: -34), scale: 0.85),
            cards: [
                WorkspaceCard(
                    id: try XCTUnwrap(UUID(uuidString: "0BC230D1-182E-4700-9740-47456C681017")),
                    kind: .todo,
                    position: CanvasPoint(x: 80, y: 140),
                    size: CardSize(width: 280, height: 180),
                    title: "Launch Checklist",
                    content: "Verify canvas interactions."
                )
            ]
        )

        let data = try JSONEncoder().encode(state)
        let decodedState = try JSONDecoder().decode(WorkspaceState.self, from: data)

        XCTAssertEqual(decodedState.viewport, state.viewport)
        XCTAssertEqual(decodedState.cards, state.cards)
    }

    func testStoreSavesAndLoadsWorkspaceState() throws {
        let state = WorkspaceState(
            viewport: CanvasViewport(origin: CanvasPoint(x: -90, y: 24), scale: 1.4),
            cards: [
                WorkspaceCard(
                    id: try XCTUnwrap(UUID(uuidString: "28178064-2D77-448A-B47B-17CDDB4E6317")),
                    kind: .note,
                    position: CanvasPoint(x: 260, y: 120),
                    size: CardSize(width: 300, height: 190),
                    title: "Memory",
                    content: "Keep canvas state local."
                )
            ]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        try WorkspaceStore.save(state, to: url)
        let loadedState = try WorkspaceStore.load(from: url)

        XCTAssertEqual(loadedState, state)
    }

    @MainActor
    func testPanDoesNotSynchronouslyPersistWorkspaceState() {
        let state = WorkspaceState(
            viewport: CanvasViewport(origin: .zero, scale: 1),
            cards: []
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(
            state: state,
            storageURL: url,
            persistenceDelay: 60
        )

        store.pan(by: CanvasVector(dx: 12, dy: -8))

        XCTAssertEqual(store.state.viewport.origin, CanvasPoint(x: 12, y: -8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testPanPersistsWorkspaceStateAfterDebounce() async throws {
        let state = WorkspaceState(
            viewport: CanvasViewport(origin: .zero, scale: 1),
            cards: []
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(
            state: state,
            storageURL: url,
            persistenceDelay: 0.01
        )

        store.pan(by: CanvasVector(dx: 12, dy: -8))
        try await Task.sleep(nanoseconds: 50_000_000)

        let loadedState = try WorkspaceStore.load(from: url)
        XCTAssertEqual(loadedState.viewport.origin, CanvasPoint(x: 12, y: -8))
    }

    func testSeedStateIncludesEachV0CardKind() {
        let seedState = WorkspaceStore.makeSeedState()
        let kinds = Set(seedState.cards.map(\.kind))

        XCTAssertTrue(kinds.contains(.agent))
        XCTAssertTrue(kinds.contains(.note))
        XCTAssertTrue(kinds.contains(.todo))
        XCTAssertTrue(kinds.contains(.browser))
    }

    func testWorkspaceSummaryEncodesAndDecodes() throws {
        let summary = WorkspaceSummary(
            id: try XCTUnwrap(UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")),
            name: "Main Canvas",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            cardCount: 4
        )

        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(WorkspaceSummary.self, from: data)

        XCTAssertEqual(decoded, summary)
    }

    func testWorkspaceLibraryEncodesAndDecodes() throws {
        let selectedID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let otherID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let library = WorkspaceLibrary(
            selectedWorkspaceID: selectedID,
            workspaces: [
                WorkspaceSummary(id: selectedID, name: "Main Canvas", cardCount: 3),
                WorkspaceSummary(id: otherID, name: "Research", cardCount: 0)
            ]
        )

        let data = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(WorkspaceLibrary.self, from: data)

        XCTAssertEqual(decoded.selectedWorkspaceID, selectedID)
        XCTAssertEqual(decoded.workspaces, library.workspaces)
    }

    func testLibraryRoundTripsSelectedWorkspaceID() throws {
        let selectedID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let library = WorkspaceLibrary(
            selectedWorkspaceID: selectedID,
            workspaces: [
                WorkspaceSummary(id: selectedID, name: "Active", cardCount: 1)
            ]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        try WorkspaceStore.saveLibrary(library, to: url)
        let loaded = try WorkspaceStore.loadLibrary(from: url)

        XCTAssertEqual(loaded.selectedWorkspaceID, selectedID)
    }

    func testSaveAndLoadWorkspaceStateByWorkspaceID() throws {
        let workspaceID = try XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = WorkspaceState(
            viewport: CanvasViewport(origin: CanvasPoint(x: 5, y: 10), scale: 1.2),
            cards: [
                WorkspaceCard(
                    id: try XCTUnwrap(UUID(uuidString: "55555555-5555-5555-5555-555555555555")),
                    kind: .note,
                    position: CanvasPoint(x: 100, y: 200),
                    size: CardSize(width: 300, height: 180),
                    title: "Note",
                    content: "Persisted per workspace."
                )
            ]
        )
        let url = WorkspaceStore.workspaceURL(for: workspaceID, in: directory)

        try WorkspaceStore.save(state, to: url)
        let loaded = try WorkspaceStore.load(from: url)

        XCTAssertEqual(loaded, state)
    }

    @MainActor
    func testNewStoreCreatesLibraryWithOneSelectedWorkspace() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json")
        )

        XCTAssertEqual(store.library.workspaces.count, 1)
        XCTAssertEqual(store.library.selectedWorkspaceID, store.library.workspaces[0].id)
        XCTAssertEqual(store.library.workspaces[0].name, "Main Canvas")
        XCTAssertFalse(store.state.cards.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.path))
    }

    @MainActor
    func testLegacyWorkspaceJSONMigratesToLibrary() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let legacyURL = baseDirectory.appendingPathComponent("workspace.json")
        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let legacyState = WorkspaceState(
            viewport: CanvasViewport(origin: CanvasPoint(x: 42, y: -12), scale: 1.1),
            cards: [
                WorkspaceCard(
                    id: try XCTUnwrap(UUID(uuidString: "66666666-6666-6666-6666-666666666666")),
                    kind: .agent,
                    position: CanvasPoint(x: 90, y: 120),
                    size: CardSize(width: 360, height: 240),
                    title: "Legacy Agent",
                    content: "Migrated workspace."
                )
            ]
        )
        try WorkspaceStore.save(legacyState, to: legacyURL)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: legacyURL
        )

        XCTAssertEqual(store.library.workspaces.count, 1)
        XCTAssertEqual(store.library.workspaces[0].name, "Main Canvas")
        XCTAssertEqual(store.state, legacyState)
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))

        let workspaceURL = WorkspaceStore.workspaceURL(
            for: store.library.selectedWorkspaceID,
            in: workspacesDirectory
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.path))
    }

    @MainActor
    func testCreateWorkspaceAddsSelectedWorkspaceAndUpdatesState() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json")
        )
        let originalID = store.library.selectedWorkspaceID
        let originalCardCount = store.state.cards.count

        store.createWorkspace(named: "Research")

        XCTAssertEqual(store.library.workspaces.count, 2)
        XCTAssertNotEqual(store.library.selectedWorkspaceID, originalID)
        XCTAssertEqual(store.library.workspaces.last?.name, "Research")
        XCTAssertTrue(store.state.cards.isEmpty)

        let originalWorkspaceURL = WorkspaceStore.workspaceURL(for: originalID, in: workspacesDirectory)
        let originalLoaded = try WorkspaceStore.load(from: originalWorkspaceURL)
        XCTAssertEqual(originalLoaded.cards.count, originalCardCount)
    }

    @MainActor
    func testSwitchWorkspaceFlushesCurrentStateAndLoadsTarget() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json"),
            persistenceDelay: 60
        )
        let firstWorkspaceID = store.library.selectedWorkspaceID

        store.pan(by: CanvasVector(dx: 25, dy: -10))
        store.createWorkspace(named: "Second")
        let secondWorkspaceID = store.library.selectedWorkspaceID

        store.switchWorkspace(id: firstWorkspaceID)

        XCTAssertEqual(store.library.selectedWorkspaceID, firstWorkspaceID)
        XCTAssertEqual(store.state.viewport.origin, CanvasPoint(x: 25, y: -10))

        store.switchWorkspace(id: secondWorkspaceID)
        XCTAssertEqual(store.library.selectedWorkspaceID, secondWorkspaceID)
        XCTAssertEqual(store.state.viewport.origin, .zero)
        XCTAssertTrue(store.state.cards.isEmpty)

        store.switchWorkspace(id: secondWorkspaceID)
        XCTAssertEqual(store.library.selectedWorkspaceID, secondWorkspaceID)
    }

    @MainActor
    func testAddCardUpdatesActiveSummaryCardCount() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json")
        )
        let startingCount = store.state.cards.count

        store.addCard(kind: .note)

        let activeSummary = try XCTUnwrap(
            store.library.workspaces.first(where: { $0.id == store.library.selectedWorkspaceID })
        )
        XCTAssertEqual(activeSummary.cardCount, startingCount + 1)
        XCTAssertEqual(store.state.cards.count, startingCount + 1)
    }

    @MainActor
    func testRenameWorkspaceUpdatesLibrarySummary() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json")
        )
        let workspaceID = store.library.selectedWorkspaceID

        store.renameWorkspace(id: workspaceID, to: "Launch Plan")

        XCTAssertEqual(store.library.workspaces.first?.name, "Launch Plan")

        let loadedLibrary = try WorkspaceStore.loadLibrary(from: libraryURL)
        XCTAssertEqual(loadedLibrary.workspaces.first?.name, "Launch Plan")
    }

    @MainActor
    func testDeleteWorkspaceRemovesSummaryAndSwitchesWhenActive() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json")
        )
        let firstWorkspaceID = store.library.selectedWorkspaceID

        store.createWorkspace(named: "Disposable")
        let disposableID = store.library.selectedWorkspaceID

        store.deleteWorkspace(id: disposableID)

        XCTAssertEqual(store.library.workspaces.count, 1)
        XCTAssertEqual(store.library.selectedWorkspaceID, firstWorkspaceID)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: WorkspaceStore.workspaceURL(for: disposableID, in: workspacesDirectory).path
            )
        )
    }

    @MainActor
    func testDeleteWorkspaceDoesNotRemoveLastWorkspace() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json")
        )
        let workspaceID = store.library.selectedWorkspaceID

        store.deleteWorkspace(id: workspaceID)

        XCTAssertEqual(store.library.workspaces.count, 1)
        XCTAssertEqual(store.library.selectedWorkspaceID, workspaceID)
    }

    @MainActor
    func testMoveWorkspaceByIDReordersLibraryAndPersists() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json")
        )

        store.createWorkspace(named: "Second")
        store.createWorkspace(named: "Third")

        let thirdID = try XCTUnwrap(store.library.workspaces.last?.id)
        store.moveWorkspace(id: thirdID, toIndex: 0)

        XCTAssertEqual(store.library.workspaces.map(\.name), ["Third", "Main Canvas", "Second"])

        let loadedLibrary = try WorkspaceStore.loadLibrary(from: libraryURL)
        XCTAssertEqual(loadedLibrary.workspaces.map(\.name), store.library.workspaces.map(\.name))
    }

    @MainActor
    func testMoveWorkspaceToPositionOfTargetReordersWithoutChangingSelection() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json")
        )

        store.createWorkspace(named: "Second")
        store.createWorkspace(named: "Third")

        let selectedWorkspaceID = store.library.selectedWorkspaceID
        let mainCanvasID = try XCTUnwrap(store.library.workspaces.first { $0.name == "Main Canvas" }?.id)
        let secondID = try XCTUnwrap(store.library.workspaces.first { $0.name == "Second" }?.id)

        store.moveWorkspace(id: mainCanvasID, toPositionOf: secondID)

        XCTAssertEqual(store.library.workspaces.map(\.name), ["Second", "Main Canvas", "Third"])
        XCTAssertEqual(store.library.selectedWorkspaceID, selectedWorkspaceID)

        let loadedLibrary = try WorkspaceStore.loadLibrary(from: libraryURL)
        XCTAssertEqual(loadedLibrary.workspaces.map(\.name), store.library.workspaces.map(\.name))
    }

    func testDeleteCardRemovesCardAndClearsSelection() throws {
        let cardID = try XCTUnwrap(UUID(uuidString: "7A8B9C0D-1E2F-3A4B-5C6D-7E8F9A0B1C2D"))
        let otherCardID = try XCTUnwrap(UUID(uuidString: "8B9C0D1E-2F3A-4B5C-6D7E-8F9A0B1C2D3E"))
        var state = WorkspaceState(
            selectedCardID: cardID,
            cards: [
                WorkspaceCard(
                    id: cardID,
                    kind: .note,
                    position: CanvasPoint(x: 100, y: 100),
                    size: CardSize(width: 300, height: 200),
                    title: "Note",
                    content: "Content"
                ),
                WorkspaceCard(
                    id: otherCardID,
                    kind: .todo,
                    position: CanvasPoint(x: 400, y: 100),
                    size: CardSize(width: 280, height: 180),
                    title: "Todo",
                    content: "[ ] Item"
                )
            ]
        )

        state.deleteCard(id: cardID)

        XCTAssertEqual(state.cards.count, 1)
        XCTAssertNil(state.selectedCardID)
        XCTAssertEqual(state.cards.first?.id, otherCardID)
    }

    func testResizeCardEnforcesMinimumSize() throws {
        let cardID = try XCTUnwrap(UUID(uuidString: "9C0D1E2F-3A4B-5C6D-7E8F-9A0B1C2D3E4F"))
        var state = WorkspaceState(
            cards: [
                WorkspaceCard(
                    id: cardID,
                    kind: .browser,
                    position: CanvasPoint(x: 50, y: 50),
                    size: CardSize(width: 380, height: 230),
                    title: "Preview",
                    content: "https://example.com"
                )
            ]
        )

        state.resizeCard(id: cardID, to: CardSize(width: 100, height: 80))

        let card = try XCTUnwrap(state.cards.first)
        XCTAssertEqual(card.size.width, CardSize.minimumWidth)
        XCTAssertEqual(card.size.height, CardSize.minimumHeight)
    }

    func testResizeCardUpdatesPositionWhenProvided() throws {
        let cardID = try XCTUnwrap(UUID(uuidString: "0D1E2F3A-4B5C-6D7E-8F9A-0B1C2D3E4F5A"))
        var state = WorkspaceState(
            cards: [
                WorkspaceCard(
                    id: cardID,
                    kind: .agent,
                    position: CanvasPoint(x: 120, y: 80),
                    size: CardSize(width: 360, height: 240),
                    title: "Agent",
                    content: "Session"
                )
            ]
        )

        let newPosition = CanvasPoint(x: 90, y: 60)
        let newSize = CardSize(width: 400, height: 260)
        state.resizeCard(id: cardID, to: newSize, position: newPosition)

        let card = try XCTUnwrap(state.cards.first)
        XCTAssertEqual(card.size, newSize)
        XCTAssertEqual(card.position, newPosition)
    }

    func testUpdateCardTitleTrimsAndRejectsEmpty() throws {
        let cardID = try XCTUnwrap(UUID(uuidString: "1E2F3A4B-5C6D-7E8F-9A0B-1C2D3E4F5A6B"))
        var state = WorkspaceState(
            cards: [
                WorkspaceCard(
                    id: cardID,
                    kind: .note,
                    position: CanvasPoint(x: 0, y: 0),
                    size: CardSize(width: 320, height: 190),
                    title: "Original",
                    content: "Body"
                )
            ]
        )

        state.updateCardTitle(id: cardID, to: "  Renamed  ")
        XCTAssertEqual(state.cards.first?.title, "Renamed")

        state.updateCardTitle(id: cardID, to: "   ")
        XCTAssertEqual(state.cards.first?.title, "Renamed")
    }

    func testUpdateCardContentReplacesBody() throws {
        let cardID = try XCTUnwrap(UUID(uuidString: "2F3A4B5C-6D7E-8F9A-0B1C-2D3E4F5A6B7C"))
        var state = WorkspaceState(
            cards: [
                WorkspaceCard(
                    id: cardID,
                    kind: .todo,
                    position: CanvasPoint(x: 0, y: 0),
                    size: CardSize(width: 300, height: 210),
                    title: "Tasks",
                    content: "[ ] First"
                )
            ]
        )

        state.updateCardContent(id: cardID, to: "[x] First\n[ ] Second")

        XCTAssertEqual(state.cards.first?.content, "[x] First\n[ ] Second")
    }

    @MainActor
    func testDeleteCardUpdatesActiveSummaryCardCount() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)

        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: baseDirectory.appendingPathComponent("workspace.json")
        )
        let cardID = try XCTUnwrap(store.state.cards.first?.id)
        let startingCount = store.state.cards.count

        store.selectCard(id: cardID)
        store.deleteCard(id: cardID)

        XCTAssertEqual(store.state.cards.count, startingCount - 1)
        XCTAssertNil(store.state.selectedCardID)

        let activeSummary = try XCTUnwrap(
            store.library.workspaces.first(where: { $0.id == store.library.selectedWorkspaceID })
        )
        XCTAssertEqual(activeSummary.cardCount, startingCount - 1)
    }

    @MainActor
    func testResizeCardPersistsAfterDebounce() async throws {
        let cardID = try XCTUnwrap(UUID(uuidString: "3A4B5C6D-7E8F-9A0B-1C2D-3E4F5A6B7C8D"))
        let state = WorkspaceState(
            cards: [
                WorkspaceCard(
                    id: cardID,
                    kind: .note,
                    position: CanvasPoint(x: 10, y: 20),
                    size: CardSize(width: 320, height: 190),
                    title: "Note",
                    content: "Body"
                )
            ]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(
            state: state,
            storageURL: url,
            persistenceDelay: 0.01
        )

        store.resizeCard(id: cardID, to: CardSize(width: 400, height: 220))
        try await Task.sleep(nanoseconds: 50_000_000)

        let loadedState = try WorkspaceStore.load(from: url)
        let card = try XCTUnwrap(loadedState.cards.first)
        XCTAssertEqual(card.size.width, 400, accuracy: 0.0001)
        XCTAssertEqual(card.size.height, 220, accuracy: 0.0001)
    }

    func testAgentCardKindRawValueRemainsAgent() {
        // The agent kind is relabeled "Terminal" in the UI only; the persisted
        // rawValue must stay "agent" for backward compatibility.
        XCTAssertEqual(CardKind.agent.rawValue, "agent")
    }

    func testWorkspaceStateDecodesLegacyJSONWithoutAnnotationKeys() throws {
        let legacyJSON = """
        {
          "viewport": { "origin": { "x": 10, "y": 20 }, "scale": 1.25 },
          "selectedCardID": null,
          "cards": [
            {
              "id": "66666666-6666-6666-6666-666666666666",
              "kind": "agent",
              "position": { "x": 90, "y": 120 },
              "size": { "width": 360, "height": 240 },
              "title": "Legacy Agent",
              "content": "Old workspace."
            }
          ]
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let state = try JSONDecoder().decode(WorkspaceState.self, from: data)

        XCTAssertEqual(state.cards.count, 1)
        XCTAssertTrue(state.connections.isEmpty)
        XCTAssertTrue(state.strokes.isEmpty)
        XCTAssertTrue(state.textElements.isEmpty)
        XCTAssertNil(state.selectedTextID)
    }

    func testWorkspaceStateRoundTripsAnnotations() throws {
        let cardA = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001"))
        let cardB = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002"))
        let state = WorkspaceState(
            viewport: CanvasViewport(origin: CanvasPoint(x: 1, y: 2), scale: 1.1),
            cards: [
                WorkspaceCard(id: cardA, kind: .note, position: CanvasPoint(x: 0, y: 0), size: CardSize(width: 300, height: 200), title: "A", content: ""),
                WorkspaceCard(id: cardB, kind: .todo, position: CanvasPoint(x: 400, y: 0), size: CardSize(width: 300, height: 200), title: "B", content: "")
            ],
            connections: [CardConnection(from: cardA, to: cardB)],
            strokes: [
                DrawingStroke(
                    points: [CanvasPoint(x: 0, y: 0), CanvasPoint(x: 10, y: 12)],
                    color: RGBAColor(red: 0.2, green: 0.4, blue: 0.6, opacity: 1),
                    thickness: 4
                )
            ],
            textElements: [
                TextElement(position: CanvasPoint(x: 50, y: 60), size: CardSize(width: 120, height: 40), text: "hi", fontSize: 20)
            ],
            selectedTextID: nil
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        XCTAssertEqual(decoded, state)
    }

    @MainActor
    func testAddCardFromCornersNormalizesAndClampsRect() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(
            state: WorkspaceState(),
            storageURL: url,
            persistenceDelay: 60
        )

        // Drag bottom-right to top-left, with a tiny size that should clamp up.
        let id = store.addCard(
            kind: .note,
            fromCorner: CanvasPoint(x: 500, y: 400),
            toCorner: CanvasPoint(x: 480, y: 380)
        )

        let card = try XCTUnwrap(store.state.cards.last)
        XCTAssertEqual(card.id, id)
        XCTAssertEqual(card.position.x, 480, accuracy: 0.0001)
        XCTAssertEqual(card.position.y, 380, accuracy: 0.0001)
        XCTAssertEqual(card.size.width, CardSize.minimumWidth, accuracy: 0.0001)
        XCTAssertEqual(card.size.height, CardSize.minimumHeight, accuracy: 0.0001)
        XCTAssertEqual(store.state.selectedCardID, id)
    }

    @MainActor
    func testAddCardFromCornersKeepsLargeRectSize() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(
            state: WorkspaceState(),
            storageURL: url,
            persistenceDelay: 60
        )

        let id = store.addCard(
            kind: .browser,
            fromCorner: CanvasPoint(x: 100, y: 100),
            toCorner: CanvasPoint(x: 500, y: 420)
        )

        let card = try XCTUnwrap(store.state.cards.last)
        XCTAssertEqual(card.id, id)
        XCTAssertEqual(card.position.x, 100, accuracy: 0.0001)
        XCTAssertEqual(card.position.y, 100, accuracy: 0.0001)
        XCTAssertEqual(card.size.width, 400, accuracy: 0.0001)
        XCTAssertEqual(card.size.height, 320, accuracy: 0.0001)
    }

    // MARK: - Stage 1: non-overlapping placement + enlarged defaults

    func testNonOverlappingOriginReturnsCenterWhenAreaFree() {
        let state = WorkspaceState()
        let size = CardSize(width: 400, height: 300)
        let center = CanvasPoint(x: 500, y: 400)

        let origin = state.nonOverlappingOrigin(for: size, centeredAt: center)

        XCTAssertEqual(origin.x, center.x - (size.width / 2), accuracy: 0.0001)
        XCTAssertEqual(origin.y, center.y - (size.height / 2), accuracy: 0.0001)
    }

    func testTwoCardsCenteredAtSamePointDoNotOverlap() {
        var state = WorkspaceState()
        let size = CardSize(width: 400, height: 300)
        let center = CanvasPoint(x: 500, y: 400)

        let first = state.nonOverlappingOrigin(for: size, centeredAt: center)
        state.addCard(
            WorkspaceCard(kind: .note, position: first, size: size, title: "A", content: "")
        )
        let second = state.nonOverlappingOrigin(for: size, centeredAt: center)

        XCTAssertNotEqual(second, first, "second card must cascade off the first")

        let overlaps = first.x < second.x + size.width
            && first.x + size.width > second.x
            && first.y < second.y + size.height
            && first.y + size.height > second.y
        XCTAssertFalse(overlaps, "cascaded card must not overlap the existing one")
    }

    func testNonOverlappingOriginRespectsSpacingAroundExistingCard() {
        var state = WorkspaceState()
        let size = CardSize(width: 400, height: 300)
        state.addCard(
            WorkspaceCard(kind: .note, position: .zero, size: size, title: "A", content: "")
        )

        // Centering the new card exactly on the existing one forces a cascade.
        let center = CanvasPoint(x: size.width / 2, y: size.height / 2)
        let spacing = 28.0
        let origin = state.nonOverlappingOrigin(for: size, centeredAt: center, spacing: spacing)

        // The new card, inflated by the spacing margin, must not intersect the
        // existing card — a diagonal cascade separates on one axis, not both.
        let aMinX = origin.x - spacing
        let aMinY = origin.y - spacing
        let aMaxX = origin.x + size.width + spacing
        let aMaxY = origin.y + size.height + spacing
        let intersects = aMinX < size.width && aMaxX > 0 && aMinY < size.height && aMaxY > 0
        XCTAssertFalse(intersects, "placement must keep the spacing margin clear of the existing card")
    }

    @MainActor
    func testDefaultCardSizesAreEnlarged() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(), storageURL: url, persistenceDelay: 60)

        let expected: [CardKind: CardSize] = [
            .agent: CardSize(width: 480, height: 320),
            .note: CardSize(width: 440, height: 300),
            .todo: CardSize(width: 420, height: 300),
            .browser: CardSize(width: 520, height: 340)
        ]

        // Spread placements far apart so the non-overlap cascade never resizes
        // or shifts what we are asserting.
        var y = 0.0
        for kind in CardKind.allCases {
            store.addCard(kind: kind, centeredAt: CanvasPoint(x: 5000, y: y))
            y += 4000
            let card = try XCTUnwrap(store.state.cards.last)
            XCTAssertEqual(card.size, expected[kind])
            XCTAssertGreaterThanOrEqual(card.size.width, CardSize.minimumWidth)
            XCTAssertGreaterThanOrEqual(card.size.height, CardSize.minimumHeight)
        }
    }

    // MARK: - Stage 2: connections + text elements

    func testAddConnectionRejectsSelfMissingAndDuplicate() throws {
        let a = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-0000-0000-0000-0000000000A1"))
        let b = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-0000-0000-0000-0000000000B2"))
        let missing = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-0000-0000-0000-0000000000C3"))
        var state = WorkspaceState(cards: [
            WorkspaceCard(id: a, kind: .note, position: .zero, size: CardSize(width: 300, height: 200), title: "A", content: ""),
            WorkspaceCard(id: b, kind: .todo, position: CanvasPoint(x: 400, y: 0), size: CardSize(width: 300, height: 200), title: "B", content: "")
        ])

        state.addConnection(from: a, to: a)
        XCTAssertTrue(state.connections.isEmpty, "self-loop should be rejected")

        state.addConnection(from: a, to: missing)
        XCTAssertTrue(state.connections.isEmpty, "missing endpoint should be rejected")

        state.addConnection(from: a, to: b)
        XCTAssertEqual(state.connections.count, 1)

        state.addConnection(from: a, to: b)
        XCTAssertEqual(state.connections.count, 1, "duplicate (from,to) should be rejected")

        state.addConnection(from: b, to: a)
        XCTAssertEqual(state.connections.count, 1, "reverse (to,from) is the same undirected edge and should be rejected")
    }

    func testRemoveConnectionDeletesByID() throws {
        let a = try XCTUnwrap(UUID(uuidString: "DDDDDDDD-0000-0000-0000-0000000000A1"))
        let b = try XCTUnwrap(UUID(uuidString: "DDDDDDDD-0000-0000-0000-0000000000B2"))
        var state = WorkspaceState(cards: [
            WorkspaceCard(id: a, kind: .note, position: .zero, size: CardSize(width: 300, height: 200), title: "A", content: ""),
            WorkspaceCard(id: b, kind: .todo, position: CanvasPoint(x: 400, y: 0), size: CardSize(width: 300, height: 200), title: "B", content: "")
        ])

        state.addConnection(from: a, to: b)
        let edgeID = try XCTUnwrap(state.connections.first?.id)
        XCTAssertEqual(state.connections.count, 1)

        state.removeConnection(id: UUID())
        XCTAssertEqual(state.connections.count, 1, "removing an unknown id is a no-op")

        state.removeConnection(id: edgeID)
        XCTAssertTrue(state.connections.isEmpty, "removing by id deletes the edge")
    }

    func testDeleteCardPrunesReferencingConnections() throws {
        let a = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-0000-0000-0000-0000000000A1"))
        let b = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-0000-0000-0000-0000000000B2"))
        let c = try XCTUnwrap(UUID(uuidString: "BBBBBBBB-0000-0000-0000-0000000000C3"))
        var state = WorkspaceState(cards: [
            WorkspaceCard(id: a, kind: .note, position: .zero, size: CardSize(width: 300, height: 200), title: "A", content: ""),
            WorkspaceCard(id: b, kind: .todo, position: CanvasPoint(x: 400, y: 0), size: CardSize(width: 300, height: 200), title: "B", content: ""),
            WorkspaceCard(id: c, kind: .browser, position: CanvasPoint(x: 800, y: 0), size: CardSize(width: 300, height: 200), title: "C", content: "")
        ])

        state.addConnection(from: a, to: b)
        state.addConnection(from: b, to: c)
        XCTAssertEqual(state.connections.count, 2)

        state.deleteCard(id: b)
        XCTAssertTrue(state.connections.isEmpty, "connections touching the deleted card are pruned")
    }

    func testConnectionEndpointsAnchorOnCardBorders() {
        let from = CanvasRect(origin: CanvasPoint(x: 0, y: 0), size: CardSize(width: 100, height: 100))
        let to = CanvasRect(origin: CanvasPoint(x: 300, y: 0), size: CardSize(width: 100, height: 100))

        let endpoints = connectionEndpoints(from: from, to: to)

        XCTAssertEqual(endpoints.start.x, 100, accuracy: 0.0001)
        XCTAssertEqual(endpoints.start.y, 50, accuracy: 0.0001)
        XCTAssertEqual(endpoints.end.x, 300, accuracy: 0.0001)
        XCTAssertEqual(endpoints.end.y, 50, accuracy: 0.0001)
    }

    func testSelectingCardAndTextAreMutuallyExclusive() throws {
        let cardID = try XCTUnwrap(UUID(uuidString: "CCCCCCCC-0000-0000-0000-0000000000A1"))
        let textID = try XCTUnwrap(UUID(uuidString: "CCCCCCCC-0000-0000-0000-0000000000B2"))
        var state = WorkspaceState(
            cards: [
                WorkspaceCard(id: cardID, kind: .note, position: .zero, size: CardSize(width: 300, height: 200), title: "A", content: "")
            ],
            textElements: [
                TextElement(id: textID, position: CanvasPoint(x: 10, y: 10), size: CardSize(width: 120, height: 40), text: "hi")
            ]
        )

        state.selectCard(id: cardID)
        XCTAssertEqual(state.selectedCardID, cardID)
        XCTAssertNil(state.selectedTextID)

        state.selectTextElement(id: textID)
        XCTAssertEqual(state.selectedTextID, textID)
        XCTAssertNil(state.selectedCardID)

        state.clearSelection()
        XCTAssertNil(state.selectedCardID)
        XCTAssertNil(state.selectedTextID)
    }

    @MainActor
    func testAddTextElementFromCornersClampsToTextMinimums() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(), storageURL: url, persistenceDelay: 60)

        let id = store.addTextElement(
            fromCorner: CanvasPoint(x: 110, y: 105),
            toCorner: CanvasPoint(x: 100, y: 100)
        )

        let element = try XCTUnwrap(store.state.textElements.last)
        XCTAssertEqual(element.id, id)
        XCTAssertEqual(element.position.x, 100, accuracy: 0.0001)
        XCTAssertEqual(element.position.y, 100, accuracy: 0.0001)
        XCTAssertEqual(element.size.width, TextElement.minimumWidth, accuracy: 0.0001)
        XCTAssertEqual(element.size.height, TextElement.minimumHeight, accuracy: 0.0001)
        XCTAssertEqual(store.state.selectedTextID, id)
    }

    @MainActor
    func testAddTextElementCenteredCentersOnPoint() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(), storageURL: url, persistenceDelay: 60)

        store.addTextElement(centeredAt: CanvasPoint(x: 500, y: 400))

        let element = try XCTUnwrap(store.state.textElements.last)
        XCTAssertEqual(element.position.x + (element.size.width / 2), 500, accuracy: 0.0001)
        XCTAssertEqual(element.position.y + (element.size.height / 2), 400, accuracy: 0.0001)
    }

    @MainActor
    func testAddCardCenteredAtPlacesCardCenterOnPoint() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(
            state: WorkspaceState(),
            storageURL: url,
            persistenceDelay: 60
        )

        store.addCard(kind: .note, centeredAt: CanvasPoint(x: 500, y: 400))

        let card = try XCTUnwrap(store.state.cards.last)
        XCTAssertEqual(card.position.x + (card.size.width / 2), 500, accuracy: 0.0001)
        XCTAssertEqual(card.position.y + (card.size.height / 2), 400, accuracy: 0.0001)
    }

    // MARK: - Stage 3: brush strokes & eraser

    private func makeStroke(
        _ points: [CanvasPoint],
        color: RGBAColor = RGBAColor(red: 0.1, green: 0.2, blue: 0.3, opacity: 1),
        thickness: Double = 4
    ) -> DrawingStroke {
        DrawingStroke(points: points, color: color, thickness: thickness)
    }

    func testAddStrokeAppendsStroke() {
        var state = WorkspaceState()
        state.addStroke(makeStroke([CanvasPoint(x: 0, y: 0), CanvasPoint(x: 10, y: 0)]))
        XCTAssertEqual(state.strokes.count, 1)
    }

    @MainActor
    func testStoreAddStrokeRejectsFewerThanTwoPoints() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(), storageURL: url, persistenceDelay: 60)

        store.addStroke(makeStroke([CanvasPoint(x: 0, y: 0)]))
        XCTAssertTrue(store.state.strokes.isEmpty)

        store.addStroke(makeStroke([CanvasPoint(x: 0, y: 0), CanvasPoint(x: 5, y: 5)]))
        XCTAssertEqual(store.state.strokes.count, 1)
    }

    func testEraseWholeStrokeRemovesTouchedAndKeepsOthers() {
        var state = WorkspaceState()
        let near = makeStroke([CanvasPoint(x: 0, y: 0), CanvasPoint(x: 100, y: 0)])
        let far = makeStroke([CanvasPoint(x: 0, y: 500), CanvasPoint(x: 100, y: 500)])
        state.addStroke(near)
        state.addStroke(far)

        let changed = state.eraseStrokes(at: CanvasPoint(x: 50, y: 2), radius: 10, mode: .wholeStroke)

        XCTAssertTrue(changed)
        XCTAssertEqual(state.strokes.count, 1)
        XCTAssertEqual(state.strokes.first?.points, far.points)
    }

    func testEraseSegmentSplitsStraightStrokePreservingColorAndThickness() {
        var state = WorkspaceState()
        let color = RGBAColor(red: 0.5, green: 0.25, blue: 0.75, opacity: 0.8)
        // A straight horizontal stroke sampled densely along x.
        let points = (0...10).map { CanvasPoint(x: Double($0) * 10, y: 0) }
        state.addStroke(makeStroke(points, color: color, thickness: 7))

        // Erase the middle (around x=50) so vertices at 40/50/60 drop, leaving a
        // run before and after.
        let changed = state.eraseStrokes(at: CanvasPoint(x: 50, y: 0), radius: 12, mode: .segment)

        XCTAssertTrue(changed)
        XCTAssertEqual(state.strokes.count, 2)
        for fragment in state.strokes {
            XCTAssertGreaterThanOrEqual(fragment.points.count, 2)
            XCTAssertEqual(fragment.color, color)
            XCTAssertEqual(fragment.thickness, 7)
        }
        // The two fragments live on opposite sides of the erased gap.
        let maxXFirst = state.strokes[0].points.map(\.x).max() ?? 0
        let minXSecond = state.strokes[1].points.map(\.x).min() ?? 0
        XCTAssertLessThan(maxXFirst, minXSecond)
    }

    func testEraseLeavesStateUnchangedWhenNothingTouched() {
        var state = WorkspaceState()
        state.addStroke(makeStroke([CanvasPoint(x: 0, y: 0), CanvasPoint(x: 10, y: 0)]))

        let changed = state.eraseStrokes(at: CanvasPoint(x: 1000, y: 1000), radius: 10, mode: .wholeStroke)

        XCTAssertFalse(changed)
        XCTAssertEqual(state.strokes.count, 1)
    }

    func testErasePixelClipsSparseStraightStrokeAtCircleBoundary() {
        var state = WorkspaceState()
        let color = RGBAColor(red: 0.2, green: 0.4, blue: 0.6, opacity: 0.9)
        // Only two endpoints — no vertex falls inside the disc, so a vertex-drop
        // eraser would not cut it. The footprint eraser must split it anyway.
        state.addStroke(makeStroke([CanvasPoint(x: 0, y: 0), CanvasPoint(x: 100, y: 0)], color: color, thickness: 6))

        let radius = 10.0
        let changed = state.eraseStrokes(at: CanvasPoint(x: 50, y: 0), radius: radius, mode: .segment)

        XCTAssertTrue(changed)
        XCTAssertEqual(state.strokes.count, 2)

        // The inner endpoints land on the circle boundary (≈ radius from center).
        let innerRight = state.strokes[0].points.map(\.x).max() ?? 0
        let innerLeft = state.strokes[1].points.map(\.x).min() ?? 0
        XCTAssertEqual(innerRight, 40, accuracy: 0.001)
        XCTAssertEqual(innerLeft, 60, accuracy: 0.001)

        for fragment in state.strokes {
            XCTAssertGreaterThanOrEqual(fragment.points.count, 2)
            XCTAssertEqual(fragment.color, color)
            XCTAssertEqual(fragment.thickness, 6)
        }
    }

    func testErasePixelBoundaryPointsLieOnTheCircle() {
        var state = WorkspaceState()
        // A diagonal stroke so the boundary points are non-trivial in x and y.
        state.addStroke(makeStroke([CanvasPoint(x: 0, y: 0), CanvasPoint(x: 100, y: 100)]))

        let center = CanvasPoint(x: 50, y: 50)
        let radius = 14.0
        let changed = state.eraseStrokes(at: center, radius: radius, mode: .segment)

        XCTAssertTrue(changed)
        XCTAssertEqual(state.strokes.count, 2)

        // The new gap-edge points (inner endpoints) sit on the circle boundary.
        let innerRight = state.strokes[0].points.last
        let innerLeft = state.strokes[1].points.first
        let dRight = hypot((innerRight?.x ?? 0) - center.x, (innerRight?.y ?? 0) - center.y)
        let dLeft = hypot((innerLeft?.x ?? 0) - center.x, (innerLeft?.y ?? 0) - center.y)
        XCTAssertEqual(dRight, radius, accuracy: 0.001)
        XCTAssertEqual(dLeft, radius, accuracy: 0.001)
    }

    func testViewportZoomClampsAndKeepsAnchorFixed() {
        var viewport = CanvasViewport(origin: CanvasPoint(x: 30, y: 20), scale: 1)
        let anchor = ScreenPoint(x: 400, y: 250)
        let anchorCanvasBefore = viewport.canvasPoint(forScreenPoint: anchor)

        // A huge magnification clamps to the maximum scale.
        viewport.zoom(by: 100, anchoredAt: anchor)
        XCTAssertEqual(viewport.scale, CanvasViewport.maximumScale, accuracy: 0.0001)

        // The anchor canvas point still maps back to the same screen location.
        let anchorScreenAfter = viewport.screenPoint(forCanvasPoint: anchorCanvasBefore)
        XCTAssertEqual(anchorScreenAfter.x, anchor.x, accuracy: 0.001)
        XCTAssertEqual(anchorScreenAfter.y, anchor.y, accuracy: 0.001)

        // A tiny magnification clamps to the minimum scale.
        viewport.zoom(by: 0.0001, anchoredAt: anchor)
        XCTAssertEqual(viewport.scale, CanvasViewport.minimumScale, accuracy: 0.0001)
    }

    func testZoomStepSnapsToHundredPercentWhenStepWouldCrossIt() {
        let anchor = ScreenPoint(x: 400, y: 250)

        // Stepping up from just below 100% lands exactly on 100%.
        var zoomingIn = CanvasViewport(scale: 0.98)
        zoomingIn.zoomStep(by: 1.15, anchoredAt: anchor)
        XCTAssertEqual(zoomingIn.scale, 1.0, accuracy: 1e-9)

        // Stepping down from just above 100% lands exactly on 100%.
        var zoomingOut = CanvasViewport(scale: 1.02)
        zoomingOut.zoomStep(by: 1 / 1.15, anchoredAt: anchor)
        XCTAssertEqual(zoomingOut.scale, 1.0, accuracy: 1e-9)
    }

    func testZoomStepDoesNotSnapWhenStepStaysOnOneSideOfHundred() {
        let anchor = ScreenPoint(x: 0, y: 0)

        // A step that never crosses 100% behaves like a plain zoom.
        var viewport = CanvasViewport(scale: 0.8)
        viewport.zoomStep(by: 1.15, anchoredAt: anchor)
        XCTAssertEqual(viewport.scale, 0.92, accuracy: 1e-9)
    }

    func testZoomStepFromExactlyHundredPercentStepsAwayNormally() {
        let anchor = ScreenPoint(x: 0, y: 0)

        // Already at 100%, a step moves away (it must not stay pinned at 100%).
        var viewport = CanvasViewport(scale: 1.0)
        viewport.zoomStep(by: 1.15, anchoredAt: anchor)
        XCTAssertEqual(viewport.scale, 1.15, accuracy: 1e-9)
    }

    func testZoomStepKeepsAnchorFixed() {
        var viewport = CanvasViewport(origin: CanvasPoint(x: 30, y: 20), scale: 0.95)
        let anchor = ScreenPoint(x: 400, y: 250)
        let anchorCanvasBefore = viewport.canvasPoint(forScreenPoint: anchor)

        viewport.zoomStep(by: 1.15, anchoredAt: anchor)

        let anchorScreenAfter = viewport.screenPoint(forCanvasPoint: anchorCanvasBefore)
        XCTAssertEqual(anchorScreenAfter.x, anchor.x, accuracy: 0.001)
        XCTAssertEqual(anchorScreenAfter.y, anchor.y, accuracy: 0.001)
    }

    func testStrokesRoundTripThroughCodable() throws {
        var state = WorkspaceState()
        state.addStroke(
            makeStroke(
                [CanvasPoint(x: 1, y: 2), CanvasPoint(x: 3, y: 4), CanvasPoint(x: 5, y: 6)],
                color: RGBAColor(red: 0.9, green: 0.1, blue: 0.4, opacity: 0.6),
                thickness: 9
            )
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        XCTAssertEqual(decoded.strokes, state.strokes)
    }

    // MARK: - Marquee selection

    private func makeMarqueeState() -> (WorkspaceState, left: UUID, right: UUID) {
        let left = UUID()
        let right = UUID()
        let state = WorkspaceState(
            cards: [
                WorkspaceCard(
                    id: left,
                    kind: .note,
                    position: CanvasPoint(x: 0, y: 0),
                    size: CardSize(width: 100, height: 100),
                    title: "Left",
                    content: ""
                ),
                WorkspaceCard(
                    id: right,
                    kind: .note,
                    position: CanvasPoint(x: 400, y: 0),
                    size: CardSize(width: 100, height: 100),
                    title: "Right",
                    content: ""
                )
            ]
        )
        return (state, left, right)
    }

    func testSelectCardsMarksEveryIntersectingCard() {
        var (state, left, right) = makeMarqueeState()

        state.selectCards(
            fromCorner: CanvasPoint(x: -10, y: -10),
            toCorner: CanvasPoint(x: 510, y: 110)
        )

        XCTAssertEqual(state.marqueeSelectedCardIDs, Set([left, right]))
        // Two hits: no single selectedCardID.
        XCTAssertNil(state.selectedCardID)
        XCTAssertNil(state.selectedTextID)
    }

    func testSelectCardsWithSingleHitSetsSelectedCardID() {
        var (state, left, _) = makeMarqueeState()

        state.selectCards(
            fromCorner: CanvasPoint(x: -10, y: -10),
            toCorner: CanvasPoint(x: 50, y: 50)
        )

        XCTAssertEqual(state.marqueeSelectedCardIDs, Set([left]))
        XCTAssertEqual(state.selectedCardID, left)
    }

    func testSelectCardsWithMissClearsSelection() {
        var (state, _, _) = makeMarqueeState()
        state.selectCards(
            fromCorner: CanvasPoint(x: -10, y: -10),
            toCorner: CanvasPoint(x: 50, y: 50)
        )
        XCTAssertFalse(state.marqueeSelectedCardIDs.isEmpty)

        state.selectCards(
            fromCorner: CanvasPoint(x: 1_000, y: 1_000),
            toCorner: CanvasPoint(x: 1_100, y: 1_100)
        )

        XCTAssertTrue(state.marqueeSelectedCardIDs.isEmpty)
        XCTAssertNil(state.selectedCardID)
    }

    func testSelectCardClearsMarqueeSelection() {
        var (state, left, right) = makeMarqueeState()
        state.selectCards(
            fromCorner: CanvasPoint(x: -10, y: -10),
            toCorner: CanvasPoint(x: 510, y: 110)
        )
        XCTAssertEqual(state.marqueeSelectedCardIDs.count, 2)

        state.selectCard(id: right)

        XCTAssertEqual(state.selectedCardID, right)
        XCTAssertTrue(state.marqueeSelectedCardIDs.isEmpty)
        _ = left
    }

    func testClearSelectionClearsMarqueeSelection() {
        var (state, _, _) = makeMarqueeState()
        state.selectCards(
            fromCorner: CanvasPoint(x: -10, y: -10),
            toCorner: CanvasPoint(x: 510, y: 110)
        )
        XCTAssertFalse(state.marqueeSelectedCardIDs.isEmpty)

        state.clearSelection()

        XCTAssertTrue(state.marqueeSelectedCardIDs.isEmpty)
    }

    func testMarqueeSelectionDoesNotRoundTripThroughCodable() throws {
        var (state, _, _) = makeMarqueeState()
        state.selectCards(
            fromCorner: CanvasPoint(x: -10, y: -10),
            toCorner: CanvasPoint(x: 510, y: 110)
        )
        XCTAssertFalse(state.marqueeSelectedCardIDs.isEmpty)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        XCTAssertTrue(decoded.marqueeSelectedCardIDs.isEmpty)
    }

    // MARK: - Toggle selection (⌘-click)

    func testToggleAddsCardToEmptySelection() {
        var (state, left, _) = makeMarqueeState()

        state.toggleCardInSelection(id: left)

        XCTAssertEqual(state.marqueeSelectedCardIDs, Set([left]))
        XCTAssertEqual(state.selectedCardID, left)
    }

    func testTogglePromotesLoneSingleSelectionIntoSet() {
        var (state, left, right) = makeMarqueeState()
        state.selectCard(id: left)
        XCTAssertEqual(state.selectedCardID, left)
        XCTAssertTrue(state.marqueeSelectedCardIDs.isEmpty)

        state.toggleCardInSelection(id: right)

        XCTAssertEqual(state.marqueeSelectedCardIDs, Set([left, right]))
        // Two members: no lone selectedCardID.
        XCTAssertNil(state.selectedCardID)
    }

    func testToggleRemovesAlreadySelectedMember() {
        var (state, left, right) = makeMarqueeState()
        state.selectCards(
            fromCorner: CanvasPoint(x: -10, y: -10),
            toCorner: CanvasPoint(x: 510, y: 110)
        )
        XCTAssertEqual(state.marqueeSelectedCardIDs, Set([left, right]))

        state.toggleCardInSelection(id: left)

        // Down to one member: it becomes the lone selectedCardID.
        XCTAssertEqual(state.marqueeSelectedCardIDs, Set([right]))
        XCTAssertEqual(state.selectedCardID, right)
    }

    func testToggleLastMemberClearsSelection() {
        var (state, left, _) = makeMarqueeState()
        state.selectCard(id: left)

        state.toggleCardInSelection(id: left)

        XCTAssertTrue(state.marqueeSelectedCardIDs.isEmpty)
        XCTAssertNil(state.selectedCardID)
    }

    func testToggleClearsTextSelection() {
        var (state, left, _) = makeMarqueeState()
        state.textElements = [
            TextElement(position: CanvasPoint(x: 0, y: 0), size: CardSize(width: 120, height: 40), text: "hi")
        ]
        state.selectTextElement(id: state.textElements[0].id)
        XCTAssertNotNil(state.selectedTextID)

        state.toggleCardInSelection(id: left)

        XCTAssertNil(state.selectedTextID)
    }

    func testToggleUnknownCardIsNoOp() {
        var (state, left, _) = makeMarqueeState()
        state.selectCard(id: left)

        state.toggleCardInSelection(id: UUID())

        XCTAssertEqual(state.selectedCardID, left)
        XCTAssertTrue(state.marqueeSelectedCardIDs.isEmpty)
    }

    // MARK: - Additive marquee (⌘-drag)

    func testAdditiveMarqueeUnionsWithBase() {
        var (state, left, right) = makeMarqueeState()

        // Box hits only `right`, additive against a base that already holds `left`.
        state.selectCards(
            fromCorner: CanvasPoint(x: 390, y: -10),
            toCorner: CanvasPoint(x: 510, y: 110),
            additive: true,
            base: Set([left])
        )

        XCTAssertEqual(state.marqueeSelectedCardIDs, Set([left, right]))
        XCTAssertNil(state.selectedCardID)
    }

    func testAdditiveMarqueeKeepsBaseWhenBoxHitsNothing() {
        var (state, left, _) = makeMarqueeState()

        state.selectCards(
            fromCorner: CanvasPoint(x: 1_000, y: 1_000),
            toCorner: CanvasPoint(x: 1_100, y: 1_100),
            additive: true,
            base: Set([left])
        )

        XCTAssertEqual(state.marqueeSelectedCardIDs, Set([left]))
        // A single surviving member is promoted to the lone selectedCardID.
        XCTAssertEqual(state.selectedCardID, left)
    }

    func testNonAdditiveMarqueeReplacesIgnoringBase() {
        var (state, left, right) = makeMarqueeState()

        // Box hits only `right`; non-additive must drop the base entirely.
        state.selectCards(
            fromCorner: CanvasPoint(x: 390, y: -10),
            toCorner: CanvasPoint(x: 510, y: 110),
            additive: false,
            base: Set([left])
        )

        XCTAssertEqual(state.marqueeSelectedCardIDs, Set([right]))
        XCTAssertEqual(state.selectedCardID, right)
    }

    // MARK: - Stage 4: text styling + deselect

    @MainActor
    func testStoreClearSelectionClearsSelectedTextID() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(), storageURL: url, persistenceDelay: 60)
        let id = store.addTextElement(centeredAt: CanvasPoint(x: 100, y: 100))
        XCTAssertEqual(store.state.selectedTextID, id)

        store.clearSelection()

        XCTAssertNil(store.state.selectedTextID)
        XCTAssertNil(store.state.selectedCardID)
    }

    @MainActor
    func testUpdateTextElementStylePersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(), storageURL: url, persistenceDelay: 60)
        let id = store.addTextElement(centeredAt: CanvasPoint(x: 100, y: 100))

        store.updateTextElementFontSize(id: id, to: 42)
        store.updateTextElementColor(id: id, toHex: "#11223344")
        store.updateTextElementFont(id: id, to: "Georgia")

        let element = try XCTUnwrap(store.state.textElements.first(where: { $0.id == id }))
        XCTAssertEqual(element.fontSize, 42, accuracy: 0.0001)
        XCTAssertEqual(element.colorHex, "#11223344")
        XCTAssertEqual(element.fontName, "Georgia")
    }

    func testTextElementFontNameRoundTripsThroughCodable() throws {
        let state = WorkspaceState(
            textElements: [
                TextElement(
                    position: CanvasPoint(x: 10, y: 20),
                    size: CardSize(width: 120, height: 40),
                    text: "styled",
                    fontSize: 24,
                    colorHex: "#AABBCCDD",
                    fontName: "Menlo"
                )
            ]
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)

        XCTAssertEqual(decoded.textElements.first?.fontName, "Menlo")
        XCTAssertEqual(decoded, state)
    }

    func testTextElementWithoutFontNameDecodesToNil() throws {
        let legacyJSON = """
        {
          "viewport": { "origin": { "x": 0, "y": 0 }, "scale": 1 },
          "cards": [],
          "textElements": [
            {
              "id": "77777777-7777-7777-7777-777777777777",
              "position": { "x": 5, "y": 6 },
              "size": { "width": 120, "height": 40 },
              "text": "legacy",
              "fontSize": 17,
              "colorHex": "#FFFFFFFF"
            }
          ]
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let state = try JSONDecoder().decode(WorkspaceState.self, from: data)

        XCTAssertEqual(state.textElements.count, 1)
        XCTAssertNil(state.textElements.first?.fontName)
    }

    // MARK: - Grid placement (double-click instant-create)

    private func makeGridCard() -> WorkspaceCard {
        WorkspaceCard(
            kind: .note,
            position: .zero,
            size: CardSize(width: 520, height: 340),
            title: "Grid",
            content: "Content"
        )
    }

    private func assertPoint(
        _ point: CanvasPoint,
        _ x: Double,
        _ y: Double,
        accuracy: Double = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(point.x, x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: accuracy, file: file, line: line)
    }

    func testGridPlacementFillsReadingOrder2x2Page() {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 1600, y: 1000)

        for _ in 0..<4 {
            state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        }

        XCTAssertEqual(state.cards.count, 4)
        // Each card fills one quadrant: usable = (1600 - 96 - 40)/2 = 732 wide,
        // (1000 - 96 - 40)/2 = 432 tall, in reading order TL, TR, BL, BR.
        assertPoint(state.cards[0].position, 48, 48)
        assertPoint(state.cards[1].position, 820, 48)
        assertPoint(state.cards[2].position, 48, 520)
        assertPoint(state.cards[3].position, 820, 520)
        for card in state.cards {
            XCTAssertEqual(card.size.width, 732, accuracy: 0.001)
            XCTAssertEqual(card.size.height, 432, accuracy: 0.001)
        }
        // A full page fits, so the viewport stays put where the user was looking.
        XCTAssertEqual(state.viewport.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(state.viewport.origin.y, 0, accuracy: 0.001)
    }

    func testGridPlacementStartsNewPageAndPansNewestCardToTopLeft() {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 1600, y: 1000)

        for _ in 0..<5 {
            state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        }

        // The 5th card starts a fresh page to the RIGHT: content shifts left one
        // full viewport width and the new card lands at the viewport's top-left
        // margin, so pages flow horizontally.
        assertPoint(state.cards[4].position, 1648, 48)

        let screen = state.viewport.screenPoint(forCanvasPoint: state.cards[4].position)
        XCTAssertEqual(screen.x, 48, accuracy: 0.001)
        XCTAssertEqual(screen.y, 48, accuracy: 0.001)
        XCTAssertEqual(state.viewport.origin.x, -1600, accuracy: 0.001)
        XCTAssertEqual(state.viewport.origin.y, 0, accuracy: 0.001)
    }

    func testGridPlacementFillsQuadrantFreedByMidPageDelete() {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 1600, y: 1000)

        for _ in 0..<4 {
            state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        }

        // Delete the top-right card; its visible quadrant is now empty.
        let topRight = state.cards[1]
        state.deleteCards(ids: [topRight.id])

        // Occupancy-based placement fills the freed top-right quadrant in place
        // rather than flipping to a new page or stacking on a survivor.
        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)

        let newest = try! XCTUnwrap(state.cards.last)
        XCTAssertEqual(state.viewport.origin.x, 0, accuracy: 0.001)
        assertPoint(newest.position, 820, 48)
        for survivor in state.cards.dropLast() {
            XCTAssertFalse(
                abs(newest.position.x - survivor.position.x) < 0.001
                    && abs(newest.position.y - survivor.position.y) < 0.001,
                "new card must not overlap a surviving card"
            )
        }
    }

    func testGridPlacementKeepsNewestCardFullyVisibleOnSmallViewport() {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 700, y: 520)

        for _ in 0..<6 {
            state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
            let card = try! XCTUnwrap(state.cards.last)
            let topLeft = state.viewport.screenPoint(forCanvasPoint: card.position)
            let width = card.size.width * state.viewport.scale
            let height = card.size.height * state.viewport.scale

            XCTAssertGreaterThanOrEqual(topLeft.x, 0)
            XCTAssertGreaterThanOrEqual(topLeft.y, 0)
            XCTAssertLessThanOrEqual(topLeft.x + width, viewportSize.x + 0.001)
            XCTAssertLessThanOrEqual(topLeft.y + height, viewportSize.y + 0.001)
        }
    }

    func testGridPlacementAfterPanStartsFreshPageAtTopLeft() {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 1600, y: 1000)

        // Place two cards (TL, TR), then pan to a brand-new, empty area.
        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        state.viewport.pan(by: CanvasVector(dx: -1600, dy: 0))

        // The next double-click must start a fresh page at the visible top-left,
        // not continue the stale slot order onto the right/bottom column (Issue B).
        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)

        let newest = try! XCTUnwrap(state.cards.last)
        let screen = state.viewport.screenPoint(forCanvasPoint: newest.position)
        XCTAssertEqual(screen.x, 48, accuracy: 0.001)
        XCTAssertEqual(screen.y, 48, accuracy: 0.001)
    }

    func testGridPlacementForcesTopLeftAfterPanEvenWhenAStaleCardOverlaps() {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 1600, y: 1000)

        // Place one quadrant-sized card, then pan only slightly — little enough
        // that the existing card still covers the NEW top-left quadrant's center.
        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        state.viewport.pan(by: CanvasVector(dx: -100, dy: -100))

        // The first double-click after moving must re-anchor a fresh page at the
        // visible top-left, NOT get bumped to the right column by the stale
        // overlap. This is the "first card sometimes on the right" report.
        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)

        let screen = state.viewport.screenPoint(forCanvasPoint: state.cards.last!.position)
        XCTAssertEqual(screen.x, 48, accuracy: 0.001)
        XCTAssertEqual(screen.y, 48, accuracy: 0.001)
    }

    func testGridPlacementIgnoresStalePageStateAcrossAFullRunThenFlips() {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 1600, y: 1000)

        // Earlier in the session: one grid card placed, then the user panned away
        // — the classic Issue A setup that leaves a counter out of sync.
        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        state.viewport.pan(by: CanvasVector(dx: -1600, dy: 0))

        // Four double-clicks fill the current page in reading order, starting at
        // the visible top-left regardless of the earlier placement.
        let expectedSlots: [(x: Double, y: Double)] = [(48, 48), (820, 48), (48, 520), (820, 520)]
        for expected in expectedSlots {
            state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
            let screen = state.viewport.screenPoint(forCanvasPoint: state.cards.last!.position)
            XCTAssertEqual(screen.x, expected.x, accuracy: 0.001)
            XCTAssertEqual(screen.y, expected.y, accuracy: 0.001)
        }

        // The fifth fills no remaining quadrant, so it flips to a fresh page to
        // the right and lands at the visible top-left.
        let originBeforeFlip = state.viewport.origin.x
        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        XCTAssertEqual(state.viewport.origin.x, originBeforeFlip - 1600, accuracy: 0.001)
        let fifth = state.viewport.screenPoint(forCanvasPoint: state.cards.last!.position)
        XCTAssertEqual(fifth.x, 48, accuracy: 0.001)
        XCTAssertEqual(fifth.y, 48, accuracy: 0.001)
    }

    func testGridPlacementIsStatelessAcrossEncodeDecode() throws {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 1600, y: 1000)

        for _ in 0..<3 {
            state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        }

        let data = try JSONEncoder().encode(state)
        var decoded = try JSONDecoder().decode(WorkspaceState.self, from: data)
        XCTAssertEqual(decoded.cards.count, 3)

        // Placement carries no transient counter: it is derived entirely from the
        // persisted cards and viewport, so the post-decode placement fills the one
        // remaining quadrant (BR) of the same page, just as it would have before.
        decoded.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        assertPoint(decoded.cards.last!.position, 820, 520)
        XCTAssertEqual(decoded.viewport.origin.x, 0, accuracy: 0.001)
    }

    func testGridPlacementWillFlipPagePredicateMatchesPlacement() {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 1600, y: 1000)

        // An empty page never flips; placing cards 1...3 keeps a free quadrant.
        for _ in 0..<3 {
            XCTAssertFalse(state.gridPlacementWillFlipPage(viewportSize: viewportSize))
            state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        }
        // After the 4th the page is full, so the predicate now reports a flip.
        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)
        XCTAssertTrue(state.gridPlacementWillFlipPage(viewportSize: viewportSize))
    }

    func testGridPlacementRespectsViewportScale() {
        var state = WorkspaceState(viewport: CanvasViewport(origin: .zero, scale: 0.5))
        let viewportSize = ScreenPoint(x: 1600, y: 1000)

        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)

        let card = state.cards[0]
        // Card size is the on-screen quadrant divided back into canvas units:
        // 732 / 0.5 = 1464 wide, 432 / 0.5 = 864 tall.
        XCTAssertEqual(card.size.width, 1464, accuracy: 0.001)
        XCTAssertEqual(card.size.height, 864, accuracy: 0.001)
        // The slot is placed by screen margin, so the canvas origin scales but
        // the on-screen top-left still lands at the margin.
        assertPoint(card.position, 96, 96)
        let screen = state.viewport.screenPoint(forCanvasPoint: card.position)
        XCTAssertEqual(screen.x, 48, accuracy: 0.001)
        XCTAssertEqual(screen.y, 48, accuracy: 0.001)
    }

    func testGridPlacementReservesBottomInsetSoCardsClearTheDock() {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 1600, y: 1000)
        let bottomInset: Double = 100

        for _ in 0..<4 {
            state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize, bottomInset: bottomInset)
        }

        // The bottom row must stay clear of the reserved dock band: every card's
        // on-screen bottom edge sits at or above `size.y - bottomInset`.
        for card in state.cards {
            let topLeft = state.viewport.screenPoint(forCanvasPoint: card.position)
            let bottomEdge = topLeft.y + (card.size.height * state.viewport.scale)
            XCTAssertLessThanOrEqual(bottomEdge, viewportSize.y - bottomInset + 0.001)
        }

        // The top margin is untouched — only the usable height shrinks — so the
        // first card still anchors at the top-left margin.
        assertPoint(state.cards[0].position, 48, 48)
        // Bottom-row bottom edge lands exactly at size.y - margin - bottomInset.
        let bottomRow = state.cards[2]
        let bottomScreen = state.viewport.screenPoint(forCanvasPoint: bottomRow.position)
        XCTAssertEqual(
            bottomScreen.y + (bottomRow.size.height * state.viewport.scale),
            1000 - 48 - 100,
            accuracy: 0.001
        )
    }

    func testGridPlacementDefaultsToNoBottomInset() {
        var state = WorkspaceState()
        let viewportSize = ScreenPoint(x: 1600, y: 1000)

        // Omitting bottomInset keeps the legacy full-height layout.
        state.placeCardInGrid(makeGridCard(), viewportSize: viewportSize)

        XCTAssertEqual(state.cards[0].size.height, 432, accuracy: 0.001)
    }

    @MainActor
    func testAddCardInGridReturnsNewCardIDAtFirstSlot() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: WorkspaceState(), storageURL: url)

        let id = store.addCardInGrid(kind: .note, viewportSize: ScreenPoint(x: 1600, y: 1000))

        XCTAssertEqual(store.state.cards.last?.id, id)
        XCTAssertEqual(store.state.cards.count, 1)
        assertPoint(try! XCTUnwrap(store.state.cards.last).position, 48, 48)
    }

    // MARK: - Stage 4: marquee group move + delete

    private func makePositionedCard(_ id: UUID, x: Double, y: Double) -> WorkspaceCard {
        WorkspaceCard(
            id: id,
            kind: .note,
            position: CanvasPoint(x: x, y: y),
            size: CardSize(width: 100, height: 100),
            title: "Card",
            content: ""
        )
    }

    func testMoveCardsOffsetsGroupMembersAndLeavesOthers() {
        let a = UUID(); let b = UUID(); let c = UUID()
        var state = WorkspaceState(cards: [
            makePositionedCard(a, x: 0, y: 0),
            makePositionedCard(b, x: 200, y: 0),
            makePositionedCard(c, x: 400, y: 0)
        ])

        state.moveCards(ids: [a, b], screenTranslation: CanvasVector(dx: 50, dy: -30))

        assertPoint(state.cards[0].position, 50, -30)
        assertPoint(state.cards[1].position, 250, -30)
        // Non-member stays put.
        assertPoint(state.cards[2].position, 400, 0)
    }

    func testMoveCardsConvertsScreenTranslationByScale() {
        let a = UUID()
        var state = WorkspaceState(
            viewport: CanvasViewport(origin: .zero, scale: 2),
            cards: [makePositionedCard(a, x: 0, y: 0)]
        )

        state.moveCards(ids: [a], screenTranslation: CanvasVector(dx: 40, dy: 20))

        // Screen translation divided by scale once.
        assertPoint(state.cards[0].position, 20, 10)
    }

    func testDeleteCardsRemovesGroupConnectionsAndUpdatesSelection() {
        let a = UUID(); let b = UUID(); let c = UUID(); let d = UUID()
        var state = WorkspaceState(cards: [
            makePositionedCard(a, x: 0, y: 0),
            makePositionedCard(b, x: 200, y: 0),
            makePositionedCard(c, x: 400, y: 0),
            makePositionedCard(d, x: 600, y: 0)
        ])
        state.addConnection(from: a, to: b) // both members
        state.addConnection(from: b, to: c) // one member
        state.addConnection(from: c, to: d) // unrelated
        state.selectCard(id: a)             // selectedCardID = a, clears marquee
        state.marqueeSelectedCardIDs = [a, b, c]

        state.deleteCards(ids: [a, b])

        XCTAssertEqual(state.cards.map(\.id), [c, d])
        XCTAssertEqual(state.connections.count, 1)
        let edge = state.connections[0]
        XCTAssertTrue((edge.from == c && edge.to == d) || (edge.from == d && edge.to == c))
        XCTAssertNil(state.selectedCardID)
        XCTAssertEqual(state.marqueeSelectedCardIDs, [c])
    }

    func testDeleteCardsIgnoresUnknownIDs() {
        let a = UUID(); let b = UUID()
        var state = WorkspaceState(cards: [
            makePositionedCard(a, x: 0, y: 0),
            makePositionedCard(b, x: 200, y: 0)
        ])

        state.deleteCards(ids: [UUID()])

        XCTAssertEqual(state.cards.count, 2)
    }

    @MainActor
    func testStoreMoveCardsIsDebounced() {
        let a = UUID(); let b = UUID()
        let state = WorkspaceState(cards: [
            makePositionedCard(a, x: 0, y: 0),
            makePositionedCard(b, x: 200, y: 0)
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: state, storageURL: url, persistenceDelay: 60)

        store.moveCards(ids: [a, b], screenTranslation: CanvasVector(dx: 30, dy: 10))

        assertPoint(store.state.cards[0].position, 30, 10)
        assertPoint(store.state.cards[1].position, 230, 10)
        // Debounced: nothing written synchronously.
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testStoreDeleteCardsPersistsImmediately() throws {
        let a = UUID(); let b = UUID(); let c = UUID()
        var state = WorkspaceState(cards: [
            makePositionedCard(a, x: 0, y: 0),
            makePositionedCard(b, x: 200, y: 0),
            makePositionedCard(c, x: 400, y: 0)
        ])
        state.marqueeSelectedCardIDs = [a, b]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = WorkspaceStore(state: state, storageURL: url, persistenceDelay: 60)

        store.deleteCards(ids: [a, b])

        XCTAssertEqual(store.state.cards.map(\.id), [c])
        // Structural change persists immediately.
        let loaded = try WorkspaceStore.load(from: url)
        XCTAssertEqual(loaded.cards.map(\.id), [c])
    }

    // MARK: - BrowserURLResolver (Core)

    func testBrowserResolverPrependsHTTPSForSchemelessHost() {
        XCTAssertEqual(BrowserURLResolver.normalized(from: "google.com")?.absoluteString, "https://google.com")
    }

    func testBrowserResolverKeepsExplicitScheme() {
        XCTAssertEqual(BrowserURLResolver.normalized(from: "http://example.com")?.scheme, "http")
    }

    func testBrowserResolverRejectsEmpty() {
        XCTAssertNil(BrowserURLResolver.normalized(from: "   "))
        XCTAssertFalse(BrowserURLResolver.isValid(""))
    }

    func testBrowserResolverLenientResolveAlwaysReturnsURL() {
        XCTAssertNotNil(BrowserURLResolver.resolve(from: ""))   // fallback, never nil
    }

    // MARK: - C1: Chat models + reducer

    func testReducerAppendsUserThenPendingAssistant() {
        let assistantID = UUID()
        let thread = ConversationReducer.appendingUserAndPendingAssistant([], userText: "hi", assistantID: assistantID)
        XCTAssertEqual(thread.count, 2)
        XCTAssertEqual(thread[0].role, .user)
        XCTAssertEqual(thread[0].text, "hi")
        XCTAssertEqual(thread[1].role, .assistant)
        XCTAssertEqual(thread[1].id, assistantID)
        XCTAssertTrue(thread[1].isPending)
    }

    func testReducerAccumulatesStreamChunks() {
        let id = UUID()
        var t = ConversationReducer.appendingUserAndPendingAssistant([], userText: "x", assistantID: id)
        t = ConversationReducer.appendingStreamChunk(t, messageID: id, chunk: "Hel")
        t = ConversationReducer.appendingStreamChunk(t, messageID: id, chunk: "lo")
        XCTAssertEqual(t[1].streamingText, "Hello")
        XCTAssertTrue(t[1].isStreaming)
    }

    func testReducerCompletesAndFails() {
        let id = UUID()
        let t = ConversationReducer.appendingUserAndPendingAssistant([], userText: "x", assistantID: id)
        let done = ConversationReducer.completing(t, messageID: id, text: "final")
        XCTAssertEqual(done[1].text, "final")
        XCTAssertEqual(done[1].status, .complete)
        let failed = ConversationReducer.failing(t, messageID: id, error: "boom")
        XCTAssertEqual(failed[1].status, .failed("boom"))
    }

    func testReducerFindsUserTextBeforeAssistantForRetry() {
        let id = UUID()
        let t = ConversationReducer.appendingUserAndPendingAssistant([], userText: "question", assistantID: id)
        XCTAssertEqual(ConversationReducer.userText(before: id, in: t), "question")
    }

    func testReducerResettingToPendingClearssStreamingStateAndText() {
        let id = UUID()
        var t = ConversationReducer.appendingUserAndPendingAssistant([], userText: "hi", assistantID: id)
        t = ConversationReducer.appendingStreamChunk(t, messageID: id, chunk: "partial response")
        XCTAssertTrue(t[1].isStreaming)

        t = ConversationReducer.resettingToPending(t, messageID: id)

        XCTAssertTrue(t[1].isPending)
        XCTAssertFalse(t[1].isStreaming)
        XCTAssertEqual(t[1].text, "")
    }

    // MARK: - Appearance enums (Task D1)

    func testTextSizeFontScale() {
        XCTAssertEqual(TextSize.small.fontScale, 0.9, accuracy: 0.0001)
        XCTAssertEqual(TextSize.medium.fontScale, 1.0, accuracy: 0.0001)
        XCTAssertEqual(TextSize.large.fontScale, 1.1, accuracy: 0.0001)
    }

    func testAppearanceModeRoundTripsRawValue() {
        XCTAssertEqual(AppearanceMode(rawValue: "dark"), .dark)
    }

    // MARK: - M1: Content bounding box

    func testContentBoundingBoxUnionsAllCards() throws {
        let state = WorkspaceState(cards: [
            WorkspaceCard(
                kind: .note,
                position: CanvasPoint(x: 100, y: 100),
                size: CardSize(width: 200, height: 150),
                title: "A",
                content: ""
            ),
            WorkspaceCard(
                kind: .note,
                position: CanvasPoint(x: 500, y: 400),
                size: CardSize(width: 300, height: 200),
                title: "B",
                content: ""
            )
        ])
        let box = try XCTUnwrap(state.contentBoundingBox())
        XCTAssertEqual(box.origin.x, 100, accuracy: 0.0001)
        XCTAssertEqual(box.origin.y, 100, accuracy: 0.0001)
        XCTAssertEqual(box.size.width, 700, accuracy: 0.0001)    // 800 - 100
        XCTAssertEqual(box.size.height, 500, accuracy: 0.0001)   // 600 - 100
    }

    func testContentBoundingBoxIsNilWhenNoCards() {
        let state = WorkspaceState(cards: [])
        XCTAssertNil(state.contentBoundingBox())
    }

    // MARK: - TC1: Typed connections + chain traversal

    func testLinkedCardIDsReturnsUndirectedNeighbors() throws {
        let a = try XCTUnwrap(UUID(uuidString: "EC100000-0000-0000-0000-000000000001"))
        let b = try XCTUnwrap(UUID(uuidString: "EC100000-0000-0000-0000-000000000002"))
        let c = try XCTUnwrap(UUID(uuidString: "EC100000-0000-0000-0000-000000000003"))
        var state = WorkspaceState(cards: [
            WorkspaceCard(id: a, kind: .note, position: .zero, size: CardSize(width: 300, height: 200), title: "A", content: "alpha"),
            WorkspaceCard(id: b, kind: .note, position: CanvasPoint(x: 400, y: 0), size: CardSize(width: 300, height: 200), title: "B", content: "beta"),
            WorkspaceCard(id: c, kind: .todo, position: CanvasPoint(x: 800, y: 0), size: CardSize(width: 300, height: 200), title: "C", content: "gamma")
        ])

        state.addConnection(from: a, to: b)

        XCTAssertEqual(state.linkedCardIDs(to: a), Set([b]))
        XCTAssertEqual(state.linkedCardIDs(to: b), Set([a]))
        XCTAssertEqual(state.linkedCardIDs(to: c), Set())
    }

    func testLinkedContextIncludesCardAndNeighborsContent() throws {
        let a = try XCTUnwrap(UUID(uuidString: "EC100000-0000-0000-0000-000000000011"))
        let b = try XCTUnwrap(UUID(uuidString: "EC100000-0000-0000-0000-000000000012"))
        var state = WorkspaceState(cards: [
            WorkspaceCard(id: a, kind: .todo, position: .zero, size: CardSize(width: 300, height: 200), title: "TODO list", content: "buy milk"),
            WorkspaceCard(id: b, kind: .note, position: CanvasPoint(x: 400, y: 0), size: CardSize(width: 300, height: 200), title: "Notes", content: "context")
        ])

        state.addConnection(from: a, to: b)

        let context = state.linkedContext(for: a)
        // Focus card (A) appears before neighbor (B).
        XCTAssertTrue(context.contains("TODO list"))
        XCTAssertTrue(context.contains("buy milk"))
        XCTAssertTrue(context.contains("Notes"))
        XCTAssertTrue(context.contains("context"))
        let rangeA = context.range(of: "TODO list")!
        let rangeB = context.range(of: "Notes")!
        XCTAssertLessThan(rangeA.lowerBound, rangeB.lowerBound, "focus card must appear before neighbor")
    }

    func testLinkedContextIsEmptyForBlankUnlinkedCard() throws {
        let id = try XCTUnwrap(UUID(uuidString: "EC200000-0000-0000-0000-000000000001"))
        let state = WorkspaceState(cards: [
            WorkspaceCard(
                id: id,
                kind: .note,
                position: .zero,
                size: CardSize(width: 300, height: 200),
                title: "",
                content: ""
            )
        ])

        let context = state.linkedContext(for: id)

        XCTAssertEqual(context, "", "blank unlinked card must produce an empty context string, not a bare newline")
    }

    func testConnectionTypeDefaultsToGenericForLegacyJSON() throws {
        let legacyJSON = """
        {"id":"DEADBEEF-0000-0000-0000-000000000001","from":"DEADBEEF-0000-0000-0000-000000000002","to":"DEADBEEF-0000-0000-0000-000000000003"}
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let connection = try JSONDecoder().decode(CardConnection.self, from: data)

        XCTAssertEqual(connection.type, .generic)
    }

    func testAddConnectionDerivesTypeFromEndpointKinds() throws {
        let a = try XCTUnwrap(UUID(uuidString: "EC100000-0000-0000-0000-000000000021"))
        let b = try XCTUnwrap(UUID(uuidString: "EC100000-0000-0000-0000-000000000022"))
        let c = try XCTUnwrap(UUID(uuidString: "EC100000-0000-0000-0000-000000000023"))
        var state = WorkspaceState(cards: [
            WorkspaceCard(id: a, kind: .note, position: .zero, size: CardSize(width: 300, height: 200), title: "Note", content: ""),
            WorkspaceCard(id: b, kind: .note, position: CanvasPoint(x: 400, y: 0), size: CardSize(width: 300, height: 200), title: "Note2", content: ""),
            WorkspaceCard(id: c, kind: .todo, position: CanvasPoint(x: 800, y: 0), size: CardSize(width: 300, height: 200), title: "Todo", content: "")
        ])

        state.addConnection(from: a, to: b)
        XCTAssertEqual(state.connections.first?.type, .noteToNote, "note+note should derive .noteToNote")

        state.addConnection(from: a, to: c)
        let noteTodo = state.connections.first(where: {
            ($0.from == a && $0.to == c) || ($0.from == c && $0.to == a)
        })
        XCTAssertEqual(noteTodo?.type, .todoToNote, "note+todo should derive .todoToNote")
    }

    // MARK: - BK: cleanShutdown flag + rolling backup recovery

    @MainActor
    func testRollingBackupKeepsLastNAndRotates() throws {
        // Pure helper: given 5 filenames and keep=3, oldest 2 are pruned.
        let names = ["backup-01.json", "backup-02.json", "backup-03.json",
                     "backup-04.json", "backup-05.json"]
        let pruned = WorkspaceStore.backupsToPrune(existing: names, keep: 3)
        XCTAssertEqual(Set(pruned), Set(["backup-01.json", "backup-02.json"]))

        // On-disk: N+2 (5) saves produce exactly N (3) backup files.
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let storageURL = baseDirectory.appendingPathComponent("workspace.json")
        let store = WorkspaceStore(
            state: WorkspaceState(),
            storageURL: storageURL,
            persistenceDelay: 60
        )
        let workspaceID = store.library.selectedWorkspaceID

        for _ in 0..<5 {
            store.persist()
            // Small sleep so timestamps differ in the filename.
            Thread.sleep(forTimeInterval: 0.002)
        }

        let backupsDir = baseDirectory
            .appendingPathComponent("backups")
            .appendingPathComponent(workspaceID.uuidString)
        let files = try FileManager.default.contentsOfDirectory(atPath: backupsDir.path)
        XCTAssertEqual(files.count, 3, "exactly 3 backups should remain after 5 saves")
    }

    @MainActor
    func testRecoversFromNewestBackupWhenCurrentMissingAfterUncleanShutdown() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)
        let legacyURL = baseDirectory.appendingPathComponent("workspace.json")

        // First launch: create store, add card (persists immediately + writes backup).
        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: legacyURL
        )
        store.addCard(kind: .note)
        let savedCardCount = store.state.cards.count
        let workspaceID = store.library.selectedWorkspaceID

        // Simulate crash: delete the current workspace file without marking clean.
        let workspaceFileURL = WorkspaceStore.workspaceURL(for: workspaceID, in: workspacesDirectory)
        try FileManager.default.removeItem(at: workspaceFileURL)
        // markCleanShutdown() is NOT called → marker stays false.

        // Second launch should recover from the backup.
        let recoveredStore = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: legacyURL
        )

        XCTAssertEqual(
            recoveredStore.state.cards.count, savedCardCount,
            "state must be recovered from the newest backup"
        )
    }

    @MainActor
    func testRecoversFromBackupWhenCurrentFileIsCorruptAfterUncleanShutdown() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)
        let legacyURL = baseDirectory.appendingPathComponent("workspace.json")

        // First launch: create store, add card (persists immediately + writes backup).
        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: legacyURL
        )
        store.addCard(kind: .note)
        let savedCardCount = store.state.cards.count
        let workspaceID = store.library.selectedWorkspaceID

        // Simulate crash: overwrite workspace file with invalid bytes, leave marker unclean.
        let workspaceFileURL = WorkspaceStore.workspaceURL(for: workspaceID, in: workspacesDirectory)
        try "{ not json".data(using: .utf8)!.write(to: workspaceFileURL)
        // markCleanShutdown() is NOT called → marker stays false.

        // Second launch should recover from the backup despite the corrupt (but present) file.
        let recoveredStore = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: legacyURL
        )

        XCTAssertEqual(
            recoveredStore.state.cards.count, savedCardCount,
            "state must be recovered from the newest backup when the current file is corrupt"
        )
    }

    @MainActor
    func testRecoversFromBackupOnCorruptFileEvenAfterCleanShutdown() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)
        let legacyURL = baseDirectory.appendingPathComponent("workspace.json")

        // First launch: create store, add card (persists immediately + writes backup).
        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: legacyURL
        )
        store.addCard(kind: .note)
        let savedCardCount = store.state.cards.count
        let workspaceID = store.library.selectedWorkspaceID

        // Graceful (clean) shutdown — the bug case: shutdown was clean but the file
        // gets corrupted afterwards (disk error, external tool, etc.).
        store.markCleanShutdown()

        // Corrupt the current workspace file after the clean shutdown.
        let workspaceFileURL = WorkspaceStore.workspaceURL(for: workspaceID, in: workspacesDirectory)
        try "{ not json".data(using: .utf8)!.write(to: workspaceFileURL)

        // Second launch must still recover from backup even though shutdown was clean.
        let recoveredStore = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: legacyURL
        )

        XCTAssertEqual(
            recoveredStore.state.cards.count, savedCardCount,
            "state must be recovered from backup even after a clean shutdown when the current file is corrupt"
        )
    }

    @MainActor
    func testCleanShutdownMarkerRoundTrips() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let libraryURL = baseDirectory.appendingPathComponent("library.json")
        let workspacesDirectory = baseDirectory.appendingPathComponent("workspaces", isDirectory: true)
        let legacyURL = baseDirectory.appendingPathComponent("workspace.json")
        let markerURL = baseDirectory.appendingPathComponent("shutdown.json")

        // Launch → marker is written false (running, potentially unclean).
        let store = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: legacyURL
        )
        XCTAssertFalse(
            WorkspaceStore.readShutdownMarker(from: markerURL),
            "marker should be false immediately after launch"
        )

        // Graceful shutdown → marker flips to true.
        store.markCleanShutdown()
        XCTAssertTrue(
            WorkspaceStore.readShutdownMarker(from: markerURL),
            "marker should be true after markCleanShutdown()"
        )

        // Fresh launch → marker reset to false again.
        _ = WorkspaceStore(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectory,
            legacyStorageURL: legacyURL
        )
        XCTAssertFalse(
            WorkspaceStore.readShutdownMarker(from: markerURL),
            "marker should be false again after a fresh store launch"
        )
    }

    func testCanvasRectUnionCoversBoth() {
        let a = CanvasRect(origin: CanvasPoint(x: 0, y: 0), size: CardSize(width: 100, height: 100))
        let b = CanvasRect(origin: CanvasPoint(x: 200, y: 50), size: CardSize(width: 100, height: 100))
        let u = a.union(b)
        XCTAssertEqual(u.origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(u.origin.y, 0, accuracy: 0.0001)
        XCTAssertEqual(u.size.width, 300, accuracy: 0.0001)   // 300 - 0
        XCTAssertEqual(u.size.height, 150, accuracy: 0.0001)  // 150 - 0
    }
}
