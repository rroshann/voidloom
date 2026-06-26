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
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public enum CardKind: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case agent
    case note
    case todo
    case browser

    public var id: String { rawValue }
}

public struct WorkspaceCard: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: CardKind
    public var position: CanvasPoint
    public var size: CardSize
    public var title: String
    public var content: String

    public init(
        id: UUID = UUID(),
        kind: CardKind,
        position: CanvasPoint,
        size: CardSize,
        title: String,
        content: String
    ) {
        self.id = id
        self.kind = kind
        self.position = position
        self.size = size
        self.title = title
        self.content = content
    }
}

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

public struct WorkspaceState: Codable, Equatable, Sendable {
    public var viewport: CanvasViewport
    public var cards: [WorkspaceCard]

    public init(viewport: CanvasViewport = CanvasViewport(), cards: [WorkspaceCard] = []) {
        self.viewport = viewport
        self.cards = cards
    }

    public mutating func moveCard(id: UUID, screenTranslation: CanvasVector) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }

        cards[index].position.x += screenTranslation.dx / viewport.scale
        cards[index].position.y += screenTranslation.dy / viewport.scale
    }

    public mutating func addCard(_ card: WorkspaceCard) {
        cards.append(card)
    }

    public mutating func replaceCard(_ card: WorkspaceCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[index] = card
    }
}

