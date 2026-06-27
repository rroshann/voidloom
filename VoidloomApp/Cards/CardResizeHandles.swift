import AppKit
import SwiftUI
import VoidloomCore

private struct BottomRightResizeGuide: Shape {
    let cornerRadius: CGFloat
    let edgeLength: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.maxX - radius - edgeLength, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius - edgeLength))

        return path
    }
}

private struct ResizeHitRegion: Shape {
    let cornerRadius: CGFloat
    let edgeLength: CGFloat
    let hitWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.addRect(
            CGRect(
                x: rect.maxX - radius - edgeLength - hitWidth,
                y: rect.maxY - hitWidth,
                width: edgeLength + radius + hitWidth,
                height: hitWidth
            )
        )
        path.addRect(
            CGRect(
                x: rect.maxX - hitWidth,
                y: rect.maxY - radius - edgeLength - hitWidth,
                width: hitWidth,
                height: edgeLength + radius + hitWidth
            )
        )
        path.addRect(
            CGRect(
                x: rect.maxX - radius - hitWidth,
                y: rect.maxY - radius - hitWidth,
                width: radius + hitWidth,
                height: radius + hitWidth
            )
        )

        return path
    }
}

struct CardResizeHandles: View {
    let cardSize: CardSize
    let cardPosition: CanvasPoint
    let viewportScale: Double
    let isResizeEnabled: Bool
    let accentColor: Color
    let onResizeStart: () -> Void
    let onResize: (CardSize, CanvasPoint) -> Void
    let onResizeEnd: () -> Void

    @State private var isDragging = false
    @State private var startSize = CardSize(width: 0, height: 0)
    @State private var startPosition = CanvasPoint.zero

    private let cornerRadius: CGFloat = 24
    private let edgeLength: CGFloat = 36
    private let strokeWidth: CGFloat = 3.5
    private let hitWidth: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let guide = BottomRightResizeGuide(cornerRadius: cornerRadius, edgeLength: edgeLength)

            ZStack(alignment: .bottomTrailing) {
                guide
                    .stroke(
                        accentColor.opacity(isResizeEnabled ? 0.92 : 0.55),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)
                    )

                ResizeHitRegion(cornerRadius: cornerRadius, edgeLength: edgeLength, hitWidth: hitWidth)
                    .fill(Color.clear)
                    .contentShape(
                        ResizeHitRegion(cornerRadius: cornerRadius, edgeLength: edgeLength, hitWidth: hitWidth)
                    )
                    .onHover { isHovering in
                        guard isResizeEnabled else { return }
                        if isHovering {
                            NSCursor.crosshair.push()
                        } else if !isDragging {
                            NSCursor.pop()
                        }
                    }
                    .highPriorityGesture(resizeGesture)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(isResizeEnabled)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                guard isResizeEnabled else { return }

                if !isDragging {
                    isDragging = true
                    startSize = cardSize
                    startPosition = cardPosition
                    onResizeStart()
                }

                let canvasDelta = CanvasVector(
                    dx: value.translation.width / viewportScale,
                    dy: value.translation.height / viewportScale
                )
                let result = resizedFrame(
                    startSize: startSize,
                    startPosition: startPosition,
                    totalCanvasDelta: canvasDelta
                )
                onResize(result.size, result.position)
            }
            .onEnded { _ in
                isDragging = false
                NSCursor.pop()
                onResizeEnd()
            }
    }

    private func resizedFrame(
        startSize: CardSize,
        startPosition: CanvasPoint,
        totalCanvasDelta: CanvasVector
    ) -> (size: CardSize, position: CanvasPoint) {
        let width = startSize.width + totalCanvasDelta.dx
        let height = startSize.height + totalCanvasDelta.dy
        let clampedSize = CardSize(width: width, height: height).clampedToMinimums()
        return (clampedSize, startPosition)
    }
}
