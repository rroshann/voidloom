import Foundation

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

public struct WorkspaceState: Codable, Equatable, Sendable {
    public var viewport: CanvasViewport
    public var selectedCardID: UUID?
    public var cards: [WorkspaceCard]

    public init(
        viewport: CanvasViewport = CanvasViewport(),
        selectedCardID: UUID? = nil,
        cards: [WorkspaceCard] = []
    ) {
        self.viewport = viewport
        self.selectedCardID = selectedCardID
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

    public mutating func selectCard(id: UUID) {
        guard cards.contains(where: { $0.id == id }) else { return }
        selectedCardID = id
    }

    public mutating func clearSelection() {
        selectedCardID = nil
    }
}
