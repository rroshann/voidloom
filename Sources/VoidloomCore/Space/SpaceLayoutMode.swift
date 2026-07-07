import Foundation

/// How a Space presents its cards: the paginated auto-tiled grid, or a
/// free-arrange surface where the user places cards anywhere.
public enum SpaceLayoutMode: String, Codable, Sendable {
    case pagedGrid      // positions derived by SpaceGrid, never persisted
    case freeArrange    // per-card frames persisted in SpaceConfig.freeFrames
}

/// A card's persisted frame in free-arrange mode, in screen points.
public struct SpaceFreeFrame: Codable, Equatable, Sendable {
    public var origin: ScreenPoint
    public var size: ScreenPoint

    public init(origin: ScreenPoint, size: ScreenPoint) {
        self.origin = origin
        self.size = size
    }
}
