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
    public let memory: AgentMemory

    public init(store: WorkspaceStore, terminals: AgentTerminalControlling,
                namePool: AgentNamePool, memory: AgentMemory = AgentMemory()) {
        self.store = store
        self.terminals = terminals
        self.namePool = namePool
        self.memory = memory
    }

    public func execute(_ command: MediatorCommand, confirmed: Bool = false) -> ExecutionResult {
        switch command {
        case .spawnAgents(let count, let kind, let names):
            return spawnAgents(count: count, kind: kind, names: names)
        case .sendPrompt(let target, let text):
            return withAgent(named: target) { id, name in
                // Auto-brief on the first task: prepend what the other agents are
                // doing so this one starts work aware of them (model-agnostic — it is
                // just text into the terminal). One-time; no-op once briefed or solo.
                let prefix = memory.briefingPrefix(for: id, amongst: agentCards())
                terminals.send(text: prefix + text, to: id)
                memory.record(cardID: id, action: .received(text))
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
            let body = content ?? ""
            // Title notes from their text so they stay addressable by name
            // ("close buy milk") instead of piling up as identical "New Note"s.
            let title = kind == .note ? Self.noteTitle(from: body) : ""
            store.addTitledCard(kind: kind, title: title, content: body)
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

        case .delegate:
            // Delegation is long and asynchronous (a CLI subprocess + harvest),
            // so the coordinator runs it and never routes it here. This is an
            // unreachable safety only.
            return .refused(reason: "Delegation isn't available right now.")

        case .relayBetweenAgents(let from, let to):
            return withAgent(named: from) { fromID, fromName in
                withAgent(named: to) { toID, toName in
                    guard fromID != toID else {
                        return .needsClarification(question: "Relay needs two different agents.")
                    }
                    let output = terminals.recentOutput(of: fromID, maxLines: Self.outputLines)
                    let body = output.isEmpty ? "\(fromName) has no output yet." : output.joined(separator: "\n")
                    terminals.send(text: "Context from \(fromName): \(body)", to: toID)
                    memory.record(cardID: toID, action: .relayed(from: fromName))
                    return .success(narration: "Relayed \(fromName) → \(toName)")
                }
            }

        case .briefAgent(let target):
            return withAgent(named: target) { id, name in
                let others = agentCards()
                let roster = memory.roster(for: others, excluding: id)
                guard !roster.isEmpty else {
                    return .success(narration: "\(name) is the only agent here.")
                }
                terminals.send(text: "Other agents in this workspace — \(roster).", to: id)
                memory.record(cardID: id, action: .received("a briefing on the other agents"))
                return .success(narration: "Briefed \(name) on the others")
            }
        }
    }

    /// Derives a note card's title from its text: the first non-empty line,
    /// capped at 40 characters. Empty text keeps the store's default title.
    static func noteTitle(from content: String) -> String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !firstLine.isEmpty else { return "" }
        guard firstLine.count > 40 else { return firstLine }
        return String(firstLine.prefix(40)) + "…"
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
            memory.record(cardID: id, action: .spawned)
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
