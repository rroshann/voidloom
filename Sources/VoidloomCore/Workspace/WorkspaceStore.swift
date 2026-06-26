import Combine
import Foundation

@MainActor
public final class WorkspaceStore: ObservableObject {
    @Published public private(set) var state: WorkspaceState
    @Published public private(set) var lastPersistenceError: String?

    private let storageURL: URL
    private let persistenceDelay: TimeInterval
    private var pendingPersistenceTask: Task<Void, Never>?

    public init(
        storageURL: URL = WorkspaceStore.defaultStorageURL(),
        persistenceDelay: TimeInterval = 0.25
    ) {
        self.storageURL = storageURL
        self.persistenceDelay = persistenceDelay
        self.state = (try? Self.load(from: storageURL)) ?? Self.makeSeedState()
    }

    public init(
        state: WorkspaceState,
        storageURL: URL = WorkspaceStore.defaultStorageURL(),
        persistenceDelay: TimeInterval = 0.25
    ) {
        self.storageURL = storageURL
        self.persistenceDelay = persistenceDelay
        self.state = state
    }

    public func pan(by translation: CanvasVector) {
        guard translation != .zero else { return }
        state.viewport.pan(by: translation)
        schedulePersistence()
    }

    public func zoom(by magnification: Double, anchoredAt anchor: ScreenPoint) {
        state.viewport.zoom(by: magnification, anchoredAt: anchor)
        schedulePersistence()
    }

    public func moveCard(id: UUID, screenTranslation: CanvasVector) {
        guard screenTranslation != .zero else { return }
        state.moveCard(id: id, screenTranslation: screenTranslation)
        schedulePersistence()
    }

    public func selectCard(id: UUID) {
        guard state.selectedCardID != id else { return }
        guard state.cards.contains(where: { $0.id == id }) else { return }

        state.selectCard(id: id)
        schedulePersistence()
    }

    public func clearSelection() {
        guard state.selectedCardID != nil else { return }
        state.clearSelection()
        schedulePersistence()
    }

    public func addCard(kind: CardKind) {
        state.addCard(Self.makeCard(kind: kind, index: state.cards.count))
        persist()
    }

    public func resetViewport() {
        state.viewport = CanvasViewport()
        persist()
    }

    public func persist() {
        writeCurrentState()
    }

    public func flushPendingPersistence() {
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = nil
        writeCurrentState()
    }

    private func schedulePersistence() {
        pendingPersistenceTask?.cancel()

        let delay = persistenceDelay
        pendingPersistenceTask = Task { [weak self, delay] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }
            self?.commitScheduledPersistence()
        }
    }

    private func commitScheduledPersistence() {
        pendingPersistenceTask = nil
        writeCurrentState()
    }

    private func writeCurrentState() {
        do {
            try Self.save(state, to: storageURL)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    nonisolated public static func load(from url: URL) throws -> WorkspaceState {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WorkspaceState.self, from: data)
    }

    nonisolated public static func save(_ state: WorkspaceState, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: [.atomic])
    }

    nonisolated public static func defaultStorageURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("Voidloom", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }

    nonisolated public static func makeSeedState() -> WorkspaceState {
        WorkspaceState(
            viewport: CanvasViewport(),
            cards: [
                WorkspaceCard(
                    id: UUID(uuidString: "8A02AC1A-446C-42F6-A7AD-45563421E547") ?? UUID(),
                    kind: .agent,
                    position: CanvasPoint(x: 160, y: 120),
                    size: CardSize(width: 360, height: 240),
                    title: "Atlas",
                    content: "Agent session placeholder\n- Inspect repo\n- Draft plan\n- Report findings"
                ),
                WorkspaceCard(
                    id: UUID(uuidString: "AF0E8F62-A875-4CDE-B142-4C383C0950E9") ?? UUID(),
                    kind: .todo,
                    position: CanvasPoint(x: 560, y: 150),
                    size: CardSize(width: 300, height: 220),
                    title: "Canvas Checklist",
                    content: "[ ] Pan\n[ ] Zoom\n[ ] Drag cards\n[ ] Persist layout"
                ),
                WorkspaceCard(
                    id: UUID(uuidString: "173A36E8-E9E9-44DB-9D47-43DCB6DA0DA8") ?? UUID(),
                    kind: .note,
                    position: CanvasPoint(x: 260, y: 430),
                    size: CardSize(width: 320, height: 190),
                    title: "Shared Note",
                    content: "Use this as the scratchpad layer before real cross-agent memory exists."
                ),
                WorkspaceCard(
                    id: UUID(uuidString: "E6687CEF-D831-42DE-909E-CE380041ED85") ?? UUID(),
                    kind: .browser,
                    position: CanvasPoint(x: 650, y: 450),
                    size: CardSize(width: 380, height: 230),
                    title: "Preview",
                    content: "Browser placeholder for future design-loop screenshots."
                )
            ]
        )
    }

    nonisolated private static func makeCard(kind: CardKind, index: Int) -> WorkspaceCard {
        let column = index % 3
        let row = index / 3
        let position = CanvasPoint(
            x: 140 + Double(column * 340),
            y: 120 + Double(row * 260)
        )

        switch kind {
        case .agent:
            return WorkspaceCard(
                kind: .agent,
                position: position,
                size: CardSize(width: 360, height: 240),
                title: "New Agent",
                content: "Placeholder for an AI coding agent session."
            )
        case .note:
            return WorkspaceCard(
                kind: .note,
                position: position,
                size: CardSize(width: 320, height: 190),
                title: "New Note",
                content: "Capture spatial context here."
            )
        case .todo:
            return WorkspaceCard(
                kind: .todo,
                position: position,
                size: CardSize(width: 300, height: 210),
                title: "New Todo",
                content: "[ ] First item\n[ ] Next item"
            )
        case .browser:
            return WorkspaceCard(
                kind: .browser,
                position: position,
                size: CardSize(width: 380, height: 230),
                title: "New Preview",
                content: "Browser card placeholder."
            )
        }
    }
}
