import Foundation

/// Pure URL normalization for the browser card. No SwiftUI/WebKit.
public enum BrowserURLResolver {
    public static let fallback = URL(string: "https://voidloom.local")!

    /// Strict: nil for empty/invalid input. Use for URL-bar validation.
    public static func normalized(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        if let url = URL(string: "https://\(trimmed)"), url.host != nil { return url }
        return nil
    }

    /// Lenient: always returns a URL (falls back). Use for the webview load.
    public static func resolve(from input: String) -> URL {
        normalized(from: input) ?? fallback
    }

    public static func isValid(_ input: String) -> Bool { normalized(from: input) != nil }
}
