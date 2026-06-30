import SwiftUI

/// Centered, Raycast-style command overlay. Filters `commands` as the user
/// types; an "Ask Assistant" row at the bottom routes free text to the AI.
/// Arrow keys move the selection, Return runs it, Escape (or backdrop) closes.
struct CommandPaletteView: View {
    @Binding var query: String
    let commands: [PaletteCommand]
    let onAskAI: (String) -> Void
    let onClose: () -> Void

    @FocusState private var isSearchFocused: Bool
    @State private var selectedIndex = 0
    @Environment(\.theme) private var theme

    private var filtered: [PaletteCommand] {
        CommandPaletteFilter.filter(commands, query: query)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showAskRow: Bool { !trimmedQuery.isEmpty }

    private var rowCount: Int { filtered.count + (showAskRow ? 1 : 0) }

    private var maxIndex: Int { max(0, rowCount - 1) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                searchField

                Divider().overlay(theme.ink(0.1))

                resultsList

                footer
            }
            .frame(width: 600)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.ink(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 40, x: 0, y: 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 120)
        }
        .onAppear {
            isSearchFocused = true
            selectedIndex = 0
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.ink(0.5))

            TextField("Search commands or ask the assistant…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(theme.ink(0.92))
                .focused($isSearchFocused)
                .onSubmit(runSelected)
                .onExitCommand(perform: onClose)
                .onMoveCommand { direction in
                    switch direction {
                    case .up: move(-1)
                    case .down: move(1)
                    default: break
                    }
                }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, command in
                        if index == 0 || filtered[index - 1].section != command.section {
                            sectionHeader(command.section.rawValue)
                        }

                        CommandRow(
                            title: command.title,
                            systemImage: command.systemImage,
                            isSelected: index == selectedIndex
                        )
                        .id(index)
                        .onTapGesture { run(command) }
                        .onHover { if $0 { selectedIndex = index } }
                    }

                    if showAskRow {
                        sectionHeader("Assistant")

                        AskAssistantRow(query: trimmedQuery, isSelected: selectedIndex == filtered.count)
                            .id(filtered.count)
                            .onTapGesture(perform: runAsk)
                            .onHover { if $0 { selectedIndex = filtered.count } }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 360)
            .onChange(of: selectedIndex) { _, index in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            shortcutHint("↑↓", "Navigate")
            shortcutHint("↩", "Run")
            shortcutHint("esc", "Close")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(theme.surface(0.03))
        .overlay(alignment: .top) {
            Divider().overlay(theme.ink(0.08))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(theme.ink(0.38))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(theme.ink(0.6))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(theme.surface(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(theme.ink(0.4))
        }
    }

    private func move(_ delta: Int) {
        guard rowCount > 0 else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), maxIndex)
    }

    private func runSelected() {
        if showAskRow, selectedIndex == filtered.count {
            runAsk()
        } else if filtered.indices.contains(selectedIndex) {
            run(filtered[selectedIndex])
        } else if showAskRow {
            runAsk()
        }
    }

    private func run(_ command: PaletteCommand) {
        onClose()
        command.action()
    }

    private func runAsk() {
        let text = trimmedQuery
        guard !text.isEmpty else { return }
        onClose()
        onAskAI(text)
    }
}

private struct CommandRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.ink(0.82))
                .frame(width: 22)

            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(theme.ink(0.9))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.surface(isSelected ? 0.12 : 0))
        )
        .contentShape(Rectangle())
    }
}

private struct AskAssistantRow: View {
    let query: String
    let isSelected: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 22)

            Text("Ask Assistant: ")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(theme.ink(0.6))
            + Text("“\(query)”")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.ink(0.92))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.surface(isSelected ? 0.12 : 0))
        )
        .contentShape(Rectangle())
    }
}

#Preview("Command Palette") {
    CommandPaletteView(
        query: .constant(""),
        commands: [
            PaletteCommand(id: "agent", title: "New Agent Card", section: .create, systemImage: "sparkles") {},
            PaletteCommand(id: "note", title: "New Note Card", section: .create, systemImage: "note.text") {},
            PaletteCommand(id: "reset", title: "Reset Viewport", section: .view, systemImage: "scope") {},
            PaletteCommand(id: "settings", title: "Open Settings", section: .app, systemImage: "gearshape") {}
        ],
        onAskAI: { _ in },
        onClose: {}
    )
    .frame(width: 1000, height: 700)
    .preferredColorScheme(.dark)
    .background(Color(red: 0.04, green: 0.05, blue: 0.07))
}
