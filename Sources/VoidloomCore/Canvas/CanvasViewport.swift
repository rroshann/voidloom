import Foundation

public struct CanvasViewport: Codable, Equatable, Sendable {
    public static let minimumScale = 0.35
    public static let maximumScale = 2.4

    public var origin: CanvasPoint
    public var scale: Double

    public init(origin: CanvasPoint = .zero, scale: Double = 1) {
        self.origin = origin
        self.scale = Self.clampedScale(scale)
    }

    public func canvasPoint(forScreenPoint point: ScreenPoint) -> CanvasPoint {
        CanvasPoint(
            x: (point.x - origin.x) / scale,
            y: (point.y - origin.y) / scale
        )
    }

    public func screenPoint(forCanvasPoint point: CanvasPoint) -> ScreenPoint {
        ScreenPoint(
            x: (point.x * scale) + origin.x,
            y: (point.y * scale) + origin.y
        )
    }

    public mutating func pan(by screenTranslation: CanvasVector) {
        origin.x += screenTranslation.dx
        origin.y += screenTranslation.dy
    }

    /// Pans so that canvas point `p` lands at screen point `s` (scale unchanged).
    public mutating func pan(soCanvasPoint p: CanvasPoint, appearsAt s: ScreenPoint) {
        origin = CanvasPoint(
            x: s.x - (p.x * scale),
            y: s.y - (p.y * scale)
        )
    }

    /// Pans the minimum amount needed to bring a canvas rect fully inside the
    /// viewport's `margin` inset. A no-op when the rect is already visible. The
    /// top-left edge is prioritized, so an oversized rect stays pinned top-left.
    public mutating func panToReveal(
        canvasRectOrigin rectOrigin: CanvasPoint,
        size: CardSize,
        viewportSize: ScreenPoint,
        margin: Double
    ) {
        guard viewportSize.x > 0, viewportSize.y > 0 else { return }

        let topLeft = screenPoint(forCanvasPoint: rectOrigin)
        let rectWidth = size.width * scale
        let rectHeight = size.height * scale

        let minX = margin
        let maxX = viewportSize.x - margin
        let minY = margin
        let maxY = viewportSize.y - margin

        var dx = 0.0
        if topLeft.x < minX {
            dx = minX - topLeft.x
        } else if topLeft.x + rectWidth > maxX {
            dx = maxX - (topLeft.x + rectWidth)
        }

        var dy = 0.0
        if topLeft.y < minY {
            dy = minY - topLeft.y
        } else if topLeft.y + rectHeight > maxY {
            dy = maxY - (topLeft.y + rectHeight)
        }

        if dx != 0 || dy != 0 {
            pan(by: CanvasVector(dx: dx, dy: dy))
        }
    }

    public mutating func zoom(by magnification: Double, anchoredAt anchor: ScreenPoint) {
        guard magnification.isFinite, magnification > 0 else { return }

        let anchorBeforeZoom = canvasPoint(forScreenPoint: anchor)
        scale = Self.clampedScale(scale * magnification)
        origin = CanvasPoint(
            x: anchor.x - (anchorBeforeZoom.x * scale),
            y: anchor.y - (anchorBeforeZoom.y * scale)
        )
    }

    public mutating func focus(
        onCanvasRect rectOrigin: CanvasPoint,
        size: CardSize,
        padding: Double,
        viewportSize: ScreenPoint
    ) {
        guard size.width > 0, size.height > 0 else { return }
        guard viewportSize.x > 0, viewportSize.y > 0 else { return }

        let cardCenter = CanvasPoint(
            x: rectOrigin.x + (size.width / 2),
            y: rectOrigin.y + (size.height / 2)
        )

        let availableWidth = viewportSize.x - (padding * 2)
        let availableHeight = viewportSize.y - (padding * 2)
        guard availableWidth > 0, availableHeight > 0 else { return }

        let fitScale = min(availableWidth / size.width, availableHeight / size.height)
        scale = Self.clampedScale(fitScale)
        origin = CanvasPoint(
            x: (viewportSize.x / 2) - (cardCenter.x * scale),
            y: (viewportSize.y / 2) - (cardCenter.y * scale)
        )
    }

    private static func clampedScale(_ scale: Double) -> Double {
        min(max(scale, minimumScale), maximumScale)
    }
}
