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

public struct AlignmentGuide: Equatable, Sendable {
    public enum Axis: Equatable, Sendable { case vertical, horizontal }
    public var axis: Axis
    public var canvasCoordinate: Double
    public init(axis: Axis, canvasCoordinate: Double) {
        self.axis = axis
        self.canvasCoordinate = canvasCoordinate
    }
}

extension CanvasSnapping {
    /// Snaps a moving rect's edges/centers to nearby rects' edges/centers.
    /// Returns the adjusted origin and the guide lines that matched.
    public static func align(
        movingOrigin: CanvasPoint,
        size: CardSize,
        others: [CanvasRect],
        threshold: Double
    ) -> (origin: CanvasPoint, guides: [AlignmentGuide]) {
        var origin = movingOrigin
        var guides: [AlignmentGuide] = []

        // Vertical axis (x coordinates): left, centerX, right.
        let movingXs = [movingOrigin.x, movingOrigin.x + size.width / 2, movingOrigin.x + size.width]
        let otherXs = others.flatMap { [$0.origin.x, $0.origin.x + $0.size.width / 2, $0.origin.x + $0.size.width] }
        if let best = bestSnap(moving: movingXs, candidates: otherXs, threshold: threshold) {
            origin.x += best.delta
            guides.append(AlignmentGuide(axis: .vertical, canvasCoordinate: best.target))
        }

        // Horizontal axis (y coordinates): top, centerY, bottom.
        let movingYs = [movingOrigin.y, movingOrigin.y + size.height / 2, movingOrigin.y + size.height]
        let otherYs = others.flatMap { [$0.origin.y, $0.origin.y + $0.size.height / 2, $0.origin.y + $0.size.height] }
        if let best = bestSnap(moving: movingYs, candidates: otherYs, threshold: threshold) {
            origin.y += best.delta
            guides.append(AlignmentGuide(axis: .horizontal, canvasCoordinate: best.target))
        }

        return (origin, guides)
    }

    /// Finds the smallest within-threshold gap between any moving line and any candidate line.
    /// Returns the delta to apply to the origin and the target coordinate the guide sits on.
    private static func bestSnap(
        moving: [Double],
        candidates: [Double],
        threshold: Double
    ) -> (delta: Double, target: Double)? {
        var best: (delta: Double, target: Double, distance: Double)?
        for m in moving {
            for c in candidates {
                let distance = abs(c - m)
                if distance <= threshold, best == nil || distance < best!.distance {
                    best = (delta: c - m, target: c, distance: distance)
                }
            }
        }
        guard let best else { return nil }
        return (best.delta, best.target)
    }
}
