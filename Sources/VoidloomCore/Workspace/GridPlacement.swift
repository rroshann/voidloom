import Foundation

/// Viewport-relative slot geometry for double-click instant-create card placement.
///
/// Each page is a tidy 2x2 grid that exactly fills the *current* viewport (at the
/// current zoom) minus a comfortable margin and inter-card gap: every card owns
/// one quadrant of the visible area. Slots fill in reading order — slot 0
/// top-left, 1 top-right, 2 bottom-left, 3 bottom-right — then the next card
/// starts a fresh page (the viewport-follow logic lives in
/// `WorkspaceState.placeCardInGrid`).
public enum GridPlacement {
    /// Padding from the viewport edge to the first card of a page (screen px).
    public static let margin: Double = 48
    /// Visible gap between adjacent cards on a page (screen px).
    public static let gap: Double = 40

    public static let columnsPerPage = 2
    public static let rowsPerPage = 2
    public static var cardsPerPage: Int { columnsPerPage * rowsPerPage }

    /// Floor for a card's on-screen side, so a tiny window still yields usable
    /// (if overflowing) cards rather than zero/negative footprints.
    public static let minimumCardScreenSide: Double = 120

    /// The screen origins and canvas card size for one full page at a given
    /// viewport size and scale. `slotScreenOrigins` are in reading order
    /// (TL, TR, BL, BR) and `cardSize` is in canvas units at `scale`.
    public struct PageLayout: Equatable {
        public let cardSize: CardSize
        public let slotScreenOrigins: [ScreenPoint]

        public init(cardSize: CardSize, slotScreenOrigins: [ScreenPoint]) {
            self.cardSize = cardSize
            self.slotScreenOrigins = slotScreenOrigins
        }
    }

    /// Computes the 2x2 page layout that fills `viewportSize` (screen px) at
    /// `scale`. Falls back to a 1440x900 viewport when given a non-positive size
    /// so callers never crash on an unmeasured window.
    ///
    /// `bottomInset` reserves a band (screen px) at the bottom of the viewport —
    /// e.g. the floating dock's footprint — so the bottom row never lays cards
    /// behind it. Only the usable height shrinks; the top margin is untouched, so
    /// the inset is asymmetric (a larger gap below the bottom row than above the
    /// top row), which matches the dock genuinely occupying that band.
    public static func pageLayout(
        viewportSize: ScreenPoint,
        scale: Double,
        bottomInset: Double = 0
    ) -> PageLayout {
        let size = (viewportSize.x > 0 && viewportSize.y > 0)
            ? viewportSize
            : ScreenPoint(x: 1440, y: 900)
        let safeScale = max(scale, 0.0001)
        let reserve = max(bottomInset, 0)

        let usableW = size.x - (2 * margin) - gap
        let usableH = size.y - (2 * margin) - gap - reserve
        let cardWScreen = max(usableW / 2, minimumCardScreenSide)
        let cardHScreen = max(usableH / 2, minimumCardScreenSide)

        var origins: [ScreenPoint] = []
        for row in 0..<rowsPerPage {
            for column in 0..<columnsPerPage {
                origins.append(
                    ScreenPoint(
                        x: margin + (Double(column) * (cardWScreen + gap)),
                        y: margin + (Double(row) * (cardHScreen + gap))
                    )
                )
            }
        }

        return PageLayout(
            cardSize: CardSize(width: cardWScreen / safeScale, height: cardHScreen / safeScale),
            slotScreenOrigins: origins
        )
    }
}
