import SwiftUI
import VoidloomCore

/// Bottom-center mediator pill: typed command input, live pipeline state,
/// result narration, and confirm/cancel for destructive commands. Voice
/// states light up when the voice plan lands — same coordinator, same view.
struct MediatorHUDView: View {
    @ObservedObject var mediator: MediatorSessionCoordinator
    var showsPushToTalkMic: Bool = false
    /// When false and the request came by voice, Sunday's reply is spoken but not
    /// shown as text — a pure spoken conversation.
    var showTextReplies: Bool = true
    /// True while Sunday is reading a reply aloud — drives the speaking indicator.
    var isSpeaking: Bool = false
    @State private var input = ""
    @State private var isMicHeld = false
    @FocusState private var inputFocused: Bool
    @State private var refocusTask: Task<Void, Never>?
    @State private var hintIndex = 0
    @State private var showNarration = false
    @State private var narrationDismissTask: Task<Void, Never>?
    @State private var isHoveringNarration = false
    @State private var boxPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// While the mic is capturing, the machine's `.capturing` state carries the
    /// live transcript — surfacing it lets the user SEE what Sunday heard.
    private var listeningTranscript: String? {
        if case .capturing(let text) = mediator.state { return text }
        return nil
    }
    private var isListening: Bool {
        if case .capturing = mediator.state { return true }
        return false
    }
    /// The whole pill glows/pulses while Sunday is listening, working, or speaking,
    /// so the user knows something is happening (not just a small icon).
    private var isBoxActive: Bool { isListening || isThinking || isSpeaking }

    /// Rotating examples so users discover Sunday's breadth beyond spawning.
    private static let hints = [
        "start 2 claude agents", "ask ember about the build", "rename ember to scout",
        "research how auth works", "brief slate", "make a todo: ship it",
    ]
    private let hintTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    private var placeholder: String {
        let hint = reduceMotion ? Self.hints[0] : Self.hints[hintIndex % Self.hints.count]
        return "Ask \(AssistantIdentity.name) — try \"\(hint)\""
    }

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
            // Pure-voice mode: when the request came by voice and text replies are
            // off, Sunday speaks but shows no bubble.
            if showNarration, !mediator.narration.isEmpty,
               !(mediator.lastInputWasVoice && !showTextReplies) {
                narrationBubble
            }
            if case .awaitingConfirmation(let prompt, _) = mediator.state {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(prompt)
                        .font(.callout.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Cancel") { mediator.confirm(false) }
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Cancel")
                        .accessibilityIdentifier("mediator.cancel")
                    // No default (Enter) shortcut on a destructive action, so an
                    // idle Return never confirms it by accident — the user clicks
                    // or types "confirm".
                    Button("Confirm") { mediator.confirm(true) }
                        .tint(.red)
                        .accessibilityLabel("Confirm")
                        .accessibilityIdentifier("mediator.confirm")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 420)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                .accessibilityElement(children: .contain)
            }
            HStack(spacing: 8) {
                if showsPushToTalkMic {
                    micButton
                }
                Image(systemName: stateIcon)
                    .foregroundStyle(isThinking || isSpeaking ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .symbolEffect(.variableColor.iterative, isActive: (isThinking || isSpeaking) && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                if isListening {
                    // Voice: show what Sunday is hearing, live, in place of the field.
                    Text(listeningTranscript?.isEmpty == false ? listeningTranscript! : "Listening…")
                        .foregroundStyle(listeningTranscript?.isEmpty == false ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(listeningTranscript?.isEmpty == false ? "Heard: \(listeningTranscript!)" : "Listening")
                } else {
                    TextField(placeholder, text: $input)
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .accessibilityIdentifier("mediator.input")
                        // Stable label — the visible placeholder rotates, but VoiceOver
                        // should always hear the same thing.
                        .accessibilityLabel("Ask \(AssistantIdentity.name)")
                        .onSubmit(submit)
                        .onReceive(hintTimer) { _ in
                            // Rotate only while empty (never mid-typing); reduce motion
                            // pins to the first hint.
                            guard !reduceMotion, input.isEmpty else { return }
                            withAnimation(.easeInOut(duration: 0.4)) { hintIndex += 1 }
                        }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 420)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                // The whole pill glows while listening/working — a bigger, calmer
                // signal than the small icon that something is happening.
                Capsule()
                    .strokeBorder(.tint, lineWidth: 1.5)
                    .opacity(isBoxActive ? (boxPulse ? 0.85 : 0.28) : 0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: boxPulse)
            )
        }
        .onChange(of: isBoxActive) { _, active in
            boxPulse = active && !reduceMotion
        }
        .onChange(of: mediator.narration) { _, new in
            // Sunday's reply is transient: show it, keep it up while streaming, then
            // fade it ~3s after it settles. The stored copy lives in the sidebar.
            narrationDismissTask?.cancel()
            guard !new.isEmpty else { showNarration = false; return }
            showNarration = true
            narrationDismissTask = Task {
                while mediator.isStreamingReply { try? await Task.sleep(nanoseconds: 200_000_000) }
                // Longer replies linger a little longer so they stay readable
                // (~3s short → ~6s long); hovering pauses the dismissal.
                let delay = max(3.0, min(6.0, 2.0 + Double(new.count) / 60.0))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                while isHoveringNarration { try? await Task.sleep(nanoseconds: 300_000_000) }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.4)) { showNarration = false }
            }
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

    /// Sunday's reply, styled as her speaking: an identity glyph, refined
    /// material, an accent hairline, and a soft lift — not a debug label.
    private var narrationBubble: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: mediator.isStreamingReply && !reduceMotion)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(mediator.narration)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mediator.narration")
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        // Hovering keeps the reply up so you can finish reading a long one.
        .onHover { isHoveringNarration = $0 }
        .onChange(of: mediator.narration) { _, newValue in
            guard !newValue.isEmpty else { return }
            AccessibilityNotification.Announcement(newValue).post()
        }
    }

    private var stateIcon: String {
        // Delegation reads as consulting another agent, distinct from thinking.
        if mediator.isDelegating { return "person.wave.2.fill" }
        if isSpeaking { return "speaker.wave.2.fill" }   // Sunday is talking back
        return switch mediator.state {
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
