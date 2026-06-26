import SwiftUI
import VoidloomCore

struct ToolRail: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 12) {
            RailButton(systemName: "sparkles", label: "Agent") {
                store.addCard(kind: .agent)
            }

            RailButton(systemName: "note.text", label: "Note") {
                store.addCard(kind: .note)
            }

            RailButton(systemName: "checklist", label: "Todo") {
                store.addCard(kind: .todo)
            }

            RailButton(systemName: "safari", label: "Preview") {
                store.addCard(kind: .browser)
            }

            Divider()
                .frame(width: 26)
                .overlay(.white.opacity(0.16))
                .padding(.vertical, 3)

            RailButton(systemName: "scope", label: "Reset") {
                store.resetViewport()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 16)
    }
}

private struct RailButton: View {
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
