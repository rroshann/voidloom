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
    @AppStorage("spaces.defaultRows") private var defaultRows = 0

    /// Currently shown grid page (0-based). Clamped to the live page count.
    @State private var currentPage = 0
    /// Live page count, mirrored here so the key handler can page with arrows.
    @State private var pageCount = 1

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

    /// Builds a tiling from the global Settings defaults, used when a space has no
    /// tiling of its own. Columns 0 = Auto (fit all); Rows 0 = no pagination.
    private static func fallbackTiling(columns: Int, rows: Int) -> SpaceTiling {
        if columns == 0 { return SpaceTiling(mode: .auto) }
        return SpaceTiling(mode: .fixedColumns, columns: columns, maxRows: rows == 0 ? nil : rows)
    }

    var body: some View {
        GeometryReader { geo in
            let tiling = store.state.space?.tiling
                ?? Self.fallbackTiling(columns: defaultColumns, rows: defaultRows)
            let orderedIDs = store.state.orderedCardIDsForSpace
            let cardsByID = Dictionary(uniqueKeysWithValues: store.state.cards.map { ($0.id, $0) })
            let paged = SpaceGrid.pagedLayout(
                cardCount: orderedIDs.count,
                viewportSize: ScreenPoint(x: geo.size.width, y: geo.size.height),
                topInset: topInset,
                bottomInset: bottomInset,
                tiling: tiling,
                page: currentPage
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
                ForEach(Array(zip(paged.cardRange, orderedIDs[paged.cardRange])), id: \.1) { globalIndex, id in
                    if let card = cardsByID[id] {
                        let localIndex = globalIndex - paged.cardRange.lowerBound
                        let origin = paged.tileOrigins[localIndex]
                        SpaceTileCard(
                            card: card,
                            store: store,
                            sessionManager: sessionManager,
                            onDragChanged: { _ in
                                if draggingIndex != globalIndex { draggingIndex = globalIndex }
                            },
                            onDropped: { globalLocation -> Bool in
                                let geoOrigin = shellFrame.origin
                                if let localTarget = slotIndex(
                                    for: globalLocation,
                                    tileOrigins: paged.tileOrigins,
                                    tileSize: paged.tileSize,
                                    geoOrigin: geoOrigin
                                ) {
                                    let globalTarget = paged.cardRange.lowerBound + localTarget
                                    if globalTarget != globalIndex {
                                        store.moveSpaceCard(fromIndex: globalIndex, toIndex: globalTarget)
                                        draggingIndex = nil
                                        return true
                                    }
                                }
                                draggingIndex = nil
                                return false
                            }
                        )
                        .frame(width: paged.tileSize.x, height: paged.tileSize.y)
                        .position(
                            x: origin.x + paged.tileSize.x / 2,
                            y: origin.y + paged.tileSize.y / 2
                        )
                        .zIndex(draggingIndex == globalIndex ? 2 : (store.state.selectedCardID == id ? 1 : 0))
                    }
                }
                .animation(
                    reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85),
                    value: orderedIDs
                )
                .animation(
                    reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85),
                    value: paged.tileSize
                )

                VStack {
                    SpaceTopBar(store: store, sessionManager: sessionManager, onReTile: reTile)
                        .background(GeometryReader { p in
                            Color.clear.preference(key: SpacesTopBarHeightKey.self, value: p.size.height)
                        })
                        .padding(.top, Self.topPadding)
                    Spacer()
                }

                VStack(spacing: 12) {
                    Spacer()
                    if paged.pageCount > 1 { pager(paged) }
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
            .onChange(of: paged.pageCount) { _, newCount in
                pageCount = newCount
                if currentPage > newCount - 1 { currentPage = max(0, newCount - 1) }
            }
            .onChange(of: store.library.selectedWorkspaceID) { _, _ in currentPage = 0 }
            .onChange(of: store.state.space?.tiling) { _, _ in currentPage = 0 }
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
        case 123:   // left arrow
            guard !typing, pageCount > 1 else { return false }
            currentPage = max(0, currentPage - 1)
            return true
        case 124:   // right arrow
            guard !typing, pageCount > 1 else { return false }
            currentPage = min(pageCount - 1, currentPage + 1)
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
        currentPage = 0
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

    @ViewBuilder private func pager(_ paged: SpaceGrid.PagedLayout) -> some View {
        HStack(spacing: 10) {
            Button { currentPage = max(0, currentPage - 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
            }
            .disabled(paged.page == 0)
            Text("\(paged.page + 1) / \(paged.pageCount)")
                .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            Button { currentPage = min(paged.pageCount - 1, currentPage + 1) } label: {
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

struct SpacesTopBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct SpacesDockHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
