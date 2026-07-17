import SwiftUI
import VoidloomCore

/// Shared sizing for bottom docks — slim floating glass bars.
enum DockMetrics {
    static let iconSide: CGFloat = 34
    static let glyphSize: CGFloat = 18
    static let iconGap: CGFloat = 3
    static let groupGap: CGFloat = 12
}

/// The dock's single Liquid-Glass sheet. Uses Apple's real `.glassEffect` on
/// macOS 26+, and a translucent frosted-material fallback (with a faint rim) on
/// older systems. `.clear` is the high-transparency variant, so the background
/// bleeds strongly through the dock.
struct DockGlass<S: Shape>: ViewModifier {
    let shape: S

    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear, in: shape)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial).opacity(0.7))
                .overlay(shape.stroke(theme.ink(0.12), lineWidth: 1))
        }
    }
}

/// Monochrome glyph affordance shared by dock icon buttons and gesture-based tools.
struct DockIconGlyph: View {
    let icon: String
    var side: CGFloat = DockMetrics.iconSide
    var glyph: CGFloat = DockMetrics.glyphSize
    var isActive: Bool = false
    var activeColor: Color? = nil
    var isEnabled: Bool = true

    @Environment(\.theme) private var theme
    @State private var hovering = false

    private var glyphColor: Color {
        if !isEnabled { return theme.ink(0.32) }
        if isActive { return activeColor ?? theme.accent }
        return theme.ink(0.95)
    }

    private var fillOpacity: Double {
        if !isEnabled { return 0 }
        if isActive { return 0.22 }
        return hovering ? 0.16 : 0
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: glyph, weight: .semibold))
            .foregroundStyle(glyphColor)
            .frame(width: side, height: side)
            .background(
                Circle().fill(theme.surface(fillOpacity))
            )
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

/// Workspace switcher menu shared by Canvas and Spaces docks.
struct DockWorkspaceMenu: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @EnvironmentObject private var session: AppSession
    @Environment(\.theme) private var theme

    private var activeName: String {
        store.library.workspaces.first { $0.id == store.library.selectedWorkspaceID }?.name ?? "Space"
    }

    private var projectFolderLabel: String {
        guard let path = store.state.space?.folderPath, !path.isEmpty else {
            return "No project folder"
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var body: some View {
        Menu {
            ForEach(store.library.workspaces) { ws in
                Button {
                    guard ws.id != store.library.selectedWorkspaceID else { return }
                    // Sessions persist across workspace switches; the terminals
                    // reattach when this workspace is reopened. Only ⌘Q (app
                    // termination) or deleting the workspace shuts them down.
                    store.switchWorkspace(id: ws.id)
                } label: {
                    if ws.id == store.library.selectedWorkspaceID {
                        Label(ws.name, systemImage: "checkmark")
                    } else {
                        Text(ws.name)
                    }
                }
            }
            Divider()
            Text(projectFolderLabel).disabled(true)
            Button("Set Project Folder…") {
                MenuAction.setProjectFolder.post()
            }
            Divider()
            Button("New Space") {
                session.present()
            }
            Button("Back to Launcher") {
                session.isWorkspaceOpen = false
            }
        } label: {
            HStack(spacing: 6) {
                Text(activeName.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(theme.ink(0.95))
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.ink(0.6))
            }
            .padding(.horizontal, 12).frame(height: DockMetrics.iconSide)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

/// Text segmented switcher for the space layout mode (GRID ⇄ BOARD). Spells out
/// the current mode instead of a glyph, so which view is active is never
/// ambiguous. Stateless apart from per-segment hover; the highlight animates via
/// the dock's layout-mode keyed animation.
struct DockLayoutModeSwitcher: View {
    let mode: SpaceLayoutMode
    let onSelect: (SpaceLayoutMode) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            segment("GRID", .pagedGrid)
            segment("BOARD", .freeArrange)
        }
        .padding(2)
        .background(Capsule().fill(theme.surface(0.08)))
        .frame(height: DockMetrics.iconSide)
    }

    private func segment(_ title: String, _ target: SpaceLayoutMode) -> some View {
        DockModeSegment(title: title, isActive: mode == target) {
            if mode != target { onSelect(target) }
        }
    }
}

private struct DockModeSegment: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(theme.ink(isActive ? 0.95 : 0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(theme.surface(isActive ? 0.18 : (hovering ? 0.1 : 0)))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(isActive ? "\(title.capitalized) view (current)" : "Switch to \(title.capitalized) view")
        .accessibilityLabel("\(title.capitalized) view")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// A plain monochrome glyph button that lives directly on the dock glass (no
/// glass of its own). A faint fill fades in on hover; active tools get a
/// brighter/accent-tinted glyph and subtle fill.
struct DockIconButton: View {
    let icon: String
    let help: String
    var side: CGFloat = DockMetrics.iconSide
    var glyph: CGFloat = DockMetrics.glyphSize
    var isActive: Bool = false
    var activeColor: Color? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: { if isEnabled { action() } }) {
            DockIconGlyph(
                icon: icon,
                side: side,
                glyph: glyph,
                isActive: isActive,
                activeColor: activeColor,
                isEnabled: isEnabled
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
        .help(help)
        .accessibilityLabel(help)
    }
}
