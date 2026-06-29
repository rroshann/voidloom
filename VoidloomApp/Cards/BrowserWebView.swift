import SwiftUI
import VoidloomCore
import WebKit

struct BrowserWebView: NSViewRepresentable {
    let urlString: String
    @ObservedObject var model: BrowserLoadModel

    private var url: URL { BrowserURLResolver.resolve(from: urlString) }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.observeProgress(of: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        if coordinator.lastReloadToken != model.reloadToken {
            coordinator.lastReloadToken = model.reloadToken
            coordinator.lastLoadedURL = url
            webView.load(URLRequest(url: url))
            return
        }
        guard coordinator.lastLoadedURL != url else { return }
        coordinator.lastLoadedURL = url
        webView.load(URLRequest(url: url))
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: BrowserLoadModel
        var lastLoadedURL: URL?
        var lastReloadToken = 0
        private var progressObservation: NSKeyValueObservation?

        init(model: BrowserLoadModel) { self.model = model }

        func observeProgress(of webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                let progress = webView.estimatedProgress
                Task { @MainActor in self?.model.progress = progress }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true; model.lastError = nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.isLoading = false
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.isLoading = false; model.lastError = error.localizedDescription
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.isLoading = false; model.lastError = error.localizedDescription
        }
    }
}
