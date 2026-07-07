import AppKit
import SwiftUI
import VoidloomCore

struct SpacesShellView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @ObservedObject var conversationStore: ConversationStore
    @EnvironmentObject private var assistantContext: AssistantContextProvider

    @AppStorage("spaces.defaultColumns") private var defaultColumns = 0
    @AppStorage("spaces.defaultRows") private var defaultRows = 0

    /// Currently shown grid page (0-based). Clamped to the live page count.
    @State private var currentPage = 0
    /// Live page count, mirrored here so the key handler can page with arrows.
    @State private var pageCount = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dockHeight: CGFloat = 0
    /// Current global frame of the shell, updated continuously via a background
    /// GeometryReader so drop hit-tests always use up-to-date geometry even if
    /// the window is resized during a drag.
    @State private var shellFrame: CGRect = .zero

    /// Id of the tile currently being dragged, or nil when idle.
    @State private var draggingCardID: UUID?
    /// Cumulative drag translation for the dragged tile (keeps it under the cursor).
    @State private var dragTranslation: CGSize = .zero
    /// Page-local slot the dragged tile currently hovers, driving the live preview.
    @State private var dragHoverLocal: Int?
    /// Direction of the last page change, so the slide transition moves correctly.
    @State private var pageForward = true
    /// Card kept invisible while a creation-triggered page slide is in flight, so
    /// the new card doesn't ride the slide as its birth animation. Cleared with a
    /// spring once the slide lands, popping the card in like a same-page creation.
    @State private var pendingRevealCardID: UUID?
    /// Marquee selection-box corners in the shell's local space, or nil when idle.
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    /// Selection captured at ⌘-drag start, so additive marquee keeps extending it.
    @State private var marqueeBase: Set<UUID> = []
    @State private var marqueeAdditive = false
    @State private var isAIConversationVisible = false

    /// Extra top clearance above the tiling margin. Zero makes the top gap equal the
    /// side margin (symmetric card field); the tiling margin alone already clears the
    /// traffic-light buttons of the hidden-titlebar window, so cards sit as high as
    /// looks balanced.
    private static let topPadding: CGFloat = 0
    private static let bottomPadding: CGFloat = 12
    private static let dockGap: CGFloat = 16

    private var topInset: Double { Double(Self.topPadding) }
    private var bottomInset: Double { Double(dockHeight + Self.bottomPadding + Self.dockGap) }
    private var isPagedGrid: Bool { (store.state.space?.layoutMode ?? .pagedGrid) == .pagedGrid }

    private var activeWorkspaceID: UUID {
        store.library.selectedWorkspaceID
    }

    /// Builds a context string from the selected card plus its direct neighbors
    /// (via `WorkspaceState.linkedContext`). Returns nil when no card is selected
    /// or the assembled string is empty — so the nil path is byte-for-byte
    /// equivalent to the previous behavior.
    private var selectedCardContext: String? {
        guard let id = store.state.selectedCardID else { return nil }
        let s = store.state.linkedContext(for: id)
        return s.isEmpty ? nil : s
    }

    private var chatContext: String {
        assistantContext.snapshot(selectedCardContext: selectedCardContext)
    }

    /// The first thing you see in a new workspace — inviting, on-brand, and it
    /// points at Sunday rather than a bare "no cards" label.
    private var emptyWorkspaceState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tint)
            Text("A blank canvas")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Text("Ask Sunday below to begin — or add a card from the dock.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                ForEach(["start 2 claude agents", "note: my ideas", "todo: plan the week"], id: \.self) { hint in
                    Button { MenuAction.runMediatorCommand(hint).post() } label: {
                        Text(hint)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help("Run: \(hint)")
                }
            }
            .padding(.top, 4)
        }
        // Chips are individually actionable buttons — leave them as distinct
        // accessibility elements rather than combining the whole block.
    }

    /// Builds a tiling from the global Settings defaults, used when a space has no
    /// tiling of its own. Columns 0 = Auto (fit all); Rows 0 = no pagination.
    private static func fallbackTiling(columns: Int, rows: Int) -> SpaceTiling {
        if columns == 0 { return SpaceTiling(mode: .auto) }
        return SpaceTiling(mode: .fixedColumns, columns: columns, maxRows: rows == 0 ? nil : rows)
    }

    /// Tiles per page for a paginating tiling, else `Int.max` (single page). Used to
    /// send the view to the page a freshly-added (always last) card landed on.
    private static func pageCapacity(_ tiling: SpaceTiling) -> Int {
        if tiling.mode == .fixedColumns, let r = tiling.maxRows, r > 0 {
            return max(tiling.columns, 1) * r
        }
        return Int.max
    }

    var body: some View {
        GeometryReader { geo in
            let tiling = store.state.space?.tiling
                ?? Self.fallbackTiling(columns: defaultColumns, rows: defaultRows)
            let layoutMode = store.state.space?.layoutMode ?? .pagedGrid
            let orderedIDs = store.state.orderedCardIDsForSpace
            let cardsByID = Dictionary(uniqueKeysWithValues: store.state.cards.map { ($0.id, $0) })
            let freeFrames = layoutMode == .freeArrange
                ? effectiveFreeFrames(orderedIDs: orderedIDs, tiling: tiling, viewport: geo.size)
                : [:]
            let paged = SpaceGrid.pagedLayout(
                cardCount: orderedIDs.count,
                viewportSize: ScreenPoint(x: geo.size.width, y: geo.size.height),
                topInset: topInset,
                bottomInset: bottomInset,
                tiling: tiling,
                page: currentPage
            )

            let pageIDs = Array(orderedIDs[paged.cardRange])
            // Live drag preview: while a tile is dragged, show the order as it will
            // be AFTER drop (dragged card slotted at the hovered position, the rest
            // shifted), so the final arrangement is visible before releasing. The
            // dragged tile itself floats under the cursor; the data commits on drop.
            let draggedFromLocal = draggingCardID.flatMap { pageIDs.firstIndex(of: $0) }
            let displayIDs: [UUID] = {
                guard let dragID = draggingCardID, let from = draggedFromLocal,
                      let hover = dragHoverLocal else { return pageIDs }
                var arr = pageIDs
                arr.remove(at: from)
                arr.insert(dragID, at: min(max(hover, 0), arr.count))
                return arr
            }()

            ZStack {
                SpaceBackgroundView(
                    background: store.state.space?.background ?? .atmosphere,
                    dimming: store.state.space?.backgroundDimming ?? 0.35,
                    backgroundsDirectory: store.backgroundsDirectoryURL()
                )

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.clearSelection()
                        // Also drop content focus so an "invisible" active
                        // terminal can't keep swallowing keystrokes.
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                    .gesture(marqueeGesture(
                        paged: paged, orderedIDs: orderedIDs,
                        freeFrames: layoutMode == .freeArrange ? freeFrames : nil
                    ))

                if orderedIDs.isEmpty {
                    emptyWorkspaceState
                }

                if layoutMode == .freeArrange {
                    SpaceFreeArrangeLayer(
                        store: store,
                        sessionManager: sessionManager,
                        orderedIDs: orderedIDs,
                        cardsByID: cardsByID,
                        effectiveFrames: freeFrames,
                        viewportSize: geo.size
                    )
                } else {
                // Single ForEach + zIndex (Canvas gotcha #1 discipline: never split
                // the dragged/selected tile into its own branch). Idle tiles sit at
                // their preview slot; the dragged tile floats under the cursor. The
                // whole page is keyed by `paged.page` so page changes slide.
                ZStack {
                    ForEach(Array(displayIDs.enumerated()), id: \.element) { slot, id in
                        if let card = cardsByID[id], slot < paged.tileOrigins.count {
                            let isDragged = id == draggingCardID
                            let slotOrigin = paged.tileOrigins[slot]
                            let center: CGPoint = {
                                // The dragged tile tracks the cursor from its ORIGINAL
                                // slot, so it never jumps when the preview reorders.
                                if isDragged, let from = draggedFromLocal, from < paged.tileOrigins.count {
                                    let o = paged.tileOrigins[from]
                                    return CGPoint(x: o.x + paged.tileSize.x / 2 + dragTranslation.width,
                                                   y: o.y + paged.tileSize.y / 2 + dragTranslation.height)
                                }
                                return CGPoint(x: slotOrigin.x + paged.tileSize.x / 2,
                                               y: slotOrigin.y + paged.tileSize.y / 2)
                            }()
                            SpaceTileCard(
                                card: card,
                                store: store,
                                sessionManager: sessionManager,
                                onDragChanged: { translation, location in
                                    if draggingCardID != id {
                                        draggingCardID = id
                                        dragTranslation = .zero
                                    }
                                    dragTranslation = translation
                                    if let hover = slotIndex(
                                        for: location,
                                        tileOrigins: paged.tileOrigins,
                                        tileSize: paged.tileSize,
                                        geoOrigin: shellFrame.origin
                                    ) {
                                        dragHoverLocal = hover
                                    }
                                },
                                onDragEnded: { _ in
                                    if let dragID = draggingCardID,
                                       let from = pageIDs.firstIndex(of: dragID),
                                       let hover = dragHoverLocal {
                                        let target = min(max(hover, 0), pageIDs.count - 1)
                                        if target != from {
                                            store.moveSpaceCard(
                                                fromIndex: paged.cardRange.lowerBound + from,
                                                toIndex: paged.cardRange.lowerBound + target
                                            )
                                        }
                                    }
                                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                                        draggingCardID = nil
                                        dragTranslation = .zero
                                        dragHoverLocal = nil
                                    }
                                }
                            )
                            .frame(width: paged.tileSize.x, height: paged.tileSize.y)
                            .scaleEffect(id == pendingRevealCardID ? 0.86 : 1)
                            .opacity(id == pendingRevealCardID ? 0 : 1)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity))
                            .position(center)
                            .zIndex(isDragged ? 2
                                    : (store.state.selectedCardID == id || store.state.activeCardID == id ? 1 : 0))
                            // The dragged tile must follow the cursor instantly, never
                            // ride the reorder spring.
                            .transaction { if isDragged { $0.animation = nil } }
                        }
                    }
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85),
                        value: displayIDs
                    )
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85),
                        value: paged.tileSize
                    )
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .id(paged.page)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: pageForward ? .trailing : .leading),
                    removal: .move(edge: pageForward ? .leading : .trailing)
                ))
                }

                if let s = marqueeStart, let c = marqueeCurrent {
                    let rect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                                      width: abs(c.x - s.x), height: abs(c.y - s.y))
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(Rectangle().stroke(Color.accentColor.opacity(0.65), lineWidth: 1))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }

                if isAIConversationVisible {
                    AIConversationSidebar(
                        messages: conversationStore.messages(for: activeWorkspaceID),
                        onSubmit: { conversationStore.submit(workspaceID: activeWorkspaceID, text: $0, context: chatContext) },
                        onRetry: { conversationStore.retry(workspaceID: activeWorkspaceID, messageID: $0) },
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.24)) {
                                isAIConversationVisible = false
                            }
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
                }

                VStack(spacing: 12) {
                    Spacer()
                    if layoutMode == .pagedGrid, paged.pageCount > 1 { pager(paged) }
                    SpaceBottomDock(
                        store: store,
                        sessionManager: sessionManager,
                        onReTile: {
                            reTile(orderedIDs: orderedIDs, tiling: tiling, viewport: geo.size)
                        },
                        onAddCard: { kind in
                            store.addCard(kind: kind)
                            // Free-arrange: the card is seeded a frame by the
                            // onChange below; no page to jump to.
                            guard layoutMode == .pagedGrid else { return }
                            // A new card is appended (always the last card). Same page:
                            // the tile transition pops it in. Another page: keep it
                            // hidden while sliding there, then pop it in on arrival so
                            // creation reads the same on every page.
                            let orderedAfterAdd = store.state.orderedCardIDsForSpace
                            let cap = Self.pageCapacity(tiling)
                            let target = cap > 0 ? (orderedAfterAdd.count - 1) / cap : 0
                            guard target != currentPage else { return }
                            pageForward = target >= currentPage
                            guard !reduceMotion else {
                                currentPage = target
                                return
                            }
                            pendingRevealCardID = orderedAfterAdd.last
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9),
                                          completionCriteria: .logicallyComplete) {
                                currentPage = target
                            } completion: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    pendingRevealCardID = nil
                                }
                            }
                        },
                        errorMessage: store.lastPersistenceError,
                        isAIActive: isAIConversationVisible,
                        onToggleAI: { isAIConversationVisible.toggle() }
                    )
                    .background(GeometryReader { p in
                        Color.clear.preference(key: SpacesDockHeightKey.self, value: p.size.height)
                    })
                    .padding(.bottom, Self.bottomPadding)
                }
            }
            .onChange(of: paged.pageCount, initial: true) { _, newCount in
                pageCount = newCount
                if currentPage > newCount - 1 { currentPage = max(0, newCount - 1) }
            }
            .background(ContentClickMonitor { point, commandHeld in
                selectCard(atContentClick: point, commandHeld: commandHeld,
                           paged: paged, orderedIDs: orderedIDs, freeFrames: freeFrames)
            })
            .onChange(of: store.library.selectedWorkspaceID) { _, _ in currentPage = 0 }
            .onChange(of: store.state.space?.tiling) { _, _ in currentPage = 0 }
            .onChange(of: layoutMode, initial: true) { _, _ in
                seedFreeFramesIfNeeded(orderedIDs: orderedIDs, tiling: tiling, viewport: geo.size)
            }
            .onChange(of: orderedIDs) { _, newIDs in
                seedFreeFramesIfNeeded(orderedIDs: newIDs, tiling: tiling, viewport: geo.size)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ShellFrameKey.self, value: proxy.frame(in: .global))
            }
        )
        .background(CanvasKeyMonitor(onKeyDown: handleSpacesKey))
        .preferredColorScheme(.dark)
        .onPreferenceChange(ShellFrameKey.self) { shellFrame = $0 }
        .onPreferenceChange(SpacesDockHeightKey.self) { dockHeight = $0 }
        .animation(.easeInOut(duration: 0.24), value: isAIConversationVisible)
    }

    /// Window-scoped key handling for Spaces. Delete/Backspace removes the marquee
    /// group or the single selected tile (terminating any agent sessions first);
    /// Escape clears selection. Stays inert while a text control is first responder
    /// so typing in a title/note/todo/terminal keeps its keys.
    private func handleSpacesKey(_ event: NSEvent) -> Bool {
        let typing = isTypingResponder(event.window?.firstResponder)
        switch event.keyCode {
        case 51, 117:   // delete / forward-delete
            guard !typing else { return false }
            if !store.state.marqueeSelectedCardIDs.isEmpty {
                let ids = store.state.marqueeSelectedCardIDs
                terminateAgentSessions(for: ids)
                store.deleteCards(ids: ids)
                return true
            }
            if let id = store.state.selectedCardID {
                terminateAgentSessions(for: [id])
                store.deleteCard(id: id)
                return true
            }
            return false
        case 53:        // escape
            guard !typing else { return false }
            store.clearSelection()
            return true
        case 123:   // left arrow
            guard !typing, pageCount > 1, isPagedGrid else { return false }
            goToPage(currentPage - 1)
            return true
        case 124:   // right arrow
            guard !typing, pageCount > 1, isPagedGrid else { return false }
            goToPage(currentPage + 1)
            return true
        default:
            return false
        }
    }

    /// Terminates the agent session for every `.agent` card in `ids`, mirroring the
    /// per-card close button so Delete never leaks a running terminal.
    private func terminateAgentSessions(for ids: Set<UUID>) {
        for id in ids where store.state.cards.first(where: { $0.id == id })?.kind == .agent {
            sessionManager.terminateSession(cardID: id)
        }
    }

    private func reTile(orderedIDs: [UUID], tiling: SpaceTiling, viewport: CGSize) {
        if (store.state.space?.layoutMode ?? .pagedGrid) == .freeArrange {
            // Snap every free-arranged card back to the tidy fit-all grid.
            store.setSpaceFreeFrames(
                defaultFreeFrames(orderedIDs: orderedIDs, tiling: tiling, viewport: viewport)
            )
        } else {
            // Resets Spaces order to the canonical cards array order and persists.
            store.resetSpaceCardOrder()
        }
        draggingCardID = nil
        dragTranslation = .zero
        dragHoverLocal = nil
        currentPage = 0
    }

    /// Grid-derived frames for every card: the single-screen fit-all layout at
    /// the space's gap/margin/aspect. Pure — used for seeding and Re-tile.
    private func defaultFreeFrames(
        orderedIDs: [UUID], tiling: SpaceTiling, viewport: CGSize
    ) -> [UUID: SpaceFreeFrame] {
        let layout = SpaceGrid.layout(
            cardCount: orderedIDs.count,
            viewportSize: ScreenPoint(x: viewport.width, y: viewport.height),
            topInset: topInset,
            bottomInset: bottomInset,
            tiling: SpaceTiling(mode: .auto, gap: tiling.gap, margin: tiling.margin,
                                targetAspect: tiling.targetAspect)
        )
        var frames: [UUID: SpaceFreeFrame] = [:]
        for (i, id) in orderedIDs.enumerated() where i < layout.tileOrigins.count {
            frames[id] = SpaceFreeFrame(origin: layout.tileOrigins[i], size: layout.tileSize)
        }
        return frames
    }

    /// Persisted free frames overlaid on grid-derived defaults, so a card that
    /// hasn't been seeded yet still renders somewhere sensible this frame.
    private func effectiveFreeFrames(
        orderedIDs: [UUID], tiling: SpaceTiling, viewport: CGSize
    ) -> [UUID: SpaceFreeFrame] {
        var frames = defaultFreeFrames(orderedIDs: orderedIDs, tiling: tiling, viewport: viewport)
        frames.merge(store.state.space?.freeFrames ?? [:]) { _, persisted in persisted }
        return frames
    }

    /// Persists default frames for any free-arrange card that lacks one. Runs on
    /// mode entry and card additions; never touches an existing frame.
    private func seedFreeFramesIfNeeded(orderedIDs: [UUID], tiling: SpaceTiling, viewport: CGSize) {
        guard (store.state.space?.layoutMode ?? .pagedGrid) == .freeArrange else { return }
        let persisted = store.state.space?.freeFrames ?? [:]
        let missing = defaultFreeFrames(orderedIDs: orderedIDs, tiling: tiling, viewport: viewport)
            .filter { persisted[$0.key] == nil }
        guard !missing.isEmpty else { return }
        store.seedSpaceFreeFrames(missing)
    }

    /// Animated, direction-aware page change (drives the horizontal slide between
    /// pages). Clamps to the live page count; no-op if already there.
    private func goToPage(_ target: Int) {
        let clamped = min(max(target, 0), max(0, pageCount - 1))
        guard clamped != currentPage else { return }
        pageForward = clamped > currentPage
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) {
            currentPage = clamped
        }
    }

    /// Routes a raw mouse-down anywhere in the shell. This is the ONLY
    /// click-handling path in Spaces — it fires for every left click (via
    /// `ContentClickMonitor`), including clicks on AppKit-backed card content
    /// (terminal, web view) that SwiftUI tap gestures never see. A click on a
    /// card's HEADER selects it (accent highlight, armed for Delete); a click
    /// anywhere in its CONTENT makes it active (focus ring, typing lands in
    /// it). ⌘-click toggles the multi-selection from either region.
    private func selectCard(
        atContentClick point: CGPoint, commandHeld: Bool,
        paged: SpaceGrid.PagedLayout, orderedIDs: [UUID],
        freeFrames: [UUID: SpaceFreeFrame]
    ) {
        let hitID: UUID?
        let tileTopY: CGFloat
        if isPagedGrid {
            if let local = slotIndex(for: point, tileOrigins: paged.tileOrigins,
                                     tileSize: paged.tileSize, geoOrigin: .zero) {
                let global = paged.cardRange.lowerBound + local
                hitID = orderedIDs.indices.contains(global) ? orderedIDs[global] : nil
                tileTopY = paged.tileOrigins[local].y
            } else {
                hitID = nil
                tileTopY = 0
            }
        } else {
            let hits = Set(SpaceGrid.cardIDs(
                fromCorner: ScreenPoint(x: point.x - 0.5, y: point.y - 0.5),
                toCorner: ScreenPoint(x: point.x + 0.5, y: point.y + 0.5),
                frames: freeFrames))
            // Topmost wins: the selected/active card renders above, then space order.
            let raised = store.state.selectedCardID ?? store.state.activeCardID
            if let raised, hits.contains(raised) {
                hitID = raised
            } else {
                hitID = orderedIDs.last(where: { hits.contains($0) })
            }
            tileTopY = hitID.flatMap { freeFrames[$0]?.origin.y }.map { CGFloat($0) } ?? 0
        }
        guard let hitID else { return }

        if commandHeld {
            store.toggleCardInSelection(id: hitID)
            return
        }

        let inHeader = point.y - tileTopY < WorkspaceCardView.approximateHeaderHeight
        if inHeader {
            if store.state.selectedCardID != hitID
                || store.state.activeCardID != nil
                || !store.state.marqueeSelectedCardIDs.isEmpty {
                store.selectCard(id: hitID)
            }
            // Drop any text/terminal focus so Delete acts on the selection
            // instead of typing into whatever was focused.
            NSApp.keyWindow?.makeFirstResponder(nil)
        } else if store.state.activeCardID != hitID
                    || store.state.selectedCardID != nil
                    || !store.state.marqueeSelectedCardIDs.isEmpty {
            store.activateCard(id: hitID)
        }
    }

    /// Returns the page-local tile index whose frame contains `globalPoint`
    /// (converted to the GeometryReader's local space via `geoOrigin`), or nil.
    private func slotIndex(
        for globalPoint: CGPoint,
        tileOrigins: [ScreenPoint],
        tileSize: ScreenPoint,
        geoOrigin: CGPoint
    ) -> Int? {
        let lx = globalPoint.x - geoOrigin.x
        let ly = globalPoint.y - geoOrigin.y
        for (i, origin) in tileOrigins.enumerated() {
            if lx >= origin.x && lx < origin.x + tileSize.x
                && ly >= origin.y && ly < origin.y + tileSize.y {
                return i
            }
        }
        return nil
    }

    /// Left-drag on empty background draws a selection box; ⌘-drag extends the
    /// existing selection. Coordinates are `.local` to the shell, matching the
    /// `SpaceGrid` tile origins used by `tileIndices`.
    private func marqueeGesture(
        paged: SpaceGrid.PagedLayout,
        orderedIDs: [UUID],
        freeFrames: [UUID: SpaceFreeFrame]?
    ) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if marqueeStart == nil {
                    marqueeStart = value.startLocation
                    marqueeAdditive = NSEvent.modifierFlags.contains(.command)
                    if marqueeAdditive {
                        var base = store.state.marqueeSelectedCardIDs
                        if let single = store.state.selectedCardID { base.insert(single) }
                        marqueeBase = base
                    } else {
                        marqueeBase = []
                    }
                }
                marqueeCurrent = value.location
                let hits = marqueeHits(start: value.startLocation, current: value.location,
                                       paged: paged, orderedIDs: orderedIDs, freeFrames: freeFrames)
                store.selectCardsInSpace(ids: marqueeAdditive ? marqueeBase.union(hits) : hits)
            }
            .onEnded { _ in
                marqueeStart = nil
                marqueeCurrent = nil
                marqueeBase = []
                marqueeAdditive = false
            }
    }

    /// Maps a screen-space selection box to the set of card ids it covers — on
    /// the current page in grid mode, or across all free frames in free-arrange.
    private func marqueeHits(
        start: CGPoint, current: CGPoint,
        paged: SpaceGrid.PagedLayout, orderedIDs: [UUID],
        freeFrames: [UUID: SpaceFreeFrame]?
    ) -> Set<UUID> {
        if let freeFrames {
            return Set(SpaceGrid.cardIDs(
                fromCorner: ScreenPoint(x: start.x, y: start.y),
                toCorner: ScreenPoint(x: current.x, y: current.y),
                frames: freeFrames))
        }
        let locals = SpaceGrid.tileIndices(
            fromCorner: ScreenPoint(x: start.x, y: start.y),
            toCorner: ScreenPoint(x: current.x, y: current.y),
            tileOrigins: paged.tileOrigins, tileSize: paged.tileSize)
        var ids = Set<UUID>()
        for local in locals {
            let global = paged.cardRange.lowerBound + local
            if orderedIDs.indices.contains(global) { ids.insert(orderedIDs[global]) }
        }
        return ids
    }

    @ViewBuilder private func pager(_ paged: SpaceGrid.PagedLayout) -> some View {
        HStack(spacing: 10) {
            Button { goToPage(paged.page - 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
            }
            .disabled(paged.page == 0)
            Text("\(paged.page + 1) / \(paged.pageCount)")
                .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            Button { goToPage(paged.page + 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
            }
            .disabled(paged.page >= paged.pageCount - 1)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}

struct ShellFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct SpacesDockHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
