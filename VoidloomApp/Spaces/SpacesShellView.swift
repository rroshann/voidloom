import SwiftUI
import VoidloomCore

struct SpacesShellView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager

    var body: some View {
        ZStack {
            AtmosphereBackground()
            Text("Spaces — coming together")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .preferredColorScheme(.dark)
    }
}
