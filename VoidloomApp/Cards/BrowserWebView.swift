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
        context.coordinator.startObserving(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator

        // Navigation commands: process all before the reload/URL checks (no early return here)
        if coordinator.lastBackToken != model.backToken {
            coordinator.lastBackToken = model.backToken
            webView.goBack()
        }
        if coordinator.lastForwardToken != model.forwardToken {
            coordinator.lastForwardToken = model.forwardToken
            webView.goForward()
        }
        if coordinator.lastStopToken != model.stopToken {
            coordinator.lastStopToken = model.stopToken
            webView.stopLoading()
        }

        // Explicit reload takes priority over URL-change detection
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
        var lastBackToken = 0
        var lastForwardToken = 0
        var lastStopToken = 0
        // Retain all observations so they aren't released prematurely
        private var observations: [NSKeyValueObservation] = []

        init(model: BrowserLoadModel) { self.model = model }

        func startObserving(_ webView: WKWebView) {
            // Each closure: capture the Sendable value first, then hop to MainActor.
            // This avoids crossing the actor boundary with WKWebView itself.
            let progress = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
                let value = wv.estimatedProgress
                Task { @MainActor in self?.model.progress = value }
            }
            let canBack = webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
                let value = wv.canGoBack
                Task { @MainActor in self?.model.canGoBack = value }
            }
            let canForward = webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
                let value = wv.canGoForward
                Task { @MainActor in self?.model.canGoForward = value }
            }
            let currentURL = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
                let value = wv.url
                Task { @MainActor in self?.model.currentURL = value }
            }
            let title = webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
                let value = wv.title
                Task { @MainActor in self?.model.pageTitle = value }
            }
            observations = [progress, canBack, canForward, currentURL, title]
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
