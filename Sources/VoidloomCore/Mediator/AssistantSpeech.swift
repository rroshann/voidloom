import Foundation

/// Prepares assistant text for spoken output. A HUD reply can be long or contain
/// code and markdown; speaking all of it is tedious, so trim to the first couple
/// of sentences and strip noise, pointing to the screen when there's more.
public enum AssistantSpeech {
    public static func spoken(from text: String, maxSentences: Int = 2) -> String {
        let cleaned = stripNoise(text)
        guard !cleaned.isEmpty else { return "" }

        let sentences = SentenceSplitter.split(cleaned)
        guard sentences.count > maxSentences else { return cleaned }
        let head = sentences.prefix(maxSentences).joined(separator: " ")
        return head + " There's more on screen."
    }

    /// Drops fenced code blocks, inline-code backticks, and common markdown
    /// bullets/emphasis so the synthesizer doesn't read punctuation aloud.
    private static func stripNoise(_ text: String) -> String {
        var s = text.replacingOccurrences(
            of: "```[\\s\\S]*?```", with: " code block ", options: .regularExpression)
        // Markdown links [label](url) -> just the label; never read the URL aloud.
        s = s.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        // Bare URLs -> a short word rather than a spelled-out address.
        s = s.replacingOccurrences(
            of: "https?://\\S+", with: "a link", options: .regularExpression)
        // File paths -> just the basename. Reading "app slash spaces slash…" aloud
        // is jarring; the filename carries the meaning. Requires >=1 slash and a
        // short trailing extension so natural-language slashes (and/or, 24/7) survive.
        s = s.replacingOccurrences(
            of: "(?:[\\w.-]+/)+([\\w.-]+\\.[A-Za-z]{1,5})", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "`", with: "")
        s = s.replacingOccurrences(of: "[*_#>]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
