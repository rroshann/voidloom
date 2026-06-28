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

    /// Transient marquee multi-selection: the cards a drag-box currently covers.
    /// Deliberately excluded from `CodingKeys`, so it is never encoded and a
    /// fresh decode always starts empty (no JSON schema change, legacy-safe).
    /// Cleared by single-selection and `clearSelection`.
    public var marqueeSelectedCardIDs: Set<UUID> = []

    /// Transient grid-placement bookkeeping for double-click instant-create: the
    /// next slot index within the current 2x2 page (0...3, wrapping to a fresh
    /// page at 4). Like `marqueeSelectedCardIDs`, it is excluded from
    /// `CodingKeys` and the memberwise/decode inits, so it resets to 0 on every
    /// decode, workspace switch, or fresh create (no JSON schema change,
    /// legacy-safe). Deriving the slot from this page-local counter — never from
    /// `cards.count` — keeps reading order stable across deletes.
    public var gridPlacementSlot: Int = 0

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

    /// Moves every card in `ids` by the same screen translation, converted to
    /// canvas units once. Drives marquee group drag: dragging any selected card
    /// moves the whole highlighted set together. Cards outside the set are
    /// untouched; unknown ids are silently ignored.
    public mutating func moveCards(ids: Set<UUID>, screenTranslation: CanvasVector) {
        guard !ids.isEmpty else { return }
        let dx = screenTranslation.dx / viewport.scale
        let dy = screenTranslation.dy / viewport.scale
        for index in cards.indices where ids.contains(cards[index].id) {
            cards[index].position.x += dx
            cards[index].position.y += dy
        }
    }

    public mutating func addCard(_ card: WorkspaceCard) {
        cards.append(card)
    }

    /// Places a card in the next reading-order slot of a 2x2 page that exactly
    /// fills the current viewport (at the current zoom) minus margins and gap, so
    /// each card owns one visible quadrant. Slots fill TL, TR, BL, BR; the fifth
    /// card starts a fresh page, shifting canvas content up one full viewport
    /// height so the new page's first card lands at the viewport's top-left.
    ///
    /// The slot index is page-local (0...3) and lives in `gridPlacementSlot`, not
    /// `cards.count`, so reading order survives deletes. Sizing every card to the
    /// margin-inset quadrant guarantees full visibility, so no extra pan-to-reveal
    /// pass is needed.
    ///
    /// `bottomInset` reserves a band (screen px) at the bottom of the viewport for
    /// the floating dock, so the bottom row never renders behind it (see
    /// `GridPlacement.pageLayout`). The page-flip shift stays a full viewport
    /// height: each new page re-lays from the top margin, so the reserved band
    /// only enlarges the empty gap below a page, never the top-left landing spot.
    public mutating func placeCardInGrid(
        _ card: WorkspaceCard,
        viewportSize: ScreenPoint,
        bottomInset: Double = 0
    ) {
        if gridPlacementSlot >= GridPlacement.cardsPerPage {
            // Page full: start a new page by shifting content up one viewport
            // height, so the empty region appears at the top-left.
            viewport.origin.y -= viewportSize.y
            gridPlacementSlot = 0
        }

        let layout = GridPlacement.pageLayout(
            viewportSize: viewportSize,
            scale: viewport.scale,
            bottomInset: bottomInset
        )
        let slotScreen = layout.slotScreenOrigins[gridPlacementSlot]

        var placed = card
        placed.size = layout.cardSize
        placed.position = viewport.canvasPoint(forScreenPoint: slotScreen)

        cards.append(placed)
        gridPlacementSlot += 1
    }

    public mutating func replaceCard(_ card: WorkspaceCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[index] = card
    }

    /// A top-left origin for a card of `size` whose center sits on `center`,
    /// nudged along a diagonal cascade ONLY if the centered placement would
    /// overlap an existing card (each existing rect inflated by `spacing`).
    ///
    /// When the centered spot is free the base origin is returned unchanged, so
    /// the exact-center contract holds for the first card placed at a point.
    /// Otherwise candidates `base + (i*step, i*step)` are scanned until one is
    /// free or `maxAttempts` is exhausted (falling back to the base origin).
    public func nonOverlappingOrigin(
        for size: CardSize,
        centeredAt center: CanvasPoint,
        spacing: Double = 28,
        step: Double = 36,
        maxAttempts: Int = 200
    ) -> CanvasPoint {
        let base = CanvasPoint(
            x: center.x - (size.width / 2),
            y: center.y - (size.height / 2)
        )

        func isFree(_ origin: CanvasPoint) -> Bool {
            for card in cards where Self.rectsIntersect(
                origin: origin,
                size: size,
                otherOrigin: card.position,
                otherSize: card.size,
                spacing: spacing
            ) {
                return false
            }
            return true
        }

        if isFree(base) { return base }

        for attempt in 1...maxAttempts {
            let candidate = CanvasPoint(
                x: base.x + (Double(attempt) * step),
                y: base.y + (Double(attempt) * step)
            )
            if isFree(candidate) { return candidate }
        }

        return base
    }

    /// AABB intersection test where the first rect is inflated by `spacing` on
    /// every side, so placements keep a visible gap from existing cards.
    private static func rectsIntersect(
        origin: CanvasPoint,
        size: CardSize,
        otherOrigin: CanvasPoint,
        otherSize: CardSize,
        spacing: Double
    ) -> Bool {
        let aMinX = origin.x - spacing
        let aMinY = origin.y - spacing
        let aMaxX = origin.x + size.width + spacing
        let aMaxY = origin.y + size.height + spacing
        let bMinX = otherOrigin.x
        let bMinY = otherOrigin.y
        let bMaxX = otherOrigin.x + otherSize.width
        let bMaxY = otherOrigin.y + otherSize.height
        return aMinX < bMaxX && aMaxX > bMinX && aMinY < bMaxY && aMaxY > bMinY
    }

    public mutating func selectCard(id: UUID) {
        guard cards.contains(where: { $0.id == id }) else { return }
        selectedCardID = id
        // Card and text selection are mutually exclusive.
        selectedTextID = nil
        // A deliberate single selection supersedes any marquee selection.
        marqueeSelectedCardIDs = []
    }

    public mutating func clearSelection() {
        selectedCardID = nil
        selectedTextID = nil
        marqueeSelectedCardIDs = []
    }

    /// Toggles `id` in or out of the multi-selection (⌘-click). A lone
    /// `selectedCardID` is first promoted into the marquee set, so ⌘-clicking a
    /// second card grows a single selection into a two-card group. After the
    /// toggle, `selectedCardID` mirrors the marquee set the same way
    /// `selectCards` does: the lone id when one card remains, nil when several
    /// do; an empty result clears the whole selection. Text selection is always
    /// cleared. Unknown ids are ignored.
    public mutating func toggleCardInSelection(id: UUID) {
        guard cards.contains(where: { $0.id == id }) else { return }
        selectedTextID = nil

        var working = marqueeSelectedCardIDs
        if working.isEmpty, let single = selectedCardID {
            working.insert(single)
        }

        if working.contains(id) {
            working.remove(id)
        } else {
            working.insert(id)
        }

        if working.isEmpty {
            clearSelection()
        } else {
            marqueeSelectedCardIDs = working
            selectedCardID = working.count == 1 ? working.first : nil
        }
    }

    /// Selects every card whose rect intersects the marquee rectangle defined by
    /// two opposite canvas corners. A single hit also sets `selectedCardID` (so
    /// resize/keyboard affordances keep working); multiple hits leave it nil and
    /// rely on `marqueeSelectedCardIDs`. A miss clears the selection. Text
    /// selection is always cleared.
    public mutating func selectCards(fromCorner a: CanvasPoint, toCorner b: CanvasPoint) {
        selectCards(fromCorner: a, toCorner: b, additive: false, base: [])
    }

    /// Marquee selection with an optional additive mode (⌘-drag). When
    /// `additive` is true the box's hits are unioned with `base` — the set
    /// captured at drag start — so dragging keeps extending the original
    /// selection rather than its own growing result. When false it replaces the
    /// selection with the hits and ignores `base`, matching the plain marquee.
    /// `selectedCardID`/`selectedTextID` follow the same rules as the plain
    /// overload (lone hit ⇒ `selectedCardID`, else nil; text always cleared).
    public mutating func selectCards(
        fromCorner a: CanvasPoint,
        toCorner b: CanvasPoint,
        additive: Bool,
        base: Set<UUID>
    ) {
        let rect = Self.normalizedRect(a, b)
        let hitIDs = cards
            .filter { Self.cardIntersects(card: $0, marqueeOrigin: rect.origin, marqueeSize: rect.size) }
            .map { $0.id }

        let combined = additive ? base.union(hitIDs) : Set(hitIDs)
        marqueeSelectedCardIDs = combined
        selectedCardID = combined.count == 1 ? combined.first : nil
        selectedTextID = nil
    }

    /// AABB intersection between a card's rect and the marquee rect (canvas space).
    private static func cardIntersects(
        card: WorkspaceCard,
        marqueeOrigin: CanvasPoint,
        marqueeSize: CardSize
    ) -> Bool {
        let mMaxX = marqueeOrigin.x + marqueeSize.width
        let mMaxY = marqueeOrigin.y + marqueeSize.height
        let cMaxX = card.position.x + card.size.width
        let cMaxY = card.position.y + card.size.height
        return marqueeOrigin.x < cMaxX
            && mMaxX > card.position.x
            && marqueeOrigin.y < cMaxY
            && mMaxY > card.position.y
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

    /// Removes every card in `ids` and any connection touching one of them, so
    /// no dangling edges survive. Drives marquee group delete. Also clears
    /// `selectedCardID` if it was in the set and drops the ids from the transient
    /// marquee selection. A no-op for an empty set or unknown ids.
    public mutating func deleteCards(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        cards.removeAll { ids.contains($0.id) }
        connections.removeAll { ids.contains($0.from) || ids.contains($0.to) }
        if let selected = selectedCardID, ids.contains(selected) {
            selectedCardID = nil
        }
        marqueeSelectedCardIDs.subtract(ids)
    }

    // MARK: - Connections

    /// Adds a visual edge between two distinct, existing cards, rejecting
    /// self-loops, missing endpoints, and duplicate pairs. Connections are
    /// non-directional, so an existing (a, b) edge also rejects a (b, a) insert.
    public mutating func addConnection(from: UUID, to: UUID) {
        guard from != to else { return }
        guard cards.contains(where: { $0.id == from }) else { return }
        guard cards.contains(where: { $0.id == to }) else { return }
        guard !connections.contains(where: {
            ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from)
        }) else { return }
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

    public mutating func updateTextElementFontSize(id: UUID, to fontSize: Double) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        textElements[index].fontSize = fontSize
    }

    public mutating func updateTextElementColor(id: UUID, toHex hex: String) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        textElements[index].colorHex = hex
    }

    public mutating func updateTextElementFont(id: UUID, to fontName: String?) {
        guard let index = textElements.firstIndex(where: { $0.id == id }) else { return }
        textElements[index].fontName = fontName
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
    /// - `segment`: erases exactly the pixels under the circular footprint —
    ///   each segment is clipped against the disc, keeping only the portions
    ///   outside it and inserting boundary intersection points, so even sparse
    ///   straight strokes are cut where the disc visually covers them. Surviving
    ///   runs become separate strokes of >=2 points, preserving color/thickness.
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
                let pts = stroke.points
                guard !pts.isEmpty else { continue }

                if pts.count == 1 {
                    if Self.distance(pts[0], point) <= radius {
                        changed = true
                    } else {
                        result.append(stroke)
                    }
                    continue
                }

                var fragments: [[CanvasPoint]] = []
                var run: [CanvasPoint] = []
                var strokeChanged = false

                func endRun() {
                    if !run.isEmpty {
                        fragments.append(run)
                        run = []
                    }
                }

                // Seed the first run with the start vertex when it is outside the
                // disc; otherwise it is erased.
                if Self.distance(pts[0], point) > radius {
                    run.append(pts[0])
                } else {
                    strokeChanged = true
                }

                for index in 0..<(pts.count - 1) {
                    let a = pts[index]
                    let b = pts[index + 1]
                    var inside = Self.distance(a, point) <= radius

                    for t in Self.segmentCircleIntersections(a, b, center: point, radius: radius) {
                        let crossing = CanvasPoint(
                            x: a.x + (t * (b.x - a.x)),
                            y: a.y + (t * (b.y - a.y))
                        )
                        if inside {
                            // Exiting the disc: begin a new fragment on the boundary.
                            run.append(crossing)
                        } else {
                            // Entering the disc: close the current fragment on the boundary.
                            run.append(crossing)
                            endRun()
                        }
                        inside.toggle()
                        strokeChanged = true
                    }

                    if Self.distance(b, point) <= radius {
                        strokeChanged = true
                    } else {
                        run.append(b)
                    }
                }
                endRun()

                if strokeChanged {
                    changed = true
                    for fragment in fragments where fragment.count >= 2 {
                        result.append(
                            DrawingStroke(
                                points: fragment,
                                color: stroke.color,
                                thickness: stroke.thickness
                            )
                        )
                    }
                } else {
                    result.append(stroke)
                }
            }

            if changed { strokes = result }
            return changed
        }
    }

    /// Parameters `t` in (0, 1) where the segment a→b crosses the circle of
    /// `radius` about `center`, sorted ascending. Used to clip strokes against
    /// the eraser's circular footprint.
    private static func segmentCircleIntersections(
        _ a: CanvasPoint,
        _ b: CanvasPoint,
        center: CanvasPoint,
        radius: Double
    ) -> [Double] {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = (dx * dx) + (dy * dy)
        guard lengthSquared > 0 else { return [] }

        let fx = a.x - center.x
        let fy = a.y - center.y
        let b2 = 2 * ((fx * dx) + (fy * dy))
        let c = (fx * fx) + (fy * fy) - (radius * radius)
        let discriminant = (b2 * b2) - (4 * lengthSquared * c)
        guard discriminant > 0 else { return [] }

        let root = discriminant.squareRoot()
        let t1 = (-b2 - root) / (2 * lengthSquared)
        let t2 = (-b2 + root) / (2 * lengthSquared)

        var crossings: [Double] = []
        if t1 > 0, t1 < 1 { crossings.append(t1) }
        if t2 > 0, t2 < 1 { crossings.append(t2) }
        return crossings
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
