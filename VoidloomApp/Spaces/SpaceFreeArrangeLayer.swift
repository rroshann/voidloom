import SwiftUI
import VoidloomCore

/// Free-arrange presentation of a Space: every card renders at its `position`/
/// `size` (screen points at identity), dragged by its header — one card or the
/// whole marquee group — with no pagination. The shell owns position seeding and
/// marquee selection; this layer renders tiles and forwards header drags to
/// `WorkspaceStore.moveSpaceCardsFreely`.
struct SpaceFreeArrangeLayer: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    let orderedIDs: [UUID]
    let cardsByID: [UUID: WorkspaceCard]
    /// Persisted frames overlaid on grid-derived defaults, so unseeded cards
    /// still have a home while seeding persists in the background.
    let effectiveFrames: [UUID: SpaceFreeFrame]
    let viewportSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The grabbed card (raised while dragging), or nil when idle.
    @State private var draggingCardID: UUID?
    /// The move set captured on the first move of a drag — the marquee group when
    /// dragging a multi-selected member, else just the grabbed card — held for the
    /// whole drag so single-vs-group is decided once (mirrors Canvas).
    @State private var draggingGroup: Set<UUID>?
    /// Last cumulative translation, so each event applies only its delta.
    @State private var lastDragTranslation: CGSize = .zero
    /// Card being resized via the corner handle, so its frame changes track
    /// the cursor instead of riding the layout spring.
    @State private var resizingCardID: UUID?

    var body: some View {
        ZStack {
            // Single ForEach + zIndex, same discipline as the grid layer: never
            // split the dragged/selected tile into its own branch.
            ForEach(Array(orderedIDs.enumerated()), id: \.element) { index, id in
                if let card = cardsByID[id], let frame = effectiveFrames[id] {
                    let isDragged = id == draggingCardID
                    SpaceTileCard(
                        card: card,
                        store: store,
                        sessionManager: sessionManager,
                        onDragChanged: { translation, _ in
                            let group: Set<UUID>
                            if let captured = draggingGroup {
                                group = captured
                            } else {
                                draggingCardID = id
                                let marquee = store.state.marqueeSelectedCardIDs
                                group = (marquee.count > 1 && marquee.contains(id)) ? marquee : [id]
                                draggingGroup = group
                                if group.count == 1 { store.selectCard(id: id) }
                            }
                            let delta = ScreenPoint(x: translation.width - lastDragTranslation.width,
                                                    y: translation.height - lastDragTranslation.height)
                            store.moveSpaceCardsFreely(ids: group, byScreen: delta)
                            lastDragTranslation = translation
                        },
                        onDragEnded: { _ in
                            draggingCardID = nil
                            draggingGroup = nil
                            lastDragTranslation = .zero
                        }
                    )
                    .frame(width: frame.size.x, height: frame.size.y)
                    .overlay {
                        if store.state.selectedCardID == id
                            || store.state.activeCardID == id
                            || store.state.marqueeSelectedCardIDs.contains(id) {
                            CardResizeHandles(
                                cardSize: CardSize(width: frame.size.x, height: frame.size.y),
                                cardPosition: CanvasPoint(x: frame.origin.x, y: frame.origin.y),
                                viewportScale: 1,   // free frames live in screen points
                                accentColor: CardPalette(kind: card.kind).accent,
                                onResizeStart: { resizingCardID = id },
                                onResize: { size, _ in
                                    store.resizeSpaceCardFreely(
                                        id: id,
                                        to: ScreenPoint(x: size.width, y: size.height)
                                    )
                                },
                                onResizeEnd: { resizingCardID = nil }
                            )
                        }
                    }
                    .position(x: frame.origin.x + frame.size.x / 2,
                              y: frame.origin.y + frame.size.y / 2)
                    .zIndex(zIndex(for: id, at: index, isDragged: isDragged))
                    // Dragged/resized tiles must track the cursor instantly,
                    // never ride the frame-change spring below.
                    .transaction { if isDragged || id == resizingCardID { $0.animation = nil } }
                }
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85),
                value: effectiveFrames
            )
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
    }

    /// Dragged tile on top, then the selected/active card, then stacking by
    /// space order so overlapping cards resolve deterministically.
    private func zIndex(for id: UUID, at index: Int, isDragged: Bool) -> Double {
        if isDragged { return 10_000 }
        if store.state.selectedCardID == id
            || store.state.activeCardID == id
            || store.state.marqueeSelectedCardIDs.contains(id) {
            return 9_000
        }
        return Double(index)
    }
}
