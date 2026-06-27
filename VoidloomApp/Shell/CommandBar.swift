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
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .frame(width: 520)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(errorMessage == nil ? 0.13 : 0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 16)
    }
}

struct PersistenceErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 520)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.orange.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 10)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
