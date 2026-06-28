import AppKit
import SwiftUI

extension View {
    /// Shows the macOS pointing-hand cursor while hovering — SwiftUI does not do
    /// this automatically for custom buttons.
    ///
    /// Uses continuous hover so the cursor holds (a one-shot `.onHover` set is
    /// overridden by AppKit's per-move cursor reset) and reverts to the arrow on
    /// exit, without touching the global `NSCursor.push/pop` stack.
    func pointerCursor() -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }
}
