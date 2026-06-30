import SwiftUI
import VoidloomCore

struct SpacesShellView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager

    var body: some View {
        ZStack {
            SpaceBackgroundView(
                background: store.state.space?.background ?? .atmosphere,
                dimming: store.state.space?.backgroundDimming ?? 0.35,
                backgroundsDirectory: store.backgroundsDirectoryURL()
            )
            Text("Spaces — coming together")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .preferredColorScheme(.dark)
    }
}
