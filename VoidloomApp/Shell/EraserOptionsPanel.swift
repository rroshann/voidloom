import SwiftUI
import VoidloomCore

/// Options panel revealed above the dock while the eraser tool is armed. Bound
/// to the shared interaction model's eraser settings. Stage 3 wires these into
/// actual stroke erasing; the controls themselves are live.
struct EraserOptionsPanel: View {
    @ObservedObject var interaction: CanvasInteractionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "eraser.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.pink)
                Text("Eraser")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Thickness")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("\(Int(interaction.eraserThickness)) pt")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Slider(value: $interaction.eraserThickness, in: 8...120)
                    .tint(.pink)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Mode")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Picker("", selection: $interaction.eraserMode) {
                    Text("Whole stroke").tag(EraseMode.wholeStroke)
                    Text("Erase pixel").tag(EraseMode.segment)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 16)
    }
}
