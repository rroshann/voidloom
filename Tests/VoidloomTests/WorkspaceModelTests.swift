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
}
