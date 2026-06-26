import SwiftUI

struct TopToolbar: View {
    let cardCount: Int
    let isSidebarVisible: Bool
    let onToggleSidebar: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 24)
                    .foregroundStyle(.white.opacity(isSidebarVisible ? 0.94 : 0.74))
                    .background(
                        Capsule()
                            .fill(.white.opacity(isSidebarVisible ? 0.12 : 0.06))
                    )
            }
            .buttonStyle(.plain)
            .help(isSidebarVisible ? "Hide workspaces" : "Show workspaces")

            Divider()
                .frame(height: 14)
                .overlay(.white.opacity(0.18))

            Text("VOIDLOOM")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.86))

            Divider()
                .frame(height: 14)
                .overlay(.white.opacity(0.18))

            Text("\(cardCount) cards")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
    }
}
