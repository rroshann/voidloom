import SwiftUI
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
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 16) {
                header

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
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 32, x: -18, y: 0)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.teal)

            Text("Assistant")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.48))

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.white.opacity(0.7))
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Close conversation")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()

            Text("No conversation yet")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))

            Text("Ask the assistant to add cards, reset the canvas, or organize this workspace.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
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
                .foregroundStyle(.white.opacity(0.86))
                .focused($isInputFocused)
                .onSubmit(submit)

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(canSubmit ? .teal : .white.opacity(0.22))
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .disabled(!canSubmit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear { isInputFocused = true }
    }

    private var canSubmit: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        onSubmit(input)
        input = ""
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let onRetry: () -> Void

    private var isUser: Bool { message.role == .user }

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
                        .fill(.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )

        case .streaming(_):
            TimelineView(.periodic(from: .now, by: 0.5)) { tl in
                let caret = Int(tl.date.timeIntervalSince1970 * 2) % 2 == 0
                Text((message.streamingText ?? "") + (caret ? "▋" : " "))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
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
                .foregroundStyle(.white.opacity(isUser ? 0.92 : 0.78))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isUser ? Color.teal.opacity(0.22) : .white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isUser ? Color.teal.opacity(0.3) : .white.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

// MARK: - Pulsing Dots

private struct PulsingDots: View {
    @State private var phase = [false, false, false]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(.white.opacity(phase[i] ? 0.8 : 0.25))
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
    .frame(width: 340, height: 760)
    .preferredColorScheme(.dark)
    .background(Color(red: 0.04, green: 0.05, blue: 0.07))
}
