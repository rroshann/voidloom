import AppKit
import SwiftUI
import VoidloomCore

struct CanvasWorkspaceView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    var isCardFocused: Bool
    var onToggleCardFocus: () -> Void

    @State private var lastPanTranslation: CGSize = .zero
    @State private var lastMagnification: CGFloat = 1
    @State private var contextMenuLocation: CGPoint?

    private let canvasSize = CGSize(width: 5_000, height: 3_400)
    private let contextMenuSize = CGSize(width: 196, height: 200)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        resignKeyboardFocus()
                        store.clearSelection()
                    }
                    .gesture(panGesture)
                    .simultaneousGesture(zoomGesture(in: geometry))

                ZStack(alignment: .topLeading) {
                    CanvasGrid()

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
                }
                .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
                .scaleEffect(CGFloat(store.state.viewport.scale), anchor: .topLeading)
                .offset(
                    x: CGFloat(store.state.viewport.origin.x),
                    y: CGFloat(store.state.viewport.origin.y)
                )

                CanvasTrackpadPanView { translation in
                    guard store.state.selectedCardID == nil else { return false }
                    store.pan(by: translation)
                    return true
                }
                .frame(width: geometry.size.width, height: geometry.size.height)

                CanvasRightClickCatcher { point in
                    contextMenuLocation = point
                }
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
        }
    }

    private func addCard(kind: CardKind, atViewPoint point: CGPoint) {
        let canvasPoint = store.state.viewport.canvasPoint(
            forScreenPoint: ScreenPoint(x: point.x, y: point.y)
        )
        store.addCard(kind: kind, centeredAt: canvasPoint)
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
        isCardFocused: false,
        onToggleCardFocus: {}
    )
    .frame(width: 900, height: 580)
    .background(.black)
}
