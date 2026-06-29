import AppKit
import SwiftUI
import VoidloomCore

struct RootView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @ObservedObject var conversationStore: ConversationStore
    @ObservedObject var interaction: CanvasInteractionModel

    @AppStorage("isWorkspaceSidebarVisible") private var isWorkspaceSidebarVisible = false
    @State private var isCommandBarVisible = false
    @State private var isAIConversationVisible = false
    @State private var commandText = ""
    @State private var isCommandPaletteVisible = false
    @State private var paletteQuery = ""
    @State private var viewportBeforeCardFocus: CanvasViewport?
    /// Measured height of the floating dock capsule (screen px). Grid placement
    /// reserves this band so freshly created cards never land behind the dock.
    @State private var measuredDockHeight: CGFloat = 0

    /// Live pointer location (root coordinates) while it is over the eraser
    /// options panel, so the size-preview ring tracks the cursor as the user
    /// drags the thickness slider — the ring effectively *is* the cursor there.
    /// Held as plain `@State` (not `@StateObject`) so updating it every pointer
    /// move re-renders only `EraserSizePreview`, never this whole view.
    @State private var eraserPreview = EraserPreviewModel()

    /// Gap between the dock capsule and the window bottom. Kept as a single
    /// source of truth so the grid reserve below matches the actual padding.
    private static let bottomChromePadding: CGFloat = 24
    /// Breathing room between the bottom row of grid cards and the dock's top
    /// edge, so cards clear the dock comfortably rather than touching it.
    private static let dockClearanceGap: CGFloat = 16

    /// The screen-space band the grid must keep clear at the bottom: the measured
    /// dock height plus its bottom padding plus a comfortable gap.
    private var gridBottomInset: Double {
        Double(measuredDockHeight + Self.bottomChromePadding + Self.dockClearanceGap)
    }

    private var activeWorkspaceID: UUID {
        store.library.selectedWorkspaceID
    }

    private var activeWorkspaceName: String {
        store.library.workspaces
            .first(where: { $0.id == store.library.selectedWorkspaceID })?
            .name ?? "Workspace"
    }

    /// Handles a Delete/Backspace key press for the canvas. Removes, in priority
    /// order, the selected connection edge, the marquee-selected card group, or
    /// the single selected card. Returns whether the event was consumed.
    ///
    /// Stays inert (returns false, so the key falls through) while any text
    /// editor has focus — the tracked inline-edit states plus any first-responder
    /// `NSText` (note/todo bodies, card title, text element, terminal input) —
    /// so it never swallows Backspace mid-typing.
    private func handleDeleteKey(_ event: NSEvent) -> Bool {
        // 51 = delete/backspace, 117 = forward delete.
        guard event.keyCode == 51 || event.keyCode == 117 else { return false }

        guard interaction.editingTextID == nil,
              interaction.editingCardTitleID == nil else { return false }
        if event.window?.firstResponder is NSText { return false }

        if let id = interaction.selectedConnectionID {
            store.deleteConnection(id: id)
            interaction.selectedConnectionID = nil
            return true
        }
        if !store.state.marqueeSelectedCardIDs.isEmpty {
            let ids = store.state.marqueeSelectedCardIDs
            terminateAgentSessions(for: ids)
            store.deleteCards(ids: ids)
            return true
        }
        if let id = store.state.selectedCardID {
            terminateAgentSessions(for: [id])
            store.deleteCard(id: id)
            return true
        }
        return false
    }

    /// Handles the Escape key: always disarms any armed canvas tool, and also
    /// deselects the current card/text selection — except when the selected card
    /// is an agent. An agent card's terminal may bind Escape to its own action
    /// (e.g. interrupting an AI agent), so its selection is left intact here
    /// rather than the terminal having to special-case the key.
    private func handleEscape() {
        interaction.disarm()

        let selectedIsAgent = store.state.selectedCardID
            .flatMap { id in store.state.cards.first(where: { $0.id == id }) }?
            .kind == .agent
        if !selectedIsAgent {
            store.clearSelection()
        }
    }

    /// Terminates the agent session for every `.agent` card in `ids`, mirroring
    /// the per-card close button so Delete never leaks a running terminal.
    private func terminateAgentSessions(for ids: Set<UUID>) {
        for id in ids where store.state.cards.first(where: { $0.id == id })?.kind == .agent {
            sessionManager.terminateSession(cardID: id)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AtmosphereBackground()

                CanvasWorkspaceView(
                    store: store,
                    sessionManager: sessionManager,
                    interaction: interaction,
                    isCardFocused: viewportBeforeCardFocus != nil,
                    onToggleCardFocus: {
                        toggleCardFocus(in: geometry.size)
                    }
                )
                    .ignoresSafeArea()

                if isWorkspaceSidebarVisible {
                    WorkspaceSidebar(
                        library: store.library,
                        activeWorkspaceID: store.library.selectedWorkspaceID,
                        onSelectWorkspace: { id in
                            sessionManager.terminateAllSessions()
                            store.switchWorkspace(id: id)
                        },
                        onCreateWorkspace: {
                            let untitledCount = store.library.workspaces.filter { $0.name.hasPrefix("Untitled") }.count
                            let name = untitledCount == 0 ? "Untitled" : "Untitled \(untitledCount + 1)"
                            store.createWorkspace(named: name)
                        },
                        onRenameWorkspace: { id, name in
                            store.renameWorkspace(id: id, to: name)
                        },
                        onDeleteWorkspace: { id in
                            store.deleteWorkspace(id: id)
                        },
                        onMoveWorkspace: { draggedID, targetID in
                            store.moveWorkspace(id: draggedID, toPositionOf: targetID)
                        },
                        onCloseSidebar: {
                            withAnimation(.easeInOut(duration: 0.24)) {
                                isWorkspaceSidebarVisible = false
                            }
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
                }

                if isAIConversationVisible {
                    AIConversationSidebar(
                        messages: conversationStore.messages(for: activeWorkspaceID),
                        onSubmit: { text in
                            conversationStore.submit(workspaceID: activeWorkspaceID, text: text)
                        },
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.24)) {
                                isAIConversationVisible = false
                            }
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(1)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 12) {
                        if let persistenceError = store.lastPersistenceError {
                            PersistenceErrorBanner(message: persistenceError)
                        }

                        if isCommandBarVisible {
                            CommandBar(text: $commandText, onSubmit: submitCommand)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        if interaction.isArmed(.drawing) {
                            BrushOptionsPanel(interaction: interaction)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        if interaction.isArmed(.erasing) {
                            EraserOptionsPanel(interaction: interaction)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                // Track the cursor over the panel so the preview
                                // ring follows it (and resizes) as the slider is
                                // dragged, instead of sitting at a fixed center.
                                .onContinuousHover(coordinateSpace: .named("rootSpace")) { phase in
                                    switch phase {
                                    case .active(let location):
                                        beginEraserAdjust(at: location)
                                    case .ended:
                                        endEraserAdjust()
                                    }
                                }
                                // `.onContinuousHover` stops firing once the Slider
                                // captures the drag, so the ring would freeze and the
                                // arrow would reappear mid-drag. This simultaneous
                                // gesture keeps the ring tracking the pointer and
                                // re-hides the cursor while the slider is dragged; it
                                // runs alongside the Slider, which still works.
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 0, coordinateSpace: .named("rootSpace"))
                                        .onChanged { beginEraserAdjust(at: $0.location) }
                                        .onEnded { beginEraserAdjust(at: $0.location) }
                                )
                        }

                        if interaction.isArmed(.placingText) || store.state.selectedTextID != nil {
                            TextOptionsPanel(store: store, interaction: interaction)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        ToolDock(
                            store: store,
                            interaction: interaction,
                            errorMessage: store.lastPersistenceError,
                            isAIHintActive: isCommandBarVisible || isAIConversationVisible,
                            onToggleAIHint: toggleAISurface,
                            zoomScale: store.state.viewport.scale,
                            onZoomIn: {
                                let anchor = ScreenPoint(
                                    x: geometry.size.width / 2,
                                    y: geometry.size.height / 2
                                )
                                store.zoomStep(by: 1.15, anchoredAt: anchor)
                            },
                            onZoomOut: {
                                let anchor = ScreenPoint(
                                    x: geometry.size.width / 2,
                                    y: geometry.size.height / 2
                                )
                                store.zoomStep(by: 1 / 1.15, anchoredAt: anchor)
                            },
                            isCardFocused: viewportBeforeCardFocus != nil,
                            isCardSelected: store.state.selectedCardID != nil,
                            onToggleCardFocus: {
                                toggleCardFocus(in: geometry.size)
                            },
                            workspaceName: activeWorkspaceName,
                            isWorkspaceSidebarVisible: isWorkspaceSidebarVisible,
                            onToggleWorkspaceSidebar: {
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    isWorkspaceSidebarVisible.toggle()
                                }
                            },
                            onAddCard: { kind in
                                let viewportSize = ScreenPoint(
                                    x: geometry.size.width,
                                    y: geometry.size.height
                                )
                                // A full page flips the viewport one width to the
                                // right; animate that pan so the canvas glides over
                                // rather than jumping. Cards 1-4 of a page don't
                                // move the viewport, so they still appear instantly.
                                let willFlipPage = store.state.gridPlacementWillFlipPage(
                                    viewportSize: viewportSize,
                                    bottomInset: gridBottomInset
                                )
                                if willFlipPage {
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        store.addCardInGrid(
                                            kind: kind,
                                            viewportSize: viewportSize,
                                            bottomInset: gridBottomInset
                                        )
                                    }
                                } else {
                                    store.addCardInGrid(
                                        kind: kind,
                                        viewportSize: viewportSize,
                                        bottomInset: gridBottomInset
                                    )
                                }
                                // Match onAddText: a double-click instant-create
                                // always resolves back to idle so the transient
                                // mouse-down arm never lingers.
                                interaction.disarm()
                            },
                            onAddText: {
                                addTextAtViewportCenter(in: geometry.size)
                            }
                        )
                        .background(
                            GeometryReader { dockProxy in
                                Color.clear.preference(
                                    key: DockHeightPreferenceKey.self,
                                    value: dockProxy.size.height
                                )
                            }
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, Self.bottomChromePadding)
                    .animation(.easeInOut(duration: 0.22), value: store.lastPersistenceError)
                    .animation(.easeInOut(duration: 0.22), value: isCommandBarVisible)
                    .animation(.easeInOut(duration: 0.22), value: interaction.mode)
                    .animation(.easeInOut(duration: 0.22), value: store.state.selectedTextID)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .zIndex(2)

                // Eraser size preview: while the pointer is over the eraser panel
                // adjusting the thickness slider, the on-canvas cursor ring sits
                // behind the panel (the dock VStack is zIndex 2). This follows the
                // cursor above the dock so the ring is effectively the cursor and
                // grows/shrinks as the slider moves. Isolated so pointer-move
                // updates re-render only the ring, not this whole view.
                EraserSizePreview(
                    preview: eraserPreview,
                    interaction: interaction,
                    scale: CGFloat(store.state.viewport.scale)
                )
                .zIndex(3)

                if isCommandPaletteVisible {
                    CommandPaletteView(
                        query: $paletteQuery,
                        commands: paletteCommands(in: geometry.size),
                        onAskAI: { text in
                            conversationStore.submit(workspaceID: activeWorkspaceID, text: text)
                            withAnimation(.easeInOut(duration: 0.24)) {
                                isAIConversationVisible = true
                            }
                        },
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isCommandPaletteVisible = false
                            }
                        }
                    )
                    .transition(.opacity)
                    .zIndex(4)
                }
            }
            .background(
                ZStack {
                    Button("Open Command Palette") { openCommandPalette() }
                        .keyboardShortcut("k", modifiers: .command)
                    Button("Disarm Canvas Tool or Deselect") { handleEscape() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
                .hidden()
            )
            // Delete/Backspace is handled by a window-level key monitor rather
            // than a hidden button: it must fire for a single selected card and a
            // marquee group, yet stay inert while a text editor holds focus (so
            // Backspace keeps reaching the editor).
            .coordinateSpace(.named("rootSpace"))
            .background(CanvasKeyMonitor(onKeyDown: handleDeleteKey))
            .animation(.easeInOut(duration: 0.15), value: isCommandPaletteVisible)
            .animation(.easeInOut(duration: 0.24), value: isWorkspaceSidebarVisible)
            .animation(.easeInOut(duration: 0.24), value: isAIConversationVisible)
            .preferredColorScheme(.dark)
            .onPreferenceChange(DockHeightPreferenceKey.self) { height in
                measuredDockHeight = height
            }
            .onChange(of: store.state.selectedCardID) { _, _ in
                viewportBeforeCardFocus = nil
            }
            .onChange(of: store.library.selectedWorkspaceID) { _, _ in
                interaction.disarm()
                interaction.editingTextID = nil
            }
        }
    }

    /// Tracks the pointer over the eraser panel for the size-preview ring. The
    /// location goes to the isolated `eraserPreview` model (no shared-model churn),
    /// and the transparent cursor is re-asserted every move so only the ring shows.
    /// `isAdjustingEraserSize` is published only on the false→true edge so a drag
    /// doesn't re-invalidate every canvas observer on each move.
    private func beginEraserAdjust(at location: CGPoint) {
        eraserPreview.location = location
        if !interaction.isAdjustingEraserSize {
            interaction.isAdjustingEraserSize = true
        }
        CanvasToolCursor.transparentCursor.set()
    }

    /// Pointer left the eraser panel: restore the arrow and let the on-canvas
    /// cursor ring take over again.
    private func endEraserAdjust() {
        if interaction.isAdjustingEraserSize {
            interaction.isAdjustingEraserSize = false
        }
        NSCursor.arrow.set()
    }

    /// AI dock icon: open the conversation directly if this workspace already
    /// has a thread; otherwise reveal the bottom command launcher (empty state).
    private func toggleAISurface() {
        if conversationStore.hasConversation(for: activeWorkspaceID) {
            withAnimation(.easeInOut(duration: 0.24)) {
                isAIConversationVisible.toggle()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.22)) {
                isCommandBarVisible.toggle()
            }
        }
    }

    private func submitCommand() {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        conversationStore.submit(workspaceID: activeWorkspaceID, text: trimmed)
        commandText = ""

        withAnimation(.easeInOut(duration: 0.24)) {
            isCommandBarVisible = false
            isAIConversationVisible = true
        }
    }

    /// The canvas point currently at the center of the visible viewport — where
    /// newly created cards should appear.
    private func viewportCenterCanvasPoint(in size: CGSize) -> CanvasPoint {
        store.state.viewport.canvasPoint(
            forScreenPoint: ScreenPoint(x: size.width / 2, y: size.height / 2)
        )
    }

    /// Instant text element at the visible center (double-click on the Text
    /// dock tool), auto-focused for inline editing.
    private func addTextAtViewportCenter(in size: CGSize) {
        let id = store.addTextElement(
            centeredAt: viewportCenterCanvasPoint(in: size),
            fontSize: interaction.textFontSize,
            colorHex: interaction.textColor.hexStringRGBA,
            fontName: interaction.textFontName
        )
        interaction.editingTextID = id
        interaction.disarm()
    }

    private func openCommandPalette() {
        paletteQuery = ""
        withAnimation(.easeInOut(duration: 0.15)) {
            isCommandPaletteVisible = true
        }
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    /// All palette commands for the current state, ordered by section so the
    /// palette can show section headers without extra grouping logic.
    private func paletteCommands(in size: CGSize) -> [PaletteCommand] {
        let zoomAnchor = ScreenPoint(x: size.width / 2, y: size.height / 2)
        let cardCenter = viewportCenterCanvasPoint(in: size)
        var commands: [PaletteCommand] = []

        // Create
        commands.append(PaletteCommand(id: "new-agent", title: "New Terminal Card", section: .create, systemImage: "terminal", keywords: ["add", "create", "agent", "terminal"]) {
            store.addCard(kind: .agent, centeredAt: cardCenter)
        })
        commands.append(PaletteCommand(id: "new-note", title: "New Note Card", section: .create, systemImage: "note.text", keywords: ["add", "create"]) {
            store.addCard(kind: .note, centeredAt: cardCenter)
        })
        commands.append(PaletteCommand(id: "new-todo", title: "New Todo Card", section: .create, systemImage: "checklist", keywords: ["add", "create", "task"]) {
            store.addCard(kind: .todo, centeredAt: cardCenter)
        })
        commands.append(PaletteCommand(id: "new-browser", title: "New Browser Card", section: .create, systemImage: "safari", keywords: ["add", "create", "preview", "web"]) {
            store.addCard(kind: .browser, centeredAt: cardCenter)
        })
        commands.append(PaletteCommand(id: "new-text", title: "New Text", section: .create, systemImage: "textformat", keywords: ["add", "create", "label", "annotation"]) {
            interaction.editingTextID = store.addTextElement(
                centeredAt: cardCenter,
                fontSize: interaction.textFontSize,
                colorHex: interaction.textColor.hexStringRGBA,
                fontName: interaction.textFontName
            )
        })

        // Workspaces
        commands.append(PaletteCommand(id: "new-workspace", title: "New Workspace", section: .workspaces, systemImage: "plus.rectangle.on.rectangle", keywords: ["add", "create"]) {
            let untitledCount = store.library.workspaces.filter { $0.name.hasPrefix("Untitled") }.count
            let name = untitledCount == 0 ? "Untitled" : "Untitled \(untitledCount + 1)"
            store.createWorkspace(named: name)
        })
        for workspace in store.library.workspaces where workspace.id != activeWorkspaceID {
            commands.append(PaletteCommand(id: "switch-\(workspace.id)", title: "Switch to \(workspace.name)", section: .workspaces, systemImage: "rectangle.on.rectangle", keywords: ["open", "go", "workspace"]) {
                sessionManager.terminateAllSessions()
                store.switchWorkspace(id: workspace.id)
            })
        }

        // View
        commands.append(PaletteCommand(id: "reset-view", title: "Reset Viewport", section: .view, systemImage: "scope", keywords: ["zoom", "center", "fit"]) {
            store.resetViewport()
        })
        commands.append(PaletteCommand(id: "zoom-in", title: "Zoom In", section: .view, systemImage: "plus.magnifyingglass") {
            store.zoomStep(by: 1.15, anchoredAt: zoomAnchor)
        })
        commands.append(PaletteCommand(id: "zoom-out", title: "Zoom Out", section: .view, systemImage: "minus.magnifyingglass") {
            store.zoomStep(by: 1 / 1.15, anchoredAt: zoomAnchor)
        })
        if store.state.selectedCardID != nil {
            let focused = viewportBeforeCardFocus != nil
            commands.append(PaletteCommand(
                id: "focus-card",
                title: focused ? "Exit Card Focus" : "Focus Selected Card",
                section: .view,
                systemImage: focused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) {
                toggleCardFocus(in: size)
            })
        }

        // App
        commands.append(PaletteCommand(id: "open-settings", title: "Open Settings", section: .app, systemImage: "gearshape", keywords: ["preferences"]) {
            openSettings()
        })
        commands.append(PaletteCommand(
            id: "toggle-workspaces",
            title: isWorkspaceSidebarVisible ? "Hide Workspaces Sidebar" : "Show Workspaces Sidebar",
            section: .app,
            systemImage: "sidebar.left"
        ) {
            withAnimation(.easeInOut(duration: 0.24)) {
                isWorkspaceSidebarVisible.toggle()
            }
        })
        commands.append(PaletteCommand(id: "open-ai", title: "Open AI Conversation", section: .app, systemImage: "bubble.left.and.bubble.right", keywords: ["chat", "assistant"]) {
            withAnimation(.easeInOut(duration: 0.24)) {
                isAIConversationVisible = true
            }
        })

        return commands
    }

    private func toggleCardFocus(in size: CGSize) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if let savedViewport = viewportBeforeCardFocus {
                store.restoreViewport(savedViewport)
                viewportBeforeCardFocus = nil
            } else {
                viewportBeforeCardFocus = store.state.viewport
                store.focusOnSelectedCard(
                    viewportSize: ScreenPoint(x: size.width, y: size.height)
                )
            }
        }
    }
}

/// Carries the floating dock's measured height up to `RootView` so grid
/// placement can reserve that band and keep new cards clear of the dock.
private struct DockHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("Voidloom Shell") {
    RootView(
        store: PreviewSupport.makeStore(),
        sessionManager: AgentSessionManager(),
        conversationStore: ConversationStore(),
        interaction: CanvasInteractionModel()
    )
    .frame(width: 1180, height: 760)
}
