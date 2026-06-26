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
                    .padding(.top, 18)

                Spacer()

                CommandBar(errorMessage: store.lastPersistenceError)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .allowsHitTesting(false)

            HStack {
                ToolRail(store: store)
                    .padding(.leading, 22)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Voidloom Shell") {
    RootView(store: PreviewSupport.makeStore())
        .frame(width: 1180, height: 760)
}
