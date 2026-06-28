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
    public var connections: [CardConnection]
    public var strokes: [DrawingStroke]
    public var textElements: [TextElement]
    public var selectedTextID: UUID?

    public init(
        viewport: CanvasViewport = CanvasViewport(),
        selectedCardID: UUID? = nil,
        cards: [WorkspaceCard] = [],
        connections: [CardConnection] = [],
        strokes: [DrawingStroke] = [],
        textElements: [TextElement] = [],
        selectedTextID: UUID? = nil
    ) {
        self.viewport = viewport
        self.selectedCardID = selectedCardID
        self.cards = cards
        self.connections = connections
        self.strokes = strokes
        self.textElements = textElements
        self.selectedTextID = selectedTextID
    }

    private enum CodingKeys: String, CodingKey {
        case viewport
        case selectedCardID
        case cards
        case connections
        case strokes
        case textElements
        case selectedTextID
    }

    // Custom decode so workspaces persisted before annotations existed still
    // load: the four annotation fields default to empty/nil instead of throwing
    // keyNotFound. Encodable stays synthesized so .sortedKeys output is stable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        viewport = try container.decode(CanvasViewport.self, forKey: .viewport)
        selectedCardID = try container.decodeIfPresent(UUID.self, forKey: .selectedCardID)
        cards = try container.decode([WorkspaceCard].self, forKey: .cards)
        connections = try container.decodeIfPresent([CardConnection].self, forKey: .connections) ?? []
        strokes = try container.decodeIfPresent([DrawingStroke].self, forKey: .strokes) ?? []
        textElements = try container.decodeIfPresent([TextElement].self, forKey: .textElements) ?? []
        selectedTextID = try container.decodeIfPresent(UUID.self, forKey: .selectedTextID)
    }

    /// Normalizes two opposite corners into a top-left origin and a positive
    /// size, regardless of drag direction.
    public static func normalizedRect(
        _ a: CanvasPoint,
        _ b: CanvasPoint
    ) -> (origin: CanvasPoint, size: CardSize) {
        let origin = CanvasPoint(x: min(a.x, b.x), y: min(a.y, b.y))
        let size = CardSize(width: abs(a.x - b.x), height: abs(a.y - b.y))
        return (origin, size)
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
        // Card and text selection are mutually exclusive.
        selectedTextID = nil
    }

    public mutating func clearSelection() {
        selectedCardID = nil
        selectedTextID = nil
    }

    public mutating func deleteCard(id: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards.remove(at: index)

        // Drop any connection that referenced the removed card so dangling
        // edges never render or persist.
        connections.removeAll { $0.from == id || $0.to == id }

        if selectedCardID == id {
            selectedCardID = nil
        }
    }

    // MARK: - Connections

    /// Adds a visual edge between two distinct, existing cards, rejecting
    /// self-loops, missing endpoints, and duplicate (from, to) pairs.
    public mutating func addConnection(from: UUID, to: UUID) {
        guard from != to else { return }
        guard cards.contains(where: { $0.id == from }) else { return }
        guard cards.contains(where: { $0.id == to }) else { return }
        guard !connections.contains(where: { $0.from == from && $0.to == to }) else { return }
        connections.append(CardConnection(from: from, to: to))
    }

    public mutating func removeConnection(id: UUID) {
        connections.removeAll { $0.id == id }
    }

    // MARK: - Text elements

    public mutating func addTextElement(_ element: TextElement) {
        textElements.append(element)
    }

    public mutating func moveTextElement(id: UUID, screenTranslation: CanvasVector) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        textElements[index].position.x += screenTranslation.dx / viewport.scale
        textElements[index].position.y += screenTranslation.dy / viewport.scale
    }

    public mutating func resizeTextElement(id: UUID, to size: CardSize, position: CanvasPoint? = nil) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        textElements[index].size = size.clamped(
            minWidth: TextElement.minimumWidth,
            minHeight: TextElement.minimumHeight
        )
        if let position {
            textElements[index].position = position
        }
    }

    public mutating func updateTextElementText(id: UUID, to text: String) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        textElements[index].text = text
    }

    public mutating func deleteTextElement(id: UUID) {
        textElements.removeAll { $0.id == id }
        if selectedTextID == id {
            selectedTextID = nil
        }
    }

    public mutating func selectTextElement(id: UUID) {
        guard textElements.contains(where: { $0.id == id }) else { return }
        selectedTextID = id
        // Card and text selection are mutually exclusive.
        selectedCardID = nil
    }

    // MARK: - Drawing strokes

    public mutating func addStroke(_ stroke: DrawingStroke) {
        strokes.append(stroke)
    }

    /// Erases brush strokes within `radius` (canvas space) of `point`.
    ///
    /// - `wholeStroke`: removes any stroke the eraser disc touches (tested
    ///   against the stroke's line segments, so sparse strokes still erase).
    /// - `segment`: drops the vertices that fall inside the disc and splits the
    ///   surviving runs into separate strokes of >=2 points, preserving each
    ///   fragment's color/thickness.
    ///
    /// Returns true if any stroke was removed or split.
    @discardableResult
    public mutating func eraseStrokes(at point: CanvasPoint, radius: Double, mode: EraseMode) -> Bool {
        guard radius > 0, !strokes.isEmpty else { return false }

        switch mode {
        case .wholeStroke:
            let before = strokes.count
            strokes.removeAll { Self.strokeTouched($0, at: point, radius: radius) }
            return strokes.count != before

        case .segment:
            var changed = false
            var result: [DrawingStroke] = []

            for stroke in strokes {
                var runs: [[CanvasPoint]] = []
                var run: [CanvasPoint] = []
                var dropped = false

                for vertex in stroke.points {
                    if Self.distance(vertex, point) <= radius {
                        dropped = true
                        if !run.isEmpty {
                            runs.append(run)
                            run = []
                        }
                    } else {
                        run.append(vertex)
                    }
                }
                if !run.isEmpty { runs.append(run) }

                if !dropped {
                    result.append(stroke)
                    continue
                }

                changed = true
                for fragment in runs where fragment.count >= 2 {
                    result.append(
                        DrawingStroke(
                            points: fragment,
                            color: stroke.color,
                            thickness: stroke.thickness
                        )
                    )
                }
            }

            if changed { strokes = result }
            return changed
        }
    }

    private static func distance(_ a: CanvasPoint, _ b: CanvasPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Whether the eraser disc at `point`/`radius` touches any segment of the
    /// stroke (or its single vertex, for a degenerate one-point stroke).
    private static func strokeTouched(_ stroke: DrawingStroke, at point: CanvasPoint, radius: Double) -> Bool {
        let points = stroke.points
        guard !points.isEmpty else { return false }
        if points.count == 1 {
            return distance(points[0], point) <= radius
        }
        for index in 0..<(points.count - 1) {
            if distanceToSegment(point, points[index], points[index + 1]) <= radius {
                return true
            }
        }
        return false
    }

    /// Shortest distance from `p` to the line segment a–b (canvas space).
    private static func distanceToSegment(_ p: CanvasPoint, _ a: CanvasPoint, _ b: CanvasPoint) -> Double {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = (dx * dx) + (dy * dy)
        guard lengthSquared > 0 else { return distance(p, a) }
        var t = (((p.x - a.x) * dx) + ((p.y - a.y) * dy)) / lengthSquared
        t = max(0, min(1, t))
        let projection = CanvasPoint(x: a.x + (t * dx), y: a.y + (t * dy))
        return distance(p, projection)
    }

    public mutating func resizeCard(id: UUID, to size: CardSize, position: CanvasPoint? = nil) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }

        cards[index].size = size.clampedToMinimums()
        if let position {
            cards[index].position = position
        }
    }

    public mutating func updateCardTitle(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }

        cards[index].title = trimmed
    }

    public mutating func updateCardContent(id: UUID, to content: String) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].content = content
    }
}
