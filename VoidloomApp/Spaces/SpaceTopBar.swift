import AppKit
import SwiftUI
import VoidloomCore

/// Top-center space controls: space switcher, re-tile, and settings. Styled like
/// the bottom ToolDock capsule. Tools live in the bottom dock, not here.
struct SpaceTopBar: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    let onReTile: () -> Void

    private var activeName: String {
        store.library.workspaces.first { $0.id == store.library.selectedWorkspaceID }?.name ?? "Space"
    }

    var body: some View {
        HStack(spacing: 7) {
            Menu {
                ForEach(store.library.workspaces) { ws in
                    Button {
                        guard ws.id != store.library.selectedWorkspaceID else { return }
                        sessionManager.terminateAllSessions()
                        store.switchWorkspace(id: ws.id)
                    } label: {
                        Label(ws.name, systemImage: ws.id == store.library.selectedWorkspaceID ? "checkmark" : "")
                    }
                }
                Divider()
                Button("New Space") {
                    let n = store.library.workspaces.filter { $0.name.hasPrefix("Untitled") }.count
                    store.createWorkspace(named: n == 0 ? "Untitled" : "Untitled \(n + 1)")
                }
            } label: {
                HStack(spacing: 6) {
                    Text(activeName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12).frame(height: 38)
            }
            .menuStyle(.borderlessButton).fixedSize()

            barDivider
            barButton("rectangle.grid.2x2", help: "Re-tile", action: onReTile)
            barButton("gearshape", help: "Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 12)
    }

    private var barDivider: some View {
        RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.14)).frame(width: 1, height: 30)
    }

    private func barButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86)).frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain).help(help)
    }
}
