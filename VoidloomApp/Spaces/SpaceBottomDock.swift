import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoidloomCore

/// The single bottom-center dock for Spaces. One capsule that groups, left to
/// right: the space switcher, the space-management controls (layout mode,
/// re-tile, grid, background, settings), and the card-creation tools. Popovers
/// and the switcher menu open upward since the dock sits at the bottom edge.
struct SpaceBottomDock: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    let onReTile: () -> Void
    /// Creates a card of the given kind (Spaces appends + handles the page jump).
    let onAddCard: (CardKind) -> Void
    /// Latest persistence error, surfaced as an inert warning glyph when present.
    let errorMessage: String?

    @State private var showBackgroundPopover = false
    @State private var showLayoutPopover = false
    @State private var showImportError = false

    @AppStorage("spaces.defaultColumns") private var defaultColumns = 0
    @AppStorage("spaces.defaultRows") private var defaultRows = 0

    private var activeName: String {
        store.library.workspaces.first { $0.id == store.library.selectedWorkspaceID }?.name ?? "Space"
    }

    private var layoutMode: SpaceLayoutMode { store.state.space?.layoutMode ?? .pagedGrid }

    /// Effective column setting for the current space (0 = Auto). Falls back to the
    /// global default when the space has no tiling yet.
    private var currentColumns: Int {
        guard let t = store.state.space?.tiling else { return defaultColumns }
        return t.mode == .fixedColumns ? t.columns : 0
    }

    /// Effective row cap for the current space (0 = Auto / unbounded).
    private var currentRows: Int {
        guard let t = store.state.space?.tiling, t.mode == .fixedColumns else { return defaultRows }
        return t.maxRows ?? 0
    }

    /// Writes a new per-space tiling, preserving the current gap/margin/aspect.
    private func writeTiling(columns: Int, rows: Int) {
        let base = store.state.space?.tiling ?? SpaceTiling()
        let tiling: SpaceTiling
        if columns == 0 {
            tiling = SpaceTiling(mode: .auto, columns: base.columns, maxRows: nil,
                                 gap: base.gap, margin: base.margin, targetAspect: base.targetAspect)
        } else {
            tiling = SpaceTiling(mode: .fixedColumns, columns: columns, maxRows: rows == 0 ? nil : rows,
                                 gap: base.gap, margin: base.margin, targetAspect: base.targetAspect)
        }
        store.setSpaceTiling(tiling)
    }

    var body: some View {
        // No outer capsule: each control is its own frosted chip. Logical groups
        // (switcher · space controls · card tools) are separated by wider spacing
        // instead of dividers.
        HStack(spacing: 16) {
            spaceSwitcher

            HStack(spacing: 8) {
                barButton(
                    layoutMode == .pagedGrid ? "rectangle.3.group" : "square.grid.2x2",
                    help: layoutMode == .pagedGrid ? "Free-arrange" : "Grid"
                ) {
                    store.setSpaceLayoutMode(layoutMode == .pagedGrid ? .freeArrange : .pagedGrid)
                }
                barButton("rectangle.grid.2x2", help: "Re-tile", action: onReTile)
                barButton("square.grid.3x3", help: "Layout") { showLayoutPopover = true }
                    .popover(isPresented: $showLayoutPopover, arrowEdge: .top) {
                        layoutPopover.padding(16).frame(width: 240)
                    }
                    .disabled(layoutMode == .freeArrange)
                    .opacity(layoutMode == .freeArrange ? 0.4 : 1)
                barButton("photo", help: "Background") { showBackgroundPopover = true }
                    .popover(isPresented: $showBackgroundPopover, arrowEdge: .top) {
                        backgroundPopover.padding(16).frame(width: 260)
                    }
                barButton("gearshape", help: "Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }

            HStack(spacing: 8) {
                barButton("terminal", help: "Add terminal card") { onAddCard(.agent) }
                barButton("note.text", help: "Add note card") { onAddCard(.note) }
                barButton("checklist", help: "Add todo card") { onAddCard(.todo) }
                barButton("safari", help: "Add browser card") { onAddCard(.browser) }
            }

            if let errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 40, height: 40)
                    .modifier(DockChip())
                    .help(errorMessage)
            }
        }
        .alert("Import failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected image could not be imported. Make sure it is a valid PNG, JPEG, or HEIC file.")
        }
    }

    private var spaceSwitcher: some View {
        Menu {
            ForEach(store.library.workspaces) { ws in
                Button {
                    guard ws.id != store.library.selectedWorkspaceID else { return }
                    sessionManager.terminateAllSessions()
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
            Button("New Space") {
                let n = store.library.workspaces.filter { $0.name.hasPrefix("Untitled") }.count
                store.createWorkspace(named: n == 0 ? "Untitled" : "Untitled \(n + 1)")
            }
        } label: {
            HStack(spacing: 6) {
                Text(activeName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 14).frame(height: 40)
            .modifier(DockChip())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private func barButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9)).frame(width: 40, height: 40)
                .modifier(DockChip())
        }
        .buttonStyle(.plain).help(help)
    }

    @ViewBuilder private var backgroundPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background").font(.headline)
            Button("Atmosphere (default)") { store.setSpaceBackground(.atmosphere) }
            Button("Solid dark") { store.setSpaceBackground(.solid(hex: "#0A0E14FF")) }
            Button("Choose image…") { chooseImage() }

            Divider()
            Text("Dimming").font(.subheadline)
            Slider(value: Binding(
                get: { store.state.space?.backgroundDimming ?? 0.35 },
                set: { store.setBackgroundDimming($0) }
            ), in: 0...0.85)
        }
    }

    @ViewBuilder private var layoutPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layout").font(.headline)

            Picker("Columns", selection: Binding(
                get: { currentColumns },
                set: { writeTiling(columns: $0, rows: currentRows) }
            )) {
                Text("Auto").tag(0)
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.menu)

            Picker("Rows", selection: Binding(
                get: { currentRows },
                set: { writeTiling(columns: currentColumns, rows: $0) }
            )) {
                Text("Auto").tag(0)
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            .disabled(currentColumns == 0)

            Text("Auto fits every card on one screen. A fixed columns × rows grid paginates the overflow.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if store.importBackgroundImage(from: url) == nil {
                showImportError = true
            }
        }
    }
}

/// Frosted, self-contained chip background for a single dock control. Used per
/// icon (and the switcher) now that the dock has no unifying capsule, so each
/// control stays legible and lifted over any space background.
private struct DockChip: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 7)
            .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
    }
}
