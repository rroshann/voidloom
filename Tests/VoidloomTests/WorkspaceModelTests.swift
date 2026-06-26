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

    func testSeedStateIncludesEachV0CardKind() {
        let seedState = WorkspaceStore.makeSeedState()
        let kinds = Set(seedState.cards.map(\.kind))

        XCTAssertTrue(kinds.contains(.agent))
        XCTAssertTrue(kinds.contains(.note))
        XCTAssertTrue(kinds.contains(.todo))
        XCTAssertTrue(kinds.contains(.browser))
    }
}
