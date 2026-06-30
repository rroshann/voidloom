import SwiftUI
import VoidloomCore

/// Options panel revealed above the dock while the brush tool is armed. Bound
/// directly to the shared interaction model's brush settings. Stage 3 wires
/// these values into actual stroke drawing; the controls themselves are live.
struct BrushOptionsPanel: View {
    @ObservedObject var interaction: CanvasInteractionModel
    @Environment(\.theme) private var theme

    private let presets: [Color] = [
        Color(red: 0.34, green: 0.93, blue: 0.82),
        Color(red: 0.93, green: 0.71, blue: 0.36),
        Color(red: 0.75, green: 0.63, blue: 1.0),
        Color(red: 0.48, green: 0.76, blue: 1.0),
        Color(red: 0.96, green: 0.45, blue: 0.55),
        .white
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text("Brush")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.ink(0.9))
                Spacer(minLength: 0)
                strokePreview
            }

            HStack(spacing: 8) {
                ColorPicker("", selection: $interaction.brushColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 30)

                ForEach(Array(presets.enumerated()), id: \.offset) { _, color in
                    Button {
                        interaction.brushColor = color
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle().stroke(theme.ink(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }

            labeledSlider(
                title: "Thickness",
                value: $interaction.brushThickness,
                range: 1...40,
                valueText: "\(Int(interaction.brushThickness)) pt"
            )

            labeledSlider(
                title: "Opacity",
                value: $interaction.brushOpacity,
                range: 0.1...1,
                valueText: "\(Int(interaction.brushOpacity * 100))%"
            )
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

    private var strokePreview: some View {
        Capsule()
            .fill(interaction.brushColor.opacity(interaction.brushOpacity))
            .frame(width: 60, height: max(2, min(interaction.brushThickness, 18)))
    }

    private func labeledSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.ink(0.6))
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.ink(0.75))
            }
            Slider(value: value, in: range)
                .tint(theme.accent)
        }
    }
}
