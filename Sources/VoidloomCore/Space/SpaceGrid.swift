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

    public static func layout(
        cardCount: Int,
        viewportSize: ScreenPoint,
        topInset: Double,
        bottomInset: Double,
        tiling: SpaceTiling
    ) -> Layout {
        guard cardCount > 0 else {
            return Layout(columns: 0, rows: 0, tileSize: ScreenPoint(x: 0, y: 0), tileOrigins: [])
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

        let cols: Int
        switch tiling.mode {
        case .fixedColumns:
            cols = min(max(tiling.columns, 1), cardCount)
        case .auto:
            cols = bestColumnCount(cardCount: cardCount, usableW: usableW,
                                   usableH: usableH, gap: gap, targetAspect: tiling.targetAspect)
        }
        let rows = Int((Double(cardCount) / Double(cols)).rounded(.up))

        let rawTileW = (usableW - Double(cols - 1) * gap) / Double(cols)
        let rawTileH = (usableH - Double(rows - 1) * gap) / Double(rows)
        let tileW = max(rawTileW, minimumTileSide)
        let tileH = max(rawTileH, minimumTileSide)

        var origins: [ScreenPoint] = []
        origins.reserveCapacity(cardCount)
        for i in 0..<cardCount {
            let r = i / cols
            let c = i % cols
            let countInRow = min(cols, cardCount - r * cols)
            let rowW = Double(countInRow) * tileW + Double(countInRow - 1) * gap
            let rowX = usableX + max(0, (usableW - rowW) / 2)   // center an incomplete row
            origins.append(ScreenPoint(
                x: rowX + Double(c) * (tileW + gap),
                y: usableY + Double(r) * (tileH + gap)
            ))
        }

        return Layout(columns: cols, rows: rows,
                      tileSize: ScreenPoint(x: tileW, y: tileH), tileOrigins: origins)
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
