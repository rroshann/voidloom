import Foundation
import VoidloomCore

/// Small utilities for a workspace's project folder. The folder is chosen once in
/// the New Project dialog and is not editable afterward, so this no longer owns a
/// picker — just naming and git detection.
@MainActor
enum WorkspaceFolder {
    /// The next "Untitled"/"Untitled N" name, matching the existing creation UIs.
    static func nextUntitledName(in store: WorkspaceStore) -> String {
        let count = store.library.workspaces.filter { $0.name.hasPrefix("Untitled") }.count
        return count == 0 ? "Untitled" : "Untitled \(count + 1)"
    }

    /// True when `path` (or an ancestor) contains a `.git` entry — so subfolders
    /// of a repo count, and `.git` files (worktrees/submodules) count too.
    nonisolated static func isGitRepository(_ path: String) -> Bool {
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
