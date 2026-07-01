import AppKit
import SwiftUI
import VoidloomCore

struct SpacesShellView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager

    /// Dedicated interaction model for the Spaces dock. The dock requires a
    /// CanvasInteractionModel to satisfy its initializer, but in .spaces mode all
    /// interaction-driven controls are hidden, so this object stays effectively idle.
    @StateObject private var dockInteraction = CanvasInteractionModel()

    @AppStorage("spaces.defaultColumns") private var defaultColumns = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var topBarHeight: CGFloat = 0
    @State private var dockHeight: CGFloat = 0
    /// Current global frame of the shell, updated continuously via a background
    /// GeometryReader so drop hit-tests always use up-to-date geometry even if
    /// the window is resized during a drag.
    @State private var shellFrame: CGRect = .zero

    /// Index of the tile currently being dragged, or nil when idle.
    @State private var draggingIndex: Int?

    private static let topPadding: CGFloat = 16
    private static let bottomPadding: CGFloat = 24
    private static let dockGap: CGFloat = 16

    private var topInset: Double { Double(topBarHeight + Self.topPadding) }
    private var bottomInset: Double { Double(dockHeight + Self.bottomPadding + Self.dockGap) }

    var body: some View {
        GeometryReader { geo in
            let tiling = store.state.space?.tiling ?? SpaceTiling(
                mode: defaultColumns == 0 ? .auto : .fixedColumns,
                columns: defaultColumns == 0 ? 2 : defaultColumns
            )
            let orderedIDs = store.state.orderedCardIDsForSpace
            let cardsByID = Dictionary(uniqueKeysWithValues: store.state.cards.map { ($0.id, $0) })
            let layout = SpaceGrid.layout(
                cardCount: orderedIDs.count,
                viewportSize: ScreenPoint(x: geo.size.width, y: geo.size.height),
                topInset: topInset,
                bottomInset: bottomInset,
                tiling: tiling
            )

            ZStack {
                SpaceBackgroundView(
                    background: store.state.space?.background ?? .atmosphere,
                    dimming: store.state.space?.backgroundDimming ?? 0.35,
                    backgroundsDirectory: store.backgroundsDirectoryURL()
                )

                if orderedIDs.isEmpty {
                    Text("No cards yet — add one from the dock below.")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }

                // Single ForEach + zIndex (Canvas gotcha #1 discipline: never split
                // the selected tile into its own branch). Dragged tile floats highest;
                // selected tile floats above idle tiles.
                ForEach(Array(orderedIDs.enumerated()), id: \.element) { index, id in
                    if let card = cardsByID[id], index < layout.tileOrigins.count {
                        let origin = layout.tileOrigins[index]
                        SpaceTileCard(
                            card: card,
                            store: store,
                            sessionManager: sessionManager,
                            onDragChanged: { _ in
                                if draggingIndex != index { draggingIndex = index }
                            },
                            onDropped: { globalLocation -> Bool in
                                // shellFrame is tracked via a background GeometryReader
                                // so it reflects the current window position even when
                                // the window was moved or resized mid-drag.
                                let geoOrigin = shellFrame.origin
                                if let target = slotIndex(
                                    for: globalLocation,
                                    layout: layout,
                                    geoOrigin: geoOrigin
                                ), target != index {
                                    store.moveSpaceCard(fromIndex: index, toIndex: target)
                                    draggingIndex = nil
                                    return true
                                }
                                draggingIndex = nil
                                return false
                            }
                        )
                        .frame(width: layout.tileSize.x, height: layout.tileSize.y)
                        .position(
                            x: origin.x + layout.tileSize.x / 2,
                            y: origin.y + layout.tileSize.y / 2
                        )
                        .zIndex(draggingIndex == index ? 2 : (store.state.selectedCardID == id ? 1 : 0))
                    }
                }
                .animation(
                    reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85),
                    value: orderedIDs
                )
                .animation(
                    reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85),
                    value: layout.tileSize
                )

                VStack {
                    SpaceTopBar(store: store, sessionManager: sessionManager, onReTile: reTile)
                        .background(GeometryReader { p in
                            Color.clear.preference(key: SpacesTopBarHeightKey.self, value: p.size.height)
                        })
                        .padding(.top, Self.topPadding)
                    Spacer()
                }

                VStack {
                    Spacer()
                    ToolDock(
                        store: store,
                        interaction: dockInteraction,
                        errorMessage: store.lastPersistenceError,
                        isAIHintActive: false,
                        onToggleAIHint: {},
                        zoomScale: 1,
                        onZoomIn: {},
                        onZoomOut: {},
                        isCardFocused: false,
                        isCardSelected: store.state.selectedCardID != nil,
                        onToggleCardFocus: nil,
                        workspaceName: "",
                        isWorkspaceSidebarVisible: false,
                        onToggleWorkspaceSidebar: {},
                        onAddCard: { kind in store.addCard(kind: kind) },
                        onAddText: {},
                        variant: .spaces
                    )
                    .background(GeometryReader { p in
                        Color.clear.preference(key: SpacesDockHeightKey.self, value: p.size.height)
                    })
                    .padding(.bottom, Self.bottomPadding)
                }
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
        .onPreferenceChange(SpacesTopBarHeightKey.self) { topBarHeight = $0 }
        .onPreferenceChange(SpacesDockHeightKey.self) { dockHeight = $0 }
    }

    /// Window-scoped key handling for Spaces. Delete/Backspace removes the marquee
    /// group or the single selected tile (terminating any agent sessions first);
    /// Escape clears selection. Stays inert while a text control is first responder
    /// so typing in a title/note/todo/terminal keeps its keys.
    private func handleSpacesKey(_ event: NSEvent) -> Bool {
        let typing = event.window?.firstResponder is NSText
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

    private func reTile() {
        // Resets Spaces order to the canonical cards array order and persists.
        store.resetSpaceCardOrder()
        draggingIndex = nil
    }

    /// Returns the tile index whose frame contains `globalPoint` (converted to the
    /// GeometryReader's local space via `geoOrigin`), or nil if no tile was hit.
    private func slotIndex(
        for globalPoint: CGPoint,
        layout: SpaceGrid.Layout,
        geoOrigin: CGPoint
    ) -> Int? {
        let lx = globalPoint.x - geoOrigin.x
        let ly = globalPoint.y - geoOrigin.y
        for (i, origin) in layout.tileOrigins.enumerated() {
            if lx >= origin.x && lx < origin.x + layout.tileSize.x
                && ly >= origin.y && ly < origin.y + layout.tileSize.y {
                return i
            }
        }
        return nil
    }
}

struct ShellFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct SpacesTopBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SpacesDockHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
