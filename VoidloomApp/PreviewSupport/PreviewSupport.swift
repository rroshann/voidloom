import Foundation
import VoidloomCore

@MainActor
enum PreviewSupport {
    static func makeStore() -> WorkspaceStore {
        WorkspaceStore(
            state: makeState(),
            storageURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("VoidloomPreview")
                .appendingPathComponent("workspace.json")
        )
    }

    static func makeState() -> WorkspaceState {
        var state = WorkspaceStore.makeSeedState()
        state.viewport = CanvasViewport(origin: CanvasPoint(x: 40, y: 24), scale: 0.92)
        return state
    }

    static var cards: [WorkspaceCard] {
        WorkspaceStore.makeSeedState().cards
    }
}
