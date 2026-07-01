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

    // (c) Incomplete final row (N=5 or 7): every tile rect — including the centered
    // last row — must stay inside the usable rectangle.
    func testIncompleteLastRowStaysWithinUsableRect() {
        for n in [5, 7] {
            let l = layout(n)
            let usableTop = topInset + tiling.margin
            let usableBottom = viewport.y - bottomInset - tiling.margin
            let usableLeft = tiling.margin
            let usableRight = viewport.x - tiling.margin
            for (idx, origin) in l.tileOrigins.enumerated() {
                XCTAssertGreaterThanOrEqual(
                    origin.x, usableLeft - 0.5,
                    "N=\(n) tile \(idx): left edge out of usable bounds"
                )
                XCTAssertGreaterThanOrEqual(
                    origin.y, usableTop - 0.5,
                    "N=\(n) tile \(idx): top edge out of usable bounds"
                )
                XCTAssertLessThanOrEqual(
                    origin.x + l.tileSize.x, usableRight + 0.5,
                    "N=\(n) tile \(idx): right edge out of usable bounds"
                )
                XCTAssertLessThanOrEqual(
                    origin.y + l.tileSize.y, usableBottom + 0.5,
                    "N=\(n) tile \(idx): bottom edge out of usable bounds"
                )
            }
        }
    }

    // (d) fixedColumns edge cases: columns=0 clamps to 1; columns=100 with few
    // cards clamps down to cardCount.
    func testFixedColumnsEdgeCases() {
        let zeroColumns = SpaceTiling(mode: .fixedColumns, columns: 0)
        let l1 = SpaceGrid.layout(
            cardCount: 3, viewportSize: viewport,
            topInset: topInset, bottomInset: bottomInset, tiling: zeroColumns
        )
        XCTAssertEqual(l1.columns, 1, "columns=0 should clamp to 1")

        let manyColumns = SpaceTiling(mode: .fixedColumns, columns: 100)
        let l2 = SpaceGrid.layout(
            cardCount: 3, viewportSize: viewport,
            topInset: topInset, bottomInset: bottomInset, tiling: manyColumns
        )
        XCTAssertEqual(l2.columns, 3, "columns=100 with 3 cards should clamp to cardCount")
    }

    private func paged(_ n: Int, _ tiling: SpaceTiling, page: Int) -> SpaceGrid.PagedLayout {
        SpaceGrid.pagedLayout(cardCount: n, viewportSize: viewport,
                              topInset: topInset, bottomInset: bottomInset, tiling: tiling, page: page)
    }

    func testPagedLayoutSinglePageMatchesLayoutForAuto() {
        let l = layout(7)
        let p = paged(7, SpaceTiling(), page: 0)
        XCTAssertEqual(p.pageCount, 1)
        XCTAssertEqual(p.page, 0)
        XCTAssertEqual(p.cardRange, 0..<7)
        XCTAssertEqual(p.columns, l.columns)
        XCTAssertEqual(p.rows, l.rows)
        XCTAssertEqual(p.tileSize, l.tileSize)
        XCTAssertEqual(p.tileOrigins, l.tileOrigins)
    }

    func testPagedLayoutSinglePageMatchesLayoutForFixedColumns() {
        let tiling = SpaceTiling(mode: .fixedColumns, columns: 3)   // no maxRows
        let l = SpaceGrid.layout(cardCount: 5, viewportSize: viewport,
                                 topInset: topInset, bottomInset: bottomInset, tiling: tiling)
        let p = paged(5, tiling, page: 0)
        XCTAssertEqual(p.pageCount, 1)
        XCTAssertEqual(p.tileOrigins, l.tileOrigins)
        XCTAssertEqual(p.tileSize, l.tileSize)
    }

    func testPagedLayoutPaginatesFixedGrid() {
        let tiling = SpaceTiling(mode: .fixedColumns, columns: 3, maxRows: 2)   // capacity 6
        let p0 = paged(8, tiling, page: 0)
        let p1 = paged(8, tiling, page: 1)
        XCTAssertEqual(p0.pageCount, 2)
        XCTAssertEqual(p0.page, 0)
        XCTAssertEqual(p0.cardRange, 0..<6)
        XCTAssertEqual(p0.tileOrigins.count, 6)
        XCTAssertEqual(p1.page, 1)
        XCTAssertEqual(p1.cardRange, 6..<8)
        XCTAssertEqual(p1.tileOrigins.count, 2)
        // Tiles are the same size on every page (the "tiles stay large" promise).
        XCTAssertEqual(p0.tileSize, p1.tileSize)
        XCTAssertEqual(p0.columns, 3)
        XCTAssertEqual(p0.rows, 2)
    }

    func testPagedLayoutClampsPageBeyondRange() {
        let tiling = SpaceTiling(mode: .fixedColumns, columns: 3, maxRows: 2)
        let p = paged(8, tiling, page: 5)
        XCTAssertEqual(p.page, 1)
        XCTAssertEqual(p.cardRange, 6..<8)
    }

    func testPagedLayoutExactMultipleFillsLastPage() {
        let tiling = SpaceTiling(mode: .fixedColumns, columns: 2, maxRows: 2)   // capacity 4
        let p = paged(8, tiling, page: 1)
        XCTAssertEqual(p.pageCount, 2)
        XCTAssertEqual(p.cardRange, 4..<8)
        XCTAssertEqual(p.tileOrigins.count, 4)
    }

    func testPagedLayoutAutoNeverPaginatesEvenWithMaxRows() {
        let tiling = SpaceTiling(mode: .auto, columns: 2, maxRows: 2)
        let p = paged(12, tiling, page: 0)
        XCTAssertEqual(p.pageCount, 1)
        XCTAssertEqual(p.cardRange, 0..<12)
    }

    func testPagedLayoutZeroCards() {
        let p = paged(0, SpaceTiling(mode: .fixedColumns, columns: 3, maxRows: 2), page: 0)
        XCTAssertEqual(p.pageCount, 1)
        XCTAssertTrue(p.tileOrigins.isEmpty)
        XCTAssertEqual(p.cardRange, 0..<0)
    }

    func testTileIndicesReturnsOverlappingTiles() {
        let origins = [ScreenPoint(x: 0, y: 0), ScreenPoint(x: 120, y: 0), ScreenPoint(x: 240, y: 0)]
        let size = ScreenPoint(x: 100, y: 100)
        // Rect spanning the first two tiles.
        let hits = SpaceGrid.tileIndices(fromCorner: ScreenPoint(x: 10, y: 10),
                                         toCorner: ScreenPoint(x: 130, y: 50),
                                         tileOrigins: origins, tileSize: size)
        XCTAssertEqual(hits, [0, 1])
    }

    func testTileIndicesReturnsEmptyWhenOutside() {
        let origins = [ScreenPoint(x: 0, y: 0), ScreenPoint(x: 120, y: 0)]
        let size = ScreenPoint(x: 100, y: 100)
        let hits = SpaceGrid.tileIndices(fromCorner: ScreenPoint(x: 400, y: 400),
                                         toCorner: ScreenPoint(x: 500, y: 500),
                                         tileOrigins: origins, tileSize: size)
        XCTAssertTrue(hits.isEmpty)
    }

    func testTileIndicesCountsPartialOverlapAndNormalizesCorners() {
        let origins = [ScreenPoint(x: 0, y: 0)]
        let size = ScreenPoint(x: 100, y: 100)
        // Corners given bottom-right -> top-left; a 1px clip of the tile still counts.
        let hits = SpaceGrid.tileIndices(fromCorner: ScreenPoint(x: 50, y: 50),
                                         toCorner: ScreenPoint(x: -10, y: -10),
                                         tileOrigins: origins, tileSize: size)
        XCTAssertEqual(hits, [0])
    }
}
