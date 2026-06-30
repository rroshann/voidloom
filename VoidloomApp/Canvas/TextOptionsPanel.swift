import SwiftUI
import VoidloomCore

/// Options panel revealed above the dock while the text tool is armed or a text
/// element is selected. When an element is selected it edits that element live
/// (font size / font / color); otherwise it edits the interaction defaults that
/// seed newly created text elements. Mirrors `BrushOptionsPanel` styling.
struct TextOptionsPanel: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var interaction: CanvasInteractionModel
    @Environment(\.theme) private var theme

    /// Curated font set. A nil name means the default system-rounded face.
    private let fonts: [(label: String, name: String?)] = [
        ("System Rounded", nil),
        ("Helvetica Neue", "HelveticaNeue"),
        ("Georgia", "Georgia"),
        ("Menlo", "Menlo"),
        ("Courier", "Courier"),
        ("Avenir Next", "AvenirNext-Regular")
    ]

    private let presets: [Color] = [
        .white,
        Color(red: 0.34, green: 0.93, blue: 0.82),
        Color(red: 0.93, green: 0.71, blue: 0.36),
        Color(red: 0.75, green: 0.63, blue: 1.0),
        Color(red: 0.48, green: 0.76, blue: 1.0),
        Color(red: 0.96, green: 0.45, blue: 0.55)
    ]

    private var selectedElement: TextElement? {
        guard let id = store.state.selectedTextID else { return nil }
        return store.state.textElements.first(where: { $0.id == id })
    }

    private var fontSize: Double { selectedElement?.fontSize ?? interaction.textFontSize }

    private var fontName: String? {
        if let element = selectedElement { return element.fontName }
        return interaction.textFontName
    }

    private var color: Color {
        if let element = selectedElement {
            return Color(hexString: element.colorHex) ?? .white
        }
        return interaction.textColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "textformat")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(selectedElement == nil ? "Text Defaults" : "Text")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.ink(0.9))
                Spacer(minLength: 0)
                preview
            }

            HStack(spacing: 8) {
                ColorPicker("", selection: colorBinding, supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 30)

                ForEach(Array(presets.enumerated()), id: \.offset) { _, swatch in
                    Button {
                        applyColor(swatch)
                    } label: {
                        Circle()
                            .fill(swatch)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(theme.ink(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Font")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.ink(0.6))
                Picker("", selection: fontBinding) {
                    ForEach(fonts, id: \.label) { font in
                        Text(font.label).tag(font.name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Size")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.ink(0.6))
                    Spacer()
                    Text("\(Int(fontSize)) pt")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.ink(0.75))
                }
                Slider(value: fontSizeBinding, in: 8...96)
                    .tint(theme.accent)
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.ink(0.13), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 16)
    }

    private var preview: some View {
        Text("Ag")
            .font(previewFont)
            .foregroundStyle(color)
            .frame(height: 24)
    }

    private var previewFont: Font {
        let size = max(12, min(fontSize, 22))
        if let name = fontName {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: .semibold, design: .rounded)
    }

    // MARK: - Bindings (write to the selected element, else the defaults)

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { fontSize },
            set: { newValue in
                if let id = store.state.selectedTextID {
                    store.updateTextElementFontSize(id: id, to: newValue)
                } else {
                    interaction.textFontSize = newValue
                }
            }
        )
    }

    private var fontBinding: Binding<String?> {
        Binding(
            get: { fontName },
            set: { newValue in
                if let id = store.state.selectedTextID {
                    store.updateTextElementFont(id: id, to: newValue)
                } else {
                    interaction.textFontName = newValue
                }
            }
        )
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { color },
            set: { applyColor($0) }
        )
    }

    private func applyColor(_ newColor: Color) {
        if let id = store.state.selectedTextID {
            store.updateTextElementColor(id: id, toHex: newColor.hexStringRGBA)
        } else {
            interaction.textColor = newColor
        }
    }
}
