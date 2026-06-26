import Foundation

public struct WorkspaceSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var cardCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        cardCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cardCount = cardCount
    }
}

public struct WorkspaceLibrary: Codable, Equatable, Sendable {
    public var selectedWorkspaceID: UUID
    public var workspaces: [WorkspaceSummary]

    public init(selectedWorkspaceID: UUID, workspaces: [WorkspaceSummary]) {
        self.selectedWorkspaceID = selectedWorkspaceID
        self.workspaces = workspaces
    }
}
