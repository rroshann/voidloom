import Foundation

/// Pure snap + alignment math for canvas objects. Operates in CANVAS space.
public enum CanvasSnapping {
    /// Rounds a point to the nearest grid intersection. `gridSize <= 0` is a no-op.
    public static func snap(_ point: CanvasPoint, toGrid gridSize: Double) -> CanvasPoint {
        guard gridSize > 0 else { return point }
        return CanvasPoint(
            x: (point.x / gridSize).rounded() * gridSize,
            y: (point.y / gridSize).rounded() * gridSize
        )
    }
}
