import Foundation

/// Pure slot geometry for double-click instant-create card placement.
///
/// Cards fill a tidy 2x2 "page" in reading order — slot 0 top-left, 1 top-right,
/// 2 bottom-left, 3 bottom-right — then the next card starts a fresh page below.
/// All values are canvas-space constants; the viewport-follow logic lives in
/// `WorkspaceState.placeCardInGrid`.
public enum GridPlacement {
    /// Padding from the viewport edge to the first card of a page (screen px,
    /// reused as a canvas inset at the current scale).
    public static let margin: Double = 48
    /// Visible gap between adjacent cards on a page.
    public static let gap: Double = 40
    /// Reference card footprint used for stride math (real card sizes vary by
    /// kind but stay within this envelope).
    public static let nominalCardWidth: Double = 520
    public static let nominalCardHeight: Double = 340

    public static let columnsPerPage = 2
    public static let rowsPerPage = 2
    public static var cardsPerPage: Int { columnsPerPage * rowsPerPage }

    /// Distance between the top-left of one card and the next along each axis.
    public static var columnStride: Double { nominalCardWidth + gap }
    public static var rowStride: Double { nominalCardHeight + gap }

    /// Vertical distance between the top-left of one page and the next.
    public static var pageStride: Double { Double(rowsPerPage) * rowStride }

    public struct Slot: Equatable {
        public let column: Int
        public let row: Int
        public let page: Int
        public let isPageStart: Bool
    }

    /// The slot the `count`-th placed card occupies (zero-based count).
    public static func slot(for count: Int) -> Slot {
        let page = count / cardsPerPage
        let indexInPage = count % cardsPerPage
        return Slot(
            column: indexInPage % columnsPerPage,
            row: indexInPage / columnsPerPage,
            page: page,
            isPageStart: indexInPage == 0
        )
    }

    /// Top-left canvas origin for a card at `(column, row)` measured from the
    /// current page anchor (the page's top-left card origin).
    public static func origin(anchor: CanvasPoint, column: Int, row: Int) -> CanvasPoint {
        CanvasPoint(
            x: anchor.x + (Double(column) * columnStride),
            y: anchor.y + (Double(row) * rowStride)
        )
    }
}
