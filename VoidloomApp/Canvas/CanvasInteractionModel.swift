import SwiftUI
import VoidloomCore

/// The single shared spine for canvas tool interaction. One injected
/// `@MainActor ObservableObject` read by the dock (to drive armed state + tool
/// panels), the canvas (to gate pan/tap and capture input), and the render
/// overlays. Folds what could have been four separate controllers into one
/// owner so there is no duplicate-type or injection ambiguity.
@MainActor
final class CanvasInteractionModel: ObservableObject {
    /// The active canvas interaction mode. `.connecting` carries its source card
    /// inline so no extra published property is needed to track it.
    enum Mode: Equatable {
        case idle
        case placingCard(CardKind)
        case placingText
        case connecting(source: UUID?)
        case drawing
        case erasing

        /// Whether the canvas should route left-mouse input through the shared
        /// overlay (suppressing pan/tap/card-drag) rather than its idle gestures.
        var capturesCanvas: Bool { self != .idle }

        /// Whether this mode is sized by a press-drag-release rubber-band rect.
        var isRubberBand: Bool {
            if case .placingCard = self { return true }
            return self == .placingText
        }

        /// Whether this mode draws/erases via accumulated freehand input.
        var isFreehand: Bool { self == .drawing || self == .erasing }
    }

    @Published private(set) var mode: Mode = .idle {
        didSet {
            // A selected connection edge and an armed tool are mutually
            // exclusive — arming any tool drops the edge selection so its
            // delete control disappears.
            if mode != .idle { selectedConnectionID = nil }
            // The hover highlight only exists while the connect tool is armed,
            // so disarming or arming another tool clears the prospective pick.
            if case .connecting = mode {} else { hoveredCardID = nil }
            // The eraser size preview only makes sense while the eraser is armed.
            if mode != .erasing { isAdjustingEraserSize = false }
        }
    }

    /// The connection edge currently selected (e.g. tapped on the canvas),
    /// showing its delete control. Independent of card/text selection.
    @Published var selectedConnectionID: UUID?

    /// While the connect tool is armed, the card under the cursor — the
    /// prospective source (before a source is chosen) or target (after). Drives
    /// the hover highlight ring; cleared automatically when connect is disarmed.
    @Published var hoveredCardID: UUID?

    // Live tool settings bound to the option panels. Defined up front so the
    // brush/eraser panels can bind to them in Stage 1 even though the actual
    // drawing/erasing wiring lands in Stage 3.
    @Published var brushColor: Color = Color(red: 0.34, green: 0.93, blue: 0.82)
    @Published var brushThickness: Double = 4
    @Published var brushOpacity: Double = 1
    @Published var eraserThickness: Double = 28
    @Published var eraserMode: EraseMode = .wholeStroke

    /// True while the pointer is over the eraser options panel (i.e. adjusting the
    /// thickness slider). Drives a centered size-preview ring rendered *above* the
    /// dock — the on-canvas cursor ring would otherwise be hidden behind the
    /// panel. Mutually exclusive with the canvas ring so the two never overlap.
    @Published var isAdjustingEraserSize: Bool = false

    /// Transient alignment guide lines produced by the snapping engine while a
    /// card is being dragged. Populated by the drag handler; cleared on drag end.
    /// Consumed by `AlignmentGuidesLayer` to draw the overlay lines.
    @Published var activeAlignmentGuides: [AlignmentGuide] = []

    /// The text element currently in inline-edit mode, if any. Set when a text
    /// element is created (place-drag, double-click dock, or palette) or when
    /// the user double-taps an existing element. Read by `TextElementView` to
    /// focus its field. Independent of `mode` — editing text does not arm a tool.
    @Published var editingTextID: UUID?

    /// The card whose title is currently in inline-edit mode, if any. Shared so
    /// RootView's Delete shortcut can stay inert while a card title is being
    /// edited (mirrors `editingTextID`). Set by the card title edit lifecycle.
    @Published var editingCardTitleID: UUID?

    // Default text styling applied to NEWLY created text elements. The text
    // options panel writes these when no element is selected; the creation paths
    // (place-drag, dock double-click, palette) seed new elements from them.
    @Published var textFontSize: Double = 17
    @Published var textColor: Color = .white
    @Published var textFontName: String? = nil

    // MARK: - Arming

    /// Toggles into a mode, or back to idle if that mode is already armed.
    /// `placingCard`/`placingText` are one-shot (the caller disarms on create);
    /// `connecting`/`drawing`/`erasing` stay armed until toggled off or ESC.
    private func toggle(_ target: Mode) {
        if isArmed(target) {
            mode = .idle
        } else {
            mode = target
        }
    }

    func armPlacingCard(_ kind: CardKind) {
        toggle(.placingCard(kind))
    }

    func armText() {
        toggle(.placingText)
    }

    /// Arms the connect tool, optionally seeding the source card so the very
    /// next canvas click completes the link. Pass `preselectedSource` from the
    /// current card selection: if a card is selected the user only picks the
    /// target; if none is selected the user picks both source then target.
    /// Re-arming connect (no toggle) toggles it back off.
    func armConnect(preselectedSource: UUID? = nil) {
        if case .connecting = mode {
            mode = .idle
        } else {
            mode = .connecting(source: preselectedSource)
        }
    }

    func armBrush() {
        toggle(.drawing)
    }

    func armEraser() {
        toggle(.erasing)
    }

    func setConnectSource(_ id: UUID) {
        mode = .connecting(source: id)
    }

    func clearConnectSource() {
        if case .connecting = mode {
            mode = .connecting(source: nil)
        }
    }

    func disarm() {
        mode = .idle
    }

    // MARK: - Queries

    /// Whether `target` matches the active mode. For `placingCard` this compares
    /// the card kind; for `connecting` it ignores the inline source so the dock
    /// button stays highlighted while a source is selected.
    func isArmed(_ target: Mode) -> Bool {
        switch (mode, target) {
        case let (.placingCard(a), .placingCard(b)):
            return a == b
        case (.connecting, .connecting):
            return true
        default:
            return mode == target
        }
    }
}
