import SwiftUI
import VoidloomCore

struct RootView: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        ZStack {
            AtmosphereBackground()

            CanvasWorkspaceView(store: store)
                .ignoresSafeArea()

            VStack {
                TopToolbar(cardCount: store.state.cards.count)
                    .padding(.top, 18)

                Spacer()

                CommandBar(errorMessage: store.lastPersistenceError)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .allowsHitTesting(false)

            HStack {
                ToolRail(store: store)
                    .padding(.leading, 22)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct AtmosphereBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.07),
                    Color(red: 0.08, green: 0.08, blue: 0.11),
                    Color(red: 0.02, green: 0.09, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.92, green: 0.42, blue: 0.18).opacity(0.28),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 620
            )

            RadialGradient(
                colors: [
                    Color(red: 0.11, green: 0.68, blue: 0.67).opacity(0.24),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }
}

private struct TopToolbar: View {
    let cardCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Text("VOIDLOOM")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(2.5)

            Divider()
                .frame(height: 18)
                .overlay(.white.opacity(0.25))

            Label("\(cardCount) cards", systemImage: "square.grid.3x2")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            Label("local canvas", systemImage: "externaldrive")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, x: 0, y: 18)
    }
}

private struct ToolRail: View {
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

private struct CommandBar: View {
    let errorMessage: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: errorMessage == nil ? "terminal" : "exclamationmark.triangle")
                .foregroundStyle(errorMessage == nil ? .teal : .orange)

            Text(errorMessage ?? "Try: add agent, add note, reset canvas")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(errorMessage == nil ? 0.68 : 0.86))

            Spacer(minLength: 0)
        }
        .frame(width: 520)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 16)
    }
}

#Preview("Voidloom Shell") {
    RootView(store: PreviewSupport.makeStore())
        .frame(width: 1180, height: 760)
}
