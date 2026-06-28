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

    @Published private(set) var mode: Mode = .idle

    // Live tool settings bound to the option panels. Defined up front so the
    // brush/eraser panels can bind to them in Stage 1 even though the actual
    // drawing/erasing wiring lands in Stage 3.
    @Published var brushColor: Color = Color(red: 0.34, green: 0.93, blue: 0.82)
    @Published var brushThickness: Double = 4
    @Published var brushOpacity: Double = 1
    @Published var eraserThickness: Double = 28
    @Published var eraserMode: EraseMode = .wholeStroke

    /// The text element currently in inline-edit mode, if any. Set when a text
    /// element is created (place-drag, double-click dock, or palette) or when
    /// the user double-taps an existing element. Read by `TextElementView` to
    /// focus its field. Independent of `mode` — editing text does not arm a tool.
    @Published var editingTextID: UUID?

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

    func armConnect() {
        // Re-arming connect resets any in-progress source pick.
        if case .connecting = mode {
            mode = .idle
        } else {
            mode = .connecting(source: nil)
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
