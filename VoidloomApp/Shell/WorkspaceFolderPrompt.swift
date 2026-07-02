import AppKit
import Foundation
import VoidloomCore

/// Shared helpers for associating a workspace with a project folder. The folder
/// is stored on the space (`SpaceConfig.folderPath`) and powers the Files and
/// Git cards. AppKit-based (NSOpenPanel), so it lives in the app layer.
@MainActor
enum WorkspaceFolder {
    /// The next "Untitled"/"Untitled N" name, matching the existing creation UIs.
    static func nextUntitledName(in store: WorkspaceStore) -> String {
        let count = store.library.workspaces.filter { $0.name.hasPrefix("Untitled") }.count
        return count == 0 ? "Untitled" : "Untitled \(count + 1)"
    }

    /// Creates a new workspace (which becomes active) and immediately prompts for
    /// its project folder. Cancelling the picker just leaves the folder unset —
    /// the Files/Git cards can set it later.
    static func createWorkspaceAndPromptForFolder(store: WorkspaceStore) {
        let before = store.library.selectedWorkspaceID
        let name = nextUntitledName(in: store)
        store.createWorkspace(named: name)
        // createWorkspace is a no-op outside library mode; only prompt if a new
        // workspace actually became active.
        guard store.library.selectedWorkspaceID != before else { return }
        promptForFolder(store: store, workspaceName: name)
    }

    /// Opens a folder picker and, on confirmation, sets it on the active space.
    static func promptForFolder(store: WorkspaceStore, workspaceName: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a project folder for “\(workspaceName)”. "
            + "It powers the Files and Git cards — you can skip and set it later."
        if let current = store.state.space?.folderPath, !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        if panel.runModal() == .OK, let url = panel.url {
            store.setSpaceFolder(url.path)
        }
    }

    /// True when `path` (or an ancestor) contains a `.git` entry — so subfolders
    /// of a repo count, and `.git` files (worktrees/submodules) count too.
    static func isGitRepository(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        var url = URL(fileURLWithPath: path)
        while true {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) { return true }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return false }   // reached filesystem root
            url = parent
        }
    }
}
