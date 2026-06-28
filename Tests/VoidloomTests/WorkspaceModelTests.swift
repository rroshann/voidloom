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
}
