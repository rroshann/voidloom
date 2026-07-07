import SwiftUI
import VoidloomCore

/// Free-arrange presentation of a Space: every card renders at its persisted
/// `SpaceFreeFrame` and drags anywhere (no pagination). The shell owns frame
/// seeding and marquee selection; this layer renders tiles and forwards drags
/// to `WorkspaceStore.moveSpaceCardFreely`.
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

    @State private var draggingCardID: UUID?
    /// Frame origin captured when a drag starts, so the cumulative translation
    /// applies from a stable base instead of compounding per event.
    @State private var dragStartOrigin: ScreenPoint?
    /// Card being resized via the corner handle, so its frame changes track
    /// the cursor instead of riding the layout spring.
    @State private var resizingCardID: UUID?

    /// Minimum visible strip of a card at every screen edge, so a drag can
    /// never strand a card fully off-screen.
    private static let minVisibleEdge: Double = 60

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
                            if draggingCardID != id {
                                draggingCardID = id
                                dragStartOrigin = frame.origin
                            }
                            guard let start = dragStartOrigin else { return }
                            let proposed = ScreenPoint(x: start.x + translation.width,
                                                       y: start.y + translation.height)
                            store.moveSpaceCardFreely(id: id, to: clamped(proposed, size: frame.size))
                        },
                        onDragEnded: { _ in
                            draggingCardID = nil
                            dragStartOrigin = nil
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

    /// Keeps at least `minVisibleEdge` points of the card inside the viewport
    /// on every axis.
    private func clamped(_ origin: ScreenPoint, size: ScreenPoint) -> ScreenPoint {
        let e = Self.minVisibleEdge
        let x = min(max(origin.x, e - size.x), Double(viewportSize.width) - e)
        let y = min(max(origin.y, 0), Double(viewportSize.height) - e)
        return ScreenPoint(x: x, y: y)
    }
}
