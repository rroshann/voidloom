import AppKit
import SwiftUI
import VoidloomCore

/// App-wide session state above the workspace: whether a workspace is open (vs.
/// the startup/launcher screen) and the New Project sheet trigger. Injected once
/// by RootThemeHost so the startup screen, the shells, and the sheet all share it.
@MainActor
final class AppSession: ObservableObject {
    /// False shows the startup/launcher screen; true shows the open workspace.
    @Published var isWorkspaceOpen = false
    /// Drives the New Project dialog.
    @Published var showNewWorkspace = false

    func present() { showNewWorkspace = true }
    func openWorkspace() { isWorkspaceOpen = true }
}

/// Dialog for creating a workspace: a name, a project folder (required, chosen
/// via Browse → Finder), and a heads-up when the folder isn't a git repo. The
/// folder is fixed at creation and drives the Files/Git cards.
struct NewWorkspaceSheet: View {
    @ObservedObject var store: WorkspaceStore
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var name: String
    @State private var path = ""

    init(store: WorkspaceStore) {
        self.store = store
        _name = State(initialValue: WorkspaceFolder.nextUntitledName(in: store))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasFolder: Bool { !path.isEmpty }
    private var folderIsRepo: Bool { hasFolder && WorkspaceFolder.isGitRepository(path) }
    private var canCreate: Bool { !trimmedName.isEmpty && hasFolder }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                TextField("Workspace name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Project folder").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("Choose a folder…", text: $path)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse") { browse() }
                }
            }

            // git heads-up: only meaningful once a folder is chosen.
            if hasFolder && !folderIsRepo {
                Label("git not found — git features won't be available for this project.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            } else if folderIsRepo {
                Label("Git repository detected.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Project") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the project folder for this workspace."
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: path) }
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }

    private func create() {
        guard canCreate else { return }
        let before = store.library.selectedWorkspaceID
        store.createWorkspace(named: trimmedName)
        // Only set the folder if a new workspace actually became active
        // (createWorkspace is a no-op outside library mode).
        if store.library.selectedWorkspaceID != before {
            store.setSpaceFolder(path)
        }
        session.openWorkspace()   // enter the workspace (from startup or in-app)
        dismiss()
    }
}
