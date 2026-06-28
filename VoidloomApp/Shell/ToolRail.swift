import SwiftUI
import VoidloomCore

struct ToolDock: View {
    @ObservedObject var store: WorkspaceStore
    let errorMessage: String?
    let isAIHintActive: Bool
    let onToggleAIHint: () -> Void
    let zoomScale: Double
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let isCardFocused: Bool
    let onToggleCardFocus: (() -> Void)?
    let workspaceName: String
    let isWorkspaceSidebarVisible: Bool
    let onToggleWorkspaceSidebar: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            DockWorkspaceSegment(
                workspaceName: workspaceName,
                cardCount: store.state.cards.count,
                isWorkspaceSidebarVisible: isWorkspaceSidebarVisible,
                onToggle: onToggleWorkspaceSidebar
            )

            DockDivider()

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

            DockDivider()

            CanvasZoomControls(
                scale: zoomScale,
                onZoomIn: onZoomIn,
                onZoomOut: onZoomOut,
                isCardFocused: isCardFocused,
                onToggleCardFocus: onToggleCardFocus,
                embedded: true
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.black.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.32), radius: 28, x: 0, y: 18)
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
    }
}

private struct DockWorkspaceSegment: View {
    let workspaceName: String
    let cardCount: Int
    let isWorkspaceSidebarVisible: Bool
    let onToggle: () -> Void

    @State private var isHovering = false

    private var restingFill: Color {
        if isWorkspaceSidebarVisible {
            return .white.opacity(isHovering ? 0.16 : 0.12)
        }
        return .white.opacity(isHovering ? 0.06 : 0.0)
    }

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 1) {
                Text(workspaceName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(cardCount) \(cardCount == 1 ? "card" : "cards")")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(maxWidth: 160, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(restingFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(
                        isWorkspaceSidebarVisible ? .white.opacity(0.14) : .clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .animation(.easeInOut(duration: 0.15), value: isWorkspaceSidebarVisible)
        }
        .buttonStyle(DockPressStyle())
        .onHover { isHovering = $0 }
        .help(isWorkspaceSidebarVisible ? "Hide workspaces" : "Show workspaces")
    }
}

private struct DockPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

private struct DockButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(.white.opacity(0.86))
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

private struct DockDivider: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.white.opacity(0.14))
            .frame(width: 1, height: 34)
            .padding(.horizontal, 6)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(isActive ? 0.14 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(
                            isActive ? accentColor.opacity(0.55) : .white.opacity(0.06),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .help(message)
    }
}
