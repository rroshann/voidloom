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
        }
    }

    private func spawnAgents(count: Int, kind: MediatorAgentKind, names: [String]?) -> ExecutionResult {
        guard Self.spawnLimit.contains(count) else {
            return .refused(reason: "I can spawn between \(Self.spawnLimit.lowerBound) and \(Self.spawnLimit.upperBound) agents at once.")
        }
        let existing = Set(agentCards().map(\.name))
        let assigned = names?.prefix(count).map { $0.lowercased() }
            ?? namePool.nextNames(count: count, existing: existing)
        var finalNames: [String] = Array(assigned)
        if finalNames.count < count {
            finalNames += namePool.nextNames(count: count - finalNames.count,
                                             existing: existing.union(finalNames))
        }
        for name in finalNames {
            let id = store.addTitledCard(kind: .agent, title: name)
            terminals.spawn(cardID: id, kind: kind)
        }
        return .success(narration: "Spawned \(count) \(kind.rawValue) agents: \(finalNames.joined(separator: ", "))")
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
            store.switchWorkspace(id: id)
            return .success(narration: "Switched to \(name)")
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
