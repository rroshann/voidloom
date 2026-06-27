import SwiftUI

struct CanvasZoomControls: View {
    let scale: Double
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onReset: () -> Void

    private var zoomPercentage: Int {
        Int((scale * 100).rounded())
    }

    var body: some View {
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

            CanvasZoomButton(systemName: "arrow.up.left.and.arrow.down.right", label: "Fit canvas", action: onReset)
        }
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

private struct CanvasZoomButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .foregroundStyle(.white.opacity(0.84))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }
}
