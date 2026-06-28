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
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            CanvasZoomButton(systemName: "minus", label: "Zoom out", action: onZoomOut)

            Text("\(zoomPercentage)%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.72))
                .frame(minWidth: 44)

            CanvasZoomButton(systemName: "plus", label: "Zoom in", action: onZoomIn)

            Divider()
                .frame(height: 20)
                .overlay(.white.opacity(0.16))

            CanvasZoomButton(
                systemName: isCardFocused
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right",
                label: isFocusEnabled
                    ? (isCardFocused ? "Exit card focus" : "Focus selected card")
                    : "Select a card to focus",
                isEnabled: isFocusEnabled,
                action: { onToggleCardFocus?() }
            )
        }
        .animation(.easeOut(duration: 0.15), value: isFocusEnabled)
        .animation(.easeOut(duration: 0.15), value: isCardFocused)
    }
}

private struct CanvasZoomButton: View {
    let systemName: String
    let label: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .foregroundStyle(.white.opacity(isEnabled ? 0.84 : 0.22))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(isEnabled ? 0.08 : 0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(isEnabled ? 0.1 : 0.04), lineWidth: 1)
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
