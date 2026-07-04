import AVFoundation
import SwiftUI
import VoidloomAI
import VoidloomCore

/// Top-level shell: switches between the free pan/zoom Canvas presentation and
/// the auto-tiled Spaces presentation based on the persisted `app.mode` flag.
/// Both shells render the same active `WorkspaceState`; the flag is UI-only and
/// never touches workspace data, so switching is lossless.
struct RootView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @ObservedObject var conversationStore: ConversationStore
    @ObservedObject var interaction: CanvasInteractionModel
    @ObservedObject var modelAssets: ModelAssetManager
    @StateObject private var mediator: MediatorSessionCoordinator

    @AppStorage("app.mode") private var appMode: AppMode = .canvas
    private let hasVoiceInput: Bool

    init(store: WorkspaceStore,
         sessionManager: AgentSessionManager,
         conversationStore: ConversationStore,
         interaction: CanvasInteractionModel,
         modelAssets: ModelAssetManager) {
        self.store = store
        self.sessionManager = sessionManager
        self.conversationStore = conversationStore
        self.interaction = interaction
        self.modelAssets = modelAssets

        let voiceTranscriber: ParakeetTranscriber? = Self.hasMicrophone ? ParakeetTranscriber() : nil
        let coordinator = MediatorSessionCoordinator(
            brain: MediatorBrainFactory.makeBrain(assets: modelAssets),
            executor: CommandExecutor(store: store, terminals: sessionManager, namePool: AgentNamePool()),
            transcriber: voiceTranscriber
        )
        if let voiceTranscriber {
            coordinator.setMicPermissionDenied(voiceTranscriber.isMicPermissionDenied)
            voiceTranscriber.onMicPermissionDeniedChanged = { denied in
                coordinator.setMicPermissionDenied(denied)
            }
        }
        hasVoiceInput = voiceTranscriber != nil
        _mediator = StateObject(wrappedValue: coordinator)
    }

    var body: some View {
        ZStack {
            switch appMode {
            case .canvas:
                CanvasShellView(
                    store: store,
                    sessionManager: sessionManager,
                    conversationStore: conversationStore,
                    interaction: interaction
                )
                .transition(.opacity)
            case .spaces:
                SpacesShellView(store: store, sessionManager: sessionManager)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: appMode)
        .background {
            if hasVoiceInput {
                VoicePushToTalkKeyMonitor(
                    onPress: {
                        guard !mediator.isMicPermissionDenied else { return }
                        mediator.pushToTalkPressed()
                    },
                    onRelease: { mediator.pushToTalkReleased() }
                )
            }
        }
        .overlay(alignment: .bottom) {
            MediatorHUDView(mediator: mediator, hasVoiceInput: hasVoiceInput)
                .padding(.bottom, 84)
        }
    }

    private static var hasMicrophone: Bool {
        AVCaptureDevice.default(for: .audio) != nil
    }
}
