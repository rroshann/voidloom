import SwiftUI
import VoidloomCore

struct RootView: View {
    @ObservedObject var store: WorkspaceStore

    @State private var isWorkspaceSidebarVisible = false

    var body: some View {
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
                    }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(1)
            }

            VStack {
                HStack {
                    TopToolbar(
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

            VStack {
                Spacer()

                ToolDock(store: store, errorMessage: store.lastPersistenceError)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .zIndex(2)
        }
        .animation(.easeInOut(duration: 0.24), value: isWorkspaceSidebarVisible)
        .preferredColorScheme(.dark)
    }
}

#Preview("Voidloom Shell") {
    RootView(store: PreviewSupport.makeStore())
        .frame(width: 1180, height: 760)
}
