// VoidloomApp/Design/Color+Hex.swift
import SwiftUI

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
    func toHex() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        // Clamp (wide-gamut components can fall outside 0...1) and ROUND rather
        // than truncate: truncation always biases down, so a get/set round-trip
        // through the ColorPicker binding would darken the color every drag frame
        // and drift to black. Rounding lands on a stable 1/255 grid value.
        func channel(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X",
                      channel(ns.redComponent), channel(ns.greenComponent), channel(ns.blueComponent))
    }

    /// Scales the RGB channels toward black, keeping the hue. Used to darken
    /// accents in light mode, where the dark-tuned pastels wash out.
    func darkened(_ factor: Double) -> Color {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(red: ns.redComponent * factor,
                     green: ns.greenComponent * factor,
                     blue: ns.blueComponent * factor,
                     opacity: ns.alphaComponent)
    }
}
