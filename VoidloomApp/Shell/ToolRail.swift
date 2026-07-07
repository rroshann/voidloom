import SwiftUI
import VoidloomCore

enum ToolDockVariant { case canvas, spaces }

struct ToolDock: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @ObservedObject var interaction: CanvasInteractionModel
    let errorMessage: String?
    let isAIHintActive: Bool
    let onToggleAIHint: () -> Void
    // Minimap is Canvas-only; defaulted so the Spaces dock can omit these.
    var isMinimapVisible: Bool = false
    var onToggleMinimap: () -> Void = {}
    let zoomScale: Double
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let isCardFocused: Bool
    let isCardSelected: Bool
    let onToggleCardFocus: (() -> Void)?
    /// Double-click: instant create at the visible center.
    let onAddCard: (CardKind) -> Void
    /// Double-click on the Text tool: instant text element at the visible center.
    let onAddText: () -> Void
    /// In `.spaces` the workspace segment, canvas-mode tools, reset, and zoom are hidden.
    var variant: ToolDockVariant = .canvas

    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if variant == .canvas {
                canvasDock
            } else {
                legacySpacesDock
            }
        }
    }

    /// Canvas dock — one clear-glass capsule with monochrome glyphs, matching Spaces.
    private var canvasDock: some View {
        HStack(spacing: DockMetrics.groupGap) {
            DockModeSwitch()

            DockWorkspaceMenu(store: store, sessionManager: sessionManager)

            HStack(spacing: DockMetrics.iconGap) {
                DockToolButton(
                    systemName: "terminal",
                    label: "Terminal — click to place, double-click to add",
                    isArmed: interaction.isArmed(.placingCard(.agent)),
                    onSingle: { interaction.armPlacingCard(.agent) },
                    onDouble: { onAddCard(.agent) }
                )

                DockToolButton(
                    systemName: "note.text",
                    label: "Note — click to place, double-click to add",
                    isArmed: interaction.isArmed(.placingCard(.note)),
                    onSingle: { interaction.armPlacingCard(.note) },
                    onDouble: { onAddCard(.note) }
                )

                DockToolButton(
                    systemName: "checklist",
                    label: "Todo — click to place, double-click to add",
                    isArmed: interaction.isArmed(.placingCard(.todo)),
                    onSingle: { interaction.armPlacingCard(.todo) },
                    onDouble: { onAddCard(.todo) }
                )

                DockToolButton(
                    systemName: "safari",
                    label: "Preview — click to place, double-click to add",
                    isArmed: interaction.isArmed(.placingCard(.browser)),
                    onSingle: { interaction.armPlacingCard(.browser) },
                    onDouble: { onAddCard(.browser) }
                )
            }

            HStack(spacing: DockMetrics.iconGap) {
                DockToolButton(
                    systemName: "arrow.up.right",
                    label: "Connect — link two cards",
                    isArmed: interaction.isArmed(.connecting(source: nil)),
                    onSingle: { interaction.armConnect(preselectedSource: store.state.selectedCardID) }
                )

                DockToolButton(
                    systemName: "paintbrush.pointed.fill",
                    label: "Brush — draw on the canvas",
                    isArmed: interaction.isArmed(.drawing),
                    onSingle: { interaction.armBrush() }
                )

                DockToolButton(
                    systemName: "textformat",
                    label: "Text — click to place, double-click to add",
                    isArmed: interaction.isArmed(.placingText),
                    onSingle: { interaction.armText() },
                    onDouble: { onAddText() }
                )

                DockToolButton(
                    systemName: "eraser.fill",
                    label: "Eraser — erase brush strokes",
                    isArmed: interaction.isArmed(.erasing),
                    onSingle: { interaction.armEraser() }
                )
            }

            HStack(spacing: DockMetrics.iconGap) {
                DockIconButton(systemName: "scope", label: "Reset") {
                    store.resetViewport()
                }

                DockIconButton(
                    systemName: "map",
                    label: isMinimapVisible ? "Hide minimap" : "Show minimap",
                    isActive: isMinimapVisible
                ) {
                    onToggleMinimap()
                }
            }

            DockAIHint(
                errorMessage: errorMessage,
                isActive: isAIHintActive,
                action: onToggleAIHint
            )

            CanvasZoomControls(
                scale: zoomScale,
                onZoomIn: onZoomIn,
                onZoomOut: onZoomOut,
                isCardFocused: isCardFocused,
                onToggleCardFocus: onToggleCardFocus,
                isFocusEnabled: isCardSelected,
                embedded: true
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(DockGlass(shape: Capsule()))
        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 6)
    }

    /// Legacy layout retained for the unused `.spaces` ToolDock variant.
    private var legacySpacesDock: some View {
        HStack(spacing: 7) {
            DockToolButton(
                systemName: "terminal",
                label: "Add terminal card",
                onSingle: { onAddCard(.agent) }
            )

            DockToolButton(
                systemName: "note.text",
                label: "Add note card",
                onSingle: { onAddCard(.note) }
            )

            DockToolButton(
                systemName: "checklist",
                label: "Add todo card",
                onSingle: { onAddCard(.todo) }
            )

            DockToolButton(
                systemName: "safari",
                label: "Add browser card",
                onSingle: { onAddCard(.browser) }
            )

            if errorMessage != nil {
                DockDivider()

                DockAIHint(
                    errorMessage: errorMessage,
                    isActive: false,
                    action: {}
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(theme.ink(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 28, x: 0, y: 18)
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
    }
}

/// A dock tool that distinguishes single-click (arm a canvas mode) from
/// double-click (instant create). Reuses the shared glyph treatment, driven
/// by `isArmed`. Tools without a double action pass `onDouble == nil`.
private struct DockToolButton: View {
    let systemName: String
    let label: String
    var isArmed: Bool = false
    var onSingle: () -> Void
    var onDouble: (() -> Void)? = nil

    var body: some View {
        DockIconGlyph(icon: systemName, isActive: isArmed)
            .modifier(DockToolGesture(onSingle: onSingle, onDouble: onDouble))
            .pointerCursor()
            .help(label)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isArmed ? .isSelected : [])
            .animation(.easeOut(duration: 0.12), value: isArmed)
    }
}

/// Splits a dock tool's tap handling by whether it has a double-click action.
///
/// Tools WITHOUT a double action (connect/brush/eraser) arm instantly on a
/// single click — no double-click disambiguation delay, so they feel snappy.
///
/// Tools WITH a double action (card/text) arm on mouse-DOWN via a zero-duration
/// long press so the place-mode highlight appears immediately, while a real
/// double-click still fires instant-create. Trade-off: a genuine double-click
/// transiently arms place-mode on the first press, but the create path disarms
/// right after, so the resolved state is always correct.
private struct DockToolGesture: ViewModifier {
    let onSingle: () -> Void
    let onDouble: (() -> Void)?

    func body(content: Content) -> some View {
        if let onDouble {
            content
                .onTapGesture(count: 2) { onDouble() }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0).onEnded { _ in onSingle() }
                )
        } else {
            content.onTapGesture(count: 1) { onSingle() }
        }
    }
}

private struct DockDivider: View {
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(theme.ink(0.14))
            .frame(width: 1, height: 34)
            .padding(.horizontal, 6)
    }
}

private struct DockAIHint: View {
    let errorMessage: String?
    let isActive: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme

    private var message: String {
        if isActive {
            return "Hide command hints"
        }
        return errorMessage ?? "Show command hints"
    }

    private var iconName: String {
        errorMessage == nil ? "sparkles" : "exclamationmark.triangle"
    }

    private var accentColor: Color {
        errorMessage == nil ? theme.accent : .orange
    }

    var body: some View {
        DockIconButton(
            icon: iconName,
            help: message,
            isActive: isActive || errorMessage != nil,
            activeColor: accentColor,
            action: action
        )
    }
}

private extension DockIconButton {
    init(
        systemName: String,
        label: String,
        isActive: Bool = false,
        activeColor: Color? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.init(
            icon: systemName,
            help: label,
            isActive: isActive,
            activeColor: activeColor,
            isEnabled: isEnabled,
            action: action
        )
    }
}
