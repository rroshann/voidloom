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
        // One unified macOS-style dock panel holding clear-glass icon tiles.
        // Logical groups (switcher · space controls · card tools) are separated
        // by wider spacing.
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
                glyphTile("exclamationmark.triangle", tint: .orange)
                    .help(errorMessage)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 12)
        .alert("Import failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected image could not be imported. Make sure it is a valid PNG, JPEG, or HEIC file.")
        }
    }

    /// macOS-Dock-sized tile metrics.
    private static let tileSide: CGFloat = 52
    private static let tileCorner: CGFloat = 14
    private static let iconGap: CGFloat = 6
    private static let groupGap: CGFloat = 14

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
            HStack(spacing: 7) {
                Text(activeName.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.95))
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16).frame(height: Self.tileSide)
            .modifier(DockChip(shape: RoundedRectangle(cornerRadius: Self.tileCorner, style: .continuous)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }

    private func barButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            glyphTile(icon)
        }
        .buttonStyle(.plain).help(help)
    }

    /// A single clear-glass dock tile with a monochrome glyph, at macOS-Dock size.
    private func glyphTile(_ icon: String, tint: Color = .white.opacity(0.92)) -> some View {
        Image(systemName: icon)
            .font(.system(size: 23, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: Self.tileSide, height: Self.tileSide)
            .modifier(DockChip(shape: RoundedRectangle(cornerRadius: Self.tileCorner, style: .continuous)))
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

/// A clear-glass dock tile in the spirit of the iOS/macOS 26 "clear" icon look:
/// a translucent frosted pane with a soft top specular highlight and a bright
/// glass rim — no color of its own. Kept behind the content so the glyph/text
/// stays crisp. Generic over the silhouette.
private struct DockChip<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            // Backgrounds only (behind content). Back-to-front: frosted material →
            // faint lift (so the tile reads as its own glass on the dock panel) →
            // top specular highlight.
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.02), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            )
            .background(shape.fill(.white.opacity(0.06)))
            .background(shape.fill(.ultraThinMaterial))
            // Glass rim: brighter along the top edge, faint below.
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.12)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
    }
}
