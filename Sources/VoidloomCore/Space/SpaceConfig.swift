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
    /// Legacy free-arrange placement (screen points). No longer the source of
    /// truth — `WorkspaceCard.position`/`.size` is. Kept decodable so old files
    /// upcast losslessly (see `WorkspaceState.init(from:)`), then cleared in
    /// memory so a re-save can never re-clobber a moved card.
    public var freeFrames: [UUID: SpaceFreeFrame]
    /// Ids of cards the user has explicitly placed in free-arrange mode. Seeding
    /// leaves these alone (a moved card stays put); unplaced cards are seeded a
    /// grid-derived position on first render into the mode.
    public var freePlaced: Set<UUID>
    /// Pan/zoom of the Board (free-arrange) surface. Nil means identity — the
    /// state on first switch, so an existing Board opens pixel-identical. Kept
    /// STRICTLY separate from `WorkspaceState.viewport` (the Canvas one), which
    /// can be non-identity on migrated files and must never drive Board layout.
    public var viewport: CanvasViewport?
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
        freePlaced: Set<UUID> = [],
        viewport: CanvasViewport? = nil,
        folderPath: String? = nil
    ) {
        self.background = background
        self.tiling = tiling
        self.backgroundDimming = backgroundDimming
        self.cardOrder = cardOrder
        self.layoutMode = layoutMode
        self.freeFrames = freeFrames
        self.freePlaced = freePlaced
        self.viewport = viewport
        self.folderPath = folderPath
    }

    private enum CodingKeys: String, CodingKey {
        case background, tiling, backgroundDimming, cardOrder, layoutMode, freeFrames, freePlaced, viewport, folderPath
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
        // A file written before `freePlaced` existed kept its ledger implicitly in
        // the frame keys, so fall back to exactly those cards.
        freePlaced = try container.decodeIfPresent(Set<UUID>.self, forKey: .freePlaced) ?? Set(freeFrames.keys)
        viewport = try container.decodeIfPresent(CanvasViewport.self, forKey: .viewport)
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath)
    }
}
