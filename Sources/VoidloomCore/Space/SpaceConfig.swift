import Foundation

/// The full-screen background of a Space.
public enum SpaceBackground: Codable, Equatable, Sendable {
    case atmosphere                 // the existing gradient backdrop
    case solid(hex: String)         // e.g. "#102030FF"
    case image(fileName: String)    // a file in WorkspaceStore.backgroundsDirectoryURL()
}

/// Per-workspace Spaces-mode presentation state. Stored as the optional
/// `WorkspaceState.space`; absent (nil) for pre-Spaces workspaces.
public struct SpaceConfig: Codable, Equatable, Sendable {
    public var background: SpaceBackground
    public var tiling: SpaceTiling
    public var backgroundDimming: Double   // 0…1 scrim over the background
    public var cardOrder: [UUID]?          // nil = follow the cards array order

    public init(
        background: SpaceBackground = .atmosphere,
        tiling: SpaceTiling = SpaceTiling(),
        backgroundDimming: Double = 0.35,
        cardOrder: [UUID]? = nil
    ) {
        self.background = background
        self.tiling = tiling
        self.backgroundDimming = backgroundDimming
        self.cardOrder = cardOrder
    }
}
