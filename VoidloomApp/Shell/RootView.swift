import SwiftUI
import AppKit
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
                SpacesShellView(
                    store: store,
                    sessionManager: sessionManager,
                    conversationStore: conversationStore
                )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: appMode)
        .onChange(of: store.library.workspaces.isEmpty) { _, isEmpty in
            // Deleting the last workspace from inside the app returns to the launcher
            // rather than leaving an empty canvas/space.
            if isEmpty { session.isWorkspaceOpen = false }
        }
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
            case .undo:
                if NSApp.keyWindow?.firstResponder is NSText {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } else {
                    store.undo()
                }
            case .redo:
                if NSApp.keyWindow?.firstResponder is NSText {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                } else {
                    store.redo()
                }
            case .copy:
                if NSApp.keyWindow?.firstResponder is NSText {
                    NSApp.sendAction(Selector(("copy:")), to: nil, from: nil)
                } else {
                    store.copySelection()
                }
            case .cut:
                if NSApp.keyWindow?.firstResponder is NSText {
                    NSApp.sendAction(Selector(("cut:")), to: nil, from: nil)
                } else {
                    store.cutSelection()
                }
            case .paste:
                if NSApp.keyWindow?.firstResponder is NSText {
                    NSApp.sendAction(Selector(("paste:")), to: nil, from: nil)
                } else {
                    store.pasteCards()
                }
            case .duplicate:
                if !(NSApp.keyWindow?.firstResponder is NSText) {
                    store.duplicateSelection()
                }
            case .setProjectFolder:
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Choose"
                if let current = store.state.space?.folderPath, !current.isEmpty {
                    panel.directoryURL = URL(fileURLWithPath: current)
                }
                if panel.runModal() == .OK, let url = panel.url {
                    store.setSpaceFolder(url.path)
                }
            case .zoomIn, .zoomOut, .resetViewport:
                break   // handled by CanvasShellView, which owns the zoom anchor
            }
        }
    }
}
