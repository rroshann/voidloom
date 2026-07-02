import SwiftUI
import VoidloomCore

/// Top-level shell: switches between the free pan/zoom Canvas presentation and
/// the auto-tiled Spaces presentation based on the persisted `app.mode` flag.
/// Both shells render the same active `WorkspaceState`; the flag is UI-only and
/// never touches workspace data, so switching is lossless.
struct RootView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @ObservedObject var conversationStore: ConversationStore
    @ObservedObject var interaction: CanvasInteractionModel

    @EnvironmentObject private var session: AppSession

    @AppStorage("app.mode") private var appMode: AppMode = .canvas
    @AppStorage("isWorkspaceSidebarVisible") private var isWorkspaceSidebarVisible = false
    @AppStorage("isMinimapVisible") private var isMinimapVisible = false

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
        .onReceive(NotificationCenter.default.publisher(for: MenuAction.notification)) { note in
            guard let action = note.object as? MenuAction else { return }
            switch action {
            case .toggleAppMode:
                appMode = appMode == .canvas ? .spaces : .canvas
            case .toggleWorkspaceSidebar:
                isWorkspaceSidebarVisible.toggle()
            case .toggleMinimap:
                isMinimapVisible.toggle()
            case .addCard(let kind):
                store.addCard(kind: kind)
            case .goToLauncher:
                session.isWorkspaceOpen = false
            case .zoomIn, .zoomOut, .resetViewport:
                break   // handled by CanvasShellView, which owns the zoom anchor
            }
        }
    }
}
