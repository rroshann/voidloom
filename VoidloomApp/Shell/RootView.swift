import SwiftUI
import VoidloomCore

struct RootView: View {
    @ObservedObject var store: WorkspaceStore

    @AppStorage("isWorkspaceSidebarVisible") private var isWorkspaceSidebarVisible = false
    @State private var isCommandBarVisible = false

    private var activeWorkspaceName: String {
        store.library.workspaces
            .first(where: { $0.id == store.library.selectedWorkspaceID })?
            .name ?? "Workspace"
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AtmosphereBackground()

                CanvasWorkspaceView(store: store)
                    .ignoresSafeArea()

                if isWorkspaceSidebarVisible {
                    WorkspaceSidebar(
                        library: store.library,
                        activeWorkspaceID: store.library.selectedWorkspaceID,
                        onSelectWorkspace: { id in
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
                        }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
                }

                VStack {
                    HStack {
                        TopToolbar(
                            workspaceName: activeWorkspaceName,
                            cardCount: store.state.cards.count,
                            isSidebarVisible: isWorkspaceSidebarVisible
                        ) {
                            withAnimation(.easeInOut(duration: 0.24)) {
                                isWorkspaceSidebarVisible.toggle()
                            }
                        }
                        .padding(.top, 6)

                        Spacer()
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .zIndex(3)

                VStack(spacing: 0) {
                    Spacer()

                    HStack {
                        Spacer()

                        CanvasZoomControls(
                            scale: store.state.viewport.scale,
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
                            onReset: {
                                store.resetViewport()
                            }
                        )
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 12)

                    VStack(spacing: 12) {
                        if let persistenceError = store.lastPersistenceError {
                            PersistenceErrorBanner(message: persistenceError)
                        }

                        if isCommandBarVisible {
                            CommandBar(errorMessage: store.lastPersistenceError)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        ToolDock(
                            store: store,
                            errorMessage: store.lastPersistenceError,
                            isAIHintActive: isCommandBarVisible
                        ) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isCommandBarVisible.toggle()
                            }
                        }
                        .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 24)
                    .animation(.easeInOut(duration: 0.22), value: store.lastPersistenceError)
                    .animation(.easeInOut(duration: 0.22), value: isCommandBarVisible)
                }
                .zIndex(2)
            }
            .animation(.easeInOut(duration: 0.24), value: isWorkspaceSidebarVisible)
            .preferredColorScheme(.dark)
        }
    }
}

#Preview("Voidloom Shell") {
    RootView(store: PreviewSupport.makeStore())
        .frame(width: 1180, height: 760)
}
