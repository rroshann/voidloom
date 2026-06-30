import SwiftUI
import VoidloomCore

struct AgentTerminalView: View {
    let cardID: UUID
    let accent: Color
    let isSelected: Bool

    @Environment(\.theme) private var theme
    @EnvironmentObject private var agentSessionManager: AgentSessionManager
    @State private var input = ""
    @FocusState private var isInputFocused: Bool

    private var outputLines: [String] {
        agentSessionManager.session(for: cardID)?.outputLines ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(outputLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 12 * theme.fontScale, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.ink(index == 0 ? 0.86 : 0.66))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: outputLines.count) { _, count in
                    guard count > 0 else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }

            Divider()
                .overlay(theme.ink(0.12))

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)

                TextField("Command", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12 * theme.fontScale, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.ink(0.86))
                    .focused($isInputFocused)
                    .onSubmit {
                        submitInput()
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .allowsHitTesting(isSelected)
        }
        .onAppear {
            agentSessionManager.startSession(cardID: cardID)
        }
        .onChange(of: isSelected) { _, selected in
            if !selected {
                isInputFocused = false
                input = ""
            }
        }
    }

    private func submitInput() {
        let command = input
        input = ""
        agentSessionManager.submitInput(cardID: cardID, input: command)
    }
}
