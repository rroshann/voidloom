import SwiftUI
import VoidloomCore

struct CanvasGrid: View {
    @Environment(\.theme) private var theme

    private let minorSpacing: CGFloat = 40
    private let majorSpacing: CGFloat = 160

    var body: some View {
        GeometryReader { geometry in
            switch theme.canvasBackground {
            case .solid:
                EmptyView()

            case .grid:
                ZStack {
                    gridPath(in: geometry.size, spacing: minorSpacing)
                        .stroke(theme.gridMinor, lineWidth: 1)
                    gridPath(in: geometry.size, spacing: majorSpacing)
                        .stroke(theme.gridMajor, lineWidth: 1)
                }

            case .dots:
                Canvas { context, size in
                    let dotRadius: CGFloat = 1.0
                    var x = CGFloat(0)
                    while x <= size.width {
                        var y = CGFloat(0)
                        while y <= size.height {
                            let rect = CGRect(
                                x: x - dotRadius, y: y - dotRadius,
                                width: dotRadius * 2, height: dotRadius * 2
                            )
                            let isMajor = x.truncatingRemainder(dividingBy: majorSpacing) == 0
                                && y.truncatingRemainder(dividingBy: majorSpacing) == 0
                            context.fill(
                                Path(ellipseIn: rect),
                                with: .color(isMajor ? theme.gridMajor : theme.gridMinor)
                            )
                            y += minorSpacing
                        }
                        x += minorSpacing
                    }
                }

            case .lines:
                horizontalLinesPath(in: geometry.size)
                    .stroke(theme.gridMinor, lineWidth: 1)

            case .blueprint:
                ZStack {
                    // Dense minor grid in accent, faint
                    gridPath(in: geometry.size, spacing: minorSpacing)
                        .stroke(theme.accent.opacity(0.12), lineWidth: 0.5)
                    // Major grid in accent, prominent
                    gridPath(in: geometry.size, spacing: majorSpacing)
                        .stroke(theme.accent.opacity(0.45), lineWidth: 1)
                }
            }
        }
    }

    // Crossed lines at `spacing` intervals (horizontal + vertical).
    private func gridPath(in size: CGSize, spacing: CGFloat) -> Path {
        var path = Path()

        for x in stride(from: CGFloat(0), through: size.width, by: spacing) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }

        for y in stride(from: CGFloat(0), through: size.height, by: spacing) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }

        return path
    }

    // Horizontal lines only (`.lines` style).
    private func horizontalLinesPath(in size: CGSize) -> Path {
        var path = Path()
        for y in stride(from: CGFloat(0), through: size.height, by: minorSpacing) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
        }
        return path
    }
}
