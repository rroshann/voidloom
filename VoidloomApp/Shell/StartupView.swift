import SwiftUI
import VoidloomCore

/// Launcher shown before a workspace is open: the brand, the five most recent
/// workspaces (open / rename / delete), and Create Workspace. No animation.
struct StartupView: View {
    @ObservedObject var store: WorkspaceStore
    @EnvironmentObject private var session: AppSession
    @Environment(\.theme) private var theme

    @State private var editingID: UUID?
    @State private var editingName = ""
    @State private var deleteCandidate: WorkspaceSummary?

    private var recent: [WorkspaceSummary] {
        Array(store.library.workspaces.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.06, blue: 0.09), Color(red: 0.02, green: 0.02, blue: 0.04)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                header

                if recent.isEmpty {
                    emptyState
                } else {
                    workspaceList
                    createButton
                }
            }
            .frame(maxWidth: 540)
            .padding(40)
        }
        .alert(item: $deleteCandidate) { ws in
            Alert(
                title: Text("Delete “\(ws.name)”?"),
                message: Text("This permanently deletes the workspace and its cards. This can't be undone."),
                primaryButton: .destructive(Text("Delete")) { store.deleteWorkspace(id: ws.id) },
                secondaryButton: .cancel()
            )
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Voidloom")
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Your canvas workspaces")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No workspaces yet.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
            createButton
        }
    }

    private var workspaceList: some View {
        VStack(spacing: 8) {
            ForEach(recent) { ws in
                row(ws)
            }
        }
    }

    private func row(_ ws: WorkspaceSummary) -> some View {
        HStack(spacing: 12) {
            if editingID == ws.id {
                TextField("Workspace name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename(ws) }
                    .onExitCommand { cancelRename() }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ws.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text("\(ws.cardCount) \(ws.cardCount == 1 ? "card" : "cards") · \(ws.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer(minLength: 8)
                rowButton("pencil", help: "Rename") { beginRename(ws) }
                rowButton("trash", help: "Delete", danger: true) { deleteCandidate = ws }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture { if editingID != ws.id { open(ws) } }
    }

    private func rowButton(_ icon: String, help: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(danger ? Color.red.opacity(0.85) : .white.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var createButton: some View {
        Button { session.present() } label: {
            Label("Create Workspace", systemImage: "plus")
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent)
        .frame(maxWidth: 260)
    }

    private func open(_ ws: WorkspaceSummary) {
        store.switchWorkspace(id: ws.id)
        session.openWorkspace()
    }

    private func beginRename(_ ws: WorkspaceSummary) {
        editingName = ws.name
        editingID = ws.id
    }

    private func commitRename(_ ws: WorkspaceSummary) {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { store.renameWorkspace(id: ws.id, to: trimmed) }
        cancelRename()
    }

    private func cancelRename() {
        editingID = nil
        editingName = ""
    }
}
