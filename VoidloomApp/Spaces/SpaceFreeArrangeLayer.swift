import SwiftUI
import VoidloomCore

/// Board (free-arrange) presentation of a Space: every card lives at its
/// canvas-space `position`/`size` and the whole layer is rendered through the
/// per-space `viewport` (`scaleEffect` + `offset`), so pan/zoom scale the cards
/// and their content together — exactly like the Canvas card group. The header
/// is the drag handle (one card or the marquee group); the corner resizes.
/// The shell owns position seeding, pan/zoom input, and marquee selection.
struct SpaceFreeArrangeLayer: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    let orderedIDs: [UUID]
    let cardsByID: [UUID: WorkspaceCard]
    /// The Board pan/zoom this layer renders through (identity until panned).
    let viewport: CanvasViewport
    let viewportSize: CGSize
    /// On-canvas text elements, rendered in the same transformed group as cards.
    let textElements: [TextElement]
    @Binding var editingTextID: UUID?

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
        // Single transformed group: cards at their canvas `position` (topLeading
        // offset), the whole group scaled by `viewport.scale` and shifted by
        // `viewport.origin`, so a card's on-screen frame equals
        // `viewport.screenPoint(position)` — matching the shell's screen-space
        // hit-testing. Single ForEach + zIndex (never split the dragged tile).
        ZStack(alignment: .topLeading) {
            ForEach(Array(orderedIDs.enumerated()), id: \.element) { index, id in
                if let card = cardsByID[id] {
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
                    .frame(width: card.size.width, height: card.size.height)
                    .overlay {
                        if store.state.selectedCardID == id
                            || store.state.activeCardID == id
                            || store.state.marqueeSelectedCardIDs.contains(id) {
                            CardResizeHandles(
                                cardSize: card.size,
                                cardPosition: card.position,
                                viewportScale: viewport.scale,
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
                    .offset(x: card.position.x, y: card.position.y)
                    .zIndex(zIndex(for: id, at: index, isDragged: isDragged))
                }
            }

            // Text elements share the transformed group, so they pan/zoom with
            // the cards. Each applies its own `.offset(position)`.
            ForEach(textElements) { element in
                TextElementView(
                    element: element,
                    store: store,
                    viewportScale: viewport.scale,
                    editingTextID: $editingTextID
                )
                .zIndex(element.id == store.state.selectedTextID ? 9_500 : 5_000)
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
        .scaleEffect(viewport.scale, anchor: .topLeading)
        .offset(x: viewport.origin.x, y: viewport.origin.y)
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
