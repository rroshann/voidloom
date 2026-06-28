import Combine
import Foundation

@MainActor
public final class WorkspaceStore: ObservableObject {
    @Published public private(set) var library: WorkspaceLibrary
    @Published public private(set) var state: WorkspaceState
    @Published public private(set) var lastPersistenceError: String?

    private let libraryURL: URL?
    private let workspacesDirectoryURL: URL?
    private let storageURL: URL
    private let persistenceDelay: TimeInterval
    private var pendingPersistenceTask: Task<Void, Never>?

    private var isLibraryMode: Bool { libraryURL != nil }

    public init(
        libraryURL: URL = WorkspaceStore.defaultLibraryURL(),
        workspacesDirectoryURL: URL = WorkspaceStore.defaultWorkspacesDirectoryURL(),
        legacyStorageURL: URL = WorkspaceStore.defaultStorageURL(),
        persistenceDelay: TimeInterval = 0.25
    ) {
        self.libraryURL = libraryURL
        self.workspacesDirectoryURL = workspacesDirectoryURL
        self.persistenceDelay = persistenceDelay

        let loaded = Self.loadOrCreateLibrary(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectoryURL,
            legacyStorageURL: legacyStorageURL
        )

        self.library = loaded.library
        self.storageURL = Self.workspaceURL(
            for: loaded.library.selectedWorkspaceID,
            in: workspacesDirectoryURL
        )
        self.state = loaded.state
    }

    public init(
        state: WorkspaceState,
        storageURL: URL = WorkspaceStore.defaultStorageURL(),
        persistenceDelay: TimeInterval = 0.25
    ) {
        self.libraryURL = nil
        self.workspacesDirectoryURL = nil
        self.storageURL = storageURL
        self.persistenceDelay = persistenceDelay
        let workspaceID = UUID()
        self.library = WorkspaceLibrary(
            selectedWorkspaceID: workspaceID,
            workspaces: [
                WorkspaceSummary(
                    id: workspaceID,
                    name: "Test Workspace",
                    cardCount: state.cards.count
                )
            ]
        )
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

    public func deleteCard(id: UUID) {
        guard state.cards.contains(where: { $0.id == id }) else { return }
        state.deleteCard(id: id)
        persist()
    }

    public func resizeCard(id: UUID, to size: CardSize, position: CanvasPoint? = nil) {
        guard state.cards.contains(where: { $0.id == id }) else { return }
        state.resizeCard(id: id, to: size, position: position)
        schedulePersistence()
    }

    public func updateCardTitle(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard state.cards.contains(where: { $0.id == id }) else { return }

        state.updateCardTitle(id: id, to: trimmed)
        schedulePersistence()
    }

    public func updateCardContent(id: UUID, to content: String) {
        guard state.cards.contains(where: { $0.id == id }) else { return }
        state.updateCardContent(id: id, to: content)
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

    /// Adds a card centered on the given canvas point (e.g. the center of the
    /// visible viewport, or a click location), with a small cascade offset so
    /// consecutive additions don't stack exactly on top of each other.
    public func addCard(kind: CardKind, centeredAt center: CanvasPoint) {
        var card = Self.defaultCard(kind: kind)
        let cascade = Double(state.cards.count % 6) * 22
        card.position = CanvasPoint(
            x: center.x - (card.size.width / 2) + cascade,
            y: center.y - (card.size.height / 2) + cascade
        )
        state.addCard(card)
        persist()
    }

    /// Adds a card sized by a press-drag-release rectangle (two opposite canvas
    /// corners). The rect is normalized and clamped to the card minimums; the
    /// new card is selected. Returns its id, or nil if nothing was added.
    @discardableResult
    public func addCard(kind: CardKind, fromCorner a: CanvasPoint, toCorner b: CanvasPoint) -> UUID? {
        let rect = WorkspaceState.normalizedRect(a, b)
        var card = Self.defaultCard(kind: kind)
        card.position = rect.origin
        card.size = rect.size.clamped()
        state.addCard(card)
        state.selectCard(id: card.id)
        persist()
        return card.id
    }

    // MARK: - Connections

    public func addConnection(from: UUID, to: UUID) {
        state.addConnection(from: from, to: to)
        persist()
    }

    public func deleteConnection(id: UUID) {
        state.removeConnection(id: id)
        persist()
    }

    // MARK: - Text elements

    /// Adds a default-sized text element centered on the given canvas point,
    /// selects it, and returns its id so the caller can begin inline editing.
    @discardableResult
    public func addTextElement(centeredAt center: CanvasPoint) -> UUID {
        let size = CardSize(width: 200, height: 44)
        let element = TextElement(
            position: CanvasPoint(
                x: center.x - (size.width / 2),
                y: center.y - (size.height / 2)
            ),
            size: size
        )
        state.addTextElement(element)
        state.selectTextElement(id: element.id)
        persist()
        return element.id
    }

    /// Adds a text element sized by a press-drag-release rectangle, normalized
    /// and clamped to the text minimums. Selects it and returns its id.
    @discardableResult
    public func addTextElement(fromCorner a: CanvasPoint, toCorner b: CanvasPoint) -> UUID {
        let rect = WorkspaceState.normalizedRect(a, b)
        let element = TextElement(
            position: rect.origin,
            size: rect.size.clamped(
                minWidth: TextElement.minimumWidth,
                minHeight: TextElement.minimumHeight
            )
        )
        state.addTextElement(element)
        state.selectTextElement(id: element.id)
        persist()
        return element.id
    }

    public func moveTextElement(id: UUID, screenTranslation: CanvasVector) {
        guard screenTranslation != .zero else { return }
        state.moveTextElement(id: id, screenTranslation: screenTranslation)
        schedulePersistence()
    }

    public func resizeTextElement(id: UUID, to size: CardSize, position: CanvasPoint? = nil) {
        state.resizeTextElement(id: id, to: size, position: position)
        schedulePersistence()
    }

    public func updateTextElementText(id: UUID, to text: String) {
        state.updateTextElementText(id: id, to: text)
        schedulePersistence()
    }

    public func selectTextElement(id: UUID) {
        guard state.selectedTextID != id else { return }
        state.selectTextElement(id: id)
        schedulePersistence()
    }

    public func deleteTextElement(id: UUID) {
        state.deleteTextElement(id: id)
        persist()
    }

    // MARK: - Drawing strokes

    /// Persists a finished brush stroke. Strokes with fewer than two points
    /// carry no visible geometry and are rejected.
    public func addStroke(_ stroke: DrawingStroke) {
        guard stroke.points.count >= 2 else { return }
        state.addStroke(stroke)
        persist()
    }

    /// Erases strokes under the eraser disc. Persistence is debounced during a
    /// drag; call `flushErase()` on drag end to write the final result once.
    public func erase(at point: CanvasPoint, radius: Double, mode: EraseMode) {
        let changed = state.eraseStrokes(at: point, radius: radius, mode: mode)
        if changed {
            schedulePersistence()
        }
    }

    public func flushErase() {
        flushPendingPersistence()
    }

    public func resetViewport() {
        state.viewport = CanvasViewport()
        persist()
    }

    public func focusOnSelectedCard(viewportSize: ScreenPoint, padding: Double = 48) {
        guard let selectedID = state.selectedCardID,
              let card = state.cards.first(where: { $0.id == selectedID }) else { return }

        state.viewport.focus(
            onCanvasRect: card.position,
            size: card.size,
            padding: padding,
            viewportSize: viewportSize
        )
        schedulePersistence()
    }

    public func restoreViewport(_ viewport: CanvasViewport) {
        state.viewport = viewport
        schedulePersistence()
    }

    public func createWorkspace(named name: String) {
        guard isLibraryMode,
              let libraryURL,
              let workspacesDirectoryURL else { return }

        flushPendingPersistence()

        let workspaceID = UUID()
        let now = Date()
        let newState = WorkspaceState()

        let summary = WorkspaceSummary(
            id: workspaceID,
            name: name,
            createdAt: now,
            updatedAt: now,
            cardCount: 0
        )

        library.workspaces.append(summary)
        library.selectedWorkspaceID = workspaceID
        state = newState

        do {
            try Self.save(newState, to: Self.workspaceURL(for: workspaceID, in: workspacesDirectoryURL))
            try Self.saveLibrary(library, to: libraryURL)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    public func switchWorkspace(id: UUID) {
        guard isLibraryMode,
              let libraryURL,
              let workspacesDirectoryURL else { return }
        guard library.selectedWorkspaceID != id else { return }
        guard library.workspaces.contains(where: { $0.id == id }) else { return }

        flushPendingPersistence()

        let workspaceURL = Self.workspaceURL(for: id, in: workspacesDirectoryURL)

        do {
            let loadedState = try Self.load(from: workspaceURL)
            library.selectedWorkspaceID = id
            state = loadedState
            try Self.saveLibrary(library, to: libraryURL)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    public func renameWorkspace(id: UUID, to name: String) {
        guard isLibraryMode, let libraryURL else { return }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = library.workspaces.firstIndex(where: { $0.id == id }) else { return }

        library.workspaces[index].name = trimmed
        library.workspaces[index].updatedAt = Date()

        do {
            try Self.saveLibrary(library, to: libraryURL)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    public func moveWorkspace(id: UUID, toIndex: Int) {
        guard isLibraryMode, let libraryURL else { return }
        guard let fromIndex = library.workspaces.firstIndex(where: { $0.id == id }) else { return }

        let clampedIndex = min(max(toIndex, 0), library.workspaces.count - 1)
        guard fromIndex != clampedIndex else { return }

        var workspaces = library.workspaces
        let item = workspaces.remove(at: fromIndex)
        workspaces.insert(item, at: clampedIndex)
        library.workspaces = workspaces

        do {
            try Self.saveLibrary(library, to: libraryURL)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    public func moveWorkspace(id: UUID, toPositionOf targetID: UUID) {
        guard let targetIndex = library.workspaces.firstIndex(where: { $0.id == targetID }) else { return }
        moveWorkspace(id: id, toIndex: targetIndex)
    }

    public func deleteWorkspace(id: UUID) {
        guard isLibraryMode,
              let libraryURL,
              let workspacesDirectoryURL else { return }
        guard library.workspaces.count > 1 else { return }
        guard let index = library.workspaces.firstIndex(where: { $0.id == id }) else { return }

        let wasActive = library.selectedWorkspaceID == id

        if wasActive {
            flushPendingPersistence()
        }

        library.workspaces.remove(at: index)

        let workspaceFileURL = Self.workspaceURL(for: id, in: workspacesDirectoryURL)
        try? FileManager.default.removeItem(at: workspaceFileURL)

        if wasActive {
            let replacementIndex = min(index, library.workspaces.count - 1)
            let replacementID = library.workspaces[replacementIndex].id
            let replacementURL = Self.workspaceURL(for: replacementID, in: workspacesDirectoryURL)

            do {
                library.selectedWorkspaceID = replacementID
                state = try Self.load(from: replacementURL)
                try Self.saveLibrary(library, to: libraryURL)
                lastPersistenceError = nil
            } catch {
                lastPersistenceError = error.localizedDescription
            }
        } else {
            do {
                try Self.saveLibrary(library, to: libraryURL)
                lastPersistenceError = nil
            } catch {
                lastPersistenceError = error.localizedDescription
            }
        }
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
            try Self.save(state, to: currentWorkspaceStorageURL())
            syncActiveSummary()
            if isLibraryMode, let libraryURL {
                try Self.saveLibrary(library, to: libraryURL)
            }
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    private func currentWorkspaceStorageURL() -> URL {
        if isLibraryMode, let workspacesDirectoryURL {
            return Self.workspaceURL(for: library.selectedWorkspaceID, in: workspacesDirectoryURL)
        }
        return storageURL
    }

    private func syncActiveSummary() {
        guard let index = library.workspaces.firstIndex(where: { $0.id == library.selectedWorkspaceID }) else {
            return
        }

        library.workspaces[index].cardCount = state.cards.count
        library.workspaces[index].updatedAt = Date()
    }

    private struct LoadedLibrary {
        let library: WorkspaceLibrary
        let state: WorkspaceState
    }

    nonisolated private static func loadOrCreateLibrary(
        libraryURL: URL,
        workspacesDirectoryURL: URL,
        legacyStorageURL: URL
    ) -> LoadedLibrary {
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            return loadExistingLibrary(
                libraryURL: libraryURL,
                workspacesDirectoryURL: workspacesDirectoryURL
            )
        }

        if FileManager.default.fileExists(atPath: legacyStorageURL.path) {
            return migrateLegacyWorkspace(
                legacyStorageURL: legacyStorageURL,
                libraryURL: libraryURL,
                workspacesDirectoryURL: workspacesDirectoryURL
            )
        }

        return createFreshLibrary(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectoryURL
        )
    }

    nonisolated private static func loadExistingLibrary(
        libraryURL: URL,
        workspacesDirectoryURL: URL
    ) -> LoadedLibrary {
        do {
            let library = try loadLibrary(from: libraryURL)
            let workspaceURL = workspaceURL(for: library.selectedWorkspaceID, in: workspacesDirectoryURL)
            let state = try load(from: workspaceURL)
            return LoadedLibrary(library: library, state: state)
        } catch {
            let workspaceID = UUID()
            let now = Date()
            let library = WorkspaceLibrary(
                selectedWorkspaceID: workspaceID,
                workspaces: [
                    WorkspaceSummary(
                        id: workspaceID,
                        name: "Main Canvas",
                        createdAt: now,
                        updatedAt: now,
                        cardCount: 0
                    )
                ]
            )
            let state = makeSeedState()
            try? save(state, to: workspaceURL(for: workspaceID, in: workspacesDirectoryURL))
            try? saveLibrary(library, to: libraryURL)
            return LoadedLibrary(library: library, state: state)
        }
    }

    nonisolated private static func migrateLegacyWorkspace(
        legacyStorageURL: URL,
        libraryURL: URL,
        workspacesDirectoryURL: URL
    ) -> LoadedLibrary {
        let state = (try? load(from: legacyStorageURL)) ?? makeSeedState()
        let workspaceID = UUID()
        let now = Date()
        let summary = WorkspaceSummary(
            id: workspaceID,
            name: "Main Canvas",
            createdAt: now,
            updatedAt: now,
            cardCount: state.cards.count
        )
        let library = WorkspaceLibrary(
            selectedWorkspaceID: workspaceID,
            workspaces: [summary]
        )

        try? save(state, to: workspaceURL(for: workspaceID, in: workspacesDirectoryURL))
        try? saveLibrary(library, to: libraryURL)

        return LoadedLibrary(library: library, state: state)
    }

    nonisolated private static func createFreshLibrary(
        libraryURL: URL,
        workspacesDirectoryURL: URL
    ) -> LoadedLibrary {
        let state = makeSeedState()
        let workspaceID = UUID()
        let now = Date()
        let summary = WorkspaceSummary(
            id: workspaceID,
            name: "Main Canvas",
            createdAt: now,
            updatedAt: now,
            cardCount: state.cards.count
        )
        let library = WorkspaceLibrary(
            selectedWorkspaceID: workspaceID,
            workspaces: [summary]
        )

        try? save(state, to: workspaceURL(for: workspaceID, in: workspacesDirectoryURL))
        try? saveLibrary(library, to: libraryURL)

        return LoadedLibrary(library: library, state: state)
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

    nonisolated public static func loadLibrary(from url: URL) throws -> WorkspaceLibrary {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WorkspaceLibrary.self, from: data)
    }

    nonisolated public static func saveLibrary(_ library: WorkspaceLibrary, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        try data.write(to: url, options: [.atomic])
    }

    nonisolated public static func workspaceURL(for id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    nonisolated public static func defaultLibraryURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("Voidloom", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    nonisolated public static func defaultWorkspacesDirectoryURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("Voidloom", isDirectory: true)
            .appendingPathComponent("workspaces", isDirectory: true)
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

    /// A card with default size/title/content for its kind, positioned at the
    /// origin. Callers set `position` (grid slot, viewport center, cursor, …).
    nonisolated private static func defaultCard(kind: CardKind) -> WorkspaceCard {
        switch kind {
        case .agent:
            return WorkspaceCard(
                kind: .agent,
                position: .zero,
                size: CardSize(width: 360, height: 240),
                title: "New Agent",
                content: "Placeholder for an AI coding agent session."
            )
        case .note:
            return WorkspaceCard(
                kind: .note,
                position: .zero,
                size: CardSize(width: 320, height: 190),
                title: "New Note",
                content: "Capture spatial context here."
            )
        case .todo:
            return WorkspaceCard(
                kind: .todo,
                position: .zero,
                size: CardSize(width: 300, height: 210),
                title: "New Todo",
                content: "[ ] First item\n[ ] Next item"
            )
        case .browser:
            return WorkspaceCard(
                kind: .browser,
                position: .zero,
                size: CardSize(width: 380, height: 230),
                title: "New Preview",
                content: "Browser card placeholder."
            )
        }
    }

    nonisolated private static func makeCard(kind: CardKind, index: Int) -> WorkspaceCard {
        var card = defaultCard(kind: kind)
        let column = index % 3
        let row = index / 3
        card.position = CanvasPoint(
            x: 140 + Double(column * 340),
            y: 120 + Double(row * 260)
        )
        return card
    }
}
