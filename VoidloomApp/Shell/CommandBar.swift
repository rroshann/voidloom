import SwiftUI

struct CommandBar: View {
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: errorMessage == nil ? "terminal" : "exclamationmark.triangle")
                .foregroundStyle(errorMessage == nil ? .teal : .orange)

            Text(errorMessage ?? "Try: add agent, add note, reset canvas")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(errorMessage == nil ? 0.68 : 0.86))

            Spacer(minLength: 0)
        }
        .frame(width: 520)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 16)
    }
}
