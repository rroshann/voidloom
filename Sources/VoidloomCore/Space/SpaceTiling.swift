import Foundation

/// How a Space arranges its card tiles. Pure value type, no UI.
public struct SpaceTiling: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case auto           // SpaceGrid picks the column count by maximizing tile area
        case fixedColumns   // use `columns` exactly
    }

    public var mode: Mode
    public var columns: Int        // used only when mode == .fixedColumns ("max columns")
    public var maxRows: Int?       // nil = unbounded (single screen); >0 paginates at columns × maxRows
    public var gap: Double         // screen px between tiles
    public var margin: Double      // screen px from the usable-rect edge to the first tile
    public var targetAspect: Double // preferred tile width:height for the auto column search

    public init(
        mode: Mode = .auto,
        columns: Int = 2,
        maxRows: Int? = nil,
        gap: Double = 18,
        margin: Double = 28,
        targetAspect: Double = 1.6
    ) {
        self.mode = mode
        self.columns = columns
        self.maxRows = maxRows
        self.gap = gap
        self.margin = margin
        self.targetAspect = targetAspect
    }
}
