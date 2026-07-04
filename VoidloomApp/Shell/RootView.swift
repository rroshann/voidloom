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
    @AppStorage("voice.mode") private var voiceMode: VoiceInputMode = .pushToTalk
    @AppStorage("voice.wakePhrase") private var wakePhrase = "hey voidloom"

    private let voiceRouter: VoiceTranscriberRouter?

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

        let router: VoiceTranscriberRouter?
        if Self.hasMicrophone {
            let parakeet = ParakeetTranscriber()
            let speechAnalyzer = VoiceTranscriberRouter.speechAnalyzerIfAvailable()
            router = VoiceTranscriberRouter(parakeet: parakeet, speechAnalyzer: speechAnalyzer)
        } else {
            router = nil
        }
        voiceRouter = router

        let coordinator = MediatorSessionCoordinator(
            brain: MediatorBrainFactory.makeBrain(assets: modelAssets),
            executor: CommandExecutor(store: store, terminals: sessionManager, namePool: AgentNamePool()),
            transcriber: router
        )
        if let router {
            coordinator.setMicPermissionDenied(router.isMicPermissionDenied)
            router.onMicPermissionDeniedChanged = { denied in
                coordinator.setMicPermissionDenied(denied)
            }
            router.onWakePhraseMatched = {
                coordinator.wakeDetected()
            }
        }
        _mediator = StateObject(wrappedValue: coordinator)
    }

    private var pushToTalkEnabled: Bool {
        voiceRouter != nil && voiceMode == .pushToTalk
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
            if pushToTalkEnabled {
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
            MediatorHUDView(mediator: mediator, showsPushToTalkMic: pushToTalkEnabled)
                .padding(.bottom, 84)
        }
        .onAppear { applyVoiceConfiguration() }
        .onChange(of: voiceMode) { _, _ in applyVoiceConfiguration() }
        .onChange(of: wakePhrase) { _, _ in applyVoiceConfiguration() }
    }

    private func applyVoiceConfiguration() {
        voiceRouter?.applyConfiguration(mode: voiceMode, wakePhrase: wakePhrase)
    }

    private static var hasMicrophone: Bool {
        AVCaptureDevice.default(for: .audio) != nil
    }
}
