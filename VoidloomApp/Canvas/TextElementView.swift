import AppKit
import SwiftUI
import VoidloomCore

/// A chromeless on-canvas text element — just text, no card window. Rendered in
/// the scaled canvas ZStack above the cards. Single-tap selects, double-tap
/// edits, drag moves, and (when selected) a bottom-right grip resizes down to
/// the text minimums. Mirrors `WorkspaceCardView` title editing for inline
/// editing. Visuals only.
struct TextElementView: View {
    let element: TextElement
    @ObservedObject var store: WorkspaceStore
    let viewportScale: Double
    @Binding var editingTextID: UUID?

    @State private var lastDragTranslation: CGSize = .zero
    @State private var draftText = ""
    @State private var isResizing = false

    private let accent = Color(red: 0.34, green: 0.93, blue: 0.82)

    private var isSelected: Bool { store.state.selectedTextID == element.id }
    private var isEditing: Bool { editingTextID == element.id }
    private var textColor: Color { Color(hexString: element.colorHex) ?? .white }

    /// The display font for the element: a named face when one is set, otherwise
    /// the default system-rounded face. Mirrors `TextElementEditor.resolveFont`.
    private var elementFont: Font {
        if let name = element.fontName {
            return .custom(name, size: CGFloat(element.fontSize))
        }
        return .system(size: CGFloat(element.fontSize), weight: .semibold, design: .rounded)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(
                    width: CGFloat(element.size.width),
                    height: CGFloat(element.size.height),
                    alignment: .topLeading
                )
                .background(selectionBackground)
                .overlay(selectionBorder)

            if isSelected, !isEditing {
                CardResizeHandles(
                    cardSize: element.size,
                    cardPosition: element.position,
                    viewportScale: viewportScale,
                    accentColor: accent,
                    minWidth: TextElement.minimumWidth,
                    minHeight: TextElement.minimumHeight,
                    onResizeStart: {
                        store.selectTextElement(id: element.id)
                        isResizing = true
                    },
                    onResize: { size, position in
                        store.resizeTextElement(id: element.id, to: size, position: position)
                    },
                    onResizeEnd: { isResizing = false }
                )
                .frame(width: CGFloat(element.size.width), height: CGFloat(element.size.height))
            }
        }
        .offset(x: CGFloat(element.position.x), y: CGFloat(element.position.y))
        .onTapGesture(count: 2) { beginEditing() }
        .onTapGesture(count: 1) { store.selectTextElement(id: element.id) }
        .gesture(dragGesture, isEnabled: !isEditing && !isResizing)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isEditing)
        .onChange(of: isEditing) { _, editing in
            if editing { draftText = element.text }
        }
        .onAppear {
            if isEditing { draftText = element.text }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isEditing {
            TextElementEditor(
                text: $draftText,
                fontSize: element.fontSize,
                fontName: element.fontName,
                textColor: textColor,
                onCommit: commit,
                onCancel: cancel
            )
            .padding(6)
        } else {
            Text(displayText)
                .font(elementFont)
                .foregroundStyle(element.text.isEmpty ? textColor.opacity(0.4) : textColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(6)
                .contentShape(Rectangle())
        }
    }

    private var displayText: String {
        element.text.isEmpty ? "Text" : element.text
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                store.selectTextElement(id: element.id)

                let delta = CGSize(
                    width: value.translation.width - lastDragTranslation.width,
                    height: value.translation.height - lastDragTranslation.height
                )
                store.moveTextElement(
                    id: element.id,
                    screenTranslation: CanvasVector(dx: delta.width, dy: delta.height)
                )
                lastDragTranslation = value.translation
            }
            .onEnded { _ in
                lastDragTranslation = .zero
            }
    }

    @ViewBuilder
    private var selectionBorder: some View {
        if isSelected || isEditing {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    accent.opacity(isEditing ? 0.85 : 0.6),
                    style: StrokeStyle(lineWidth: 1, dash: isEditing ? [] : [5, 4])
                )
        }
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.white.opacity(isEditing ? 0.06 : (isSelected ? 0.03 : 0)))
    }

    private func beginEditing() {
        store.selectTextElement(id: element.id)
        draftText = element.text
        editingTextID = element.id
    }

    /// Persists the draft and exits editing. Intentionally does NOT guard on
    /// `isEditing`: the editor also calls this from its teardown, which can run
    /// AFTER an external `editingTextID = nil` (clicking empty canvas) has
    /// already flipped `isEditing` false — the draft must still be saved.
    private func commit() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEditing { editingTextID = nil }
        if trimmed.isEmpty {
            // A text element with no content is a ghost — remove it on commit.
            store.deleteTextElement(id: element.id)
        } else if draftText != element.text {
            store.updateTextElementText(id: element.id, to: draftText)
        }
    }

    private func cancel() {
        if isEditing { editingTextID = nil }
        // Esc on a never-typed element discards it instead of leaving a ghost.
        if element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.deleteTextElement(id: element.id)
        }
    }
}

extension Color {
    /// Parses "#RRGGBB" or "#RRGGBBAA" (with or without the leading #).
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard let value = UInt64(hex, radix: 16) else { return nil }

        let red, green, blue, alpha: Double
        switch hex.count {
        case 6:
            red = Double((value >> 16) & 0xff) / 255
            green = Double((value >> 8) & 0xff) / 255
            blue = Double(value & 0xff) / 255
            alpha = 1
        case 8:
            red = Double((value >> 24) & 0xff) / 255
            green = Double((value >> 16) & 0xff) / 255
            blue = Double((value >> 8) & 0xff) / 255
            alpha = Double(value & 0xff) / 255
        default:
            return nil
        }
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Serializes to "#RRGGBBAA" (sRGB) — the inverse of `init?(hexString:)`,
    /// matching the format `TextElement.colorHex` persists.
    var hexStringRGBA: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        let a = Int(round(ns.alphaComponent * 255))
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
