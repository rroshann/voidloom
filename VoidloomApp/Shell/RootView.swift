import SwiftUI
import VoidloomCore

/// Top-level shell: switches between the free-canvas presentation and the
/// auto-tiled Spaces presentation based on the persisted `app.mode` flag. Both
/// shells render the same active `WorkspaceState`; the flag is UI-only and never
/// touches workspace data.
struct RootView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @ObservedObject var conversationStore: ConversationStore
    @ObservedObject var interaction: CanvasInteractionModel

    @AppStorage("app.mode") private var appMode: AppMode = .canvas

    var body: some View {
        ZStack {
            switch appMode {
            case .canvas:
                CanvasShellView(
                    store: store,
                    sessionManager: sessionManager,
                    conversationStore: conversationStore,
                    interaction: interaction
                )
                .transition(.opacity)
            case .spaces:
                SpacesShellView(store: store, sessionManager: sessionManager)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: appMode)
    }
}
