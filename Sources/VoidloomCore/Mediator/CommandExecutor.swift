import Foundation

public enum ExecutionResult: Equatable, Sendable {
    case success(narration: String)
    case needsClarification(question: String)
    case needsConfirmation(prompt: String, pending: MediatorCommand)
    case refused(reason: String)
}

/// The only component that turns a MediatorCommand into state changes.
/// Brains never touch the store; this validates, resolves targets, and
/// calls WorkspaceStore / AgentTerminalControlling. Mode-blind: effects
/// apply regardless of Canvas/Spaces mode (HUD narrates visibility).
@MainActor
public final class CommandExecutor {
    public static let spawnLimit = 1...8
    public static let outputLines = 25

    private let store: WorkspaceStore
    private let terminals: AgentTerminalControlling
    private let namePool: AgentNamePool

    public init(store: WorkspaceStore, terminals: AgentTerminalControlling, namePool: AgentNamePool) {
        self.store = store
        self.terminals = terminals
        self.namePool = namePool
    }

    public func execute(_ command: MediatorCommand, confirmed: Bool = false) -> ExecutionResult {
        switch command {
        case .spawnAgents(let count, let kind, let names):
            return spawnAgents(count: count, kind: kind, names: names)
        case .sendPrompt(let target, let text):
            return withAgent(named: target) { id, name in
                terminals.send(text: text, to: id)
                return .success(narration: "→ \(name)")
            }
        case .readOutput(let target):
            return withAgent(named: target) { id, name in
                let lines = terminals.recentOutput(of: id, maxLines: Self.outputLines)
                return .success(narration: lines.isEmpty
                    ? "\(name) has no output yet"
                    : lines.joined(separator: "\n"))
            }
        case .closeTerminal(let target):
            return withAgent(named: target) { id, name in
                guard confirmed else {
                    return .needsConfirmation(prompt: "Close \(name) and its session?", pending: command)
                }
                terminals.terminate(cardID: id)
                store.deleteCard(id: id)
                return .success(narration: "Closed \(name)")
            }
        case .arrange(let style):
            return arrange(style)
        case .createCard(let kind, let content):
            if kind == .agent {
                return spawnAgents(count: 1, kind: .claudeCode, names: nil)
            }
            store.addTitledCard(kind: kind, content: content ?? "")
            return .success(narration: "Created a \(kind.rawValue)")
        case .switchSpace(let name):
            return switchSpace(named: name)
        case .setBackground(let spec):
            switch spec {
            case .atmosphere: store.setSpaceBackground(.atmosphere)
            case .solid(let hex): store.setSpaceBackground(.solid(hex: hex))
            }
            return .success(narration: "Background updated")

        case .renameCard(let target, let newName):
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .needsClarification(question: "What should I rename it to?")
            }
            return withCard(named: target) { card in
                store.updateCardTitle(id: card.id, to: trimmed)
                return .success(narration: "Renamed \(card.title) to \(trimmed)")
            }

        case .deleteCard(let target):
            return withCard(named: target) { card in
                guard confirmed else {
                    return .needsConfirmation(prompt: "Delete \(card.title)?", pending: command)
                }
                if card.kind == .agent { terminals.terminate(cardID: card.id) }
                store.deleteCard(id: card.id)
                return .success(narration: "Deleted \(card.title)")
            }

        case .editNote(let target, let content, let append):
            return withCard(named: target) { card in
                guard card.kind == .note else {
                    return .refused(reason: "\(card.title) isn't a note card.")
                }
                let updated = append && !card.content.isEmpty ? card.content + "\n" + content : content
                store.updateCardContent(id: card.id, to: updated)
                return .success(narration: append ? "Added to \(card.title)" : "Updated \(card.title)")
            }

        case .addTodoItem(let target, let text):
            return withCard(named: target) { card in
                guard card.kind == .todo else {
                    return .refused(reason: "\(card.title) isn't a todo card.")
                }
                var items = TodoContentParser.parse(card.content)
                items.append(TodoItem(id: items.count, isComplete: false, text: text))
                store.updateCardContent(id: card.id, to: TodoContentParser.serialize(items))
                return .success(narration: "Added \"\(text)\" to \(card.title)")
            }

        case .setTodoItemDone(let target, let text, let done):
            return withCard(named: target) { card in
                guard card.kind == .todo else {
                    return .refused(reason: "\(card.title) isn't a todo card.")
                }
                var items = TodoContentParser.parse(card.content)
                let query = text.lowercased()
                guard let index = items.firstIndex(where: { $0.text.lowercased() == query })
                    ?? items.firstIndex(where: { $0.text.lowercased().contains(query) }) else {
                    return .needsClarification(question: "No item matching \"\(text)\" in \(card.title).")
                }
                items[index].isComplete = done
                store.updateCardContent(id: card.id, to: TodoContentParser.serialize(items))
                return .success(narration: "\(done ? "Checked" : "Unchecked") \"\(items[index].text)\" in \(card.title)")
            }
        }
    }

    private func spawnAgents(count: Int, kind: MediatorAgentKind, names: [String]?) -> ExecutionResult {
        guard Self.spawnLimit.contains(count) else {
            return .refused(reason: "I can spawn between \(Self.spawnLimit.lowerBound) and \(Self.spawnLimit.upperBound) agents at once.")
        }
        let existing = Set(agentCards().map { $0.name.lowercased() })
        var seen = Set<String>()
        let provided = (names ?? [])
            .map { $0.lowercased() }
            .filter { seen.insert($0).inserted }
            .prefix(count)
        if let taken = provided.first(where: { existing.contains($0) }) {
            return .needsClarification(question: "An agent named \(taken) already exists — pick a different name.")
        }
        var finalNames = Array(provided)
        if finalNames.count < count {
            finalNames += namePool.nextNames(count: count - finalNames.count,
                                             existing: existing.union(finalNames))
        }
        let workingDirectory = store.state.space?.folderPath
        for name in finalNames {
            let id = store.addTitledCard(kind: .agent, title: name)
            terminals.spawn(cardID: id, kind: kind, workingDirectory: workingDirectory)
        }
        let noun = count == 1 ? "agent" : "agents"
        return .success(narration: "Spawned \(count) \(kind.rawValue) \(noun): \(finalNames.joined(separator: ", "))")
    }

    private func arrange(_ style: ArrangeStyle) -> ExecutionResult {
        switch style {
        case .grid, .retile:
            store.setSpaceTiling(SpaceTiling())
            return .success(narration: "Re-tiled the space")
        case .focus(let target):
            return withAgent(named: target) { id, name in
                store.selectCard(id: id)
                return .success(narration: "Focused \(name)")
            }
        }
    }

    private func switchSpace(named name: String) -> ExecutionResult {
        let candidates = store.library.workspaces.map { (id: $0.id, name: $0.name) }
        switch MediatorTargetResolver.resolve(name, in: candidates) {
        case .match(let id):
            let matched = candidates.first { $0.id == id }?.name ?? name
            store.switchWorkspace(id: id)
            guard store.library.selectedWorkspaceID == id else {
                return .refused(reason: "Couldn't switch to \(matched) — the workspace failed to load.")
            }
            return .success(narration: "Switched to \(matched)")
        case .ambiguous(let names):
            return .needsClarification(question: "There are \(names.count) spaces named \(name) — rename one to switch by voice.")
        case .none(let suggestion):
            if let suggestion {
                return .needsClarification(question: "I don't see a space called \(name) — did you mean \(suggestion)?")
            }
            return .needsClarification(question: "I don't see a space called \(name).")
        }
    }

    private func agentCards() -> [(id: UUID, name: String)] {
        store.state.cards.filter { $0.kind == .agent }.map { (id: $0.id, name: $0.title) }
    }

    /// Resolves a name against ALL cards (not just agents) — the card CRUD
    /// commands operate on notes, todos, browsers, and terminals alike.
    private func withCard(named target: String, _ body: (WorkspaceCard) -> ExecutionResult) -> ExecutionResult {
        let candidates = store.state.cards.map { (id: $0.id, name: $0.title) }
        switch MediatorTargetResolver.resolve(target, in: candidates) {
        case .match(let id):
            guard let card = store.state.cards.first(where: { $0.id == id }) else {
                return .needsClarification(question: "I don't see a card called \(target).")
            }
            return body(card)
        case .ambiguous(let names):
            return .needsClarification(question: "Multiple cards match \(target): \(names.joined(separator: ", ")).")
        case .none(let suggestion):
            if let suggestion {
                return .needsClarification(question: "I don't see a \(target) — did you mean \(suggestion)?")
            }
            return .needsClarification(question: "I don't see a card called \(target).")
        }
    }

    private func withAgent(named target: String, _ body: (UUID, String) -> ExecutionResult) -> ExecutionResult {
        let candidates = agentCards()
        switch MediatorTargetResolver.resolve(target, in: candidates) {
        case .match(let id):
            let name = candidates.first { $0.id == id }?.name ?? target
            return body(id, name)
        case .ambiguous(let names):
            return .needsClarification(question: "Multiple agents match \(target): \(names.joined(separator: ", ")).")
        case .none(let suggestion):
            if let suggestion {
                return .needsClarification(question: "I don't see a \(target) — did you mean \(suggestion)?")
            }
            return .needsClarification(question: "I don't see an agent called \(target).")
        }
    }
}
