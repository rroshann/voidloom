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
    public var layoutMode: SpaceLayoutMode
    public var freeFrames: [UUID: SpaceFreeFrame]   // free-arrange only; grid derives
    /// Absolute path to this space's project folder. Powers file-browser and git
    /// cards; nil until the user picks one. Not sandboxed, so a plain path works.
    public var folderPath: String?

    public init(
        background: SpaceBackground = .atmosphere,
        tiling: SpaceTiling = SpaceTiling(),
        backgroundDimming: Double = 0.35,
        cardOrder: [UUID]? = nil,
        layoutMode: SpaceLayoutMode = .pagedGrid,
        freeFrames: [UUID: SpaceFreeFrame] = [:],
        folderPath: String? = nil
    ) {
        self.background = background
        self.tiling = tiling
        self.backgroundDimming = backgroundDimming
        self.cardOrder = cardOrder
        self.layoutMode = layoutMode
        self.freeFrames = freeFrames
        self.folderPath = folderPath
    }

    private enum CodingKeys: String, CodingKey {
        case background, tiling, backgroundDimming, cardOrder, layoutMode, freeFrames, folderPath
    }

    // Custom decode so configs persisted before free-arrange existed still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        background = try container.decode(SpaceBackground.self, forKey: .background)
        tiling = try container.decode(SpaceTiling.self, forKey: .tiling)
        backgroundDimming = try container.decode(Double.self, forKey: .backgroundDimming)
        cardOrder = try container.decodeIfPresent([UUID].self, forKey: .cardOrder)
        layoutMode = try container.decodeIfPresent(SpaceLayoutMode.self, forKey: .layoutMode) ?? .pagedGrid
        freeFrames = try container.decodeIfPresent([UUID: SpaceFreeFrame].self, forKey: .freeFrames) ?? [:]
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath)
    }
}
