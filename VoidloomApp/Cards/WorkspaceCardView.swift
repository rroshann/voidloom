import SwiftUI
import VoidloomCore

struct WorkspaceCardView: View {
    let card: WorkspaceCard
    var isSelected: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .overlay(.white.opacity(0.12))

            content
        }
        .background(cardBackground)
        .overlay(cardBorder)
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: 18)
        .animation(selectionAnimation, value: isSelected)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.18))

                Image(systemName: palette.symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)

                Text(palette.eyebrow)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .textCase(.uppercase)
                    .tracking(1.1)
                    .foregroundStyle(palette.accent.opacity(0.78))
            }

            Spacer(minLength: 0)

            Circle()
                .fill(palette.accent)
                .frame(width: 7, height: 7)
                .shadow(color: palette.accent.opacity(0.8), radius: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .agent:
            terminalContent
        case .browser:
            browserContent
        case .note, .todo:
            textContent
        }
    }

    private var terminalContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(contentLines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(index == 0 ? "$" : "›")
                        .foregroundStyle(palette.accent)
                        .fontWeight(.bold)

                    Text(line)
                        .foregroundStyle(.white.opacity(index == 0 ? 0.86 : 0.66))
                }
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .padding(16)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(contentLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 13, weight: .semibold, design: card.kind == .todo ? .monospaced : .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var browserContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(.red.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(.yellow.opacity(0.75)).frame(width: 8, height: 8)
                Circle().fill(.green.opacity(0.75)).frame(width: 8, height: 8)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(height: 20)
                    .overlay(
                        Text("voidloom.local/preview")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.45))
                    )
            }

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.accent.opacity(0.18),
                            .white.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Text(card.content)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .multilineTextAlignment(.center)
                        .padding(18)
                )
        }
        .padding(14)
    }

    private var contentLines: [String] {
        card.content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                LinearGradient(
                    colors: [
                        palette.accent.opacity(isSelected ? 0.22 : 0.16),
                        .white.opacity(0.045),
                        .black.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: isSelected
                        ? [
                            palette.accent.opacity(0.72),
                            palette.accent.opacity(0.42),
                            .white.opacity(0.18)
                        ]
                        : [
                            .white.opacity(0.22),
                            palette.accent.opacity(0.18),
                            .white.opacity(0.06)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isSelected ? 2 : 1
            )
    }

    private var cardShadowColor: Color {
        isSelected ? palette.accent.opacity(0.35) : palette.shadow
    }

    private var cardShadowRadius: CGFloat {
        isSelected ? 30 : 24
    }

    private var palette: CardPalette {
        CardPalette(kind: card.kind)
    }
}

#Preview("Workspace Cards") {
    let cards = PreviewSupport.cards
    HStack(spacing: 20) {
        if let unselected = cards.first {
            WorkspaceCardView(card: unselected, isSelected: false)
                .frame(width: CGFloat(unselected.size.width), height: CGFloat(unselected.size.height))
        }
        if let selected = cards.dropFirst().first {
            WorkspaceCardView(card: selected, isSelected: true)
                .frame(width: CGFloat(selected.size.width), height: CGFloat(selected.size.height))
        }
    }
    .padding(28)
    .background(Color(red: 0.04, green: 0.05, blue: 0.07))
}
