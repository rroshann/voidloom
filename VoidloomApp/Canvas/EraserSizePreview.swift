import SwiftUI

/// High-frequency pointer state for the eraser size preview, deliberately kept
/// OFF the shared `CanvasInteractionModel`. Updating the pointer location every
/// move on the shared model would republish to every observer (the whole canvas,
/// the dock, every card); here it is owned by `RootView` as plain `@State` (NOT
/// `@StateObject`), so only `EraserSizePreview` — which observes it — re-renders
/// as the pointer moves. Mirrors how pinch-zoom and the eraser cursor are kept
/// local to stay smooth.
@MainActor
final class EraserPreviewModel: ObservableObject {
    @Published var location: CGPoint = .zero
}

/// The cursor-tracking eraser ring shown above the dock while the thickness
/// slider is being adjusted. Isolated into its own observing view so a pointer
/// move re-renders only this ring, never `RootView`, the dock, or the canvas.
struct EraserSizePreview: View {
    @ObservedObject var preview: EraserPreviewModel
    @ObservedObject var interaction: CanvasInteractionModel
    let scale: CGFloat

    var body: some View {
        if interaction.mode == .erasing, interaction.isAdjustingEraserSize {
            EraserFootprintRing(diameter: CGFloat(interaction.eraserThickness) * scale)
                .position(preview.location)
        }
    }
}
