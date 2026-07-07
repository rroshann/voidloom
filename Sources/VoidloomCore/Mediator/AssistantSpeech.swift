import Foundation

/// Prepares assistant text for spoken output. A HUD reply can be long or contain
/// code and markdown; speaking all of it is tedious, so trim to the first couple
/// of sentences and strip noise, pointing to the screen when there's more.
public enum AssistantSpeech {
    public static func spoken(from text: String, maxSentences: Int = 2) -> String {
        let cleaned = stripNoise(text)
        guard !cleaned.isEmpty else { return "" }

        let sentences = splitSentences(cleaned)
        guard sentences.count > maxSentences else { return cleaned }
        let head = sentences.prefix(maxSentences).joined(separator: " ")
        return head + " There's more on screen."
    }

    /// Drops fenced code blocks, inline-code backticks, and common markdown
    /// bullets/emphasis so the synthesizer doesn't read punctuation aloud.
    private static func stripNoise(_ text: String) -> String {
        var s = text.replacingOccurrences(
            of: "```[\\s\\S]*?```", with: " code block ", options: .regularExpression)
        s = s.replacingOccurrences(of: "`", with: "")
        s = s.replacingOccurrences(of: "[*_#>]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits on sentence terminators, keeping the terminator. Deliberately
    /// simple — good enough to bound spoken length, not linguistically perfect.
    private static func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }
}
