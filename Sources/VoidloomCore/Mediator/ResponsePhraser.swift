import Foundation

/// Builds phrasing prompts and cleans model output for Sunday's voice.
public enum ResponsePhraser {
    /// Persona + hard fencing: rephrase ONLY the given facts, one short warm
    /// sentence (two max), first person as Sunday, no invention, no markdown,
    /// no emoji, no quotes around the output.
    public static func systemPrompt() -> String {
        [
            "You are \(AssistantIdentity.name), the assistant inside Voidloom.",
            "Rephrase only the given facts into one short, warm sentence (two at most).",
            "Speak in first person as \(AssistantIdentity.name). Invent nothing beyond what you are given.",
            "No markdown, no emoji, no quotes around the output.",
        ].joined(separator: " ")
    }

    /// "Action just completed: <fact>\n<context>\nRephrase it for the user."
    public static func userPrompt(fact: String, context: String) -> String {
        "Action just completed: \(fact)\n\(context)\nRephrase it for the user."
    }

    /// Cleans a raw model reply: collapse whitespace/newlines, strip wrapping
    /// quotes/backticks/markdown emphasis, cap at 2 sentences via
    /// SentenceSplitter. Empty/whitespace result → returns `fallback`.
    public static func sanitize(_ raw: String, fallback: String) -> String {
        var s = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasPrefix("`") && s.hasSuffix("`") && s.count >= 2 {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        s = s.replacingOccurrences(of: "`", with: "")
        s = s.replacingOccurrences(of: "[*_#>]", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !s.isEmpty else { return fallback }

        let sentences = SentenceSplitter.split(s)
        if sentences.count <= 2 { return s }
        return sentences.prefix(2).joined(separator: " ")
    }
}
