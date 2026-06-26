import SwiftUI

struct CanvasGrid: View {
    private let minorSpacing: CGFloat = 40
    private let majorSpacing: CGFloat = 160

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                gridPath(in: geometry.size, spacing: minorSpacing)
                    .stroke(.white.opacity(0.035), lineWidth: 1)

                gridPath(in: geometry.size, spacing: majorSpacing)
                    .stroke(.white.opacity(0.085), lineWidth: 1)
            }
        }
    }

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
}
