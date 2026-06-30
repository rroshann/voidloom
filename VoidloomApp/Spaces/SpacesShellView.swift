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

    @State private var topBarHeight: CGFloat = 0
    @State private var dockHeight: CGFloat = 0

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
                            onDropped: { globalLocation in
                                let geoFrame = geo.frame(in: .global)
                                let geoOrigin = CGPoint(x: geoFrame.origin.x, y: geoFrame.origin.y)
                                if let target = slotIndex(
                                    for: globalLocation,
                                    layout: layout,
                                    geoOrigin: geoOrigin
                                ), target != index {
                                    store.moveSpaceCard(fromIndex: index, toIndex: target)
                                }
                                draggingIndex = nil
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
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: orderedIDs)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: layout.tileSize)

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
        .preferredColorScheme(.dark)
        .onPreferenceChange(SpacesTopBarHeightKey.self) { topBarHeight = $0 }
        .onPreferenceChange(SpacesDockHeightKey.self) { dockHeight = $0 }
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
            if lx >= origin.x && lx <= origin.x + layout.tileSize.x
                && ly >= origin.y && ly <= origin.y + layout.tileSize.y {
                return i
            }
        }
        return nil
    }
}

struct SpacesTopBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SpacesDockHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
