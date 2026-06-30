import SwiftUI

/// The round eraser footprint indicator: a soft black halo under a bright white
/// ring so it reads on any canvas content. Render-only and never hit-tested;
/// the caller sizes it (thickness × zoom) and positions it. Shared by the
/// pointer-tracking cursor on the canvas and the size preview shown above the
/// dock while the thickness slider is being adjusted.
struct EraserFootprintRing: View {
    let diameter: CGFloat

    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Circle().stroke(Color.black.opacity(0.45), lineWidth: 3)
            Circle().stroke(theme.ink(0.95), lineWidth: 1.5)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }
}
