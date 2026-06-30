import Foundation

/// Semantic classification of a connection, derived from the `CardKind` of its
/// two endpoints. Used by the AI context-assembly layer to weight links; purely
/// informational at the canvas layer. Legacy JSON without a `type` field decodes
/// to `.generic` so no migration is needed.
public enum ConnectionType: String, Codable, Equatable, Sendable {
    case generic
    case noteToNote
    case todoToNote
    case agentToNote
    case browserToNote
    case agentToTodo
    case agentToBrowser

    /// Derives the connection type from two endpoint kinds, order-independent.
    /// Canonical ordering sorts by rawValue alphabetically so (a, b) and (b, a)
    /// produce the same result. Pairs without a named case return `.generic`.
    public static func derive(_ a: CardKind, _ b: CardKind) -> ConnectionType {
        let sorted = [a.rawValue, b.rawValue].sorted()
        switch (sorted[0], sorted[1]) {
        case ("note", "note"):      return .noteToNote
        case ("note", "todo"):      return .todoToNote
        case ("agent", "note"):     return .agentToNote
        case ("browser", "note"):   return .browserToNote
        case ("agent", "todo"):     return .agentToTodo
        case ("agent", "browser"):  return .agentToBrowser
        default:                    return .generic
        }
    }
}

/// A visual-only, non-directional (undirected) edge connecting two cards. The
/// `from`/`to` order is incidental — the edge reads the same both ways and
/// renders without an arrowhead. Connections carry no agent communication —
/// they are purely decorative links rendered on the canvas.
public struct CardConnection: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var from: UUID
    public var to: UUID
    /// Semantic type derived from endpoint `CardKind`s at insertion time.
    /// Decodes to `.generic` when absent so legacy JSON round-trips cleanly.
    public var type: ConnectionType

    public init(id: UUID = UUID(), from: UUID, to: UUID, type: ConnectionType = .generic) {
        self.id = id
        self.from = from
        self.to = to
        self.type = type
    }

    // Custom decode: back-compat — existing persisted connections have no `type`
    // field and must silently default to `.generic` instead of throwing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        from = try container.decode(UUID.self, forKey: .from)
        to = try container.decode(UUID.self, forKey: .to)
        type = try container.decodeIfPresent(ConnectionType.self, forKey: .type) ?? .generic
    }

    private enum CodingKeys: String, CodingKey {
        case id, from, to, type
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
    /// The PostScript font name applied to the element, or nil for the default
    /// system-rounded face. Optional + synthesized `Codable` means legacy JSON
    /// (written before fonts existed) decodes to nil and nil is omitted on write.
    public var fontName: String?

    public init(
        id: UUID = UUID(),
        position: CanvasPoint,
        size: CardSize,
        text: String = "",
        fontSize: Double = 17,
        colorHex: String = "#FFFFFFFF",
        fontName: String? = nil
    ) {
        self.id = id
        self.position = position
        self.size = size
        self.text = text
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.fontName = fontName
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
