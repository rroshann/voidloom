import AppKit
import SwiftUI
import VoidloomCore

struct DraggableWorkspaceCard: View {
    let card: WorkspaceCard
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @ObservedObject var interaction: CanvasInteractionModel
    let viewportScale: Double
    var isCardFocused: Bool = false
    var onToggleCardFocus: () -> Void
    @Binding var editingCardTitleID: UUID?

    @AppStorage("canvas.snapToGrid") private var snapToGrid = false
    @AppStorage("canvas.gridSize") private var gridSize = 16
    @AppStorage("canvas.showAlignmentGuides") private var showAlignmentGuides = true

    @State private var isEditingTitle = false
    @State private var isResizing = false
    /// The marquee group captured on the first move of a drag, so the choice of
    /// group-move vs single-move is decided once and held for the whole drag
    /// (mirrors the idle-drag "decide once" pattern). Nil between drags.
    @State private var draggingGroup: Set<UUID>?
    /// Captured card positions at the start of a drag, keyed by card ID.
    /// Enables total-translation snap math without accumulating floating-point error.
    @State private var dragStartPositions: [UUID: CanvasPoint] = [:]

    private var isSelected: Bool {
        store.state.selectedCardID == card.id
            || store.state.marqueeSelectedCardIDs.contains(card.id)
    }

    private var dragEnabled: Bool {
        !isEditingTitle && !isResizing
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorkspaceCardView(
                card: card,
                store: store,
                isSelected: isSelected,
                isCardFocused: isCardFocused,
                onToggleCardFocus: onToggleCardFocus,
                onClose: closeCard,
                isEditingTitle: $isEditingTitle,
                editingCardTitleID: $editingCardTitleID
            )
            .frame(width: CGFloat(card.size.width), height: CGFloat(card.size.height))

            CardResizeHandles(
                cardSize: card.size,
                cardPosition: card.position,
                viewportScale: viewportScale,
                accentColor: CardPalette(kind: card.kind).accent,
                onResizeStart: {
                    store.selectCard(id: card.id)
                    isResizing = true
                },
                onResize: { size, position in
                    store.resizeCard(id: card.id, to: size, position: position)
                },
                onResizeEnd: {
                    isResizing = false
                }
            )
            .frame(width: CGFloat(card.size.width), height: CGFloat(card.size.height))
        }
        .offset(x: CGFloat(card.position.x), y: CGFloat(card.position.y))
        .onTapGesture {
            // ⌘-click toggles this card in/out of the multi-selection. Evaluated
            // before the marquee no-op below so ⌘-clicking an existing group
            // member is honored instead of being swallowed by it.
            if NSEvent.modifierFlags.contains(.command) {
                store.toggleCardInSelection(id: card.id)
                return
            }
            // A tap on a marquee member is a no-op so the group stays selected for
            // a subsequent group drag. macOS can fire this co-located tap eagerly
            // on press; calling selectCard here would collapse the marquee set to
            // one card before cardDragGesture.onChanged reads it. A tap on a lone
            // or non-member card still selects normally.
            let marquee = store.state.marqueeSelectedCardIDs
            if marquee.count > 1 && marquee.contains(card.id) { return }
            store.selectCard(id: card.id)
        }
        .gesture(cardDragGesture, isEnabled: dragEnabled)
    }

    private var cardDragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let scale = store.state.viewport.scale

                // Decide the drag group once (preserve existing marquee-group behavior).
                let group: Set<UUID>
                if let captured = draggingGroup {
                    group = captured
                } else {
                    let marquee = store.state.marqueeSelectedCardIDs
                    group = (marquee.count > 1 && marquee.contains(card.id)) ? marquee : [card.id]
                    draggingGroup = group
                    if group.count == 1 { store.selectCard(id: card.id) }
                    // Capture start positions for every member.
                    dragStartPositions = Dictionary(uniqueKeysWithValues:
                        store.state.cards.filter { group.contains($0.id) }.map { ($0.id, $0.position) })
                }

                // Total translation in canvas units.
                let totalCanvas = CanvasVector(dx: value.translation.width / scale,
                                               dy: value.translation.height / scale)

                // Proposed anchor (this card) position from its captured start.
                guard let anchorStart = dragStartPositions[card.id] else { return }
                var anchorTarget = CanvasPoint(x: anchorStart.x + totalCanvas.dx,
                                               y: anchorStart.y + totalCanvas.dy)

                // Grid snap (anchor only; group keeps rigid offset).
                if snapToGrid {
                    anchorTarget = CanvasSnapping.snap(anchorTarget, toGrid: Double(gridSize))
                }

                // Alignment snap against all OTHER cards.
                var guides: [AlignmentGuide] = []
                if showAlignmentGuides {
                    let others = store.state.cards
                        .filter { !group.contains($0.id) }
                        .map { CanvasRect(origin: $0.position, size: $0.size) }
                    let aligned = CanvasSnapping.align(movingOrigin: anchorTarget, size: card.size,
                                                       others: others, threshold: 8)
                    anchorTarget = aligned.origin
                    guides = aligned.guides
                }
                interaction.activeAlignmentGuides = guides

                // Apply: shift the whole group by the anchor's final offset from its start.
                let appliedOffset = CanvasVector(dx: anchorTarget.x - anchorStart.x,
                                                 dy: anchorTarget.y - anchorStart.y)
                if group.count > 1 {
                    let positions = Dictionary(uniqueKeysWithValues: dragStartPositions.map {
                        ($0.key, CanvasPoint(x: $0.value.x + appliedOffset.dx, y: $0.value.y + appliedOffset.dy))
                    })
                    store.setCardPositions(positions)
                } else {
                    store.setCardPosition(id: card.id, to: anchorTarget)
                }
            }
            .onEnded { _ in
                draggingGroup = nil
                dragStartPositions = [:]
                interaction.activeAlignmentGuides = []
            }
    }

    private func closeCard() {
        if card.kind == .agent {
            sessionManager.terminateSession(cardID: card.id)
        }
        store.deleteCard(id: card.id)
    }
}
