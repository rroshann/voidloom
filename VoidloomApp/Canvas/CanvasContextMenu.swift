import AppKit
import SwiftUI
import VoidloomCore

/// Transparent overlay that intercepts ONLY right-clicks on the canvas and
/// reports their location (in top-left SwiftUI coordinates). Left-clicks,
/// drags, pan, and zoom pass straight through, because `hitTest` claims the
/// view only while the current event is a right mouse-down.
struct CanvasRightClickCatcher: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class RightClickView: NSView {
        var onRightClick: (CGPoint) -> Void = { _ in }

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            if NSApp.currentEvent?.type == .rightMouseDown {
                return self
            }
            return nil
        }

        override func rightMouseDown(with event: NSEvent) {
            let local = convert(event.locationInWindow, from: nil)
            onRightClick(CGPoint(x: local.x, y: local.y))
        }
    }
}

/// Frosted, app-styled context menu shown at the cursor on canvas right-click.
struct CanvasContextMenu: View {
    let onSelect: (CardKind) -> Void

    @Environment(\.theme) private var theme

    private struct Item: Identifiable {
        let kind: CardKind
        let title: String
        let systemImage: String
        var id: String { kind.id }
    }

    private let items: [Item] = [
        Item(kind: .agent, title: "New Terminal", systemImage: "terminal"),
        Item(kind: .note, title: "New Note", systemImage: "note.text"),
        Item(kind: .todo, title: "New Todo", systemImage: "checklist"),
        Item(kind: .browser, title: "New Browser", systemImage: "safari")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                MenuRow(title: item.title, systemImage: item.systemImage) {
                    onSelect(item.kind)
                }
            }
        }
        .padding(6)
        .frame(width: 196)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.ink(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 14)
    }
}

private struct MenuRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink(0.82))
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.ink(0.9))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.surface(isHovering ? 0.12 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
