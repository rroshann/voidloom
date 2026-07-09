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
    /// The armed-tool spine, driving Board tool highlights + arming.
    @ObservedObject var interaction: CanvasInteractionModel
    let onReTile: () -> Void
    /// Creates a card of the given kind (Spaces appends + handles the page jump).
    let onAddCard: (CardKind) -> Void
    /// Latest persistence error, surfaced as an inert warning glyph when present.
    let errorMessage: String?
    let isAIActive: Bool
    let onToggleAI: () -> Void
    /// Board zoom, shown only in Board mode (nil ⇒ grid mode, no zoom controls).
    var boardZoomScale: Double? = nil
    var onZoomIn: () -> Void = {}
    var onZoomOut: () -> Void = {}
    var onResetZoom: () -> Void = {}
    /// Board connect tool (nil ⇒ grid mode, no connect tool).
    var isConnecting: Bool = false
    var onToggleConnect: (() -> Void)? = nil
    /// Board minimap toggle (nil ⇒ grid mode, no minimap).
    var isMinimapVisible: Bool = false
    var onToggleMinimap: (() -> Void)? = nil

    @State private var showBackgroundPopover = false
    @State private var showLayoutPopover = false
    @State private var showImportError = false
    @State private var showGitUnavailable = false

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        HStack(spacing: DockMetrics.groupGap) {
            DockWorkspaceMenu(store: store, sessionManager: sessionManager)

            // Card-creation tools: terminal, notes, todo, browser, files, git.
            HStack(spacing: DockMetrics.iconGap) {
                barButton("terminal", help: "Add terminal card") { onAddCard(.agent) }
                barButton("note.text", help: "Add note card") { onAddCard(.note) }
                barButton("checklist", help: "Add todo card") { onAddCard(.todo) }
                barButton("safari", help: "Add browser card") { onAddCard(.browser) }
                barButton("folder", help: "Add file browser card") { onAddCard(.fileBrowser) }
                barButton("arrow.triangle.branch", help: "Add git card") { addGitCard() }
            }

            // Space layout: mode switcher, re-tile, layout, background.
            HStack(spacing: DockMetrics.iconGap) {
                DockLayoutModeSwitcher(mode: layoutMode) { store.setSpaceLayoutMode($0) }
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

            // Canvas tools — a distinct cluster from layout so the Board dock reads
            // as ordered groups, not one long run: connect, and (Board only) text,
            // brush, eraser, minimap.
            if onToggleConnect != nil || layoutMode == .freeArrange {
                HStack(spacing: DockMetrics.iconGap) {
                    if let onToggleConnect {
                        DockIconButton(icon: "link", help: "Connect cards",
                                       isActive: isConnecting, activeColor: theme.accent,
                                       action: onToggleConnect)
                    }
                    if layoutMode == .freeArrange {
                        DockIconButton(icon: "textformat", help: "Text",
                                       isActive: interaction.isArmed(.placingText),
                                       activeColor: theme.accent, action: { interaction.armText() })
                        DockIconButton(icon: "paintbrush.pointed", help: "Brush",
                                       isActive: interaction.isArmed(.drawing),
                                       activeColor: theme.accent, action: { interaction.armBrush() })
                        DockIconButton(icon: "eraser", help: "Eraser",
                                       isActive: interaction.isArmed(.erasing),
                                       activeColor: theme.accent, action: { interaction.armEraser() })
                        if let onToggleMinimap {
                            DockIconButton(icon: "map", help: "Minimap",
                                           isActive: isMinimapVisible,
                                           activeColor: theme.accent, action: onToggleMinimap)
                        }
                    }
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            // Board zoom (Board mode only): out / percentage-resets / in.
            if let boardZoomScale {
                HStack(spacing: DockMetrics.iconGap) {
                    barButton("minus.magnifyingglass", help: "Zoom out", action: onZoomOut)
                    Button(action: onResetZoom) {
                        Text("\(Int((boardZoomScale * 100).rounded()))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(minWidth: 40)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help("Reset zoom to 100%")
                    barButton("plus.magnifyingglass", help: "Zoom in", action: onZoomIn)
                }
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            DockIconButton(
                icon: "sparkles",
                help: "AI assistant",
                isActive: isAIActive,
                activeColor: theme.accent,
                action: onToggleAI
            )

            if let errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: DockMetrics.glyphSize, weight: .medium))
                    .foregroundStyle(.orange)
                    .frame(width: DockMetrics.iconSide, height: DockMetrics.iconSide)
                    .help(errorMessage)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        // One fast spring keyed to the mode drives the capsule's expand/contract
        // and the tool clusters' scale+fade in a single pass — no per-cluster
        // animation state to hold.
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85),
                   value: layoutMode)
        // Exiting tool clusters fade out slower than the capsule shrinks; clip to
        // the capsule so they never show outside the glass mid-contraction.
        .clipShape(Capsule())
        .modifier(DockGlass(shape: Capsule()))
        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 6)
        .alert("Import failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The selected image could not be imported. Make sure it is a valid PNG, JPEG, or HEIC file.")
        }
        .alert("Not a git repository", isPresented: $showGitUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("“\(activeName)” isn’t a git repository, so git tracking and diff are unavailable. Run `git init` in the workspace folder (or choose a folder that is a repo), then try again.")
        }
    }

    /// Adds a git card, but first warns if the workspace folder isn't a git repo
    /// (git tracking/diff would be unavailable). If no folder is set yet, the card
    /// itself prompts to choose one.
    private func addGitCard() {
        if let folder = store.state.space?.folderPath, !folder.isEmpty,
           !WorkspaceFolder.isGitRepository(folder) {
            showGitUnavailable = true
        } else {
            onAddCard(.git)
        }
    }

    private func barButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        DockIconButton(icon: icon, help: help, action: action)
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
