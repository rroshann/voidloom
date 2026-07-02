import SwiftUI

/// Shared sizing for bottom docks — slim floating glass bars.
enum DockMetrics {
    static let iconSide: CGFloat = 34
    static let glyphSize: CGFloat = 18
    static let iconGap: CGFloat = 3
    static let groupGap: CGFloat = 12
}

/// The dock's single Liquid-Glass sheet. Uses Apple's real `.glassEffect` on
/// macOS 26+, and a translucent frosted-material fallback (with a faint rim) on
/// older systems. `.clear` is the high-transparency variant, so the background
/// bleeds strongly through the dock.
struct DockGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: shape)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial).opacity(0.7))
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }
}

/// Monochrome glyph affordance shared by dock icon buttons and gesture-based tools.
struct DockIconGlyph: View {
    let icon: String
    var side: CGFloat = DockMetrics.iconSide
    var glyph: CGFloat = DockMetrics.glyphSize
    var isActive: Bool = false
    var activeColor: Color? = nil
    var isEnabled: Bool = true

    @Environment(\.theme) private var theme
    @State private var hovering = false

    private var glyphColor: Color {
        if !isEnabled { return .white.opacity(0.32) }
        if isActive { return activeColor ?? theme.accent }
        return .white.opacity(0.95)
    }

    private var fillOpacity: Double {
        if !isEnabled { return 0 }
        if isActive { return 0.22 }
        return hovering ? 0.16 : 0
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: glyph, weight: .semibold))
            .foregroundStyle(glyphColor)
            .frame(width: side, height: side)
            .background(
                Circle().fill(.white.opacity(fillOpacity))
            )
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

/// A plain monochrome glyph button that lives directly on the dock glass (no
/// glass of its own). A faint fill fades in on hover; active tools get a
/// brighter/accent-tinted glyph and subtle fill.
struct DockIconButton: View {
    let icon: String
    let help: String
    var side: CGFloat = DockMetrics.iconSide
    var glyph: CGFloat = DockMetrics.glyphSize
    var isActive: Bool = false
    var activeColor: Color? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            DockIconGlyph(
                icon: icon,
                side: side,
                glyph: glyph,
                isActive: isActive,
                activeColor: activeColor,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
        .help(help)
    }
}
