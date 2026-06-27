import SwiftUI
import WebKit

enum BrowserURLResolver {
    static func resolve(from content: String) -> URL {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return URL(string: "about:blank")!
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        if let url = URL(string: "https://\(trimmed)") {
            return url
        }

        return URL(string: "https://voidloom.local")!
    }
}

struct BrowserWebView: NSViewRepresentable {
    let urlString: String

    private var url: URL {
        BrowserURLResolver.resolve(from: urlString)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastLoadedURL != url else { return }
        context.coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastLoadedURL: URL?
    }
}
