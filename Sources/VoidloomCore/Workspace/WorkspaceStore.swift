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
    private let shutdownMarkerURL: URL

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

        let markerURL = libraryURL.deletingLastPathComponent()
            .appendingPathComponent("shutdown.json")
        self.shutdownMarkerURL = markerURL

        let loaded = Self.loadOrCreateLibrary(
            libraryURL: libraryURL,
            workspacesDirectoryURL: workspacesDirectoryURL,
            legacyStorageURL: legacyStorageURL,
            shutdownMarkerURL: markerURL
        )

        self.library = loaded.library
        self.storageURL = Self.workspaceURL(
            for: loaded.library.selectedWorkspaceID,
            in: workspacesDirectoryURL
        )
        self.state = loaded.state

        // Mark ourselves as running; stays false until markCleanShutdown() is called.
        Self.writeShutdownMarker(false, to: markerURL)
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
        self.shutdownMarkerURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("shutdown.json")
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
        Self.writeShutdownMarker(false, to: shutdownMarkerURL)
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

    /// A discrete zoom step (the +/- controls) that snaps to 100% when a step
    /// would otherwise skip over it, so 100% is always reachable by clicking.
    public func zoomStep(by magnification: Double, anchoredAt anchor: ScreenPoint) {
        state.viewport.zoomStep(by: magnification, anchoredAt: anchor)
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

    /// Moves a marquee group of cards together. Debounced like `moveCard`, since
    /// a drag emits many translations.
    public func moveCards(ids: Set<UUID>, screenTranslation: CanvasVector) {
        guard !ids.isEmpty, screenTranslation != .zero else { return }
        state.moveCards(ids: ids, screenTranslation: screenTranslation)
        schedulePersistence()
    }

    /// Deletes a marquee group of cards (and their connections). Persists
    /// immediately — a structural change, like `deleteCard`.
    public func deleteCards(ids: Set<UUID>) {
        let present = ids.filter { id in state.cards.contains(where: { $0.id == id }) }
        guard !present.isEmpty else { return }
        state.deleteCards(ids: Set(present))
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
        // Clear whenever ANY selection or focus is live — card, text, a transient
        // marquee set, or an active (content-focused) card — so clicking empty
        // canvas de-highlights everything, including a card made active by
        // clicking into its content (which sets activeCardID but not selectedCardID).
        guard state.selectedCardID != nil
            || state.selectedTextID != nil
            || !state.marqueeSelectedCardIDs.isEmpty
            || state.activeCardID != nil else { return }
        state.clearSelection()
        schedulePersistence()
    }

    /// Toggles a card in/out of the multi-selection (⌘-click). Promotes a lone
    /// single selection into the marquee set first; see
    /// `WorkspaceState.toggleCardInSelection`.
    public func toggleCardInSelection(id: UUID) {
        guard state.cards.contains(where: { $0.id == id }) else { return }
        state.toggleCardInSelection(id: id)
        schedulePersistence()
    }

    /// Marquee multi-selection driven by a left-drag selection box (two opposite
    /// canvas corners). The marquee set is transient/unpersisted, but a single
    /// hit also sets `selectedCardID`, so persistence is still scheduled.
    public func selectCards(fromCorner a: CanvasPoint, toCorner b: CanvasPoint) {
        state.selectCards(fromCorner: a, toCorner: b)
        schedulePersistence()
    }

    /// Additive marquee (⌘-drag): unions the box's hits with `base` (the
    /// selection captured at drag start) when `additive` is true, else replaces.
    /// See `WorkspaceState.selectCards(fromCorner:toCorner:additive:base:)`.
    public func selectCards(
        fromCorner a: CanvasPoint,
        toCorner b: CanvasPoint,
        additive: Bool,
        base: Set<UUID>
    ) {
        state.selectCards(fromCorner: a, toCorner: b, additive: additive, base: base)
        schedulePersistence()
    }

    /// Makes a card active (content focus) — transient UI state, no persistence.
    public func activateCard(id: UUID) {
        guard state.cards.contains(where: { $0.id == id }) else { return }
        state.activateCard(id: id)
    }

    /// Screen-space selection for Spaces (marquee/⌘). The marquee set is
    /// transient, but a lone hit also sets `selectedCardID`, so persistence is
    /// scheduled — matching the canvas `selectCards` overloads.
    public func selectCardsInSpace(ids: Set<UUID>) {
        state.selectCardsInSpace(ids: ids)
        schedulePersistence()
    }

    public func addCard(kind: CardKind) {
        var card = Self.makeCard(kind: kind, index: state.cards.count)
        // After deletions, the count-based index can map to a grid slot already
        // occupied by a surviving card. Route through nonOverlappingOrigin so the
        // candidate position cascades diagonally until it is clear of all existing
        // cards. When the slot is free the base position is returned unchanged, so
        // fresh add sequences (no deletions) land exactly on the grid.
        let center = CanvasPoint(
            x: card.position.x + card.size.width / 2,
            y: card.position.y + card.size.height / 2
        )
        card.position = state.nonOverlappingOrigin(for: card.size, centeredAt: center)
        state.addCard(card)
        persist()
    }

    /// Adds a card centered on the given canvas point (e.g. the center of the
    /// visible viewport, or a click location). When that spot would overlap an
    /// existing card the origin cascades diagonally to the nearest free slot, so
    /// rapid additions never stack on top of one another.
    public func addCard(kind: CardKind, centeredAt center: CanvasPoint) {
        var card = Self.defaultCard(kind: kind)
        card.position = state.nonOverlappingOrigin(for: card.size, centeredAt: center)
        state.addCard(card)
        persist()
    }

    /// Adds a card via the reading-order 2x2 grid (double-click instant-create),
    /// panning the viewport so the newest card is always fully on-screen. The
    /// structural add persists immediately; the viewport pan rides along. Returns
    /// the new card's id. No auto-select, matching today's double-click behavior.
    ///
    /// `bottomInset` reserves a band (screen px) at the bottom of the viewport for
    /// the floating dock, so the bottom row never lands behind it.
    @discardableResult
    public func addCardInGrid(kind: CardKind, viewportSize: ScreenPoint, bottomInset: Double = 0) -> UUID {
        let card = Self.defaultCard(kind: kind)
        state.placeCardInGrid(card, viewportSize: viewportSize, bottomInset: bottomInset)
        persist()
        return card.id
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
    public func addTextElement(
        centeredAt center: CanvasPoint,
        fontSize: Double = 17,
        colorHex: String = "#FFFFFFFF",
        fontName: String? = nil
    ) -> UUID {
        let size = CardSize(width: 200, height: 44)
        let element = TextElement(
            position: CanvasPoint(
                x: center.x - (size.width / 2),
                y: center.y - (size.height / 2)
            ),
            size: size,
            fontSize: fontSize,
            colorHex: colorHex,
            fontName: fontName
        )
        state.addTextElement(element)
        state.selectTextElement(id: element.id)
        persist()
        return element.id
    }

    /// Adds a text element sized by a press-drag-release rectangle, normalized
    /// and clamped to the text minimums. Selects it and returns its id.
    @discardableResult
    public func addTextElement(
        fromCorner a: CanvasPoint,
        toCorner b: CanvasPoint,
        fontSize: Double = 17,
        colorHex: String = "#FFFFFFFF",
        fontName: String? = nil
    ) -> UUID {
        let rect = WorkspaceState.normalizedRect(a, b)
        let element = TextElement(
            position: rect.origin,
            size: rect.size.clamped(
                minWidth: TextElement.minimumWidth,
                minHeight: TextElement.minimumHeight
            ),
            fontSize: fontSize,
            colorHex: colorHex,
            fontName: fontName
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

    public func updateTextElementFontSize(id: UUID, to fontSize: Double) {
        state.updateTextElementFontSize(id: id, to: fontSize)
        schedulePersistence()
    }

    public func updateTextElementColor(id: UUID, toHex hex: String) {
        state.updateTextElementColor(id: id, toHex: hex)
        schedulePersistence()
    }

    public func updateTextElementFont(id: UUID, to fontName: String?) {
        state.updateTextElementFont(id: id, to: fontName)
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
        // Erase on a copy and only publish when something actually changed, so
        // empty-space erase moves don't trigger a full canvas re-render (which
        // made the eraser visibly lag the cursor). Persistence stays debounced.
        var working = state
        let changed = working.eraseStrokes(at: point, radius: radius, mode: mode)
        guard changed else { return }
        state = working
        schedulePersistence()
    }

    public func flushErase() {
        flushPendingPersistence()
    }

    public func resetViewport() {
        state.viewport = CanvasViewport()
        persist()
    }

    // MARK: - Spaces

    public func setSpaceBackground(_ background: SpaceBackground) {
        state.setSpaceBackground(background)
        persist()
    }

    /// Sets the space's project folder (used by file-browser and git cards).
    public func setSpaceFolder(_ path: String?) {
        state.setSpaceFolder(path)
        persist()
    }

    public func setSpaceTiling(_ tiling: SpaceTiling) {
        state.setSpaceTiling(tiling)
        persist()
    }

    public func setBackgroundDimming(_ value: Double) {
        state.setBackgroundDimming(value)
        persist()
    }

    public func moveSpaceCard(fromIndex: Int, toIndex: Int) {
        state.reorderSpaceCard(fromIndex: fromIndex, toIndex: toIndex)
        persist()
    }

    public func resetSpaceCardOrder() {
        state.resetSpaceCardOrder()
        persist()
    }

    public func setSpaceLayoutMode(_ mode: SpaceLayoutMode) {
        state.setSpaceLayoutMode(mode)
        persist()
    }

    /// Seeds free-arrange frames for cards that don't have one yet (structural,
    /// one-time per card — persists immediately).
    public func seedSpaceFreeFrames(_ defaults: [UUID: SpaceFreeFrame]) {
        state.seedMissingFreeFrames(defaults)
        persist()
    }

    /// Replaces every free-arrange frame (Re-tile in free mode). Structural.
    public func setSpaceFreeFrames(_ frames: [UUID: SpaceFreeFrame]) {
        state.setSpaceFreeFrames(frames)
        persist()
    }

    /// Debounced like `moveCard` — a free-arrange drag emits many origins.
    public func moveSpaceCardFreely(id: UUID, to origin: ScreenPoint) {
        state.moveSpaceCardFreely(id: id, to: origin)
        schedulePersistence()
    }

    /// Debounced like `resizeCard` — a resize drag emits many sizes.
    public func resizeSpaceCardFreely(id: UUID, to size: ScreenPoint) {
        state.resizeSpaceCardFreely(id: id, to: size)
        schedulePersistence()
    }

    /// Directory holding imported background images, a sibling of the active
    /// workspace storage (so it lands in `…/Voidloom/backgrounds` in library mode
    /// and beside the test file in single-file mode).
    public func backgroundsDirectoryURL() -> URL {
        let base: URL
        if isLibraryMode, let workspacesDirectoryURL {
            base = workspacesDirectoryURL.deletingLastPathComponent()
        } else {
            base = storageURL.deletingLastPathComponent()
        }
        return base.appendingPathComponent("backgrounds", isDirectory: true)
    }

    /// Copies the chosen image into `backgroundsDirectoryURL()` under a fresh
    /// UUID filename, sets the space background to it, persists immediately, and
    /// returns the stored filename (nil on failure).
    public func importBackgroundImage(from url: URL) -> String? {
        let directory = backgroundsDirectoryURL()
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = directory.appendingPathComponent(fileName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: destination)
        } catch {
            lastPersistenceError = error.localizedDescription
            return nil
        }
        state.setSpaceBackground(.image(fileName: fileName))
        persist()
        return fileName
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

    /// Pans (never zooms) so `point` lands at the screen center — drives the
    /// minimap's click-to-recenter. Debounced like other viewport moves.
    public func centerViewport(on point: CanvasPoint, viewportSize: ScreenPoint) {
        guard viewportSize.x > 0, viewportSize.y > 0 else { return }
        state.viewport.pan(
            soCanvasPoint: point,
            appearsAt: ScreenPoint(x: viewportSize.x / 2, y: viewportSize.y / 2)
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
        guard let index = library.workspaces.firstIndex(where: { $0.id == id }) else { return }

        let wasActive = library.selectedWorkspaceID == id

        if wasActive {
            flushPendingPersistence()
        }

        library.workspaces.remove(at: index)

        let workspaceFileURL = Self.workspaceURL(for: id, in: workspacesDirectoryURL)
        try? FileManager.default.removeItem(at: workspaceFileURL)

        // Deleting the final workspace is allowed: every mode is gated behind an
        // open workspace, so an empty library just shows the launcher's empty
        // state. selectedWorkspaceID is left stale (harmless while nothing opens
        // it); creating a workspace resets it.
        if library.workspaces.isEmpty {
            state = WorkspaceState()
            do {
                try Self.saveLibrary(library, to: libraryURL)
                lastPersistenceError = nil
            } catch {
                lastPersistenceError = error.localizedDescription
            }
            return
        }

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

    /// Destructive factory reset (library mode only): deletes every workspace
    /// file, the library index, backups, imported backgrounds, and the legacy
    /// single-file store, then recreates a fresh empty "Untitled" workspace as
    /// the only library entry and persists it. Callers own any confirmation UI
    /// and terminating live agent sessions first.
    public func resetAllData() {
        guard isLibraryMode, let libraryURL, let workspacesDirectoryURL else { return }

        // Cancel (don't flush) any queued write so a debounce can't resurrect
        // the old data after the wipe.
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = nil

        let fm = FileManager.default
        let base = libraryURL.deletingLastPathComponent()
        try? fm.removeItem(at: workspacesDirectoryURL)
        try? fm.removeItem(at: base.appendingPathComponent("backups", isDirectory: true))
        try? fm.removeItem(at: base.appendingPathComponent("backgrounds", isDirectory: true))
        try? fm.removeItem(at: base.appendingPathComponent("workspace.json"))
        try? fm.removeItem(at: libraryURL)

        let workspaceID = UUID()
        let now = Date()
        library = WorkspaceLibrary(
            selectedWorkspaceID: workspaceID,
            workspaces: [
                WorkspaceSummary(id: workspaceID, name: "Untitled",
                                 createdAt: now, updatedAt: now, cardCount: 0)
            ]
        )
        state = WorkspaceState()

        do {
            try fm.createDirectory(at: workspacesDirectoryURL, withIntermediateDirectories: true)
            try Self.save(state, to: Self.workspaceURL(for: workspaceID, in: workspacesDirectoryURL))
            try Self.saveLibrary(library, to: libraryURL)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
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

    /// Call after a graceful flush/terminate so the next launch knows the
    /// previous session ended cleanly (no backup recovery needed).
    public func markCleanShutdown() {
        Self.writeShutdownMarker(true, to: shutdownMarkerURL)
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
            let baseDir = shutdownMarkerURL.deletingLastPathComponent()
            Self.writeBackup(state, workspaceID: library.selectedWorkspaceID, baseDir: baseDir)
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
        legacyStorageURL: URL,
        shutdownMarkerURL: URL
    ) -> LoadedLibrary {
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            return loadExistingLibrary(
                libraryURL: libraryURL,
                workspacesDirectoryURL: workspacesDirectoryURL,
                shutdownMarkerURL: shutdownMarkerURL
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
        workspacesDirectoryURL: URL,
        shutdownMarkerURL: URL
    ) -> LoadedLibrary {
        do {
            let library = try loadLibrary(from: libraryURL)
            let wsURL = workspaceURL(for: library.selectedWorkspaceID, in: workspacesDirectoryURL)

            // Attempt to load current workspace; nil if missing OR corrupt.
            let loadedState = try? load(from: wsURL)

            // Recover from the newest valid backup whenever the current file is
            // missing or corrupt — independent of the cleanShutdown flag.
            if shouldRecover(currentLoadable: loadedState != nil) {
                let baseDir = shutdownMarkerURL.deletingLastPathComponent()
                let backupDir = backupsDirectory(for: library.selectedWorkspaceID, relativeTo: baseDir)
                if let backupFiles = try? FileManager.default.contentsOfDirectory(atPath: backupDir.path) {
                    for name in backupFiles.filter({ $0.hasSuffix(".json") }).sorted().reversed() {
                        if let recovered = try? load(from: backupDir.appendingPathComponent(name)) {
                            return LoadedLibrary(library: library, state: recovered)
                        }
                    }
                }
            }

            // Use successfully-loaded state or fall back to a fresh seed workspace.
            // Only reaches here when current file loaded successfully, or when no
            // valid backup exists to recover from.
            let state = loadedState ?? makeSeedState()
            if loadedState == nil { try? save(state, to: wsURL) }
            return LoadedLibrary(library: library, state: state)
        } catch {
            // Library itself is unreadable — create a brand-new library.
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

    // MARK: - Shutdown marker

    /// Pure helper: returns true iff the last session called markCleanShutdown().
    /// Returns false when the file is absent (first launch) or corrupt.
    nonisolated public static func readShutdownMarker(from url: URL) -> Bool {
        struct Marker: Codable { var cleanShutdown: Bool }
        guard let data = try? Data(contentsOf: url),
              let marker = try? JSONDecoder().decode(Marker.self, from: data) else {
            return false
        }
        return marker.cleanShutdown
    }

    nonisolated private static func writeShutdownMarker(_ clean: Bool, to url: URL) {
        struct Marker: Codable { var cleanShutdown: Bool }
        guard let data = try? JSONEncoder().encode(Marker(cleanShutdown: clean)) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    // MARK: - Recovery decision (pure, testable)

    /// Returns true when the store should attempt to load from a backup.
    /// Recovery is warranted whenever the current workspace file is missing or
    /// corrupt (not loadable), regardless of how the previous session ended.
    /// The cleanShutdown marker is still written on terminate but no longer gates
    /// this decision — a clean shutdown followed by file corruption must recover.
    nonisolated public static func shouldRecover(currentLoadable: Bool) -> Bool {
        !currentLoadable
    }

    // MARK: - Rolling backup helpers (pure, testable)

    /// Given a lexicographically-sorted list of backup filenames (oldest first),
    /// returns the names that should be deleted so only `keep` remain.
    /// Fixed-width decimal timestamp (seconds since reference date) so lexicographic sort == chronological sort.
    nonisolated public static func backupsToPrune(existing: [String], keep: Int) -> [String] {
        let sorted = existing.sorted()
        let excess = sorted.count - keep
        guard excess > 0 else { return [] }
        return Array(sorted.prefix(excess))
    }

    nonisolated private static func backupsDirectory(
        for workspaceID: UUID,
        relativeTo baseDir: URL
    ) -> URL {
        baseDir
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent(workspaceID.uuidString, isDirectory: true)
    }

    /// Writes a timestamped backup of `state` and prunes old backups so that
    /// only `keepCount` remain per workspace. Failures are silently ignored —
    /// backups are best-effort and must never block the main save path.
    nonisolated private static func writeBackup(
        _ state: WorkspaceState,
        workspaceID: UUID,
        baseDir: URL,
        keepCount: Int = 3
    ) {
        let backupDir = backupsDirectory(for: workspaceID, relativeTo: baseDir)
        // Fixed-width decimal timestamp ensures lexicographic order == chronological order.
        let ts = String(format: "%020.6f", Date().timeIntervalSinceReferenceDate)
        let backupURL = backupDir.appendingPathComponent("backup-\(ts).json")

        try? save(state, to: backupURL)

        guard let files = try? FileManager.default.contentsOfDirectory(atPath: backupDir.path) else { return }
        for name in backupsToPrune(existing: files.filter { $0.hasSuffix(".json") }, keep: keepCount) {
            try? FileManager.default.removeItem(at: backupDir.appendingPathComponent(name))
        }
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
                size: CardSize(width: 480, height: 320),
                title: "New Agent",
                content: "Placeholder for an AI coding agent session."
            )
        case .note:
            return WorkspaceCard(
                kind: .note,
                position: .zero,
                size: CardSize(width: 440, height: 300),
                title: "New Note",
                content: "Capture spatial context here."
            )
        case .todo:
            return WorkspaceCard(
                kind: .todo,
                position: .zero,
                size: CardSize(width: 420, height: 300),
                title: "New Todo",
                content: "[ ] First item\n[ ] Next item"
            )
        case .browser:
            return WorkspaceCard(
                kind: .browser,
                position: .zero,
                size: CardSize(width: 520, height: 340),
                title: "New Preview",
                content: "Browser card placeholder."
            )
        case .fileBrowser:
            return WorkspaceCard(
                kind: .fileBrowser,
                position: .zero,
                size: CardSize(width: 440, height: 360),
                title: "Files",
                content: ""
            )
        case .git:
            return WorkspaceCard(
                kind: .git,
                position: .zero,
                size: CardSize(width: 560, height: 380),
                title: "Git",
                content: ""
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
