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
        // A single Liquid-Glass sheet (the dock) with plain monochrome glyphs on
        // top — never per-icon glass, per Apple's "no stacked glass" rule. Groups
        // (switcher · space controls · card tools) separated by wider spacing.
        HStack(spacing: Self.groupGap) {
            spaceSwitcher

            HStack(spacing: Self.iconGap) {
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
            }

            HStack(spacing: Self.iconGap) {
                barButton("terminal", help: "Add terminal card") { onAddCard(.agent) }
                barButton("note.text", help: "Add note card") { onAddCard(.note) }
                barButton("checklist", help: "Add todo card") { onAddCard(.todo) }
                barButton("safari", help: "Add browser card") { onAddCard(.browser) }
            }

            if let errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: Self.glyphSize, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(width: Self.iconSide, height: Self.iconSide)
                    .help(errorMessage)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .modifier(DockGlass(shape: Capsule()))
        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 6)
        .alert("Import failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected image could not be imported. Make sure it is a valid PNG, JPEG, or HEIC file.")
        }
    }

    /// Compact metrics — a slim floating glass bar, not a chunky dock.
    private static let iconSide: CGFloat = 34
    private static let glyphSize: CGFloat = 18
    private static let iconGap: CGFloat = 3
    private static let groupGap: CGFloat = 12

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
                Text(activeName.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.95))
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 12).frame(height: Self.iconSide)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private func barButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        DockIconButton(icon: icon, help: help, side: Self.iconSide, glyph: Self.glyphSize, action: action)
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

/// The dock's single Liquid-Glass sheet. Uses Apple's real `.glassEffect` on
/// macOS 26+, and a translucent frosted-material fallback (with a faint rim) on
/// older systems. `.regular` glass is translucent enough to let the background
/// bleed through while staying readable — the clear look "but not too much".
private struct DockGlass<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 1))
        }
    }
}

/// A plain monochrome glyph button that lives directly on the dock glass (no
/// glass of its own). A faint fill fades in on hover for affordance.
private struct DockIconButton: View {
    let icon: String
    let help: String
    let side: CGFloat
    let glyph: CGFloat
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: glyph, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: side, height: side)
                .background(
                    Circle().fill(.white.opacity(hovering ? 0.16 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
    }
}
