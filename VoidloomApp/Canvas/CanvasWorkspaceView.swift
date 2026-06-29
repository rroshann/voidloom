import AppKit
import SwiftUI
import VoidloomCore

struct CanvasWorkspaceView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @ObservedObject var interaction: CanvasInteractionModel
    var isCardFocused: Bool
    var onToggleCardFocus: () -> Void

    @State private var lastPanTranslation: CGSize = .zero
    /// In-progress pinch magnification (cumulative from 1) applied as a pure GPU
    /// transform during the gesture; committed to `store.viewport` on end. Keeps
    /// pinch-zoom from publishing `state` (and re-rendering every layer) per tick.
    @State private var liveZoom: CGFloat = 1
    /// Anchor for the in-progress pinch `scaleEffect`, expressed as a UnitPoint of
    /// the viewport frame. Snapshotted once on the first magnification tick from
    /// the live pointer so the preview scales into the cursor, not screen center.
    @State private var liveZoomAnchor: UnitPoint = .center
    /// The pinch anchor in view coordinates, captured once on the first tick and
    /// reused for the commit so the previewed and committed transforms match.
    @State private var zoomAnchorPoint: CGPoint?
    /// Live pointer (view coords) tracked while idle, so a pinch can anchor at the
    /// cursor even before any zoom gesture fires.
    @State private var hoverLocation: CGPoint?
    @State private var contextMenuLocation: CGPoint?
    @State private var rubberStart: CGPoint?
    @State private var rubberCurrent: CGPoint?
    /// Live cursor (screen/view coords) while the connect tool is armed, used to
    /// draw the follow-arrow from the source card to the pointer.
    @State private var connectCursor: CGPoint?
    /// Points (canvas space) accumulated for the brush stroke currently being
    /// drawn. Empty when no drag is in progress.
    @State private var liveStrokePoints: [CanvasPoint] = []

    /// Live pointer (screen/view coords) while the eraser is armed, driving the
    /// round footprint indicator. Tracks at SwiftUI refresh rate, decoupled from
    /// the erase compute. Nil when the eraser is disarmed or the pointer left.
    @State private var eraserCursor: CGPoint?
    /// The previous erase sample (screen coords) within a single drag, so fast
    /// drags erase along the swept path instead of leaving gaps. Reset on mouse up.
    @State private var lastErasePoint: CGPoint?

    /// What an in-progress idle left-drag resolved to (decided once on the first
    /// move, then held for the rest of the drag).
    @State private var idleDragMode: IdleDragMode = .none
    /// Selection-box corners in screen (view) coordinates while marquee dragging.
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    /// For an additive (⌘) marquee: the selection captured on the first move, so
    /// the box keeps unioning against the original set rather than its own
    /// growing result. Empty for a plain (replacing) marquee. Decided once.
    @State private var marqueeBase: Set<UUID> = []
    @State private var marqueeAdditive = false

    /// Which modifier (if any) a mouse/keyboard user must hold for a left-drag to
    /// draw a selection box instead of panning. `.none` makes plain drag draw the
    /// box. Two-finger trackpad pan is unaffected and always pans.
    @AppStorage("canvas.selectionBoxModifier") private var selectionBoxModifier: SelectionBoxModifier = .none

    /// Minimum spacing (canvas units) between accumulated brush points, so a
    /// stroke stays compact regardless of how fast the cursor moves.
    private let minStrokePointSpacing: Double = 1.5

    /// Drags shorter than this (in screen points) are treated as a click,
    /// creating a default-sized card instead of a rubber-band-sized one.
    private let minRubberBandDrag: CGFloat = 6

    private let canvasSize = CGSize(width: 5_000, height: 3_400)
    private let contextMenuSize = CGSize(width: 196, height: 200)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard interaction.mode == .idle else { return }
                        // End any inline text edit first so its editor tears down
                        // and commits the draft, then drop all selection so a
                        // selected text element de-highlights immediately.
                        interaction.editingTextID = nil
                        resignKeyboardFocus()
                        store.clearSelection()
                        interaction.selectedConnectionID = nil
                    }
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        if case let .active(point) = phase { hoverLocation = point }
                    }
                    .gesture(idleDragGesture, isEnabled: interaction.mode == .idle)
                    .simultaneousGesture(zoomGesture(in: geometry))

                // Pointer overlays sit BELOW the cards so they never occlude
                // card hover (header chrome, resize cursor). Pan runs off a
                // global scroll monitor (so it needs no hit testing); right-click
                // is claimed only over empty canvas — cards above intercept their
                // own right-clicks.
                CanvasTrackpadPanView { translation, cursorInView in
                    guard interaction.mode == .idle else { return false }
                    // When the pointer is over the selected card, yield the scroll
                    // to that card's own scroll view (terminal/note/todo/browser)
                    // instead of panning the canvas.
                    if let cursorInView, cursorOverSelectedCard(cursorInView) { return false }
                    store.pan(by: translation)
                    return true
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .allowsHitTesting(false)

                CanvasRightClickCatcher { point in
                    contextMenuLocation = point
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                ZStack(alignment: .topLeading) {
                    CanvasGrid()

                    // Persisted strokes and the in-progress live stroke render in
                    // two adjacent layers. The persisted layer is `.equatable()`,
                    // so accumulating live points (which change every move) never
                    // forces a redraw of every committed stroke — only the cheap
                    // live layer re-renders during a brush drag.
                    CanvasDrawingLayer(
                        strokes: store.state.strokes,
                        liveStroke: nil,
                        canvasSize: canvasSize
                    )
                    .equatable()

                    CanvasDrawingLayer(
                        strokes: [],
                        liveStroke: liveStroke,
                        canvasSize: canvasSize
                    )
                    .equatable()

                    ConnectionsLayer(
                        connections: store.state.connections,
                        cards: store.state.cards,
                        canvasSize: canvasSize,
                        selectedConnectionID: interaction.selectedConnectionID
                    )
                    .equatable()

                    // Transparent edge hit-testing sits ABOVE the rendered
                    // edges but BELOW the cards, so cards keep hit priority.
                    ConnectionHitLayer(
                        interaction: interaction,
                        connections: store.state.connections,
                        cards: store.state.cards,
                        canvasSize: canvasSize,
                        onSelect: { id in
                            store.clearSelection()
                            interaction.selectedConnectionID = id
                        }
                    )

                    ForEach(store.state.cards) { card in
                        DraggableWorkspaceCard(
                            card: card,
                            store: store,
                            sessionManager: sessionManager,
                            interaction: interaction,
                            viewportScale: store.state.viewport.scale,
                            isCardFocused: isCardFocused,
                            onToggleCardFocus: onToggleCardFocus,
                            editingCardTitleID: $interaction.editingCardTitleID
                        )
                        .zIndex(card.id == store.state.selectedCardID ? 1 : 0)
                    }

                    ForEach(store.state.textElements) { element in
                        TextElementView(
                            element: element,
                            store: store,
                            viewportScale: store.state.viewport.scale,
                            editingTextID: $interaction.editingTextID
                        )
                        .zIndex(element.id == store.state.selectedTextID ? 2 : 1)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
                .scaleEffect(CGFloat(store.state.viewport.scale), anchor: .topLeading)
                .offset(
                    x: CGFloat(store.state.viewport.origin.x),
                    y: CGFloat(store.state.viewport.origin.y)
                )
                // Constrain to the viewport so `liveZoomAnchor` (a UnitPoint of this
                // frame) maps to the same view point used as the pinch commit
                // anchor, then apply the in-progress magnification as a pure GPU
                // transform (no state publish/redraw). Anchoring at the cursor here
                // makes the preview match the committed cursor-anchored zoom.
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .scaleEffect(liveZoom, anchor: liveZoomAnchor)

                // Snap guide lines rendered in screen space — viewport.screenPoint
                // already converts canvas → screen, so this layer must sit outside
                // the pan/zoom transform group. Inert to hit testing.
                if !interaction.activeAlignmentGuides.isEmpty {
                    AlignmentGuidesLayer(
                        guides: interaction.activeAlignmentGuides,
                        viewport: store.state.viewport,
                        viewSize: geometry.size
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                }

                // Armed-tool input capture sits ABOVE the cards so place/connect
                // drags are intercepted before a card drag can begin. It is
                // inert (hitTest returns nil) whenever no tool is armed.
                CanvasInteractionOverlay(
                    mode: interaction.mode,
                    onMouseDown: handleOverlayDown,
                    onMouseDragged: handleOverlayDragged,
                    onMouseMoved: handleOverlayMoved,
                    onMouseUp: handleOverlayUp
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                // Hold the armed tool's cursor over the canvas. `.onContinuousHover`
                // re-asserts on every move so it beats SwiftUI's per-move arrow
                // reset; it adds no click-consuming view, so the overlay below
                // still receives the left-mouse-down it needs for tool input.
                .canvasToolCursor(for: interaction.mode)

                // Round eraser footprint, sized to the live thickness (screen px)
                // and tracking the pointer at refresh rate. Render-only, so it
                // never intercepts the erase drag below it.
                // The eraser cursor ring tracks the pointer over the canvas. While
                // the thickness slider is being adjusted, the centered preview in
                // RootView takes over instead (this one sits behind the panel), so
                // the two are mutually exclusive and never overlap.
                if interaction.mode == .erasing,
                   !interaction.isAdjustingEraserSize,
                   let point = eraserCursor {
                    let diameter = CGFloat(interaction.eraserThickness) * CGFloat(store.state.viewport.scale)
                    EraserFootprintRing(diameter: diameter)
                        .position(point)
                }

                CanvasInteractionLayer(
                    interaction: interaction,
                    rubberStart: rubberStart,
                    rubberCurrent: rubberCurrent,
                    connectSourceRect: connectSourceScreenRect,
                    connectHoverRect: connectHoverScreenRect,
                    connectAnchor: connectAnchorScreen,
                    connectCursor: connectCursor,
                    connectAccent: connectAccent,
                    marqueeStart: marqueeStart,
                    marqueeCurrent: marqueeCurrent
                )
                .frame(width: geometry.size.width, height: geometry.size.height)

                if let connectionID = interaction.selectedConnectionID,
                   let midpoint = connectionMidpointScreen(connectionID) {
                    ConnectionDeleteButton {
                        store.deleteConnection(id: connectionID)
                        interaction.selectedConnectionID = nil
                    }
                    .position(x: midpoint.x, y: midpoint.y)
                }

                if let location = contextMenuLocation {
                    Color.clear
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .onTapGesture { contextMenuLocation = nil }

                    CanvasContextMenu { kind in
                        addCard(kind: kind, atViewPoint: location)
                        contextMenuLocation = nil
                    }
                    .offset(
                        x: clampedMenuX(for: location.x, in: geometry.size.width),
                        y: clampedMenuY(for: location.y, in: geometry.size.height)
                    )
                }
            }
            .clipped()
            .onChange(of: interaction.mode) { _, newMode in
                if case .connecting = newMode {} else { connectCursor = nil }
                if newMode != .erasing {
                    eraserCursor = nil
                    lastErasePoint = nil
                }
            }
            .onChange(of: store.state.selectedCardID) { _, newValue in
                if newValue != nil { interaction.selectedConnectionID = nil }
            }
            .onChange(of: store.state.selectedTextID) { _, newValue in
                if newValue != nil { interaction.selectedConnectionID = nil }
            }
        }
    }

    private let connectAccent = Color(red: 0.34, green: 0.93, blue: 0.82)

    private func addCard(kind: CardKind, atViewPoint point: CGPoint) {
        let canvasPoint = store.state.viewport.canvasPoint(
            forScreenPoint: ScreenPoint(x: point.x, y: point.y)
        )
        store.addCard(kind: kind, centeredAt: canvasPoint)
    }

    // MARK: - Armed-tool overlay callbacks

    private func handleOverlayDown(_ point: CGPoint) {
        switch interaction.mode {
        case .placingCard, .placingText:
            rubberStart = point
            rubberCurrent = point
        case .connecting:
            handleConnectTap(at: point)
        case .drawing:
            liveStrokePoints = [canvasPoint(from: point)]
        case .erasing:
            eraserCursor = point
            erase(at: point)
        default:
            break
        }
    }

    private func handleOverlayDragged(_ point: CGPoint) {
        switch interaction.mode {
        case .placingCard, .placingText:
            rubberCurrent = point
        case .drawing:
            appendLivePoint(canvasPoint(from: point))
        case .erasing:
            eraserCursor = point
            erase(at: point)
        default:
            break
        }
    }

    private func handleOverlayMoved(_ point: CGPoint) {
        switch interaction.mode {
        case let .connecting(source):
            connectCursor = point
            // Highlight the card under the cursor as the prospective pick. Once a
            // source is chosen, suppress re-marking it so it stays the source ring
            // rather than flickering as a target.
            let canvas = store.state.viewport.canvasPoint(
                forScreenPoint: ScreenPoint(x: point.x, y: point.y)
            )
            let hit = cardID(atCanvas: CanvasPoint(x: canvas.x, y: canvas.y))
            let target = (hit == source) ? nil : hit
            if interaction.hoveredCardID != target { interaction.hoveredCardID = target }
        case .erasing:
            eraserCursor = point
        default:
            break
        }
    }

    private func handleOverlayUp(_ point: CGPoint) {
        // Freehand tools stay armed across strokes; they commit on release and
        // never run through the rubber-band card/text creation path below.
        switch interaction.mode {
        case .drawing:
            appendLivePoint(canvasPoint(from: point))
            commitLiveStroke()
            return
        case .erasing:
            erase(at: point)
            store.flushErase()
            lastErasePoint = nil
            return
        default:
            break
        }

        defer {
            rubberStart = nil
            rubberCurrent = nil
        }

        guard interaction.mode.isRubberBand, let start = rubberStart else { return }

        let startCanvas = store.state.viewport.canvasPoint(
            forScreenPoint: ScreenPoint(x: start.x, y: start.y)
        )
        let endCanvas = store.state.viewport.canvasPoint(
            forScreenPoint: ScreenPoint(x: point.x, y: point.y)
        )

        let dragDistance = hypot(point.x - start.x, point.y - start.y)

        switch interaction.mode {
        case let .placingCard(kind):
            if dragDistance < minRubberBandDrag {
                store.addCard(kind: kind, centeredAt: startCanvas)
            } else {
                store.addCard(kind: kind, fromCorner: startCanvas, toCorner: endCanvas)
            }
        case .placingText:
            let id: UUID
            let seedColorHex = interaction.textColor.hexStringRGBA
            if dragDistance < minRubberBandDrag {
                id = store.addTextElement(
                    centeredAt: startCanvas,
                    fontSize: interaction.textFontSize,
                    colorHex: seedColorHex,
                    fontName: interaction.textFontName
                )
            } else {
                id = store.addTextElement(
                    fromCorner: startCanvas,
                    toCorner: endCanvas,
                    fontSize: interaction.textFontSize,
                    colorHex: seedColorHex,
                    fontName: interaction.textFontName
                )
            }
            // Auto-focus inline editing on the freshly placed element.
            interaction.editingTextID = id
        default:
            break
        }

        interaction.disarm()
    }

    /// Connect tool click: pick a source card, then a distinct target card to
    /// persist an edge. After a successful link the tool DISARMS (returns to
    /// idle) so the user isn't left armed. Visuals only — no agent comms.
    private func handleConnectTap(at point: CGPoint) {
        let canvas = store.state.viewport.canvasPoint(
            forScreenPoint: ScreenPoint(x: point.x, y: point.y)
        )
        guard let hitID = cardID(atCanvas: CanvasPoint(x: canvas.x, y: canvas.y)) else { return }

        switch interaction.mode {
        case .connecting(.none):
            interaction.setConnectSource(hitID)
            connectCursor = point
        case let .connecting(.some(source)):
            // Disarm only after a SUCCESSFUL link, so a misclick on the source
            // card (or empty space) keeps the armed source instead of dropping
            // the user back to picking a source again. disarm() returns to idle
            // and (via the mode didSet) clears the hover/source highlights.
            if source != hitID {
                store.addConnection(from: source, to: hitID)
                interaction.disarm()
            }
        default:
            break
        }
    }

    /// The topmost card whose canvas rect contains `point`, matching render
    /// z-order: the selected card draws above the rest, then later cards in the
    /// array draw over earlier ones.
    private func cardID(atCanvas point: CanvasPoint) -> UUID? {
        func contains(_ card: WorkspaceCard) -> Bool {
            point.x >= card.position.x
                && point.x <= card.position.x + card.size.width
                && point.y >= card.position.y
                && point.y <= card.position.y + card.size.height
        }

        if let selectedID = store.state.selectedCardID,
           let card = store.state.cards.first(where: { $0.id == selectedID }),
           contains(card) {
            return selectedID
        }

        for card in store.state.cards.reversed() where contains(card) {
            return card.id
        }
        return nil
    }

    /// The connect source card's frame in screen coords (for the highlight ring).
    private var connectSourceScreenRect: CGRect? {
        guard case let .connecting(source?) = interaction.mode,
              let card = store.state.cards.first(where: { $0.id == source }) else { return nil }

        let topLeft = store.state.viewport.screenPoint(forCanvasPoint: card.position)
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: card.size.width * store.state.viewport.scale,
            height: card.size.height * store.state.viewport.scale
        )
    }

    /// The hovered (prospective pick) card's frame in screen coords, while the
    /// connect tool is armed. Drives the target highlight ring.
    private var connectHoverScreenRect: CGRect? {
        guard case .connecting = interaction.mode,
              let id = interaction.hoveredCardID,
              let card = store.state.cards.first(where: { $0.id == id }) else { return nil }

        let topLeft = store.state.viewport.screenPoint(forCanvasPoint: card.position)
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: card.size.width * store.state.viewport.scale,
            height: card.size.height * store.state.viewport.scale
        )
    }

    /// The follow-arrow's start point: where the source card's border meets the
    /// ray towards the cursor, in screen coords.
    private var connectAnchorScreen: CGPoint? {
        guard case let .connecting(source?) = interaction.mode,
              let card = store.state.cards.first(where: { $0.id == source }),
              let cursor = connectCursor else { return nil }

        let cursorCanvas = store.state.viewport.canvasPoint(
            forScreenPoint: ScreenPoint(x: cursor.x, y: cursor.y)
        )
        let border = CanvasRect(origin: card.position, size: card.size)
            .borderIntersection(towards: CanvasPoint(x: cursorCanvas.x, y: cursorCanvas.y))
        let screen = store.state.viewport.screenPoint(forCanvasPoint: border)
        return CGPoint(x: screen.x, y: screen.y)
    }

    /// The screen-space midpoint of the connection's border-anchored edge, or
    /// nil if the edge (or one of its cards) no longer exists — which also hides
    /// the floating delete button.
    private func connectionMidpointScreen(_ id: UUID) -> CGPoint? {
        guard let connection = store.state.connections.first(where: { $0.id == id }),
              let fromCard = store.state.cards.first(where: { $0.id == connection.from }),
              let toCard = store.state.cards.first(where: { $0.id == connection.to }) else { return nil }

        let endpoints = connectionEndpoints(
            from: CanvasRect(origin: fromCard.position, size: fromCard.size),
            to: CanvasRect(origin: toCard.position, size: toCard.size)
        )
        let midCanvas = CanvasPoint(
            x: (endpoints.start.x + endpoints.end.x) / 2,
            y: (endpoints.start.y + endpoints.end.y) / 2
        )
        let screen = store.state.viewport.screenPoint(forCanvasPoint: midCanvas)
        return CGPoint(x: screen.x, y: screen.y)
    }

    // MARK: - Brush / eraser

    /// Converts an overlay view point into canvas space (where strokes live).
    private func canvasPoint(from view: CGPoint) -> CanvasPoint {
        store.state.viewport.canvasPoint(
            forScreenPoint: ScreenPoint(x: view.x, y: view.y)
        )
    }

    /// Appends a brush point, skipping ones too close to the previous sample so
    /// the persisted stroke stays compact.
    private func appendLivePoint(_ point: CanvasPoint) {
        guard interaction.mode == .drawing else { return }
        if let last = liveStrokePoints.last,
           hypot(point.x - last.x, point.y - last.y) < minStrokePointSpacing {
            return
        }
        liveStrokePoints.append(point)
    }

    /// Persists the in-progress stroke (if it has drawable geometry) and resets
    /// the live buffer. The brush tool stays armed for the next stroke.
    private func commitLiveStroke() {
        defer { liveStrokePoints = [] }
        guard liveStrokePoints.count >= 2 else { return }
        store.addStroke(
            DrawingStroke(
                points: liveStrokePoints,
                color: currentBrushRGBA(),
                thickness: interaction.brushThickness
            )
        )
    }

    /// Erases under the eraser disc, sampling along the segment from the previous
    /// sample to `view` so a fast drag erases the whole swept path (no gaps).
    private func erase(at view: CGPoint) {
        let radius = interaction.eraserThickness / 2
        let mode = interaction.eraserMode

        defer { lastErasePoint = view }

        guard let last = lastErasePoint else {
            store.erase(at: canvasPoint(from: view), radius: radius, mode: mode)
            return
        }

        let distance = hypot(view.x - last.x, view.y - last.y)
        // Step in screen px ~ half the disc radius so consecutive footprints
        // overlap; at least one sample so a stationary press still erases.
        let radiusScreen = CGFloat(radius) * CGFloat(store.state.viewport.scale)
        let step = max(radiusScreen / 2, 1)
        let samples = max(Int((distance / step).rounded(.up)), 1)

        for index in 1...samples {
            let fraction = CGFloat(index) / CGFloat(samples)
            let sample = CGPoint(
                x: last.x + ((view.x - last.x) * fraction),
                y: last.y + ((view.y - last.y) * fraction)
            )
            store.erase(at: canvasPoint(from: sample), radius: radius, mode: mode)
        }
    }

    /// The live brush stroke rendered above persisted strokes while drawing.
    private var liveStroke: DrawingStroke? {
        guard interaction.mode == .drawing, !liveStrokePoints.isEmpty else { return nil }
        return DrawingStroke(
            points: liveStrokePoints,
            color: currentBrushRGBA(),
            thickness: interaction.brushThickness
        )
    }

    /// The active brush color (sRGB) combined with the panel's opacity.
    private func currentBrushRGBA() -> RGBAColor {
        let resolved = NSColor(interaction.brushColor).usingColorSpace(.sRGB)
            ?? NSColor.white
        return RGBAColor(
            red: Double(resolved.redComponent),
            green: Double(resolved.greenComponent),
            blue: Double(resolved.blueComponent),
            opacity: interaction.brushOpacity
        )
    }

    private func clampedMenuX(for x: CGFloat, in width: CGFloat) -> CGFloat {
        max(8, min(x, width - contextMenuSize.width - 8))
    }

    private func clampedMenuY(for y: CGFloat, in height: CGFloat) -> CGFloat {
        max(8, min(y, height - contextMenuSize.height - 8))
    }

    private func resignKeyboardFocus() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Whether `viewPoint` (canvas view coords) falls inside the selected card's
    /// on-screen rect, used to hand two-finger scroll to that card's scroll view.
    private func cursorOverSelectedCard(_ viewPoint: CGPoint) -> Bool {
        guard let id = store.state.selectedCardID,
              let card = store.state.cards.first(where: { $0.id == id }) else { return false }

        let topLeft = store.state.viewport.screenPoint(forCanvasPoint: card.position)
        let rect = CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: card.size.width * store.state.viewport.scale,
            height: card.size.height * store.state.viewport.scale
        )
        return rect.contains(viewPoint)
    }

    /// The single gesture for an idle left-drag on empty canvas. It resolves once
    /// per drag — into a marquee selection box when the configured modifier is
    /// satisfied, otherwise into a canvas pan. Two-finger trackpad pan is handled
    /// separately by `CanvasTrackpadPanView` and is unaffected by this choice.
    private var idleDragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if idleDragMode == .none {
                    // ⌘ held ⇒ additive marquee, regardless of the configured
                    // selection-box modifier (so ⌘-drag always extends the
                    // selection). Otherwise the configured modifier decides
                    // marquee-vs-pan as before.
                    let additive = NSEvent.modifierFlags.contains(.command)
                    if additive || selectionBoxModifier.matches(NSEvent.modifierFlags) {
                        idleDragMode = .marquee
                        marqueeStart = value.startLocation
                        marqueeAdditive = additive
                        if additive {
                            var base = store.state.marqueeSelectedCardIDs
                            if let single = store.state.selectedCardID { base.insert(single) }
                            marqueeBase = base
                        } else {
                            marqueeBase = []
                        }
                    } else {
                        idleDragMode = .pan
                    }
                }

                switch idleDragMode {
                case .pan:
                    let delta = CGSize(
                        width: value.translation.width - lastPanTranslation.width,
                        height: value.translation.height - lastPanTranslation.height
                    )
                    store.pan(by: CanvasVector(dx: delta.width, dy: delta.height))
                    lastPanTranslation = value.translation
                case .marquee:
                    marqueeCurrent = value.location
                    let startCanvas = store.state.viewport.canvasPoint(
                        forScreenPoint: ScreenPoint(x: value.startLocation.x, y: value.startLocation.y)
                    )
                    let endCanvas = store.state.viewport.canvasPoint(
                        forScreenPoint: ScreenPoint(x: value.location.x, y: value.location.y)
                    )
                    store.selectCards(
                        fromCorner: startCanvas,
                        toCorner: endCanvas,
                        additive: marqueeAdditive,
                        base: marqueeBase
                    )
                case .none:
                    break
                }
            }
            .onEnded { _ in
                lastPanTranslation = .zero
                idleDragMode = .none
                marqueeStart = nil
                marqueeCurrent = nil
                marqueeBase = []
                marqueeAdditive = false
            }
    }

    /// Pinch-zoom anchored at the cursor. During the gesture the cumulative
    /// magnification is held in `liveZoom` (a pure GPU `scaleEffect`, no `state`
    /// publish), then committed once to `store.viewport` on end so every
    /// stroke/connection/card redraws a single time. The anchor (cursor position)
    /// is captured ONCE on the first tick so it stays stable for the whole gesture
    /// and the preview matches the committed transform. `liveZoom` is clamped so
    /// the previewed scale matches the committed (clamped) result, keeping the
    /// preview from drifting/bouncing at the limits.
    private func zoomGesture(in geometry: GeometryProxy) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard value > 0 else { return }
                if liveZoom == 1 {
                    let point = hoverLocation ?? CGPoint(
                        x: geometry.size.width / 2,
                        y: geometry.size.height / 2
                    )
                    zoomAnchorPoint = point
                    liveZoomAnchor = UnitPoint(
                        x: point.x / max(geometry.size.width, 0.0001),
                        y: point.y / max(geometry.size.height, 0.0001)
                    )
                }
                liveZoom = clampedLiveZoom(value)
            }
            .onEnded { value in
                defer {
                    liveZoom = 1
                    liveZoomAnchor = .center
                    zoomAnchorPoint = nil
                }
                guard value > 0 else { return }

                let point = zoomAnchorPoint ?? CGPoint(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )
                store.zoom(
                    by: Double(clampedLiveZoom(value)),
                    anchoredAt: ScreenPoint(x: point.x, y: point.y)
                )
            }
    }

    /// Clamps an in-progress magnification so `viewport.scale * factor` stays
    /// within the viewport's scale limits, matching `CanvasViewport.zoom`.
    private func clampedLiveZoom(_ factor: CGFloat) -> CGFloat {
        let scale = store.state.viewport.scale
        guard scale > 0 else { return factor }
        let minFactor = CanvasViewport.minimumScale / scale
        let maxFactor = CanvasViewport.maximumScale / scale
        return min(max(factor, CGFloat(minFactor)), CGFloat(maxFactor))
    }
}

private struct CanvasTrackpadPanView: NSViewRepresentable {
    /// `cursorInView` is the pointer in the canvas view's top-left coordinate
    /// space (or nil if it can't be resolved); the closure returns whether it
    /// consumed the scroll event (pan) or let it fall through (card scroll).
    let onPan: (CanvasVector, CGPoint?) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(onPan: onPan)
    }

    func makeNSView(context: Context) -> TrackpadPanHostingView {
        let view = TrackpadPanHostingView()
        view.onScreenFrameChange = { screenFrame in
            context.coordinator.screenFrame = screenFrame
        }
        context.coordinator.hostView = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: TrackpadPanHostingView, context: Context) {
        context.coordinator.onPan = onPan
        context.coordinator.hostView = nsView
        nsView.onScreenFrameChange = { screenFrame in
            context.coordinator.screenFrame = screenFrame
        }
        nsView.updateScreenFrame()
    }

    static func dismantleNSView(_ nsView: TrackpadPanHostingView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var onPan: (CanvasVector, CGPoint?) -> Bool
        var screenFrame: CGRect?
        weak var hostView: TrackpadPanHostingView?

        private var monitor: Any?

        init(onPan: @escaping (CanvasVector, CGPoint?) -> Bool) {
            self.onPan = onPan
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                let shouldConsume = self.handle(event)
                return shouldConsume ? nil : event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }

            monitor = nil
        }

        private func handle(_ event: NSEvent) -> Bool {
            // Only pan when the scroll targets the canvas window itself — not the
            // Settings window or any other window in the app.
            guard let hostWindow = hostView?.window, event.window === hostWindow else { return false }
            guard let screenFrame, screenFrame.contains(NSEvent.mouseLocation) else { return false }

            let translation = CanvasVector(
                dx: event.scrollingDeltaX,
                dy: event.scrollingDeltaY
            )
            guard translation != .zero else { return false }

            // Map the global cursor into the view's top-left coordinate space.
            // `screenFrame` is Cocoa (bottom-left origin), so flip Y.
            let mouse = NSEvent.mouseLocation
            let cursorInView = CGPoint(
                x: mouse.x - screenFrame.minX,
                y: screenFrame.maxY - mouse.y
            )

            return onPan(translation, cursorInView)
        }

        deinit {
            uninstall()
        }
    }

    final class TrackpadPanHostingView: NSView {
        var onScreenFrameChange: (CGRect?) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateScreenFrame()
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            updateScreenFrame()
        }

        func updateScreenFrame() {
            guard let window else {
                onScreenFrameChange(nil)
                return
            }

            let windowFrame = convert(bounds, to: nil)
            onScreenFrameChange(window.convertToScreen(windowFrame))
        }
    }
}

/// What an idle left-drag resolved to, decided once on its first move.
private enum IdleDragMode {
    case none
    case pan
    case marquee
}

/// The modifier a mouse/keyboard user holds to make a left-drag draw a selection
/// box instead of panning. Persisted (`@AppStorage`) and surfaced in the Canvas
/// settings tab. `.none` means a plain drag draws the box. NSEvent-dependent, so
/// it lives on the SwiftUI side rather than in VoidloomCore.
enum SelectionBoxModifier: String, CaseIterable, Identifiable {
    case none
    case shift
    case command
    case option

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .shift: return "Shift"
        case .command: return "Command"
        case .option: return "Option"
        }
    }

    /// Whether the live modifier flags satisfy this trigger. `.none` requires no
    /// modifiers held, so a plain drag draws the box and modified drags pan.
    func matches(_ flags: NSEvent.ModifierFlags) -> Bool {
        let active = flags.intersection(.deviceIndependentFlagsMask)
        switch self {
        case .none: return active.isEmpty
        case .shift: return active.contains(.shift)
        case .command: return active.contains(.command)
        case .option: return active.contains(.option)
        }
    }
}

#Preview("Canvas Workspace") {
    CanvasWorkspaceView(
        store: PreviewSupport.makeStore(),
        sessionManager: AgentSessionManager(),
        interaction: CanvasInteractionModel(),
        isCardFocused: false,
        onToggleCardFocus: {}
    )
    .frame(width: 900, height: 580)
    .background(.black)
}
