import SwiftUI
import VoidloomCore

struct ToolDock: View {
    @ObservedObject var store: WorkspaceStore
    let errorMessage: String?
    let isAIHintActive: Bool
    let onToggleAIHint: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            DockButton(systemName: "sparkles", label: "Agent") {
                store.addCard(kind: .agent)
            }

            DockButton(systemName: "note.text", label: "Note") {
                store.addCard(kind: .note)
            }

            DockButton(systemName: "checklist", label: "Todo") {
                store.addCard(kind: .todo)
            }

            DockButton(systemName: "safari", label: "Preview") {
                store.addCard(kind: .browser)
            }

            DockDivider()

            DockButton(systemName: "scope", label: "Reset") {
                store.resetViewport()
            }

            DockDivider()

            DockAIHint(
                errorMessage: errorMessage,
                isActive: isAIHintActive,
                action: onToggleAIHint
            )
        }
        .padding(12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 16)
    }
}

private struct DockButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 38, height: 38)
                .foregroundStyle(.white.opacity(0.86))
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(.white.opacity(0.11), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

private struct DockDivider: View {
    var body: some View {
        Divider()
            .frame(height: 26)
            .overlay(.white.opacity(0.16))
            .padding(.horizontal, 2)
    }
}

private struct DockAIHint: View {
    let errorMessage: String?
    let isActive: Bool
    let action: () -> Void

    private var message: String {
        if isActive {
            return "Hide command hints"
        }
        return errorMessage ?? "Show command hints"
    }

    private var iconName: String {
        errorMessage == nil ? "terminal" : "exclamationmark.triangle"
    }

    private var accentColor: Color {
        errorMessage == nil ? .teal : .orange
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accentColor)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.white.opacity(isActive ? 0.14 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(
                            isActive ? accentColor.opacity(0.55) : .white.opacity(0.11),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .help(message)
    }
}
