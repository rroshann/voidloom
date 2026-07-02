import SwiftUI

struct CanvasZoomControls: View {
    let scale: Double
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let isCardFocused: Bool
    let onToggleCardFocus: (() -> Void)?
    /// Whether a card is selected. The focus button is ALWAYS present; when no
    /// card is selected it renders disabled/darkened and does nothing.
    var isFocusEnabled: Bool = true
    /// When embedded inside the tool dock, render only the controls and let the
    /// dock supply the shared capsule background.
    var embedded: Bool = false
    @Environment(\.theme) private var theme

    private var zoomPercentage: Int {
        Int((scale * 100).rounded())
    }

    var body: some View {
        if embedded {
            controls
        } else {
            controls
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(theme.ink(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
        }
    }

    private var controls: some View {
        HStack(spacing: embedded ? DockMetrics.iconGap : 8) {
            zoomButton(
                systemName: "minus",
                label: "Zoom out",
                action: onZoomOut
            )

            Text("\(zoomPercentage)%")
                .font(.system(size: embedded ? 11 : 11, weight: .bold, design: .monospaced))
                .foregroundStyle(embedded ? .white.opacity(0.72) : theme.ink(0.72))
                .frame(minWidth: embedded ? 40 : 44)

            zoomButton(
                systemName: "plus",
                label: "Zoom in",
                action: onZoomIn
            )

            if embedded {
                focusButton
            } else {
                Divider()
                    .frame(height: 20)
                    .overlay(theme.ink(0.16))

                focusButton
            }
        }
        .animation(.easeOut(duration: 0.15), value: isFocusEnabled)
        .animation(.easeOut(duration: 0.15), value: isCardFocused)
    }

    @ViewBuilder
    private func zoomButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        if embedded {
            DockIconButton(icon: systemName, help: label, action: action)
        } else {
            CanvasZoomButton(
                systemName: systemName,
                label: label,
                action: action
            )
        }
    }

    @ViewBuilder
    private var focusButton: some View {
        let icon = isCardFocused
            ? "arrow.down.right.and.arrow.up.left"
            : "arrow.up.left.and.arrow.down.right"
        let label = isFocusEnabled
            ? (isCardFocused ? "Exit card focus" : "Focus selected card")
            : "Select a card to focus"

        if embedded {
            DockIconButton(
                icon: icon,
                help: label,
                isEnabled: isFocusEnabled,
                action: { onToggleCardFocus?() }
            )
        } else {
            CanvasZoomButton(
                systemName: icon,
                label: label,
                isEnabled: isFocusEnabled,
                action: { onToggleCardFocus?() }
            )
        }
    }
}

private struct CanvasZoomButton: View {
    let systemName: String
    let label: String
    var side: CGFloat = 28
    var iconSize: CGFloat = 12
    var cornerRadius: CGFloat = 10
    var isEnabled: Bool = true
    @Environment(\.theme) private var theme
    let action: () -> Void

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .bold))
                .frame(width: side, height: side)
                .foregroundStyle(theme.ink(isEnabled ? 0.84 : 0.22))
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(theme.surface(isEnabled ? 0.08 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.ink(isEnabled ? 0.1 : 0.04), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
        .modifier(ConditionalPointerCursor(isEnabled: isEnabled))
        .help(label)
    }
}

/// Applies the pointer cursor only when the control is interactive, so a
/// disabled button keeps the plain arrow signalling non-interactivity.
private struct ConditionalPointerCursor: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.pointerCursor()
        } else {
            content
        }
    }
}
