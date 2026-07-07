// VoidloomApp/Design/Theme.swift
import SwiftUI
import VoidloomCore

struct Theme {
    let isDark: Bool
    let colorScheme: ColorScheme?
    let accent: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let border: Color
    let gridMinor: Color
    let gridMajor: Color
    let atmosphereStops: [Color]
    let vignetteColor: Color
    let canvasBackground: CanvasBackground
    let showVignette: Bool
    let fontScale: CGFloat
    let monospacedMetadata: Bool
    private let reduceTransparency: Bool

    /// `systemColorScheme` is the live macOS appearance (from `@Environment(\.colorScheme)`),
    /// used only when `mode == .system` so "System" follows the OS light/dark setting
    /// and updates live. It defaults to `.dark` when absent to preserve prior behavior.
    init(mode: AppearanceMode, systemColorScheme: ColorScheme? = nil, accentHex: String,
         canvasBackground: CanvasBackground,
         backgroundContrast: Double, showVignette: Bool, textSize: TextSize,
         monospacedMetadata: Bool, reduceTransparency: Bool) {
        let dark: Bool
        switch mode {
        case .light: dark = false
        case .dark: dark = true
        case .system: dark = (systemColorScheme ?? .dark) == .dark
        }
        self.isDark = dark
        self.colorScheme = (mode == .system) ? nil : (mode == .light ? .light : .dark)
        self.accent = Color(hex: accentHex)
        self.canvasBackground = canvasBackground
        self.showVignette = showVignette
        self.fontScale = CGFloat(textSize.fontScale)
        self.monospacedMetadata = monospacedMetadata
        self.reduceTransparency = reduceTransparency

        let op: (Double) -> Double = { reduceTransparency ? min(1, $0 * 1.6) : $0 }
        let k = backgroundContrast / 0.35

        if dark {
            primaryText   = .white.opacity(op(0.92))
            secondaryText = .white.opacity(op(0.72))
            tertiaryText  = .white.opacity(op(0.38))
            border        = .white.opacity(op(0.08))
            gridMinor     = .white.opacity(0.035 * k)
            gridMajor     = .white.opacity(0.085 * k)
            atmosphereStops = [
                Color(red: 0.04, green: 0.05, blue: 0.07),
                Color(red: 0.08, green: 0.08, blue: 0.11),
                Color(red: 0.02, green: 0.09, blue: 0.11)
            ]
            vignetteColor = .black
        } else {
            // Near-black at a low opacity on a light background reads much fainter
            // than white at the same opacity on a dark one, so boost the faint end
            // for legibility (the strong end is already near-solid).
            primaryText   = Color(white: 0.08).opacity(Self.lightLegibility(op(0.92)))
            secondaryText = Color(white: 0.08).opacity(Self.lightLegibility(op(0.72)))
            tertiaryText  = Color(white: 0.08).opacity(Self.lightLegibility(op(0.38)))
            border        = Color.black.opacity(op(0.12))
            gridMinor     = .black.opacity(0.05 * k)
            gridMajor     = .black.opacity(0.10 * k)
            atmosphereStops = [
                Color(red: 0.96, green: 0.96, blue: 0.98),
                Color(red: 0.93, green: 0.94, blue: 0.96),
                Color(red: 0.90, green: 0.93, blue: 0.95)
            ]
            vignetteColor = .black
        }
    }

    func ink(_ opacity: Double) -> Color {
        let boosted = reduceTransparency ? Swift.min(1, opacity * 1.6) : opacity
        return isDark ? Color.white.opacity(boosted) : Color(white: 0.08).opacity(Self.lightLegibility(boosted))
    }

    func surface(_ opacity: Double) -> Color {
        let boosted = reduceTransparency ? Swift.min(1, opacity * 1.6) : opacity
        return isDark ? Color.white.opacity(boosted) : Color.black.opacity(Self.lightLegibility(boosted))
    }

    /// Lifts faint (< 0.5) opacities in light mode for legible contrast on a
    /// light background; leaves the strong end alone.
    private static func lightLegibility(_ opacity: Double) -> Double {
        opacity < 0.5 ? Swift.min(1, opacity * 1.7) : opacity
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(mode: .dark, accentHex: "#5EE6D3", canvasBackground: .dots,
                                    backgroundContrast: 0.35, showVignette: false, textSize: .medium,
                                    monospacedMetadata: true, reduceTransparency: false)
}
extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] } set { self[ThemeKey.self] = newValue }
    }
}
