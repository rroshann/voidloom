// Sources/VoidloomCore/Appearance/AppearanceSettings.swift

public enum AppearanceMode: String, Codable, Sendable, CaseIterable {
    case system, light, dark
}

public enum CanvasBackground: String, Codable, Sendable, CaseIterable {
    case dots, grid, lines, solid, blueprint
}

public enum TextSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large

    public var fontScale: Double {
        switch self {
        case .small:  return 0.9
        case .medium: return 1.0
        case .large:  return 1.1
        }
    }
}
