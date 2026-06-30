import Foundation

/// An axis-aligned rectangle in canvas space, used to anchor connection edges
/// on card borders so an edge meets the visible edge of each card rather than
/// its center.
public struct CanvasRect: Equatable, Sendable {
    public var origin: CanvasPoint
    public var size: CardSize

    public init(origin: CanvasPoint, size: CardSize) {
        self.origin = origin
        self.size = size
    }

    public var center: CanvasPoint {
        CanvasPoint(
            x: origin.x + (size.width / 2),
            y: origin.y + (size.height / 2)
        )
    }

    /// Returns the smallest `CanvasRect` that contains both `self` and `other`.
    public func union(_ other: CanvasRect) -> CanvasRect {
        let minX = Swift.min(origin.x, other.origin.x)
        let minY = Swift.min(origin.y, other.origin.y)
        let maxX = Swift.max(origin.x + size.width,  other.origin.x + other.size.width)
        let maxY = Swift.max(origin.y + size.height, other.origin.y + other.size.height)
        return CanvasRect(
            origin: CanvasPoint(x: minX, y: minY),
            size: CardSize(width: maxX - minX, height: maxY - minY)
        )
    }

    /// The point on this rect's border that lies on the ray from the rect's
    /// center towards `target`. Returns the center for a degenerate target.
    public func borderIntersection(towards target: CanvasPoint) -> CanvasPoint {
        let c = center
        let dx = target.x - c.x
        let dy = target.y - c.y
        guard dx != 0 || dy != 0 else { return c }

        let halfWidth = size.width / 2
        let halfHeight = size.height / 2

        let scaleX = dx == 0 ? Double.greatestFiniteMagnitude : halfWidth / abs(dx)
        let scaleY = dy == 0 ? Double.greatestFiniteMagnitude : halfHeight / abs(dy)
        let t = min(scaleX, scaleY)

        return CanvasPoint(x: c.x + (dx * t), y: c.y + (dy * t))
    }
}

/// The two border-anchored endpoints for an edge drawn between two card rects:
/// the start exits `from` towards `to`'s center and the end enters `to` from
/// `from`'s center, so the edge tracks both cards as they move/resize.
public func connectionEndpoints(
    from: CanvasRect,
    to: CanvasRect
) -> (start: CanvasPoint, end: CanvasPoint) {
    let start = from.borderIntersection(towards: to.center)
    let end = to.borderIntersection(towards: from.center)
    return (start, end)
}
