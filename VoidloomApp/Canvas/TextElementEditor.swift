import AppKit
import SwiftUI

/// A small, isolated AppKit bridge wrapping `NSTextView` for inline editing of an
/// on-canvas text element. SwiftUI's `TextField` can't tell Shift+Enter (insert a
/// newline) from plain Enter (commit), and it silently drops its draft when focus
/// is pulled away by an external state change. `NSTextView` gives us both:
///
/// - Shift+Enter inserts a newline; plain Enter commits and exits.
/// - A single commit fires on teardown / loss of first responder, so an external
///   `editingTextID = nil` (e.g. clicking empty canvas) still persists the draft.
struct TextElementEditor: NSViewRepresentable {
    @Binding var text: String
    let fontSize: Double
    let fontName: String?
    let textColor: Color
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel)
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        applyStyle(to: textView)

        // First-responder must be set after the view joins a window; do it on the
        // next runloop tick and drop the caret at the end of the existing text.
        DispatchQueue.main.async {
            guard textView.window?.firstResponder !== textView else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.onCommit = onCommit
        context.coordinator.onCancel = onCancel
        if textView.string != text {
            textView.string = text
        }
        applyStyle(to: textView)
    }

    static func dismantleNSView(_ textView: NSTextView, coordinator: Coordinator) {
        // The editor is being torn down (Enter commit, Esc cancel, or an external
        // editingTextID = nil). Commit once so a yanked-away draft is never lost.
        coordinator.commitIfNeeded()
    }

    private func applyStyle(to textView: NSTextView) {
        textView.font = Self.resolveFont(name: fontName, size: fontSize)
        let color = NSColor(textColor)
        textView.textColor = color
        textView.insertionPointColor = color
    }

    /// The named font at `size`, or the system-rounded face when no font is set
    /// (or the name fails to resolve).
    static func resolveFont(name: String?, size: Double) -> NSFont {
        let pointSize = CGFloat(size)
        if let name, let custom = NSFont(name: name, size: pointSize) {
            return custom
        }
        let base = NSFont.systemFont(ofSize: pointSize, weight: .semibold)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let rounded = NSFont(descriptor: descriptor, size: pointSize) {
            return rounded
        }
        return base
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onCommit: () -> Void
        var onCancel: () -> Void
        private var finished = false

        init(text: Binding<String>, onCommit: @escaping () -> Void, onCancel: @escaping () -> Void) {
            self._text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                // Shift+Enter: let the text view insert a literal newline.
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    return false
                }
                // Plain Enter: commit and exit.
                commitIfNeeded()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finished = true
                onCancel()
                return true
            default:
                return false
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            // Focus moved elsewhere (e.g. another card clicked) — persist once.
            commitIfNeeded()
        }

        func commitIfNeeded() {
            guard !finished else { return }
            finished = true
            onCommit()
        }
    }
}
