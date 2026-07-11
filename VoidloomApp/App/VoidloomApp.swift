import AppKit
import SwiftUI
import VoidloomAI
import VoidloomCore

@main
@MainActor
struct VoidloomApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var agentSessionManager = AgentSessionManager()
    /// App-scoped (not window-scoped) so closing the window and reopening it
    /// drops back into the workspace that was open — pairing with the agent
    /// sessions that survive the window. A cold launch still shows the launcher.
    @StateObject private var appSession = AppSession()
    @StateObject private var modelAssets: ModelAssetManager
    @StateObject private var conversationStore: ConversationStore
    /// The launch-time chat backend, shared by the sidebar and the mediator's
    /// conversational fallback so both always answer with the same voice.
    private let chatProvider: ResponseProvider

    init() {
        let assets = ModelAssetManager()
        _modelAssets = StateObject(wrappedValue: assets)

        let persona = AssistantIdentity.systemPrompt()
        let provider: ResponseProvider
        if #available(macOS 26, *), AppleTierAvailability.foundationModelsAvailable {
            provider = FoundationModelsResponseProvider(systemPrompt: persona)
        } else if assets.state(of: LocalModelManifest.chatModel) == .ready,
                  let url = assets.localURL(of: LocalModelManifest.chatModel) {
            let engine = LazyLoadingEngine(
                modelURL: url,
                config: LlamaEngineConfig(contextLength: 4096))
            provider = LocalResponseProvider(engine: engine, systemPrompt: persona)
        } else {
            provider = StubResponseProvider()
        }
        chatProvider = provider
        _conversationStore = StateObject(wrappedValue: ConversationStore(provider: provider))
    }

    var body: some Scene {
        WindowGroup {
            // Theme is built inside RootThemeHost (a View) rather than here in the
            // App struct, so it can read the live `@Environment(\.colorScheme)` and
            // make the "System" appearance option follow the OS light/dark setting.
            RootThemeHost(
                store: store,
                sessionManager: agentSessionManager,
                conversationStore: conversationStore,
                modelAssets: modelAssets,
                chatProvider: chatProvider,
                session: appSession
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands { VoidloomCommands() }

        Settings {
            SettingsView()
                .environmentObject(modelAssets)
                .environmentObject(store)
                .environmentObject(agentSessionManager)
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
    @ObservedObject var modelAssets: ModelAssetManager
    let chatProvider: ResponseProvider

    /// Launch shows the startup screen; opening/creating a workspace flips this.
    /// Owned by the App (not this window-scoped view), so it survives window
    /// close/reopen.
    @ObservedObject var session: AppSession

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
        Group {
            if session.isWorkspaceOpen {
                RootView(
                    store: store,
                    sessionManager: sessionManager,
                    conversationStore: conversationStore,
                    modelAssets: modelAssets,
                    chatProvider: chatProvider
                )
            } else {
                StartupView(store: store)
            }
        }
        .environmentObject(session)
        .sheet(isPresented: $session.showNewWorkspace) {
            NewWorkspaceSheet(store: store)
                .environment(\.theme, theme)
                .environmentObject(session)
        }
        .environmentObject(sessionManager)
        .environmentObject(modelAssets)
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
