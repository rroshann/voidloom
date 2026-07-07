import AppKit
import SwiftUI
import VoidloomAI
import VoidloomCore

/// Right-side AI conversation drawer. Mirrors `WorkspaceSidebar` styling but
/// pins to the trailing edge. Displays the active workspace's message thread
/// and a bottom input for sending more messages.
struct AIConversationSidebar: View {
    let messages: [ChatMessage]
    let onSubmit: (String) -> Void
    let onRetry: (UUID) -> Void
    let onClose: () -> Void

    @State private var input = ""
    @State private var hasChatBackend = false
    @EnvironmentObject private var modelAssets: ModelAssetManager
    @FocusState private var isInputFocused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 16) {
                header

                if !hasChatBackend {
                    connectAIBanner
                }

                if messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                inputBar
            }
            .padding(.top, 28)
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(width: 340, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(theme.ink(0.1))
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 32, x: -18, y: 0)
        }
        .ignoresSafeArea()
        .onAppear { refreshAIKeyState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAIKeyState()
        }
    }

    private var connectAIBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)

                Text("Connect AI")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.ink(0.78))
            }

            Text("Chat uses Apple Intelligence when available, or the local chat model — download it in Settings. Until then, replies are simulated. A relaunch applies either change.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(theme.ink(0.42))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openSettings) {
                Text("Open Settings")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.ink(0.95))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerCursor()

            Text("Settings → AI  (⌘,)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(theme.ink(0.32))
        }
        .padding(14)
        .background(theme.surface(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(theme.accent.opacity(0.25), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)

            Text("Assistant")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(theme.ink(0.48))

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(theme.ink(0.7))
                    .background(theme.surface(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Close conversation")
            .accessibilityLabel("Close conversation")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()

            Text("No conversation yet")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(theme.ink(0.6))

            Text("Ask the assistant to add cards, reset the canvas, or organize this workspace.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(theme.ink(0.38))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message,
                                      onRetry: { onRetry(message.id) })
                            .id(message.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: messages.last?.text) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message the assistant…", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.ink(0.86))
                .focused($isInputFocused)
                .onSubmit(submit)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(canSubmit ? theme.accent : theme.ink(0.22))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(!canSubmit)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.surface(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.ink(0.1), lineWidth: 1)
        )
        .onAppear { isInputFocused = true }
    }

    private var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func refreshAIKeyState() {
        hasChatBackend = AppleTierAvailability.foundationModelsAvailable
            || modelAssets.state(of: LocalModelManifest.chatModel) == .ready
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func submit() {
        guard canSubmit else { return }
        refreshAIKeyState()
        onSubmit(input)
        input = ""
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let onRetry: () -> Void

    private var isUser: Bool { message.role == .user }
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 32) }

            bubbleContent
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 32) }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.status {
        case .pending:
            PulsingDots()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.surface(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.ink(0.08), lineWidth: 1)
                )

        case .streaming(_):
            TimelineView(.periodic(from: .now, by: 0.5)) { tl in
                let caret = Int(tl.date.timeIntervalSince1970 * 2) % 2 == 0
                Text((message.streamingText ?? "") + (caret ? "▋" : " "))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.ink(0.78))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(theme.surface(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.ink(0.08), lineWidth: 1)
                    )
            }

        case .failed(_):
            VStack(alignment: .leading, spacing: 6) {
                Text(message.text.isEmpty ? "Response failed." : message.text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.orange.opacity(0.3), lineWidth: 1)
            )

        case .sent, .complete:
            Text(message.text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(theme.ink(isUser ? 0.92 : 0.78))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isUser ? theme.accent.opacity(0.22) : theme.surface(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isUser ? theme.accent.opacity(0.3) : theme.ink(0.08), lineWidth: 1)
                )
        }
    }
}

// MARK: - Pulsing Dots

private struct PulsingDots: View {
    @State private var phase = [false, false, false]
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(theme.ink(phase[i] ? 0.8 : 0.25))
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.2),
                        value: phase[i]
                    )
            }
        }
        .onAppear {
            phase = [true, true, true]
        }
    }
}

#Preview("AI Conversation Sidebar") {
    AIConversationSidebar(
        messages: [
            ChatMessage(role: .user, text: "add an agent card"),
            ChatMessage(role: .assistant, text: "✨ AI backend isn't connected yet — this is where responses will appear.", status: .complete)
        ],
        onSubmit: { _ in },
        onRetry: { _ in },
        onClose: {}
    )
    .environmentObject(ModelAssetManager())
    .frame(width: 340, height: 760)
    .preferredColorScheme(.dark)
    .background(Color(red: 0.04, green: 0.05, blue: 0.07))
}
