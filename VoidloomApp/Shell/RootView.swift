import AVFoundation
import SwiftUI
import AppKit
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
    @StateObject private var contextProvider: AssistantContextProvider

    @EnvironmentObject private var session: AppSession

    @AppStorage("app.mode") private var appMode: AppMode = .canvas
    @AppStorage("isMinimapVisible") private var isMinimapVisible = false
    @AppStorage("voice.mode") private var voiceMode: VoiceInputMode = .pushToTalk
    @AppStorage("voice.wakePhrase") private var wakePhrase = "hey sunday"
    @AppStorage("voice.useSpeechAnalyzer") private var useSpeechAnalyzer = false
    // Default: Sunday speaks back when you SPEAK to it (fixes "I can't hear
    // Sunday" — voice replies were silent by default). Typed stays silent unless
    // you pick "Always".
    @AppStorage("voice.speechMode") private var speechMode: AssistantSpeechMode = .whenSpokenTo
    @AppStorage("voice.showTextReplies") private var showTextReplies = true
    @StateObject private var speaker = AssistantSpeaker()

    private let voiceRouter: VoiceTranscriberRouter?

    init(store: WorkspaceStore,
         sessionManager: AgentSessionManager,
         conversationStore: ConversationStore,
         interaction: CanvasInteractionModel,
         modelAssets: ModelAssetManager,
         chatProvider: ResponseProvider) {
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

        // One AgentMemory shared by the executor (writes) and the context
        // provider (reads) so Sunday and the agents stay aware of each other.
        let memory = AgentMemory()
        let coordinator = MediatorSessionCoordinator(
            brain: MediatorBrainFactory.makeBrain(assets: modelAssets),
            executor: CommandExecutor(store: store, terminals: sessionManager, namePool: AgentNamePool(), memory: memory),
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
        let context = AssistantContextProvider(
            store: store, sessionManager: sessionManager, modelAssets: modelAssets, agentMemory: memory)

        // Conversational pill: utterances no brain can parse as a command go to
        // the same chat backend the Assistant sidebar uses — grounded in the live
        // workspace context and streamed into the HUD as they arrive.
        coordinator.chatFallback = { utterance, onChunk in
            await context.refreshGit()
            let grounded = context.snapshot()
            let workspaceID = store.library.selectedWorkspaceID
            let reply = try await Self.streamChat(
                chatProvider,
                workspaceID: workspaceID,
                message: utterance,
                context: grounded,
                onChunk: onChunk)
            // The pill streamed the reply into the HUD; record the exchange so it
            // joins (and persists in) the same history the sidebar shows.
            conversationStore.record(workspaceID: workspaceID, userText: utterance, assistantText: reply)
            return reply
        }
        // Delegation: repo-technical questions run through the user's agent CLI
        // (Claude/Codex per the setting) in the project folder; the answer relays
        // into the HUD. The CLI does the work — Sunday's own brain stays local.
        let delegation = DelegationService(store: store)
        coordinator.delegateHandler = { question, target, onChunk in
            await delegation.delegate(question: question, target: target, onChunk: onChunk)
        }
        _mediator = StateObject(wrappedValue: coordinator)
        _contextProvider = StateObject(wrappedValue: context)
    }

    /// Bridges the callback-based `ResponseProvider` to async + live chunks:
    /// accumulates deltas, forwards the running text to `onChunk`, and resolves
    /// with the final reply (or throws a `backendFailure`).
    private static func streamChat(
        _ provider: ResponseProvider,
        workspaceID: UUID,
        message: String,
        context: String,
        onChunk: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var accumulated = ""
            var resumed = false
            provider.generateResponse(
                workspaceID: workspaceID,
                userMessage: message,
                context: context,
                onStreamChunk: { delta in
                    accumulated += delta
                    onChunk(accumulated)
                },
                onComplete: { reply in
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: reply.isEmpty ? accumulated : reply)
                },
                onError: { message in
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(throwing: BrainError.backendFailure(message))
                }
            )
        }
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
                SpacesShellView(
                    store: store,
                    sessionManager: sessionManager,
                    conversationStore: conversationStore
                )
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
            MediatorHUDView(mediator: mediator, showsPushToTalkMic: pushToTalkEnabled,
                            showTextReplies: showTextReplies)
                .padding(.bottom, 84)
        }
        .environmentObject(contextProvider)
        .onAppear {
            applyVoiceConfiguration()
            Task { await contextProvider.refreshGit() }
        }
        .onChange(of: voiceMode) { _, _ in applyVoiceConfiguration() }
        .onChange(of: wakePhrase) { _, _ in applyVoiceConfiguration() }
        .onChange(of: useSpeechAnalyzer) { _, _ in applyVoiceConfiguration() }
        .onChange(of: store.state.space?.folderPath) { _, _ in
            Task { await contextProvider.refreshGit() }
        }
        // Sunday speaks (opt-in): read the FINAL narration once the pipeline
        // settles, never mid-stream. Barge-in stops speech the moment the mic
        // opens, so Sunday never talks over the user.
        .onChange(of: mediator.narration) { _, newValue in
            guard speechMode.shouldSpeak(inputWasVoice: mediator.lastInputWasVoice),
                  mediator.state == .idle, !mediator.isStreamingReply,
                  !newValue.isEmpty else { return }
            speaker.speak(newValue)
        }
        .onChange(of: mediator.state) { _, newState in
            if case .capturing = newState { speaker.stop() }
        }
        .onChange(of: store.library.workspaces.isEmpty) { _, isEmpty in
            // Deleting the last workspace from inside the app returns to the launcher
            // rather than leaving an empty canvas/space.
            if isEmpty { session.isWorkspaceOpen = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: MenuAction.notification)) { note in
            guard let action = note.object as? MenuAction else { return }
            switch action {
            case .toggleAppMode:
                appMode = appMode == .canvas ? .spaces : .canvas
            case .toggleMinimap:
                isMinimapVisible.toggle()
            case .addCard(let kind):
                store.addCard(kind: kind)
            case .goToLauncher:
                session.isWorkspaceOpen = false
            case .undo:
                if isTypingResponder(NSApp.keyWindow?.firstResponder) {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } else {
                    store.undo()
                }
            case .redo:
                if isTypingResponder(NSApp.keyWindow?.firstResponder) {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                } else {
                    store.redo()
                }
            case .copy:
                if isTypingResponder(NSApp.keyWindow?.firstResponder) {
                    NSApp.sendAction(Selector(("copy:")), to: nil, from: nil)
                } else {
                    store.copySelection()
                }
            case .cut:
                if isTypingResponder(NSApp.keyWindow?.firstResponder) {
                    NSApp.sendAction(Selector(("cut:")), to: nil, from: nil)
                } else {
                    store.cutSelection()
                }
            case .paste:
                if isTypingResponder(NSApp.keyWindow?.firstResponder) {
                    NSApp.sendAction(Selector(("paste:")), to: nil, from: nil)
                } else {
                    store.pasteCards()
                }
            case .duplicate:
                if !(isTypingResponder(NSApp.keyWindow?.firstResponder)) {
                    store.duplicateSelection()
                }
            case .setProjectFolder:
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Choose"
                if let current = store.state.space?.folderPath, !current.isEmpty {
                    panel.directoryURL = URL(fileURLWithPath: current)
                }
                if panel.runModal() == .OK, let url = panel.url {
                    store.setSpaceFolder(url.path)
                }
            case .focusMediator:
                break   // handled by MediatorHUDView, which owns the input's FocusState
            case .runMediatorCommand(let text):
                mediator.submitTyped(text)
            case .toggleAIConversation:
                break   // owned by the active shell (Canvas/Spaces), which holds the state
            case .zoomIn, .zoomOut, .resetViewport:
                break   // handled by CanvasShellView, which owns the zoom anchor
            }
        }
    }

    private func applyVoiceConfiguration() {
        voiceRouter?.applyConfiguration(
            mode: voiceMode,
            wakePhrase: wakePhrase,
            useSpeechAnalyzer: useSpeechAnalyzer
        )
    }

    private static var hasMicrophone: Bool {
        AVCaptureDevice.default(for: .audio) != nil
    }
}
