import SwiftUI

struct TopToolbar: View {
    let cardCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Text("VOIDLOOM")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(2.5)

            Divider()
                .frame(height: 18)
                .overlay(.white.opacity(0.25))

            Label("\(cardCount) cards", systemImage: "square.grid.3x2")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            Label("local canvas", systemImage: "externaldrive")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 18)
    }
}
