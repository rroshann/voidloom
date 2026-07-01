import Foundation

/// Top-level presentation mode, persisted app-wide in UserDefaults under
/// "app.mode". Defaults to `.canvas` so existing users see no change.
enum AppMode: String, CaseIterable, Identifiable, Sendable {
    case canvas
    case spaces

    var id: String { rawValue }
    var label: String { self == .canvas ? "Canvas" : "Spaces" }
}
