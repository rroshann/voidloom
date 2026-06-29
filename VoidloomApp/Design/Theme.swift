// VoidloomApp/Design/Theme.swift
import SwiftUI
import VoidloomCore

struct Theme {
    let colorScheme: ColorScheme?     // nil = follow system
    let accent: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let border: Color
    let gridMinor: Color
    let gridMajor: Color
    let canvasBackground: CanvasBackground
    let showVignette: Bool
    let fontScale: CGFloat
    let monospacedMetadata: Bool

    init(mode: AppearanceMode, accentHex: String, canvasBackground: CanvasBackground,
         backgroundContrast: Double, showVignette: Bool, textSize: TextSize,
         monospacedMetadata: Bool, reduceTransparency: Bool) {
        switch mode {
        case .system: colorScheme = nil
        case .light: colorScheme = .light
        case .dark: colorScheme = .dark
        }
        accent = Color(hex: accentHex)
        self.canvasBackground = canvasBackground
        self.showVignette = showVignette
        fontScale = CGFloat(textSize.fontScale)
        self.monospacedMetadata = monospacedMetadata

        // Dark-first palette. (Light palette is a follow-on.)
        let op: (Double) -> Double = { reduceTransparency ? min(1, $0 * 1.6) : $0 }
        primaryText = .white.opacity(op(0.92))
        secondaryText = .white.opacity(op(0.72))
        tertiaryText = .white.opacity(op(0.38))
        border = .white.opacity(op(0.08))
        let contrastK = backgroundContrast / 0.35
        gridMinor = .white.opacity(0.035 * contrastK)
        gridMajor = .white.opacity(0.085 * contrastK)
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
