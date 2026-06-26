import SwiftUI
import VoidloomCore

struct RootView: View {
    @ObservedObject var store: WorkspaceStore

    @State private var isWorkspaceSidebarVisible = false

    var body: some View {
        ZStack {
            AtmosphereBackground()

            CanvasWorkspaceView(store: store)
                .ignoresSafeArea()

            if isWorkspaceSidebarVisible {
                WorkspaceSidebar(cardCount: store.state.cards.count)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
            }

            VStack {
                HStack {
                    TopToolbar(
                        cardCount: store.state.cards.count,
                        isSidebarVisible: isWorkspaceSidebarVisible
                    ) {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            isWorkspaceSidebarVisible.toggle()
                        }
                    }
                    .padding(.top, 6)

                    Spacer()
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .zIndex(3)

            VStack {
                Spacer()

                ToolDock(store: store, errorMessage: store.lastPersistenceError)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .zIndex(2)
        }
        .animation(.easeInOut(duration: 0.24), value: isWorkspaceSidebarVisible)
        .preferredColorScheme(.dark)
    }
}

private struct WorkspaceSidebar: View {
    let cardCount: Int

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Workspaces")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.48))

                VStack(alignment: .leading, spacing: 10) {
                    WorkspaceSidebarRow(
                        title: "Main Canvas",
                        subtitle: "\(cardCount) cards",
                        isSelected: true
                    )

                    WorkspaceSidebarPlaceholder(title: "Research")
                    WorkspaceSidebarPlaceholder(title: "Launch Plan")
                }

                Spacer()

                Label("New Workspace", systemImage: "plus")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .help("Workspace creation is coming next")
            }
            .padding(.top, 76)
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(width: 300, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 32, x: 18, y: 0)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
    }
}

private struct WorkspaceSidebarRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.teal.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.teal)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.1 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(isSelected ? 0.12 : 0.06), lineWidth: 1)
        )
    }
}

private struct WorkspaceSidebarPlaceholder: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.06))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.34))
                )

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview("Voidloom Shell") {
    RootView(store: PreviewSupport.makeStore())
        .frame(width: 1180, height: 760)
}
