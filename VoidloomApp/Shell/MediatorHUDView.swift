import SwiftUI
import VoidloomCore

/// Bottom-center mediator pill: typed command input, live pipeline state,
/// result narration, and confirm/cancel for destructive commands. Voice
/// states light up when the voice plan lands — same coordinator, same view.
struct MediatorHUDView: View {
    @ObservedObject var mediator: MediatorSessionCoordinator
    var hasVoiceInput: Bool = false
    @State private var input = ""
    @State private var isMicHeld = false

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
            }
            if case .awaitingConfirmation(let prompt, _) = mediator.state {
                HStack(spacing: 10) {
                    Text(prompt).font(.callout)
                    Button("Confirm") { mediator.confirm(true) }
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { mediator.confirm(false) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: 420)
            }
            HStack(spacing: 8) {
                if hasVoiceInput {
                    micButton
                }
                Image(systemName: stateIcon)
                    .foregroundStyle(.secondary)
                TextField("Ask the mediator — try \"start 2 claude agents\"", text: $input)
                    .textFieldStyle(.plain)
                    .onSubmit(submit)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 420)
            .background(.ultraThinMaterial, in: Capsule())
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
            .accessibilityHint(micHelp)
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
        mediator.submitTyped(input)
        input = ""
    }
}
