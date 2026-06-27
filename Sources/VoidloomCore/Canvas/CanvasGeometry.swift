import Foundation

public struct CanvasPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public static let zero = CanvasPoint(x: 0, y: 0)

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ScreenPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CanvasVector: Codable, Equatable, Sendable {
    public var dx: Double
    public var dy: Double

    public static let zero = CanvasVector(dx: 0, dy: 0)

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }
}

public struct CardSize: Codable, Equatable, Sendable {
    public static let minimumWidth: Double = 240
    public static let minimumHeight: Double = 160

    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public func clampedToMinimums() -> CardSize {
        CardSize(
            width: max(width, Self.minimumWidth),
            height: max(height, Self.minimumHeight)
        )
    }
}
