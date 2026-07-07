import SwiftUI
import VoidloomCore

/// Launcher shown before a workspace is open: the brand, searchable workspace list
/// (open / rename / delete), and Create Workspace. No animation.
struct StartupView: View {
    @ObservedObject var store: WorkspaceStore
    @EnvironmentObject private var session: AppSession
    @Environment(\.theme) private var theme

    @State private var editingID: UUID?
    @State private var editingName = ""
    @State private var deleteCandidate: WorkspaceSummary?
    @State private var searchText = ""
    @State private var showAll = false
    @State private var hoveredRowID: UUID?
    @State private var keyboardSelectedID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sorted: [WorkspaceSummary] {
        store.library.workspaces.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedWorkspaces: [WorkspaceSummary] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return sorted.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        } else if showAll {
            return sorted
        } else {
            return Array(sorted.prefix(5))
        }
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

                if sorted.isEmpty {
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

    private var searchField: some View {
        TextField("Search workspaces", text: $searchText)
            .textFieldStyle(.plain)
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
            )
            // Spotlight/Raycast pattern: keep the search field focused, but let
            // ↑/↓ move a highlight through the results and ⏎ open it.
            .onKeyPress(.downArrow) { moveKeyboardSelection(1); return .handled }
            .onKeyPress(.upArrow) { moveKeyboardSelection(-1); return .handled }
            .onKeyPress(.return) {
                let list = displayedWorkspaces
                if let id = keyboardSelectedID, let ws = list.first(where: { $0.id == id }) {
                    open(ws); return .handled
                }
                if let only = list.first, list.count == 1 { open(only); return .handled }
                return .ignored
            }
    }

    private var workspaceList: some View {
        VStack(spacing: 8) {
            searchField

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(displayedWorkspaces) { ws in
                        row(ws)
                    }
                }
            }
            .frame(maxHeight: 320)

            if isSearching && displayedWorkspaces.isEmpty {
                Text("No matching workspaces.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if !isSearching && !showAll && sorted.count > 5 {
                Button("Show all (\(sorted.count))") { showAll = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }

            if showAll && !isSearching {
                Button("Show recent") { showAll = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
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
                .accessibilityLabel("Open \(ws.name)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open(ws) }
                Spacer(minLength: 8)

                // Actions reveal on hover so a resting row is just its name —
                // no ambient red. They stay mounted (opacity, not removal) so
                // VoiceOver always reaches them.
                LauncherRowButton(icon: "pencil", help: "Rename", visible: hoveredRowID == ws.id) { beginRename(ws) }
                LauncherRowButton(icon: "trash", help: "Delete", danger: true, visible: hoveredRowID == ws.id) { deleteCandidate = ws }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .opacity(hoveredRowID == ws.id ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(hoveredRowID == ws.id || keyboardSelectedID == ws.id ? 0.09 : 0.05))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(keyboardSelectedID == ws.id ? Color.accentColor.opacity(0.7) : .white.opacity(0.08),
                            lineWidth: keyboardSelectedID == ws.id ? 1.5 : 1))
        )
        .contentShape(Rectangle())
        .onTapGesture { if editingID != ws.id { open(ws) } }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                if hovering { hoveredRowID = ws.id }
                else if hoveredRowID == ws.id { hoveredRowID = nil }
            }
        }
    }

    /// A launcher row action: hidden until its row is hovered, and — for the
    /// destructive one — muted gray until the button itself is hovered, so
    /// delete never shouts ambiently.
    private struct LauncherRowButton: View {
        let icon: String
        let help: String
        var danger: Bool = false
        let visible: Bool
        let action: () -> Void
        @State private var isHovered = false

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(foreground)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(isHovered ? 0.12 : 0.06)))
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .onHover { isHovered = $0 }
        }

        private var foreground: Color {
            if danger { return isHovered ? .red : .white.opacity(0.55) }
            return .white.opacity(isHovered ? 0.95 : 0.7)
        }
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

    private func moveKeyboardSelection(_ delta: Int) {
        let list = displayedWorkspaces
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == keyboardSelectedID } ?? (delta > 0 ? -1 : 0)
        let next = min(max(current + delta, 0), list.count - 1)
        keyboardSelectedID = list[next].id
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
