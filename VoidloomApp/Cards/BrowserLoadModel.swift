// VoidloomApp/Cards/BrowserLoadModel.swift
import SwiftUI

@MainActor
final class BrowserLoadModel: ObservableObject {
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var lastError: String?
    @Published private(set) var reloadToken = 0

    func reload() {
        lastError = nil
        reloadToken += 1
    }
}
