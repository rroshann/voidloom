import AppKit
import SwiftUI
import VoidloomCore

@main
@MainActor
struct VoidloomApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var agentSessionManager = AgentSessionManager()
    @StateObject private var conversationStore = ConversationStore()
    @StateObject private var interaction = CanvasInteractionModel()

    var body: some Scene {
        WindowGroup {
            RootView(
                store: store,
                sessionManager: agentSessionManager,
                conversationStore: conversationStore,
                interaction: interaction
            )
                .environmentObject(agentSessionManager)
                .frame(minWidth: 1180, minHeight: 760)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    agentSessionManager.terminateAllSessions()
                    store.flushPendingPersistence()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)

        Settings {
            SettingsView()
        }
    }
}
