import SwiftUI
import VoidloomCore

struct SpacesShellView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager

    @State private var topBarHeight: CGFloat = 0
    @State private var dockHeight: CGFloat = 0

    private static let topPadding: CGFloat = 16
    private static let bottomPadding: CGFloat = 24
    private static let dockGap: CGFloat = 16

    private var topInset: Double { Double(topBarHeight + Self.topPadding) }
    private var bottomInset: Double { Double(dockHeight + Self.bottomPadding + Self.dockGap) }

    var body: some View {
        GeometryReader { geo in
            let tiling = store.state.space?.tiling ?? SpaceTiling()
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
                // the selected tile into its own branch). Selected tile floats above.
                ForEach(Array(orderedIDs.enumerated()), id: \.element) { index, id in
                    if let card = cardsByID[id], index < layout.tileOrigins.count {
                        let origin = layout.tileOrigins[index]
                        SpaceTileCard(card: card, store: store, sessionManager: sessionManager)
                            .frame(width: layout.tileSize.x, height: layout.tileSize.y)
                            .position(
                                x: origin.x + layout.tileSize.x / 2,
                                y: origin.y + layout.tileSize.y / 2
                            )
                            .zIndex(store.state.selectedCardID == id ? 1 : 0)
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
            }
        }
        .preferredColorScheme(.dark)
        .onPreferenceChange(SpacesTopBarHeightKey.self) { topBarHeight = $0 }
        .onPreferenceChange(SpacesDockHeightKey.self) { dockHeight = $0 }
    }

    private func reTile() {
        // Order already follows the cards array in v0; clearing any manual order
        // resets to default. Layout is derived, so this just nudges a re-render.
        var tiling = store.state.space?.tiling ?? SpaceTiling()
        store.setSpaceTiling(tiling)   // immediate persist; layout recomputes
        _ = tiling   // (no-op placeholder; real reorder reset arrives with Task 12)
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
