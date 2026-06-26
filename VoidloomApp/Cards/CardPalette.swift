import SwiftUI
import VoidloomCore

struct CardPalette {
    let accent: Color
    let symbol: String
    let eyebrow: String
    let shadow: Color

    init(kind: CardKind) {
        switch kind {
        case .agent:
            accent = Color(red: 0.34, green: 0.93, blue: 0.82)
            symbol = "sparkles"
            eyebrow = "agent"
            shadow = Color(red: 0.0, green: 0.45, blue: 0.42).opacity(0.22)
        case .note:
            accent = Color(red: 0.93, green: 0.71, blue: 0.36)
            symbol = "note.text"
            eyebrow = "note"
            shadow = Color(red: 0.55, green: 0.32, blue: 0.08).opacity(0.22)
        case .todo:
            accent = Color(red: 0.75, green: 0.63, blue: 1.0)
            symbol = "checklist"
            eyebrow = "todo"
            shadow = Color(red: 0.35, green: 0.23, blue: 0.75).opacity(0.22)
        case .browser:
            accent = Color(red: 0.48, green: 0.76, blue: 1.0)
            symbol = "safari"
            eyebrow = "preview"
            shadow = Color(red: 0.05, green: 0.27, blue: 0.58).opacity(0.22)
        }
    }
}
