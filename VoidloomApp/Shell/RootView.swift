import SwiftUI
import VoidloomCore

struct RootView: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        ZStack {
            AtmosphereBackground()

            CanvasWorkspaceView(store: store)
                .ignoresSafeArea()

            VStack {
                TopToolbar(cardCount: store.state.cards.count)
                    .padding(.top, 6)

                Spacer()
            }
            .padding(.horizontal, 24)
            .allowsHitTesting(false)

            VStack {
                Spacer()

                ToolDock(store: store, errorMessage: store.lastPersistenceError)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Voidloom Shell") {
    RootView(store: PreviewSupport.makeStore())
        .frame(width: 1180, height: 760)
}
