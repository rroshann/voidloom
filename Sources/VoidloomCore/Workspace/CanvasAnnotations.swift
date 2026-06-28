import Foundation

/// A visual-only directed edge connecting two cards. Connections carry no agent
/// communication — they are purely decorative links rendered on the canvas.
public struct CardConnection: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var from: UUID
    public var to: UUID

    public init(id: UUID = UUID(), from: UUID, to: UUID) {
        self.id = id
        self.from = from
        self.to = to
    }
}

/// A lightweight chromeless text element placed directly on the canvas — just
/// text, no card window/background. Distinct from `CardKind.note` so the card
/// model and its `agent` rawValue contract stay untouched.
public struct TextElement: Codable, Equatable, Identifiable, Sendable {
    public static let minimumWidth: Double = 60
    public static let minimumHeight: Double = 28

    public var id: UUID
    public var position: CanvasPoint
    public var size: CardSize
    public var text: String
    public var fontSize: Double
    public var colorHex: String

    public init(
        id: UUID = UUID(),
        position: CanvasPoint,
        size: CardSize,
        text: String = "",
        fontSize: Double = 17,
        colorHex: String = "#FFFFFFFF"
    ) {
        self.id = id
        self.position = position
        self.size = size
        self.text = text
        self.fontSize = fontSize
        self.colorHex = colorHex
    }
}

/// An RGBA color stored as components so drawing strokes round-trip cleanly
/// without depending on SwiftUI/AppKit color spaces.
public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var opacity: Double

    public init(red: Double, green: Double, blue: Double, opacity: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
}

/// A freehand brush stroke. Points and thickness live in CANVAS space so the
/// stroke pans/zooms with the canvas and renders beneath cards.
public struct DrawingStroke: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var points: [CanvasPoint]
    public var color: RGBAColor
    public var thickness: Double

    public init(
        id: UUID = UUID(),
        points: [CanvasPoint],
        color: RGBAColor,
        thickness: Double
    ) {
        self.id = id
        self.points = points
        self.color = color
        self.thickness = thickness
    }
}

/// How the eraser removes brush strokes.
public enum EraseMode: String, Codable, Equatable, Sendable {
    /// Remove any stroke the eraser disc touches.
    case wholeStroke
    /// Remove only the portion of the stroke under the eraser disc, splitting
    /// the remainder into separate fragments.
    case segment
}
