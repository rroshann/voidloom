import SwiftUI
import VoidloomCore

struct CardPalette {
    let accent: Color
    let symbol: String
    let eyebrow: String
    let shadow: Color

    /// Accents are tuned for dark glass; pass `isDark: false` to darken them
    /// (same factor as the theme accent) so they stay legible on light surfaces.
    init(kind: CardKind, isDark: Bool = true) {
        let bright: Color
        switch kind {
        case .agent:
            bright = Color(red: 0.34, green: 0.93, blue: 0.82)
            symbol = "terminal"
            eyebrow = "terminal"
            shadow = Color(red: 0.0, green: 0.45, blue: 0.42).opacity(0.22)
        case .note:
            bright = Color(red: 0.93, green: 0.71, blue: 0.36)
            symbol = "note.text"
            eyebrow = "note"
            shadow = Color(red: 0.55, green: 0.32, blue: 0.08).opacity(0.22)
        case .todo:
            bright = Color(red: 0.75, green: 0.63, blue: 1.0)
            symbol = "checklist"
            eyebrow = "todo"
            shadow = Color(red: 0.35, green: 0.23, blue: 0.75).opacity(0.22)
        case .browser:
            bright = Color(red: 0.48, green: 0.76, blue: 1.0)
            symbol = "safari"
            eyebrow = "preview"
            shadow = Color(red: 0.05, green: 0.27, blue: 0.58).opacity(0.22)
        case .fileBrowser:
            bright = Color(red: 0.62, green: 0.82, blue: 0.62)
            symbol = "folder"
            eyebrow = "files"
            shadow = Color(red: 0.16, green: 0.40, blue: 0.16).opacity(0.22)
        case .git:
            bright = Color(red: 0.98, green: 0.58, blue: 0.40)
            symbol = "arrow.triangle.branch"
            eyebrow = "git"
            shadow = Color(red: 0.55, green: 0.22, blue: 0.10).opacity(0.22)
        }
        accent = isDark ? bright : bright.darkened(Theme.lightAccentFactor)
    }
}
