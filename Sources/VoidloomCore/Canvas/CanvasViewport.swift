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

    public mutating func zoom(by magnification: Double, anchoredAt anchor: ScreenPoint) {
        guard magnification.isFinite, magnification > 0 else { return }

        let anchorBeforeZoom = canvasPoint(forScreenPoint: anchor)
        scale = Self.clampedScale(scale * magnification)
        origin = CanvasPoint(
            x: anchor.x - (anchorBeforeZoom.x * scale),
            y: anchor.y - (anchorBeforeZoom.y * scale)
        )
    }

    private static func clampedScale(_ scale: Double) -> Double {
        min(max(scale, minimumScale), maximumScale)
    }
}
