import Foundation

public enum CardKind: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case agent
    case note
    case todo
    case browser
    case fileBrowser
    case git

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
    public var space: SpaceConfig?

    /// Transient marquee multi-selection: the cards a drag-box currently covers.
    /// Deliberately excluded from `CodingKeys`, so it is never encoded and a
    /// fresh decode always starts empty (no JSON schema change, legacy-safe).
    /// Cleared by single-selection and `clearSelection`.
    public var marqueeSelectedCardIDs: Set<UUID> = []

    /// The card whose CONTENT currently has input focus (typing lands in it) —
    /// distinct from `selectedCardID`, which arms a card for keyboard commands
    /// like Delete. Transient like the marquee set: not in `CodingKeys`, so it
    /// resets on decode/workspace-switch. Active and selected are mutually
    /// exclusive — activating clears selection and vice versa.
    public var activeCardID: UUID?

    /// Transient anchor for double-click grid placement: the viewport snapshot
    /// when the current 2x2 page began. It distinguishes "I'm still filling the
    /// page I'm looking at" from "I panned/zoomed to a new area". When the live
    /// viewport differs from this anchor the next placement re-anchors a fresh
    /// page at the visible top-left; while it matches, placement fills the first
    /// free quadrant by occupancy (so a deleted quadrant is refilled in place).
    /// Like `marqueeSelectedCardIDs`, it is excluded from `CodingKeys` and the
    /// inits, so it resets to nil on decode/workspace-switch — a reloaded
    /// workspace simply continues filling its visible page (no schema change).
    public var gridPageAnchor: CanvasViewport?

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
        case space
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
        space = try container.decodeIfPresent(SpaceConfig.self, forKey: .space)
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

    /// Places a card in a 2x2 page that exactly fills the *current* viewport (at
    /// the current zoom) minus margins and gap, so each card owns one visible
    /// quadrant. Quadrants fill in reading order TL, TR, BL, BR.
    ///
    /// Which quadrant the card lands in depends on `gridPageAnchor` — the viewport
    /// the current page was started against:
    ///
    /// - **The viewport moved since the last placement** (pan or zoom, so the live
    ///   viewport differs from the anchor): the user is looking at a new area, so
    ///   a fresh page re-anchors here and the card lands at the visible top-left —
    ///   even if a card left over from the previous area still overlaps that
    ///   quadrant. This is what makes the first card after moving reliably
    ///   top-left instead of jumping to the right column.
    /// - **The viewport is unchanged** (still filling the page in view, or a fresh
    ///   session where the anchor is nil): the card fills the first quadrant whose
    ///   center is free (`gridSlotIsOccupied`), so a quadrant emptied by a delete
    ///   is refilled in place. When all four are taken the page flips to a fresh
    ///   one on the RIGHT (content shifts left one viewport width) and the card
    ///   lands at the new top-left, so pages flow horizontally.
    ///
    /// Sizing every card to the margin-inset quadrant guarantees full visibility,
    /// so no extra pan-to-reveal pass is needed.
    ///
    /// `bottomInset` reserves a band (screen px) at the bottom of the viewport for
    /// the floating dock, so the bottom row never renders behind it (see
    /// `GridPlacement.pageLayout`). The page-flip shift stays a full viewport
    /// width: each new page re-lays from the top margin, so the reserved band
    /// only enlarges the empty gap below a page, never the top-left landing spot.
    public mutating func placeCardInGrid(
        _ card: WorkspaceCard,
        viewportSize: ScreenPoint,
        bottomInset: Double = 0
    ) {
        let layout = GridPlacement.pageLayout(
            viewportSize: viewportSize,
            scale: viewport.scale,
            bottomInset: bottomInset
        )

        let slot: Int
        if startsFreshGridPage {
            // The user moved to a new area: re-anchor a fresh page here and pin
            // the card to the visible top-left, ignoring any stale overlap.
            slot = 0
        } else if let free = firstFreeGridSlot(layout: layout) {
            // Still on the page in view: fill the first free quadrant.
            slot = free
        } else {
            // Page full: flip to a fresh page on the RIGHT, then use its top-left.
            viewport.origin.x -= viewportSize.x
            slot = firstFreeGridSlot(layout: layout) ?? 0
        }

        var placed = card
        placed.size = layout.cardSize
        placed.position = viewport.canvasPoint(forScreenPoint: layout.slotScreenOrigins[slot])

        cards.append(placed)
        gridPageAnchor = viewport
    }

    /// Whether the next `placeCardInGrid` for this viewport would flip to a new
    /// page — i.e. the page in view is full and the user has not moved to a fresh
    /// area. The UI uses this to animate the page-flip pan only when a flip will
    /// actually happen (a fresh page and cards 1...4 of a page move no viewport,
    /// so they appear instantly).
    public func gridPlacementWillFlipPage(
        viewportSize: ScreenPoint,
        bottomInset: Double = 0
    ) -> Bool {
        // A move re-anchors a fresh page at the top-left without panning.
        guard !startsFreshGridPage else { return false }
        let layout = GridPlacement.pageLayout(
            viewportSize: viewportSize,
            scale: viewport.scale,
            bottomInset: bottomInset
        )
        return firstFreeGridSlot(layout: layout) == nil
    }

    /// Whether the next grid placement should re-anchor a fresh page: true once
    /// the user has panned or zoomed since the last placement. A nil anchor (a
    /// fresh session or just-decoded workspace) is treated as "continue the
    /// visible page", so a reloaded workspace fills its remaining quadrants rather
    /// than dropping a new card on top of the existing top-left one.
    private var startsFreshGridPage: Bool {
        guard let anchor = gridPageAnchor else { return false }
        return anchor != viewport
    }

    /// The first reading-order quadrant (TL, TR, BL, BR) whose center is not
    /// covered by an existing card, or nil when every visible quadrant is taken.
    private func firstFreeGridSlot(layout: GridPlacement.PageLayout) -> Int? {
        layout.slotScreenOrigins.indices.first { !gridSlotIsOccupied($0, layout: layout) }
    }

    /// Whether any existing card covers the canvas center of grid `slot` in the
    /// current viewport — the test that decides a quadrant is "taken". Slot
    /// geometry is screen-relative, so this re-derives the slot's canvas center
    /// against the live `viewport` every call; that re-derivation is what keeps
    /// placement correct across pans, zooms, and deletes without a stored counter.
    private func gridSlotIsOccupied(_ slot: Int, layout: GridPlacement.PageLayout) -> Bool {
        let slotOrigin = viewport.canvasPoint(forScreenPoint: layout.slotScreenOrigins[slot])
        let center = CanvasPoint(
            x: slotOrigin.x + (layout.cardSize.width / 2),
            y: slotOrigin.y + (layout.cardSize.height / 2)
        )
        return cards.contains { card in
            center.x >= card.position.x
                && center.x <= card.position.x + card.size.width
                && center.y >= card.position.y
                && center.y <= card.position.y + card.size.height
        }
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
        activeCardID = nil
    }

    /// Makes `id` the active card (content focus) and drops any selection, so a
    /// card being typed into is never simultaneously armed for Delete.
    public mutating func activateCard(id: UUID) {
        guard cards.contains(where: { $0.id == id }) else { return }
        activeCardID = id
        selectedCardID = nil
        selectedTextID = nil
        marqueeSelectedCardIDs = []
    }

    public mutating func clearSelection() {
        selectedCardID = nil
        selectedTextID = nil
        marqueeSelectedCardIDs = []
        activeCardID = nil
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
        activeCardID = nil

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

    /// Screen-space marquee/⌘ selection for Spaces, where tile geometry is owned
    /// by `SpaceGrid` (not card canvas positions). Sets the transient marquee set
    /// from a pre-computed id set and mirrors `selectedCardID` (lone hit ⇒ that id,
    /// else nil), matching `selectCards(fromCorner:toCorner:additive:base:)`.
    public mutating func selectCardsInSpace(ids: Set<UUID>) {
        marqueeSelectedCardIDs = ids
        selectedCardID = ids.count == 1 ? ids.first : nil
        selectedTextID = nil
        activeCardID = nil
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
        space?.freeFrames[id] = nil

        if selectedCardID == id {
            selectedCardID = nil
        }
        if activeCardID == id {
            activeCardID = nil
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
        for id in ids { space?.freeFrames[id] = nil }
        if let selected = selectedCardID, ids.contains(selected) {
            selectedCardID = nil
        }
        if let active = activeCardID, ids.contains(active) {
            activeCardID = nil
        }
        marqueeSelectedCardIDs.subtract(ids)
    }

    // MARK: - Connections

    /// Adds a visual edge between two distinct, existing cards, rejecting
    /// self-loops, missing endpoints, and duplicate pairs. Connections are
    /// non-directional, so an existing (a, b) edge also rejects a (b, a) insert.
    /// The `type` is derived automatically from the endpoint `CardKind`s.
    public mutating func addConnection(from: UUID, to: UUID) {
        guard from != to else { return }
        guard let fromCard = cards.first(where: { $0.id == from }) else { return }
        guard let toCard = cards.first(where: { $0.id == to }) else { return }
        guard !connections.contains(where: {
            ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from)
        }) else { return }
        let derivedType = ConnectionType.derive(fromCard.kind, toCard.kind)
        connections.append(CardConnection(from: from, to: to, type: derivedType))
    }

    // MARK: - Linked-card traversal

    /// All directly-connected neighbors of `id` (undirected). For each
    /// connection where one endpoint matches `id`, the other endpoint is
    /// returned. Unknown or isolated cards return an empty set.
    public func linkedCardIDs(to id: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        for connection in connections {
            if connection.from == id { result.insert(connection.to) }
            else if connection.to == id { result.insert(connection.from) }
        }
        return result
    }

    /// Assembles a single context string from the focus card plus every directly
    /// linked neighbor. The focus card's title + content comes first; neighbors
    /// follow in `cards` array order. Pure — no mutations, no I/O.
    /// Returns an empty string when the assembled context has no non-whitespace
    /// content (e.g. a blank, unlinked card), so callers receive a byte-equivalent
    /// empty value rather than a lone newline.
    public func linkedContext(for id: UUID) -> String {
        guard let focus = cards.first(where: { $0.id == id }) else { return "" }
        var parts: [String] = ["\(focus.title)\n\(focus.content)"]
        let neighborIDs = linkedCardIDs(to: id)
        for card in cards where neighborIDs.contains(card.id) {
            parts.append("\(card.title)\n\(card.content)")
        }
        let assembled = parts.joined(separator: "\n\n")
        return assembled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : assembled
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

    /// The axis-aligned bounding box that tightly wraps every card frame
    /// (position + size) in canvas space. Returns nil when there are no cards.
    /// Used by the minimap to scale and position the content overview.
    public func contentBoundingBox() -> CanvasRect? {
        guard !cards.isEmpty else { return nil }
        let minX = cards.map { $0.position.x }.min()!
        let minY = cards.map { $0.position.y }.min()!
        let maxX = cards.map { $0.position.x + $0.size.width }.max()!
        let maxY = cards.map { $0.position.y + $0.size.height }.max()!
        return CanvasRect(
            origin: CanvasPoint(x: minX, y: minY),
            size: CardSize(width: maxX - minX, height: maxY - minY)
        )
    }

    // MARK: - Spaces

    /// Card ids in tile order: the explicit `cardOrder` (filtered to live cards,
    /// with any new cards appended), else the natural `cards` array order.
    public var orderedCardIDsForSpace: [UUID] {
        guard let order = space?.cardOrder else { return cards.map(\.id) }
        let live = Set(cards.map(\.id))
        let kept = order.filter { live.contains($0) }
        let appended = cards.map(\.id).filter { !kept.contains($0) }
        return kept + appended
    }

    /// Materializes a default `SpaceConfig` on first edit; never overwrites an
    /// existing one.
    public mutating func ensureSpaceConfig() {
        if space == nil { space = SpaceConfig() }
    }

    /// Reorders a Spaces tile by moving the displayed item from `fromIndex` to
    /// `toIndex`, writing the result to `space.cardOrder` so the canonical `cards`
    /// array (and Canvas z-order) is untouched. Operates on the current displayed
    /// order (`orderedCardIDsForSpace`). No-op for out-of-range/equal indices.
    public mutating func reorderSpaceCard(fromIndex: Int, toIndex: Int) {
        var order = orderedCardIDsForSpace
        guard order.indices.contains(fromIndex) else { return }
        let clampedTo = min(max(toIndex, 0), order.count - 1)
        guard fromIndex != clampedTo else { return }
        let id = order.remove(at: fromIndex)
        order.insert(id, at: clampedTo)
        ensureSpaceConfig()
        space?.cardOrder = order
    }

    /// Resets Spaces order to the canonical `cards` array order.
    public mutating func resetSpaceCardOrder() {
        ensureSpaceConfig()
        space?.cardOrder = nil
    }

    public mutating func setSpaceBackground(_ background: SpaceBackground) {
        ensureSpaceConfig()
        space?.background = background
    }

    public mutating func setSpaceFolder(_ path: String?) {
        ensureSpaceConfig()
        space?.folderPath = path
    }

    public mutating func setSpaceTiling(_ tiling: SpaceTiling) {
        ensureSpaceConfig()
        space?.tiling = tiling
    }

    public mutating func setBackgroundDimming(_ value: Double) {
        ensureSpaceConfig()
        space?.backgroundDimming = min(max(value, 0), 1)
    }

    public mutating func setSpaceLayoutMode(_ mode: SpaceLayoutMode) {
        ensureSpaceConfig()
        space?.layoutMode = mode
    }

    /// Seeds free-arrange frames for cards that don't have one yet, never
    /// overwriting an existing frame — a card the user has placed stays put.
    public mutating func seedMissingFreeFrames(_ defaults: [UUID: SpaceFreeFrame]) {
        guard !defaults.isEmpty else { return }
        ensureSpaceConfig()
        space?.freeFrames.merge(defaults) { existing, _ in existing }
    }

    /// Replaces every free-arrange frame — drives "Re-tile" in free mode,
    /// snapping all cards back to a computed arrangement.
    public mutating func setSpaceFreeFrames(_ frames: [UUID: SpaceFreeFrame]) {
        ensureSpaceConfig()
        space?.freeFrames = frames
    }

    /// Moves a free-arrange card to `origin`, keeping its size. No-op for a
    /// card without a seeded frame (unknown or grid-only).
    public mutating func moveSpaceCardFreely(id: UUID, to origin: ScreenPoint) {
        guard space?.freeFrames[id] != nil else { return }
        space?.freeFrames[id]?.origin = origin
    }

    /// Resizes a free-arrange card, keeping its origin (bottom-right handle
    /// semantics) and clamping to the card minimums so content stays usable.
    /// No-op for a card without a seeded frame (unknown or grid-only).
    public mutating func resizeSpaceCardFreely(id: UUID, to size: ScreenPoint) {
        guard space?.freeFrames[id] != nil else { return }
        space?.freeFrames[id]?.size = ScreenPoint(
            x: max(size.x, CardSize.minimumWidth),
            y: max(size.y, CardSize.minimumHeight)
        )
    }
}
