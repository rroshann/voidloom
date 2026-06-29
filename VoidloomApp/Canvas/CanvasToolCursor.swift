import AppKit
import SwiftUI
import VoidloomCore

/// Single source of truth for the pointer shown while a canvas tool is armed,
/// shared by the AppKit input overlay and the SwiftUI re-assert modifier below.
///
/// The eraser resolves to a fully transparent cursor so the only visible
/// indicator is the SwiftUI ring drawn over the canvas; the brush resolves to a
/// pen-tip cursor. Both images are real (non-blank) bitmaps — an empty `NSImage`
/// renders as the default arrow, which previously made the arrow and the ring
/// appear together.
@MainActor
enum CanvasToolCursor {
    /// The cursor for an armed mode. Non-capturing modes (idle) fall back to the
    /// arrow; the modifier guards on `capturesCanvas` so it never asserts this.
    static func cursor(for mode: CanvasInteractionModel.Mode) -> NSCursor {
        switch mode {
        case .erasing:
            return transparentCursor
        case .drawing:
            return penCursor
        case .idle:
            return .arrow
        default:
            return .crosshair
        }
    }

    /// A fully transparent cursor that hides the system pointer over the canvas
    /// while the SwiftUI eraser ring is shown. The image carries a real, cleared
    /// bitmap so it does not fall back to the arrow.
    static let transparentCursor: NSCursor = {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.set()
        NSBezierPath.fill(NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: .zero)
    }()

    /// A pen-style cursor for the brush tool, hot spot at the drawing tip. Falls
    /// back to the crosshair if the SF Symbol cannot be rendered.
    ///
    /// The SF Symbol is drawn into a fresh, non-template bitmap (tinted white so
    /// it reads on the dark canvas). Handing the raw template symbol straight to
    /// `NSCursor` rendered as the default arrow — same fix shape as the
    /// `transparentCursor` above, which is why the eraser worked but this didn't.
    static let penCursor: NSCursor = {
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        guard
            let symbol = NSImage(
                systemSymbolName: "paintbrush.pointed.fill",
                accessibilityDescription: "Brush"
            )?.withSymbolConfiguration(config)
        else {
            return .crosshair
        }
        let size = symbol.size
        let image = NSImage(size: size)
        image.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: size))
        NSColor.white.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return NSCursor(image: image, hotSpot: NSPoint(x: 1, y: size.height - 1))
    }()
}

extension View {
    /// Holds the armed tool's cursor over the canvas by re-asserting it on every
    /// pointer move — the same proven pattern as `pointerCursor()`.
    ///
    /// The AppKit overlay's `.set()`/`cursorUpdate`/cursor-rect mechanisms lose a
    /// per-move race: `NSHostingView` re-asserts the default arrow on every move,
    /// landing last. `.onContinuousHover`'s `.active` fires on every move too, so
    /// setting the cursor there lands *after* SwiftUI's reset and wins. Hover
    /// tracking is geometry-based and independent of the overlay's `hitTest`, so
    /// it fires even though the overlay only claims left-mouse-down for input.
    ///
    /// A no-op while idle, so cards keep managing their own cursors.
    func canvasToolCursor(for mode: CanvasInteractionModel.Mode) -> some View {
        onContinuousHover { phase in
            guard mode.capturesCanvas else { return }
            switch phase {
            case .active:
                CanvasToolCursor.cursor(for: mode).set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }
}
