import SwiftUI
import VoidloomCore

/// Render-only overlay drawn ABOVE the cards (never hit-tested) that visualizes
/// in-progress armed interactions. Stage 1 draws the dashed rubber-band sizing
/// rectangle for `placingCard`/`placingText`; later stages extend the switch
/// with the connect follow-arrow and text marquee.
struct CanvasInteractionLayer: View {
    @Environment(\.theme) private var theme
    @ObservedObject var interaction: CanvasInteractionModel
    /// Rubber-band drag corners in screen (view) coordinates, or nil when idle.
    var rubberStart: CGPoint?
    var rubberCurrent: CGPoint?
    /// Connect tool: source card frame (screen coords), the hovered (prospective
    /// pick) card frame, the border anchor the follow-arrow starts from, the live
    /// cursor, and the source accent.
    var connectSourceRect: CGRect?
    var connectHoverRect: CGRect?
    var connectAnchor: CGPoint?
    var connectCursor: CGPoint?
    var connectAccent: Color = Color(red: 0.34, green: 0.93, blue: 0.82)
    /// Selection-box drag corners in screen (view) coordinates, or nil when no
    /// marquee drag is in progress. Mode-agnostic — drawn whenever both are set.
    var marqueeStart: CGPoint?
    var marqueeCurrent: CGPoint?

    var body: some View {
        ZStack {
            if interaction.mode.isRubberBand,
               let start = rubberStart,
               let current = rubberCurrent {
                rubberBand(from: start, to: current)
            }

            if let start = marqueeStart, let current = marqueeCurrent {
                marqueeBox(from: start, to: current)
            }

            if isConnecting {
                // Prospective pick under the cursor: a filled, brighter, glowing
                // ring — visually distinct from the source ring and from normal
                // card selection — signalling "click to pick this".
                if let rect = connectHoverRect {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(connectAccent.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(connectAccent, lineWidth: 2.5)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: connectAccent.opacity(0.6), radius: 10)
                        .transition(.opacity)
                }

                // The chosen source stays marked while picking the target: a
                // solid ring with no fill/glow so it reads as "locked in".
                if let rect = connectSourceRect {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(connectAccent.opacity(0.8), lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .transition(.opacity)
                }

                if let anchor = connectAnchor, let cursor = connectCursor {
                    ConnectFollowLine(from: anchor, to: cursor, color: connectAccent)
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

    /// The system-blue dashed selection rectangle with a faint fill, drawn while
    /// the user drags a left-click marquee over empty canvas.
    private func marqueeBox(from a: CGPoint, to b: CGPoint) -> some View {
        let rect = CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(
                Color.accentColor.opacity(0.9),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private var accentColor: Color {
        if case let .placingCard(kind) = interaction.mode {
            return CardPalette(kind: kind, isDark: theme.isDark).accent
        }
        // placingText
        return theme.accent
    }
}

/// A marching-ants dashed line capped by a dot at BOTH ends, animated from the
/// source card border to the live cursor while the connect tool has a source
/// selected. No arrowhead — connections are non-directional.
private struct ConnectFollowLine: View {
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

                for anchor in [from, to] {
                    context.fill(
                        Path(ellipseIn: CGRect(x: anchor.x - 3.5, y: anchor.y - 3.5, width: 7, height: 7)),
                        with: .color(color)
                    )
                }
            }
        }
    }
}
