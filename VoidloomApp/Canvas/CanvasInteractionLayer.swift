import SwiftUI
import VoidloomCore

/// Render-only overlay drawn ABOVE the cards (never hit-tested) that visualizes
/// in-progress armed interactions. Stage 1 draws the dashed rubber-band sizing
/// rectangle for `placingCard`/`placingText`; later stages extend the switch
/// with the connect follow-arrow and text marquee.
struct CanvasInteractionLayer: View {
    @ObservedObject var interaction: CanvasInteractionModel
    /// Rubber-band drag corners in screen (view) coordinates, or nil when idle.
    var rubberStart: CGPoint?
    var rubberCurrent: CGPoint?
    /// Connect tool: source card frame (screen coords), the border anchor the
    /// follow-arrow starts from, the live cursor, and the source accent.
    var connectSourceRect: CGRect?
    var connectAnchor: CGPoint?
    var connectCursor: CGPoint?
    var connectAccent: Color = Color(red: 0.34, green: 0.93, blue: 0.82)

    var body: some View {
        ZStack {
            if interaction.mode.isRubberBand,
               let start = rubberStart,
               let current = rubberCurrent {
                rubberBand(from: start, to: current)
            }

            if isConnecting {
                if let rect = connectSourceRect {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(connectAccent.opacity(0.8), lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .transition(.opacity)
                }

                if let anchor = connectAnchor, let cursor = connectCursor {
                    ConnectFollowArrow(from: anchor, to: cursor, color: connectAccent)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var isConnecting: Bool {
        if case .connecting = interaction.mode { return true }
        return false
    }

    private func rubberBand(from a: CGPoint, to b: CGPoint) -> some View {
        let rect = CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
        let accent = accentColor

        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                accent,
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.10))
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .transition(.opacity)
    }

    private var accentColor: Color {
        if case let .placingCard(kind) = interaction.mode {
            return CardPalette(kind: kind).accent
        }
        // placingText
        return Color(red: 0.34, green: 0.93, blue: 0.82)
    }
}

/// A marching-ants dashed line with an arrowhead, animated from the source card
/// border to the live cursor while the connect tool has a source selected.
private struct ConnectFollowArrow: View {
    let from: CGPoint
    let to: CGPoint
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 22

            Canvas { context, _ in
                var line = Path()
                line.move(to: from)
                line.addLine(to: to)
                context.stroke(
                    line,
                    with: .color(color.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [7, 5], dashPhase: -phase)
                )

                let angle = atan2(to.y - from.y, to.x - from.x)
                let length: CGFloat = 13
                let width: CGFloat = 8
                let base = CGPoint(x: to.x - length * cos(angle), y: to.y - length * sin(angle))
                let left = CGPoint(
                    x: base.x + width * cos(angle + .pi / 2),
                    y: base.y + width * sin(angle + .pi / 2)
                )
                let right = CGPoint(
                    x: base.x - width * cos(angle + .pi / 2),
                    y: base.y - width * sin(angle + .pi / 2)
                )
                var head = Path()
                head.move(to: to)
                head.addLine(to: left)
                head.addLine(to: right)
                head.closeSubpath()
                context.fill(head, with: .color(color))

                context.fill(
                    Path(ellipseIn: CGRect(x: from.x - 3.5, y: from.y - 3.5, width: 7, height: 7)),
                    with: .color(color)
                )
            }
        }
    }
}
