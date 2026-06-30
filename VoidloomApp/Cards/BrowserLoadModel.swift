// VoidloomApp/Cards/BrowserLoadModel.swift
import SwiftUI

@MainActor
final class BrowserLoadModel: ObservableObject {
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var lastError: String?
    @Published private(set) var reloadToken = 0

    // Navigation state (KVO-fed from BrowserWebView.Coordinator)
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var currentURL: URL?
    @Published var pageTitle: String?

    // Intent tokens — Coordinator observes these in updateNSView
    @Published private(set) var backToken = 0
    @Published private(set) var forwardToken = 0
    @Published private(set) var stopToken = 0

    func reload() {
        lastError = nil
        reloadToken += 1
    }

    func goBack() { backToken += 1 }
    func goForward() { forwardToken += 1 }
    func stop() { stopToken += 1 }
}
