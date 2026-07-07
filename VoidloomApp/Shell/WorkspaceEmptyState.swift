import SwiftUI
import VoidloomCore

/// The inviting "blank canvas" shown in an empty workspace (both Spaces and
/// Canvas modes). Points at Sunday and offers tappable example commands, so a
/// new workspace teaches what to do rather than sitting silent.
struct WorkspaceEmptyState: View {
    private static let examples = ["start 2 claude agents", "note: my ideas", "todo: plan the week"]

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tint)
            Text("A blank canvas")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Text("Ask Sunday below to begin — or add a card from the dock.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                ForEach(Self.examples, id: \.self) { hint in
                    Button { MenuAction.runMediatorCommand(hint).post() } label: {
                        Text(hint)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help("Run: \(hint)")
                }
            }
            .padding(.top, 4)
        }
    }
}
