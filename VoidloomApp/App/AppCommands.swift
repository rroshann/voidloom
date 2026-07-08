import SwiftUI
import VoidloomCore

/// An app-wide menu action. Menu items post these through NotificationCenter;
/// the view that owns the right context performs them (mostly RootView). Board
/// zoom/minimap live on `SpacesShellView`'s own key monitor (⌘=/-/0, ⌘⇧M), not
/// here, since they need the Board viewport + window geometry.
enum MenuAction {
    case addCard(CardKind)
    case goToLauncher
    case undo
    case redo
    case copy
    case cut
    case paste
    case duplicate
    case setProjectFolder
    case focusMediator
    /// Toggle the right-side assistant (Sunday) conversation sidebar.
    case toggleAIConversation
    /// Run a command through the mediator (e.g. tapping an empty-state hint chip).
    case runMediatorCommand(String)

    static let notification = Notification.Name("voidloom.menuAction")

    func post() {
        NotificationCenter.default.post(name: Self.notification, object: self)
    }
}

/// Menu-bar commands and their keyboard shortcuts.
struct VoidloomCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { MenuAction.undo.post() }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo") { MenuAction.redo.post() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { MenuAction.cut.post() }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copy") { MenuAction.copy.post() }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste") { MenuAction.paste.post() }
                .keyboardShortcut("v", modifiers: .command)
        }

        CommandGroup(after: .pasteboard) {
            Button("Duplicate") { MenuAction.duplicate.post() }
                .keyboardShortcut("d", modifiers: .command)
        }

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
            Button("Focus Mediator") { MenuAction.focusMediator.post() }
                .keyboardShortcut("j", modifiers: .command)
            Button("Toggle Assistant") { MenuAction.toggleAIConversation.post() }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Go to Launcher") { MenuAction.goToLauncher.post() }
                .keyboardShortcut("l", modifiers: [.command, .shift, .option])
            Divider()
            Button("Set Project Folder…") { MenuAction.setProjectFolder.post() }
        }
    }
}
