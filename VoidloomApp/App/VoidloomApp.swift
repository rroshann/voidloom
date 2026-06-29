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

    @AppStorage("appearance.mode") private var appearanceMode: AppearanceMode = .system
    @AppStorage("appearance.accentHex") private var accentHex = "#5EE6D3"
    @AppStorage("appearance.canvasBackground") private var canvasBackground: CanvasBackground = .dots
    @AppStorage("appearance.backgroundContrast") private var backgroundContrast = 0.35
    @AppStorage("appearance.showVignette") private var showVignette = false
    @AppStorage("appearance.textSize") private var textSize: TextSize = .medium
    @AppStorage("appearance.monospacedMetadata") private var monospacedMetadata = true
    @AppStorage("appearance.reduceTransparency") private var reduceTransparency = false

    private var theme: Theme {
        Theme(
            mode: appearanceMode,
            accentHex: accentHex,
            canvasBackground: canvasBackground,
            backgroundContrast: backgroundContrast,
            showVignette: showVignette,
            textSize: textSize,
            monospacedMetadata: monospacedMetadata,
            reduceTransparency: reduceTransparency
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                store: store,
                sessionManager: agentSessionManager,
                conversationStore: conversationStore,
                interaction: interaction
            )
                .environmentObject(agentSessionManager)
                .environment(\.theme, theme)
                .preferredColorScheme(theme.colorScheme)
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
