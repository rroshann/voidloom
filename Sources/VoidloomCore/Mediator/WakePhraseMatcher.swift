import Foundation

/// Lowercase keyword match for opt-in wake phrase detection on streaming transcripts.
public struct WakePhraseMatcher: Equatable, Sendable {
    public let phrase: String

    public init(phrase: String) {
        self.phrase = phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace }
    }

    /// Returns command text after the wake phrase when `text` contains it (case-insensitive,
    /// whitespace-insensitive so partial ASR fragments like "hey void" + "loom …" still match).
    /// Empty string means the wake phrase matched with no trailing command in the same span.
    public func match(in text: String) -> String? {
        guard !phrase.isEmpty else { return nil }
        let compactText = text.lowercased().filter { !$0.isWhitespace }
        guard let range = compactText.range(of: phrase) else { return nil }

        let endCompactIndex = compactText.distance(from: compactText.startIndex, to: range.upperBound)
        var compactCount = 0
        var originalIndex = text.startIndex
        while compactCount < endCompactIndex, originalIndex < text.endIndex {
            if !text[originalIndex].isWhitespace { compactCount += 1 }
            originalIndex = text.index(after: originalIndex)
        }
        let after = text[originalIndex...]
        return String(after).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Appends `fragment` to `buffer`, trims to `maxCharacters`, and attempts a wake match.
    public func scanRolling(buffer: inout String, appending fragment: String, maxCharacters: Int = 240) -> String? {
        let combined = (buffer + " " + fragment)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = combined.count > maxCharacters ? String(combined.suffix(maxCharacters)) : combined
        return match(in: buffer)
    }
}
