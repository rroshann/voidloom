import AppKit
import SwiftUI
import VoidloomAI
import VoidloomCore

@main
@MainActor
struct VoidloomApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var agentSessionManager = AgentSessionManager()
    @StateObject private var conversationStore = ConversationStore()
    @StateObject private var interaction = CanvasInteractionModel()
    @StateObject private var modelAssets = ModelAssetManager()

    var body: some Scene {
        WindowGroup {
            // Theme is built inside RootThemeHost (a View) rather than here in the
            // App struct, so it can read the live `@Environment(\.colorScheme)` and
            // make the "System" appearance option follow the OS light/dark setting.
            RootThemeHost(
                store: store,
                sessionManager: agentSessionManager,
                conversationStore: conversationStore,
                interaction: interaction,
                modelAssets: modelAssets
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)

        Settings {
            SettingsView()
        }
    }
}

/// Hosts `RootView` and builds the `Theme` from the appearance settings plus the
/// live macOS color scheme. Living as a `View` (not the `App` struct) lets it read
/// `@Environment(\.colorScheme)`, so `AppearanceMode.system` resolves to the actual
/// OS appearance and flips live when the user changes it.
private struct RootThemeHost: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @ObservedObject var conversationStore: ConversationStore
    @ObservedObject var interaction: CanvasInteractionModel
    @ObservedObject var modelAssets: ModelAssetManager

    @Environment(\.colorScheme) private var systemColorScheme

    @AppStorage("appearance.mode") private var appearanceMode: AppearanceMode = .dark
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
            systemColorScheme: systemColorScheme,
            accentHex: accentHex,
            canvasBackground: canvasBackground,
            backgroundContrast: backgroundContrast,
            showVignette: showVignette,
            textSize: textSize,
            monospacedMetadata: monospacedMetadata,
            reduceTransparency: reduceTransparency
        )
    }

    var body: some View {
        let theme = theme
        RootView(
            store: store,
            sessionManager: sessionManager,
            conversationStore: conversationStore,
            interaction: interaction,
            modelAssets: modelAssets
        )
        .environmentObject(sessionManager)
        .environment(\.theme, theme)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.accent)
        .frame(minWidth: 1180, minHeight: 760)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            sessionManager.terminateAllSessions()
            store.flushPendingPersistence()
            store.markCleanShutdown()
        }
    }
}
