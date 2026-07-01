import Foundation

/// Pure, screen-space tile layout for Spaces mode. Generalizes the 2x2
/// `GridPlacement` into an N-up auto grid by maximizing aspect-weighted tile
/// area over candidate column counts. No UI, fully testable.
public enum SpaceGrid {
    /// Floor for a tile's on-screen side, so a tiny window still yields usable
    /// (possibly overflowing) tiles rather than zero/negative footprints.
    public static let minimumTileSide: Double = 160

    public struct Layout: Equatable, Sendable {
        public let columns: Int
        public let rows: Int
        public let tileSize: ScreenPoint        // uniform (w, h) in screen px
        public let tileOrigins: [ScreenPoint]   // one per card, reading order

        public init(columns: Int, rows: Int, tileSize: ScreenPoint, tileOrigins: [ScreenPoint]) {
            self.columns = columns
            self.rows = rows
            self.tileSize = tileSize
            self.tileOrigins = tileOrigins
        }
    }

    /// A single page of a (possibly paginated) Spaces grid. `tileOrigins` covers
    /// only the cards on this page; `cardRange` is their global index range into
    /// the ordered card list.
    public struct PagedLayout: Equatable, Sendable {
        public let pageCount: Int
        public let page: Int                    // clamped index actually shown
        public let columns: Int
        public let rows: Int                    // rows used for tile SIZING
        public let tileSize: ScreenPoint        // uniform, identical on every page
        public let tileOrigins: [ScreenPoint]   // one per card ON THIS PAGE, reading order
        public let cardRange: Range<Int>        // global card indices [start, end) on this page

        public init(pageCount: Int, page: Int, columns: Int, rows: Int,
                    tileSize: ScreenPoint, tileOrigins: [ScreenPoint], cardRange: Range<Int>) {
            self.pageCount = pageCount
            self.page = page
            self.columns = columns
            self.rows = rows
            self.tileSize = tileSize
            self.tileOrigins = tileOrigins
            self.cardRange = cardRange
        }
    }

    /// The all-cards, single-screen layout (unchanged behavior). Delegates to
    /// `pagedLayout` with pagination disabled so both share one implementation.
    public static func layout(
        cardCount: Int,
        viewportSize: ScreenPoint,
        topInset: Double,
        bottomInset: Double,
        tiling: SpaceTiling
    ) -> Layout {
        var single = tiling
        single.maxRows = nil
        let p = pagedLayout(cardCount: cardCount, viewportSize: viewportSize,
                            topInset: topInset, bottomInset: bottomInset, tiling: single, page: 0)
        return Layout(columns: p.columns, rows: p.rows, tileSize: p.tileSize, tileOrigins: p.tileOrigins)
    }

    /// Page-aware layout. Non-paginating tilings (`.auto`, or `.fixedColumns`
    /// without `maxRows`) return a single page equal to `layout(...)`. A fixed
    /// grid with `maxRows` shows exactly `columns × maxRows` full-size tiles per
    /// page and paginates the overflow.
    public static func pagedLayout(
        cardCount: Int,
        viewportSize: ScreenPoint,
        topInset: Double,
        bottomInset: Double,
        tiling: SpaceTiling,
        page: Int
    ) -> PagedLayout {
        guard cardCount > 0 else {
            return PagedLayout(pageCount: 1, page: 0, columns: 0, rows: 0,
                               tileSize: ScreenPoint(x: 0, y: 0), tileOrigins: [], cardRange: 0..<0)
        }

        let size = (viewportSize.x > 0 && viewportSize.y > 0)
            ? viewportSize
            : ScreenPoint(x: 1440, y: 900)

        let margin = tiling.margin
        let gap = tiling.gap
        let usableX = margin
        let usableY = topInset + margin
        let usableW = size.x - (2 * margin)
        let usableH = size.y - topInset - bottomInset - (2 * margin)

        let paginating = tiling.mode == .fixedColumns && (tiling.maxRows ?? 0) > 0

        let cols: Int
        let rowsForSizing: Int
        let capacity: Int
        if paginating {
            cols = max(tiling.columns, 1)
            rowsForSizing = max(tiling.maxRows ?? 1, 1)
            capacity = cols * rowsForSizing
        } else {
            switch tiling.mode {
            case .fixedColumns:
                cols = min(max(tiling.columns, 1), cardCount)
            case .auto:
                cols = bestColumnCount(cardCount: cardCount, usableW: usableW,
                                       usableH: usableH, gap: gap, targetAspect: tiling.targetAspect)
            }
            rowsForSizing = Int((Double(cardCount) / Double(cols)).rounded(.up))
            capacity = cardCount
        }

        let pageCount = max(1, Int((Double(cardCount) / Double(capacity)).rounded(.up)))
        let clampedPage = min(max(page, 0), pageCount - 1)
        let start = clampedPage * capacity
        let end = min(cardCount, start + capacity)
        let countOnPage = end - start

        let rawTileW = (usableW - Double(cols - 1) * gap) / Double(cols)
        let rawTileH = (usableH - Double(rowsForSizing - 1) * gap) / Double(rowsForSizing)
        let tileW = max(rawTileW, minimumTileSide)
        let tileH = max(rawTileH, minimumTileSide)

        var origins: [ScreenPoint] = []
        origins.reserveCapacity(countOnPage)
        for i in 0..<countOnPage {
            let r = i / cols
            let c = i % cols
            let countInRow = min(cols, countOnPage - r * cols)
            let rowW = Double(countInRow) * tileW + Double(countInRow - 1) * gap
            let rowX = usableX + max(0, (usableW - rowW) / 2)   // center an incomplete row
            origins.append(ScreenPoint(
                x: rowX + Double(c) * (tileW + gap),
                y: usableY + Double(r) * (tileH + gap)
            ))
        }

        return PagedLayout(
            pageCount: pageCount, page: clampedPage,
            columns: cols, rows: rowsForSizing,
            tileSize: ScreenPoint(x: tileW, y: tileH),
            tileOrigins: origins, cardRange: start..<end
        )
    }

    /// Picks the column count that maximizes the aspect-weighted area of a tile.
    /// score = min(w, h*AR) * min(h, w/AR) — rewards tiles close to `targetAspect`
    /// without letting one dimension run away.
    private static func bestColumnCount(
        cardCount: Int, usableW: Double, usableH: Double, gap: Double, targetAspect: Double
    ) -> Int {
        var bestCols = 1
        var bestScore = -Double.greatestFiniteMagnitude
        for cols in 1...cardCount {
            let rows = Int((Double(cardCount) / Double(cols)).rounded(.up))
            let tileW = (usableW - Double(cols - 1) * gap) / Double(cols)
            let tileH = (usableH - Double(rows - 1) * gap) / Double(rows)
            if tileW <= 0 || tileH <= 0 { continue }
            let score = min(tileW, tileH * targetAspect) * min(tileH, tileW / targetAspect)
            if score > bestScore {
                bestScore = score
                bestCols = cols
            }
        }
        return bestCols
    }
}
