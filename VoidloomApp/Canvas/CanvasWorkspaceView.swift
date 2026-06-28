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
    @State private var lastMagnification: CGFloat = 1
    @State private var contextMenuLocation: CGPoint?
    @State private var rubberStart: CGPoint?
    @State private var rubberCurrent: CGPoint?
    /// Live cursor (screen/view coords) while the connect tool is armed, used to
    /// draw the follow-arrow from the source card to the pointer.
    @State private var connectCursor: CGPoint?
    /// Points (canvas space) accumulated for the brush stroke currently being
    /// drawn. Empty when no drag is in progress.
    @State private var liveStrokePoints: [CanvasPoint] = []

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
                        resignKeyboardFocus()
                        store.clearSelection()
                    }
                    .gesture(panGesture, isEnabled: interaction.mode == .idle)
                    .simultaneousGesture(zoomGesture(in: geometry))

                // Pointer overlays sit BELOW the cards so they never occlude
                // card hover (header chrome, resize cursor). Pan runs off a
                // global scroll monitor (so it needs no hit testing); right-click
                // is claimed only over empty canvas — cards above intercept their
                // own right-clicks.
                CanvasTrackpadPanView { translation in
                    guard interaction.mode == .idle else { return false }
                    guard store.state.selectedCardID == nil else { return false }
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

                    CanvasDrawingLayer(
                        strokes: store.state.strokes,
                        liveStroke: liveStroke,
                        canvasSize: canvasSize
                    )

                    ConnectionsLayer(
                        connections: store.state.connections,
                        cards: store.state.cards,
                        canvasSize: canvasSize
                    )

                    ForEach(store.state.cards) { card in
                        DraggableWorkspaceCard(
                            card: card,
                            store: store,
                            sessionManager: sessionManager,
                            viewportScale: store.state.viewport.scale,
                            isCardFocused: isCardFocused,
                            onToggleCardFocus: onToggleCardFocus
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

                // Armed-tool input capture sits ABOVE the cards so place/connect
                // drags are intercepted before a card drag can begin. It is
                // inert (hitTest returns nil) whenever no tool is armed.
                CanvasInteractionOverlay(
                    mode: interaction.mode,
                    eraserScreenDiameter: CGFloat(interaction.eraserThickness * store.state.viewport.scale),
                    onMouseDown: handleOverlayDown,
                    onMouseDragged: handleOverlayDragged,
                    onMouseMoved: handleOverlayMoved,
                    onMouseUp: handleOverlayUp
                )
                .frame(width: geometry.size.width, height: geometry.size.height)

                CanvasInteractionLayer(
                    interaction: interaction,
                    rubberStart: rubberStart,
                    rubberCurrent: rubberCurrent,
                    connectSourceRect: connectSourceScreenRect,
                    connectAnchor: connectAnchorScreen,
                    connectCursor: connectCursor,
                    connectAccent: connectAccent
                )
                .frame(width: geometry.size.width, height: geometry.size.height)

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
            erase(at: point)
        default:
            break
        }
    }

    private func handleOverlayMoved(_ point: CGPoint) {
        if case .connecting = interaction.mode {
            connectCursor = point
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
            if dragDistance < minRubberBandDrag {
                id = store.addTextElement(centeredAt: startCanvas)
            } else {
                id = store.addTextElement(fromCorner: startCanvas, toCorner: endCanvas)
            }
            // Auto-focus inline editing on the freshly placed element.
            interaction.editingTextID = id
        default:
            break
        }

        interaction.disarm()
    }

    /// Connect tool click: pick a source card, then a distinct target card to
    /// persist an edge. Source is cleared after a successful link so the tool
    /// stays armed to start a new connection. Visuals only — no agent comms.
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
            if source != hitID {
                store.addConnection(from: source, to: hitID)
            }
            interaction.clearConnectSource()
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

    private func erase(at view: CGPoint) {
        store.erase(
            at: canvasPoint(from: view),
            radius: interaction.eraserThickness / 2,
            mode: interaction.eraserMode
        )
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

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastPanTranslation.width,
                    height: value.translation.height - lastPanTranslation.height
                )

                store.pan(by: CanvasVector(dx: delta.width, dy: delta.height))
                lastPanTranslation = value.translation
            }
            .onEnded { _ in
                lastPanTranslation = .zero
            }
    }

    private func zoomGesture(in geometry: GeometryProxy) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard value > 0 else { return }

                let delta = value / lastMagnification
                let anchor = ScreenPoint(
                    x: geometry.size.width / 2,
                    y: geometry.size.height / 2
                )

                store.zoom(by: delta, anchoredAt: anchor)
                lastMagnification = value
            }
            .onEnded { _ in
                lastMagnification = 1
            }
    }
}

private struct CanvasTrackpadPanView: NSViewRepresentable {
    let onPan: (CanvasVector) -> Bool

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
        var onPan: (CanvasVector) -> Bool
        var screenFrame: CGRect?
        weak var hostView: TrackpadPanHostingView?

        private var monitor: Any?

        init(onPan: @escaping (CanvasVector) -> Bool) {
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
            guard screenFrame?.contains(NSEvent.mouseLocation) == true else { return false }

            let translation = CanvasVector(
                dx: event.scrollingDeltaX,
                dy: event.scrollingDeltaY
            )
            guard translation != .zero else { return false }

            return onPan(translation)
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
