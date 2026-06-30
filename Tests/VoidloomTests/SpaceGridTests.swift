import XCTest
@testable import VoidloomCore

final class SpaceGridTests: XCTestCase {
    // Default test viewport: 1440x900, topInset 64, bottomInset 120, default tiling
    // (margin 28, gap 18, targetAspect 1.6) → usable rect ~1384x660.
    private let viewport = ScreenPoint(x: 1440, y: 900)
    private let topInset = 64.0
    private let bottomInset = 120.0
    private let tiling = SpaceTiling()

    private func layout(_ n: Int) -> SpaceGrid.Layout {
        SpaceGrid.layout(cardCount: n, viewportSize: viewport,
                         topInset: topInset, bottomInset: bottomInset, tiling: tiling)
    }

    func testColumnCountsForCommonCardCounts() {
        XCTAssertEqual((layout(1).columns, layout(1).rows).0, 1)
        XCTAssertEqual(layout(1).rows, 1)
        XCTAssertEqual(layout(2).columns, 2); XCTAssertEqual(layout(2).rows, 1)
        XCTAssertEqual(layout(4).columns, 2); XCTAssertEqual(layout(4).rows, 2)
        XCTAssertEqual(layout(5).columns, 3); XCTAssertEqual(layout(5).rows, 2)
        XCTAssertEqual(layout(6).columns, 3); XCTAssertEqual(layout(6).rows, 2)
        XCTAssertEqual(layout(9).columns, 3); XCTAssertEqual(layout(9).rows, 3)
    }

    func testProducesOneOriginPerCard() {
        for n in 1...12 { XCTAssertEqual(layout(n).tileOrigins.count, n) }
    }

    func testTilesStayWithinUsableRect() {
        let l = layout(6)
        let usableTop = topInset + tiling.margin
        let usableBottom = viewport.y - bottomInset - tiling.margin
        let usableLeft = tiling.margin
        let usableRight = viewport.x - tiling.margin
        for origin in l.tileOrigins {
            XCTAssertGreaterThanOrEqual(origin.x, usableLeft - 0.5)
            XCTAssertGreaterThanOrEqual(origin.y, usableTop - 0.5)
            XCTAssertLessThanOrEqual(origin.x + l.tileSize.x, usableRight + 0.5)
            XCTAssertLessThanOrEqual(origin.y + l.tileSize.y, usableBottom + 0.5)
        }
    }

    func testLastRowIsCentered() {
        // N=5 → 3 cols, 2 rows; last row has 2 tiles, centered → its left tile
        // starts further right than the full top row's left tile.
        let l = layout(5)
        let topRowLeftX = l.tileOrigins[0].x
        let lastRowLeftX = l.tileOrigins[3].x
        XCTAssertGreaterThan(lastRowLeftX, topRowLeftX)
    }

    func testNonPositiveViewportFallsBack() {
        let l = SpaceGrid.layout(cardCount: 4, viewportSize: ScreenPoint(x: 0, y: 0),
                                 topInset: 0, bottomInset: 0, tiling: tiling)
        XCTAssertEqual(l.tileOrigins.count, 4)          // 1440x900 fallback → no crash
        XCTAssertGreaterThan(l.tileSize.x, 0)
    }

    func testMinimumTileSideFloorOnTinyViewport() {
        let l = SpaceGrid.layout(cardCount: 9, viewportSize: ScreenPoint(x: 320, y: 240),
                                 topInset: 0, bottomInset: 0, tiling: tiling)
        XCTAssertGreaterThanOrEqual(l.tileSize.x, SpaceGrid.minimumTileSide)
        XCTAssertGreaterThanOrEqual(l.tileSize.y, SpaceGrid.minimumTileSide)
    }

    func testFixedColumnsHonoredAndClamped() {
        let fixed = SpaceTiling(mode: .fixedColumns, columns: 3)
        let l = SpaceGrid.layout(cardCount: 6, viewportSize: viewport,
                                 topInset: topInset, bottomInset: bottomInset, tiling: fixed)
        XCTAssertEqual(l.columns, 3)
        // columns clamp to cardCount when fewer cards than requested columns
        let l2 = SpaceGrid.layout(cardCount: 2, viewportSize: viewport,
                                  topInset: topInset, bottomInset: bottomInset, tiling: fixed)
        XCTAssertEqual(l2.columns, 2)
    }

    func testZeroCardsProducesEmptyLayout() {
        let l = layout(0)
        XCTAssertEqual(l.tileOrigins.count, 0)
    }
}
