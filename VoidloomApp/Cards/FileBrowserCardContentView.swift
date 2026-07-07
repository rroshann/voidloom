import AppKit
import SwiftUI
import VoidloomCore

/// A lazily-expanding file tree rooted at the space's folder. Directories can be
/// expanded inline; double-clicking a file opens it in the default app. The
/// folder is fixed at workspace creation and can't be changed from here.
struct FileBrowserCardContentView: View {
    @ObservedObject var store: WorkspaceStore
    let accent: Color

    private var folderPath: String? { store.state.space?.folderPath }

    var body: some View {
        Group {
            if let folderPath, !folderPath.isEmpty {
                tree(for: URL(fileURLWithPath: folderPath))
            } else {
                CardFolderMissing(
                    message: "No project folder is set for this workspace."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tree(for root: URL) -> some View {
        VStack(spacing: 0) {
            FolderBar(url: root, accent: accent)

            Divider().overlay(.white.opacity(0.08))

            List {
                OutlineGroup(FileNode(url: root).children ?? [], children: \.children) { node in
                    Label(node.name, systemImage: node.isDirectory ? "folder.fill" : "doc")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(node.isDirectory ? 0.92 : 0.78))
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            if !node.isDirectory { NSWorkspace.shared.open(node.url) }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .tint(accent)
        }
    }
}

/// A folder/file node that lists its children lazily (directories first, then
/// files; hidden dot-entries skipped). Identity is the URL, so OutlineGroup keeps
/// expansion stable across re-renders.
struct FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool

    init(url: URL) {
        self.url = url
        self.isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    var id: URL { url }
    var name: String { url.lastPathComponent }

    /// nil for files (leaf); the sorted child nodes for directories.
    var children: [FileNode]? {
        guard isDirectory else { return nil }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let nodes = entries.map(FileNode.init(url:))
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

/// The read-only folder name shown atop a folder-backed card.
struct FolderBar: View {
    let url: URL
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").font(.system(size: 11)).foregroundStyle(accent)
                .accessibilityHidden(true)
            Text(url.lastPathComponent)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }
}

/// Read-only empty state shown by folder-backed cards when the workspace has no
/// project folder (e.g. workspaces created before folders existed).
struct CardFolderMissing: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
