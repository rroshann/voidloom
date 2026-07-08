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
    /// One-shot outcome ring: 0 → animates to 1 (expands + fades) on success/error.
    @State private var flashProgress: CGFloat = 1
    @State private var flashColor: Color = .green
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
    /// The whole pill glows/pulses while Sunday is listening, working, speaking, or
    /// waiting on a confirmation, so the user knows something is happening.
    private var isBoxActive: Bool {
        isListening || isThinking || isSpeaking || isAwaitingConfirmation
    }

    private var isAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = mediator.state { return true }
        return false
    }

    /// Each state gets its OWN hue so the mode is legible at a glance — not seven
    /// states sharing one accent. Confirmation/consulting are warm (they want you);
    /// thinking is contemplative; listening/executing ride the app accent.
    private var stateColor: Color {
        // Warm orange is RESERVED for "you must act" (confirmation). Consulting is
        // a distinct violet ("another mind"), so the two never blur together.
        if isAwaitingConfirmation { return .orange }
        if mediator.isDelegating { return Color(red: 0.70, green: 0.45, blue: 0.98) }
        if isSpeaking { return .mint }                       // speaking back
        if isListening { return .accentColor }               // attentive
        switch mediator.state {
        case .parsing: return .indigo                        // thinking
        case .executing: return .accentColor                 // doing
        default: return .accentColor
        }
    }

    /// Breath tempo per state — the peripheral rhythm you feel without reading the
    /// hue: urgent for confirmation, quick for listening, slow at idle.
    private var pulsePeriod: Double {
        if isAwaitingConfirmation { return 0.5 }             // urgent — you're blocking
        if isListening { return 0.55 }                       // alert
        if isSpeaking { return 0.9 }
        if mediator.isDelegating { return 0.8 }
        switch mediator.state {
        case .parsing, .executing: return 1.1                // considered
        default: return 2.4                                  // idle: slow resting breath
        }
    }

    /// The bloom breathes between these bounds. Even at idle it stays faintly lit,
    /// so Sunday reads as present-and-waiting rather than powered off.
    private var glowOpacity: Double {
        if reduceMotion { return isBoxActive ? 0.5 : 0.12 }
        if isBoxActive { return boxPulse ? 0.9 : 0.32 }
        return boxPulse ? 0.2 : 0.08                         // idle whisper
    }

    /// (Re)starts the perpetual breath at the current state's tempo. A running
    /// `repeatForever` won't adopt a new duration, so a state change re-arms it.
    private func restartBreath() {
        guard !reduceMotion else { boxPulse = false; return }
        boxPulse = false
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: pulsePeriod).repeatForever(autoreverses: true)) {
                boxPulse = true
            }
        }
    }

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
            if let queued = mediator.queuedUtterance {
                queuedChip(queued)
            }
            HStack(spacing: 8) {
                if showsPushToTalkMic {
                    micButton
                } else if mediator.isMicPermissionDenied {
                    // Always-listening mode shows no mic button, so a denied mic was
                    // invisible — this standing badge makes "voice is off" clear.
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.85))
                        .help("Microphone access is off — enable it in System Settings › Privacy & Security › Microphone")
                        .accessibilityLabel("Microphone access denied")
                }
                if isListening {
                    // Live voice bars that dance with the mic level — proof Sunday
                    // is genuinely hearing you.
                    voiceLevelBars
                } else {
                    Image(systemName: stateIcon)
                        .foregroundStyle(isBoxActive ? AnyShapeStyle(stateColor) : AnyShapeStyle(.secondary))
                        .symbolEffect(.variableColor.iterative, isActive: (isThinking || isSpeaking) && !reduceMotion)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: stateColor)
                        .accessibilityHidden(true)
                }
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
                // A soft bloom that BREATHES rather than blinks — always faintly
                // present at idle (Sunday is here, not asleep) and swelling into the
                // state hue when active. Tempo varies by state (pulsePeriod).
                Capsule()
                    .stroke(stateColor, lineWidth: 2.5)
                    .blur(radius: 6)
                    .opacity(glowOpacity)
                    .scaleEffect(boxPulse ? 1.015 : 1.0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: stateColor)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isBoxActive)
            )
            .overlay(
                // A one-beat ring that expands and fades on the pill itself when a
                // command completes (green) or fails (red) — the only outcome ack
                // that reaches pure-voice mode, where there's no reply bubble.
                Capsule()
                    .stroke(flashColor, lineWidth: 2)
                    .scaleEffect(1 + flashProgress * 0.14)
                    .opacity(Double(1 - flashProgress) * 0.85)
                    .allowsHitTesting(false)
            )
        }
        .onAppear { restartBreath() }
        .onChange(of: pulsePeriod) { _, _ in restartBreath() }
        .onChange(of: mediator.narrationKind) { _, kind in
            guard !reduceMotion else { return }
            switch kind {
            case .success: flashColor = .green
            case .error: flashColor = .orange
            case .info: return
            }
            flashProgress = 0
            withAnimation(.easeOut(duration: 0.55)) { flashProgress = 1 }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: mediator.queuedUtterance)
        .onChange(of: mediator.narration) { _, new in
            // Sunday's reply is transient: show it, keep it up while streaming, then
            // fade it ~3s after it settles. The stored copy lives in the sidebar.
            narrationDismissTask?.cancel()
            guard !new.isEmpty else { showNarration = false; return }
            if showNarration {
                showNarration = true   // already visible (streaming update) — no re-spring
            } else {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.72)) {
                    showNarration = true
                }
            }
            narrationDismissTask = Task {
                while mediator.isStreamingReply { try? await Task.sleep(nanoseconds: 200_000_000) }
                // Longer replies linger a little longer so they stay readable
                // (~3s short → ~6s long); errors hold longest so a failure isn't
                // missed; hovering pauses the dismissal.
                let base = max(3.0, min(6.0, 2.0 + Double(new.count) / 60.0))
                let delay = mediator.narrationKind == .error ? max(base, 9.0) : base
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
    /// Bubble identity by outcome: a sparkle for a reply, a green check for a
    /// completed command, a red warning for a failure — distinct at a glance.
    private var bubbleGlyph: String {
        switch mediator.narrationKind {
        case .info: "sparkle"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }
    private var bubbleTint: Color {
        switch mediator.narrationKind {
        case .info: .accentColor
        case .success: .green
        case .error: .orange
        }
    }

    /// A "next up" chip so a command typed while Sunday is busy is visibly held,
    /// not silently swallowed. Re-keyed on the text so a newest-wins overwrite
    /// reads as a change rather than nothing.
    private func queuedChip(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 10, weight: .semibold))
            Text("Next: \(text)")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .id(text)
        .accessibilityLabel("Queued command: \(text)")
    }

    /// Four bars that rise and fall with the live mic level — the "it's really
    /// listening" moment. Colored by the listening state hue.
    private var voiceLevelBars: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<4, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(stateColor)
                    .frame(width: 2.5, height: barHeight(i))
            }
        }
        .frame(width: 20, height: 16)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: mediator.inputLevel)
        .accessibilityHidden(true)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        // Center bars taller so the cluster reads as a little equalizer, not a row.
        let weights: [CGFloat] = [0.55, 1.0, 0.85, 0.6]
        let level = CGFloat(max(0, min(1, mediator.inputLevel)))
        return 3 + level * 12 * weights[i]
    }

    private var narrationBubble: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: bubbleGlyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(bubbleTint)
                .symbolEffect(.variableColor.iterative, isActive: mediator.isStreamingReply && !reduceMotion)
                .contentTransition(.symbolEffect(.replace))
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
                .strokeBorder(bubbleTint.opacity(mediator.narrationKind == .info ? 0.18 : 0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mediator.narration")
        // Feels SPOKEN from the pill it sits above: it grows up out of the pill's
        // top edge on a spring rather than sliding in like a system toast, and
        // dismisses by gently fading rather than leaving the way it came.
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .scale(scale: 0.82, anchor: .bottom).combined(with: .opacity),
            removal: .opacity))
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
