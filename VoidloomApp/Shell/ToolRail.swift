import SwiftUI
import VoidloomCore

enum ToolDockVariant { case canvas, spaces }

struct ToolDock: View {
    @ObservedObject var store: WorkspaceStore
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
    let workspaceName: String
    let isWorkspaceSidebarVisible: Bool
    let onToggleWorkspaceSidebar: () -> Void
    /// Double-click: instant create at the visible center.
    let onAddCard: (CardKind) -> Void
    /// Double-click on the Text tool: instant text element at the visible center.
    let onAddText: () -> Void
    /// In `.spaces` the workspace segment, canvas-mode tools, reset, and zoom are hidden.
    var variant: ToolDockVariant = .canvas

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 7) {
            if variant == .canvas {
                DockWorkspaceSegment(
                    workspaceName: workspaceName,
                    cardCount: store.state.cards.count,
                    isWorkspaceSidebarVisible: isWorkspaceSidebarVisible,
                    onToggle: onToggleWorkspaceSidebar
                )
                DockDivider()
            }

            // Card-creation buttons — always visible.
            // In .canvas: single-click arms place-mode; double-click creates instantly.
            // In .spaces: a single click creates instantly; double-click is disabled
            // (onDouble nil) so one double-click can't spawn several cards.
            DockToolButton(
                systemName: "terminal",
                label: variant == .spaces ? "Add terminal card" : "Terminal — click to place, double-click to add",
                isArmed: variant == .canvas && interaction.isArmed(.placingCard(.agent)),
                onSingle: variant == .canvas ? { interaction.armPlacingCard(.agent) } : { onAddCard(.agent) },
                onDouble: variant == .canvas ? { onAddCard(.agent) } : nil
            )

            DockToolButton(
                systemName: "note.text",
                label: variant == .spaces ? "Add note card" : "Note — click to place, double-click to add",
                isArmed: variant == .canvas && interaction.isArmed(.placingCard(.note)),
                onSingle: variant == .canvas ? { interaction.armPlacingCard(.note) } : { onAddCard(.note) },
                onDouble: variant == .canvas ? { onAddCard(.note) } : nil
            )

            DockToolButton(
                systemName: "checklist",
                label: variant == .spaces ? "Add todo card" : "Todo — click to place, double-click to add",
                isArmed: variant == .canvas && interaction.isArmed(.placingCard(.todo)),
                onSingle: variant == .canvas ? { interaction.armPlacingCard(.todo) } : { onAddCard(.todo) },
                onDouble: variant == .canvas ? { onAddCard(.todo) } : nil
            )

            DockToolButton(
                systemName: "safari",
                label: variant == .spaces ? "Add browser card" : "Preview — click to place, double-click to add",
                isArmed: variant == .canvas && interaction.isArmed(.placingCard(.browser)),
                onSingle: variant == .canvas ? { interaction.armPlacingCard(.browser) } : { onAddCard(.browser) },
                onDouble: variant == .canvas ? { onAddCard(.browser) } : nil
            )

            if variant == .canvas {
                DockDivider()

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

                DockDivider()

                DockButton(systemName: "scope", label: "Reset") {
                    store.resetViewport()
                }

                DockButton(
                    systemName: "map",
                    label: isMinimapVisible ? "Hide minimap" : "Show minimap",
                    isActive: isMinimapVisible
                ) {
                    onToggleMinimap()
                }

                DockDivider()

                DockAIHint(
                    errorMessage: errorMessage,
                    isActive: isAIHintActive,
                    action: onToggleAIHint
                )
            } else if errorMessage != nil {
                // Spaces has no AI hint, but a persistence error should still be
                // visible rather than silently swallowed; the button is inert here.
                DockDivider()

                DockAIHint(
                    errorMessage: errorMessage,
                    isActive: false,
                    action: {}
                )
            }

            if variant == .canvas {
                DockDivider()

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

private struct DockWorkspaceSegment: View {
    let workspaceName: String
    let cardCount: Int
    let isWorkspaceSidebarVisible: Bool
    let onToggle: () -> Void

    @State private var isHovering = false
    @Environment(\.theme) private var theme

    private var restingFill: Color {
        if isWorkspaceSidebarVisible {
            return theme.surface(isHovering ? 0.16 : 0.12)
        }
        return theme.surface(isHovering ? 0.06 : 0.0)
    }

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .center, spacing: 1) {
                Text(workspaceName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.ink(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(cardCount) \(cardCount == 1 ? "card" : "cards")")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.ink(0.5))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(maxWidth: 160, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(restingFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(
                        isWorkspaceSidebarVisible ? theme.ink(0.14) : .clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .animation(.easeInOut(duration: 0.15), value: isWorkspaceSidebarVisible)
        }
        .buttonStyle(DockPressStyle())
        .onHover { isHovering = $0 }
        .pointerCursor()
        .help(isWorkspaceSidebarVisible ? "Hide workspaces" : "Show workspaces")
    }
}

private struct DockPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct DockButton: View {
    let systemName: String
    let label: String
    var isActive: Bool = false
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(isActive ? theme.accent : theme.ink(0.86))
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(theme.surface(isActive ? 0.14 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            isActive ? theme.accent.opacity(0.55) : theme.ink(0.06),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(label)
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
}

/// A dock tool that distinguishes single-click (arm a canvas mode) from
/// double-click (instant create). Reuses DockAIHint's active treatment, driven
/// by `isArmed`. Tools without a double action pass `onDouble == nil`.
private struct DockToolButton: View {
    let systemName: String
    let label: String
    var isArmed: Bool = false
    var onSingle: () -> Void
    var onDouble: (() -> Void)? = nil

    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isArmed ? theme.accent : theme.ink(0.86))
            .frame(width: 40, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(theme.surface(isArmed ? 0.14 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(
                        isArmed ? theme.accent.opacity(0.55) : theme.ink(0.06),
                        lineWidth: isArmed ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .modifier(DockToolGesture(onSingle: onSingle, onDouble: onDouble))
            .pointerCursor()
            .help(label)
            .animation(.easeInOut(duration: 0.15), value: isArmed)
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

    // `sparkles` is Apple's de-facto AI/generate glyph and is available on the
    // macOS 14 target; it also avoids clashing with the Terminal tool's icon.
    // The error state keeps the warning triangle.
    private var iconName: String {
        errorMessage == nil ? "sparkles" : "exclamationmark.triangle"
    }

    private var accentColor: Color {
        errorMessage == nil ? theme.accent : .orange
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(theme.surface(isActive ? 0.14 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            isActive ? accentColor.opacity(0.55) : theme.ink(0.06),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(message)
    }
}
