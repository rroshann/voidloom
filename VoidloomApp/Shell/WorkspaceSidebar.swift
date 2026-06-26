import SwiftUI
import VoidloomCore

private let workspaceListCoordinateSpace = "WorkspaceSidebar.WorkspaceList"

struct WorkspaceSidebar: View {
    let library: WorkspaceLibrary
    let activeWorkspaceID: UUID
    let onSelectWorkspace: (UUID) -> Void
    let onCreateWorkspace: () -> Void
    let onRenameWorkspace: (UUID, String) -> Void
    let onDeleteWorkspace: (UUID) -> Void
    let onMoveWorkspace: (UUID, UUID) -> Void

    @State private var workspaceToRename: WorkspaceSummary?
    @State private var renameText = ""
    @State private var workspaceToDelete: WorkspaceSummary?
    @State private var draggedWorkspaceID: UUID?
    @State private var dragTargetWorkspaceID: UUID?
    @State private var dragLocationY: CGFloat?
    @State private var dragGrabOffsetY: CGFloat = 0
    @State private var workspaceRowFrames: [UUID: CGRect] = [:]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canDeleteWorkspaces: Bool {
        library.workspaces.count > 1
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Workspaces")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.48))

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(library.workspaces) { workspace in
                        WorkspaceSidebarRow(
                            title: workspace.name,
                            subtitle: "\(workspace.cardCount) cards",
                            isSelected: workspace.id == activeWorkspaceID,
                            isDropTarget: dragTargetWorkspaceID == workspace.id,
                            isDragging: draggedWorkspaceID == workspace.id
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onTapGesture {
                            onSelectWorkspace(workspace.id)
                        }
                        .contextMenu {
                            if workspace.id != activeWorkspaceID {
                                Button("Open") {
                                    onSelectWorkspace(workspace.id)
                                }
                            }

                            Button("Rename…") {
                                workspaceToRename = workspace
                                renameText = workspace.name
                            }

                            Divider()

                            Button("Delete Workspace", role: .destructive) {
                                workspaceToDelete = workspace
                            }
                            .disabled(!canDeleteWorkspaces)
                        }
                        .background(WorkspaceSidebarRowFrameReader(workspaceID: workspace.id))
                        .offset(y: dragOffset(for: workspace.id))
                        .zIndex(draggedWorkspaceID == workspace.id ? 1 : 0)
                        .highPriorityGesture(workspaceDragGesture(for: workspace.id))
                    }
                }
                .coordinateSpace(name: workspaceListCoordinateSpace)
                .onPreferenceChange(WorkspaceSidebarRowFramePreferenceKey.self) { frames in
                    workspaceRowFrames = frames
                }
                .animation(reorderAnimation, value: library.workspaces.map(\.id))

                Spacer()

                Button(action: onCreateWorkspace) {
                    Label("New Workspace", systemImage: "plus")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Create a new workspace")
            }
            .padding(.top, 76)
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(width: 300, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 32, x: 18, y: 0)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .alert("Rename Workspace", isPresented: renameAlertIsPresented) {
            TextField("Workspace name", text: $renameText)
            Button("Cancel", role: .cancel) {
                workspaceToRename = nil
            }
            Button("Save") {
                guard let workspace = workspaceToRename else { return }
                onRenameWorkspace(workspace.id, renameText)
                workspaceToRename = nil
            }
        }
        .confirmationDialog(
            "Delete \"\(workspaceToDelete?.name ?? "")\"?",
            isPresented: deleteDialogIsPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Workspace", role: .destructive) {
                guard let workspace = workspaceToDelete else { return }
                onDeleteWorkspace(workspace.id)
                workspaceToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                workspaceToDelete = nil
            }
        } message: {
            Text("This permanently removes the workspace and all of its cards.")
        }
    }

    private var renameAlertIsPresented: Binding<Bool> {
        Binding(
            get: { workspaceToRename != nil },
            set: { isPresented in
                if !isPresented {
                    workspaceToRename = nil
                }
            }
        )
    }

    private var deleteDialogIsPresented: Binding<Bool> {
        Binding(
            get: { workspaceToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    workspaceToDelete = nil
                }
            }
        )
    }

    private var reorderAnimation: Animation? {
        reduceMotion ? nil : .interactiveSpring(response: 0.16, dampingFraction: 0.9, blendDuration: 0.03)
    }

    private var rowStateAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.1)
    }

    private func workspaceDragGesture(for workspaceID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(workspaceListCoordinateSpace))
            .onChanged { value in
                if draggedWorkspaceID == nil {
                    draggedWorkspaceID = workspaceID
                    let rowMinY = workspaceRowFrames[workspaceID]?.minY ?? value.startLocation.y
                    dragGrabOffsetY = value.startLocation.y - rowMinY
                }

                guard draggedWorkspaceID == workspaceID else { return }

                dragLocationY = value.location.y
                updateReorderTarget(for: workspaceID, at: value.location.y)
            }
            .onEnded { _ in
                resetWorkspaceDrag()
            }
    }

    private func dragOffset(for workspaceID: UUID) -> CGFloat {
        guard draggedWorkspaceID == workspaceID,
              let dragLocationY,
              let frame = workspaceRowFrames[workspaceID] else {
            return 0
        }

        return dragLocationY - dragGrabOffsetY - frame.minY
    }

    private func updateReorderTarget(for draggedID: UUID, at locationY: CGFloat) {
        let hitSlop: CGFloat = 8
        let targetID = library.workspaces.first { workspace in
            guard workspace.id != draggedID,
                  let frame = workspaceRowFrames[workspace.id] else {
                return false
            }

            return locationY >= frame.minY - hitSlop && locationY <= frame.maxY + hitSlop
        }?.id

        guard targetID != dragTargetWorkspaceID else { return }

        dragTargetWorkspaceID = targetID

        guard let targetID else {
            return
        }

        withAnimation(reorderAnimation) {
            onMoveWorkspace(draggedID, targetID)
        }
    }

    private func resetWorkspaceDrag() {
        withAnimation(rowStateAnimation) {
            draggedWorkspaceID = nil
            dragTargetWorkspaceID = nil
            dragLocationY = nil
            dragGrabOffsetY = 0
        }
    }
}

struct WorkspaceSidebarRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    var isDropTarget: Bool = false
    var isDragging: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rowAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.1)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(isDropTarget ? 0.62 : 0.42))
                .frame(width: 14)
                .contentShape(Rectangle())
                .help("Drag to reorder")

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.teal.opacity(isSelected ? 0.18 : 0.08))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? .teal : .white.opacity(0.42))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 0.9 : 0.62))

                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 0.52 : 0.38))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.1 : isDropTarget ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isDropTarget ? Color.teal.opacity(0.45) : .white.opacity(isSelected ? 0.12 : 0.06),
                    lineWidth: isDropTarget ? 1.5 : 1
                )
        )
        .shadow(color: .black.opacity(isDragging ? 0.26 : 0), radius: isDragging ? 14 : 0, x: 0, y: 8)
        .opacity(isDragging ? 0.96 : 1)
        .scaleEffect(isDragging ? 1.015 : 1)
        .animation(rowAnimation, value: isDragging)
        .animation(rowAnimation, value: isDropTarget)
    }
}

private struct WorkspaceSidebarRowFrameReader: View {
    let workspaceID: UUID

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: WorkspaceSidebarRowFramePreferenceKey.self,
                value: [workspaceID: proxy.frame(in: .named(workspaceListCoordinateSpace))]
            )
        }
    }
}

private struct WorkspaceSidebarRowFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

#Preview("Workspace Sidebar") {
    let workspaceID = UUID()
    let library = WorkspaceLibrary(
        selectedWorkspaceID: workspaceID,
        workspaces: [
            WorkspaceSummary(id: workspaceID, name: "Main Canvas", cardCount: 4),
            WorkspaceSummary(id: UUID(), name: "Research", cardCount: 0),
            WorkspaceSummary(id: UUID(), name: "Launch Plan", cardCount: 2)
        ]
    )

    return WorkspaceSidebar(
        library: library,
        activeWorkspaceID: workspaceID,
        onSelectWorkspace: { _ in },
        onCreateWorkspace: {},
        onRenameWorkspace: { _, _ in },
        onDeleteWorkspace: { _ in },
        onMoveWorkspace: { _, _ in }
    )
    .frame(width: 300, height: 760)
    .preferredColorScheme(.dark)
}
