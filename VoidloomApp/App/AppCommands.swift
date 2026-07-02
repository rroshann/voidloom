import SwiftUI
import VoidloomCore

/// An app-wide menu action. Menu items post these through NotificationCenter;
/// the view that owns the right context performs them — RootView for store and
/// AppStorage toggles, CanvasShellView for zoom (it owns the window geometry
/// the zoom anchor needs).
enum MenuAction {
    case toggleAppMode
    case toggleWorkspaceSidebar
    case toggleMinimap
    case addCard(CardKind)
    case zoomIn
    case zoomOut
    case resetViewport
    case goToLauncher

    static let notification = Notification.Name("voidloom.menuAction")

    func post() {
        NotificationCenter.default.post(name: Self.notification, object: self)
    }
}

/// Menu-bar commands and their keyboard shortcuts.
struct VoidloomCommands: Commands {
    var body: some Commands {
        CommandMenu("Cards") {
            Button("New Agent") { MenuAction.addCard(.agent).post() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("New Note") { MenuAction.addCard(.note).post() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Todo") { MenuAction.addCard(.todo).post() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("New Browser") { MenuAction.addCard(.browser).post() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Divider()
            Button("Go to Launcher") { MenuAction.goToLauncher.post() }
                .keyboardShortcut("l", modifiers: [.command, .shift, .option])
            Button("Toggle Spaces / Canvas") { MenuAction.toggleAppMode.post() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Toggle Workspace Sidebar") { MenuAction.toggleWorkspaceSidebar.post() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Toggle Minimap") { MenuAction.toggleMinimap.post() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            Button("Zoom In") { MenuAction.zoomIn.post() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Zoom Out") { MenuAction.zoomOut.post() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Viewport") { MenuAction.resetViewport.post() }
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}
