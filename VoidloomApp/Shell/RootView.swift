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

    private var activeWorkspaceID: UUID {
        store.library.selectedWorkspaceID
    }

    private var activeWorkspaceName: String {
        store.library.workspaces
            .first(where: { $0.id == store.library.selectedWorkspaceID })?
            .name ?? "Workspace"
    }

    /// Whether the Delete shortcut should act. It must stay inert while any text
    /// element or card title is being edited (so Backspace flows to the editor),
    /// and only fires when there's a selected connection edge or a marquee card
    /// group to remove.
    private var canDeleteSelection: Bool {
        interaction.editingTextID == nil
            && interaction.editingCardTitleID == nil
            && (interaction.selectedConnectionID != nil
                || !store.state.marqueeSelectedCardIDs.isEmpty)
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
                                store.zoom(by: 1.15, anchoredAt: anchor)
                            },
                            onZoomOut: {
                                let anchor = ScreenPoint(
                                    x: geometry.size.width / 2,
                                    y: geometry.size.height / 2
                                )
                                store.zoom(by: 1 / 1.15, anchoredAt: anchor)
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
                                store.addCardInGrid(
                                    kind: kind,
                                    viewportSize: ScreenPoint(x: geometry.size.width, y: geometry.size.height)
                                )
                                // Match onAddText: a double-click instant-create
                                // always resolves back to idle so the transient
                                // mouse-down arm never lingers.
                                interaction.disarm()
                            },
                            onAddText: {
                                addTextAtViewportCenter(in: geometry.size)
                            }
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .animation(.easeInOut(duration: 0.22), value: store.lastPersistenceError)
                    .animation(.easeInOut(duration: 0.22), value: isCommandBarVisible)
                    .animation(.easeInOut(duration: 0.22), value: interaction.mode)
                    .animation(.easeInOut(duration: 0.22), value: store.state.selectedTextID)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .zIndex(2)

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
                    Button("Disarm Canvas Tool") { interaction.disarm() }
                        .keyboardShortcut(.escape, modifiers: [])
                    // Delete removes the selected connection edge, or — when an
                    // edge isn't selected — the whole marquee-selected card group
                    // (and their connections). Disabled while a text field or
                    // card title is being edited so it never swallows backspace,
                    // and when there's nothing key-deletable selected (a single
                    // tap-selected card is closed via its button, not Delete).
                    Button("Delete Selection") {
                        if let id = interaction.selectedConnectionID {
                            store.deleteConnection(id: id)
                            interaction.selectedConnectionID = nil
                        } else if !store.state.marqueeSelectedCardIDs.isEmpty {
                            store.deleteCards(ids: store.state.marqueeSelectedCardIDs)
                        }
                    }
                    .keyboardShortcut(.delete, modifiers: [])
                    .disabled(!canDeleteSelection)
                }
                .hidden()
            )
            .animation(.easeInOut(duration: 0.15), value: isCommandPaletteVisible)
            .animation(.easeInOut(duration: 0.24), value: isWorkspaceSidebarVisible)
            .animation(.easeInOut(duration: 0.24), value: isAIConversationVisible)
            .preferredColorScheme(.dark)
            .onChange(of: store.state.selectedCardID) { _, _ in
                viewportBeforeCardFocus = nil
            }
            .onChange(of: store.library.selectedWorkspaceID) { _, _ in
                interaction.disarm()
                interaction.editingTextID = nil
            }
        }
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
            store.zoom(by: 1.15, anchoredAt: zoomAnchor)
        })
        commands.append(PaletteCommand(id: "zoom-out", title: "Zoom Out", section: .view, systemImage: "minus.magnifyingglass") {
            store.zoom(by: 1 / 1.15, anchoredAt: zoomAnchor)
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

#Preview("Voidloom Shell") {
    RootView(
        store: PreviewSupport.makeStore(),
        sessionManager: AgentSessionManager(),
        conversationStore: ConversationStore(),
        interaction: CanvasInteractionModel()
    )
    .frame(width: 1180, height: 760)
}
