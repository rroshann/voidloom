import SwiftUI
import VoidloomCore

struct WorkspaceSidebar: View {
    let library: WorkspaceLibrary
    let activeWorkspaceID: UUID
    let onSelectWorkspace: (UUID) -> Void
    let onCreateWorkspace: () -> Void
    let onRenameWorkspace: (UUID, String) -> Void
    let onDeleteWorkspace: (UUID) -> Void

    @State private var workspaceToRename: WorkspaceSummary?
    @State private var renameText = ""
    @State private var workspaceToDelete: WorkspaceSummary?

    private var canDeleteWorkspaces: Bool {
        library.workspaces.count > 1
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Workspaces")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.48))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(library.workspaces) { workspace in
                        Button {
                            onSelectWorkspace(workspace.id)
                        } label: {
                            WorkspaceSidebarRow(
                                title: workspace.name,
                                subtitle: "\(workspace.cardCount) cards",
                                isSelected: workspace.id == activeWorkspaceID
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if workspace.id != activeWorkspaceID {
                                Button("Open") {
                                    onSelectWorkspace(workspace.id)
                                }
                            }

                            Button("Rename…") {
                                workspaceToRename = workspace
                                renameText = workspace.name
                            }

                            Divider()

                            Button("Delete Workspace", role: .destructive) {
                                workspaceToDelete = workspace
                            }
                            .disabled(!canDeleteWorkspaces)
                        }
                    }
                }

                Spacer()

                Button(action: onCreateWorkspace) {
                    Label("New Workspace", systemImage: "plus")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Create a new workspace")
            }
            .padding(.top, 76)
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(width: 300, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 32, x: 18, y: 0)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .alert("Rename Workspace", isPresented: renameAlertIsPresented) {
            TextField("Workspace name", text: $renameText)
            Button("Cancel", role: .cancel) {
                workspaceToRename = nil
            }
            Button("Save") {
                guard let workspace = workspaceToRename else { return }
                onRenameWorkspace(workspace.id, renameText)
                workspaceToRename = nil
            }
        }
        .confirmationDialog(
            "Delete \"\(workspaceToDelete?.name ?? "")\"?",
            isPresented: deleteDialogIsPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Workspace", role: .destructive) {
                guard let workspace = workspaceToDelete else { return }
                onDeleteWorkspace(workspace.id)
                workspaceToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                workspaceToDelete = nil
            }
        } message: {
            Text("This permanently removes the workspace and all of its cards.")
        }
    }

    private var renameAlertIsPresented: Binding<Bool> {
        Binding(
            get: { workspaceToRename != nil },
            set: { isPresented in
                if !isPresented {
                    workspaceToRename = nil
                }
            }
        )
    }

    private var deleteDialogIsPresented: Binding<Bool> {
        Binding(
            get: { workspaceToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    workspaceToDelete = nil
                }
            }
        )
    }
}

struct WorkspaceSidebarRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.teal.opacity(isSelected ? 0.18 : 0.08))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? .teal : .white.opacity(0.42))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.62))

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 0.52 : 0.38))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.1 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(isSelected ? 0.12 : 0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview("Workspace Sidebar") {
    let workspaceID = UUID()
    let library = WorkspaceLibrary(
        selectedWorkspaceID: workspaceID,
        workspaces: [
            WorkspaceSummary(id: workspaceID, name: "Main Canvas", cardCount: 4),
            WorkspaceSummary(id: UUID(), name: "Research", cardCount: 0),
            WorkspaceSummary(id: UUID(), name: "Launch Plan", cardCount: 2)
        ]
    )

    return WorkspaceSidebar(
        library: library,
        activeWorkspaceID: workspaceID,
        onSelectWorkspace: { _ in },
        onCreateWorkspace: {},
        onRenameWorkspace: { _, _ in },
        onDeleteWorkspace: { _ in }
    )
    .frame(width: 300, height: 760)
    .preferredColorScheme(.dark)
}
