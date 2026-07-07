import SwiftUI
import VoidloomCore

/// Bottom-center mediator pill: typed command input, live pipeline state,
/// result narration, and confirm/cancel for destructive commands. Voice
/// states light up when the voice plan lands — same coordinator, same view.
struct MediatorHUDView: View {
    @ObservedObject var mediator: MediatorSessionCoordinator
    var showsPushToTalkMic: Bool = false
    @State private var input = ""
    @State private var isMicHeld = false
    @FocusState private var inputFocused: Bool
    @State private var refocusTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sunday is "thinking" while parsing/executing a command or streaming a
    /// reply — the state icon animates then, unless the user reduced motion.
    private var isThinking: Bool {
        if mediator.isStreamingReply { return true }
        switch mediator.state {
        case .parsing, .executing: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if !mediator.narration.isEmpty {
                Text(mediator.narration)
                    .font(.callout)
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: 420)
                    .accessibilityIdentifier("mediator.narration")
                    .onChange(of: mediator.narration) { _, newValue in
                        guard !newValue.isEmpty else { return }
                        AccessibilityNotification.Announcement(newValue).post()
                    }
            }
            if case .awaitingConfirmation(let prompt, _) = mediator.state {
                HStack(spacing: 10) {
                    Text(prompt).font(.callout)
                    Button("Confirm") { mediator.confirm(true) }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Confirm")
                        .accessibilityIdentifier("mediator.confirm")
                    Button("Cancel") { mediator.confirm(false) }
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("mediator.cancel")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 420)
                .accessibilityElement(children: .contain)
            }
            HStack(spacing: 8) {
                if showsPushToTalkMic {
                    micButton
                }
                Image(systemName: stateIcon)
                    .foregroundStyle(isThinking ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .symbolEffect(.variableColor.iterative, isActive: isThinking && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                TextField("Ask \(AssistantIdentity.name) — try \"start 2 claude agents\"", text: $input)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .accessibilityIdentifier("mediator.input")
                    .onSubmit(submit)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 420)
            .background(.ultraThinMaterial, in: Capsule())
        }
        // ⌘J (Focus Mediator): terminal cards hold first responder — especially
        // after workspace restore — so the HUD needs a keyboard path back in.
        .onReceive(NotificationCenter.default.publisher(for: MenuAction.notification)) { note in
            if case .focusMediator = note.object as? MenuAction {
                inputFocused = true
            }
        }
    }

    private var micButton: some View {
        Image(systemName: isMicHeld ? "mic.fill" : "mic")
            .font(.body.weight(.medium))
            .foregroundStyle(micForeground)
            .frame(width: 28, height: 28)
            .background(micBackground, in: Circle())
            .contentShape(Circle())
            .gesture(micHoldGesture)
            .help(micHelp)
            .accessibilityLabel("Hold to talk")
            .accessibilityIdentifier("mediator.mic")
            .accessibilityHint(micHelp)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isMicHeld ? "Recording" : "")
            .disabled(mediator.isMicPermissionDenied)
    }

    private var micForeground: Color {
        if mediator.isMicPermissionDenied { return .secondary }
        if isMicHeld { return .white }
        return .primary
    }

    private var micBackground: some ShapeStyle {
        if mediator.isMicPermissionDenied { return AnyShapeStyle(.quaternary) }
        if isMicHeld { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(.quaternary)
    }

    private var micHelp: String {
        if mediator.isMicPermissionDenied {
            return "Microphone access denied — voice is off; typing still works."
        }
        return "Hold to talk, or hold ⌥Space while Voidloom is active."
    }

    private var micHoldGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !mediator.isMicPermissionDenied, !isMicHeld else { return }
                isMicHeld = true
                mediator.pushToTalkPressed()
            }
            .onEnded { _ in
                guard isMicHeld else { return }
                isMicHeld = false
                mediator.pushToTalkReleased()
            }
    }

    private var stateIcon: String {
        switch mediator.state {
        case .idle: "waveform"
        case .capturing: "dot.radiowaves.left.and.right"
        case .parsing: "brain"
        case .executing: "gearshape"
        case .awaitingConfirmation: "questionmark.circle"
        }
    }

    private func submit() {
        let wasTyped = !input.isEmpty
        mediator.submitTyped(input)
        input = ""
        // A command that creates a card (a terminal or note editor) makes it
        // grab first responder on mount, stealing focus mid-conversation. Keep
        // the pill focused so the user can chain commands: assert now, then
        // re-assert after the new card has had a chance to mount and grab it.
        guard wasTyped else { return }
        inputFocused = true
        refocusTask?.cancel()
        refocusTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            inputFocused = true
        }
    }
}
