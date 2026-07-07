import Foundation

/// What kind of process an agent terminal runs.
public enum MediatorAgentKind: String, Codable, Equatable, Sendable, CaseIterable {
    case claudeCode = "claude"
    case shell = "shell"
}

public enum ArrangeStyle: Codable, Equatable, Sendable {
    case grid
    case retile
    case focus(target: String)
}

/// Backgrounds the mediator can set by voice. Mirrors `SpaceBackground`
/// minus `.image` — voice cannot usefully reference a background file.
public enum MediatorBackgroundSpec: Codable, Equatable, Sendable {
    case atmosphere
    case solid(hex: String)
}

/// The complete tool schema. A brain's ONLY output is one of these; plain
/// Swift validates and executes. Labeled associated values are load-bearing:
/// they define the wire JSON later plans generate grammars against.
public enum MediatorCommand: Codable, Equatable, Sendable {
    case spawnAgents(count: Int, kind: MediatorAgentKind, names: [String]?)
    case sendPrompt(target: String, text: String)
    case readOutput(target: String)
    case closeTerminal(target: String)
    case arrange(style: ArrangeStyle)
    case createCard(kind: CardKind, content: String?)
    case switchSpace(name: String)
    case setBackground(spec: MediatorBackgroundSpec)
    // Phase B — Sunday's hands: edit the cards, not just terminals.
    case renameCard(target: String, newName: String)
    case deleteCard(target: String)
    case editNote(target: String, content: String, append: Bool)
    case addTodoItem(target: String, text: String)
    case setTodoItemDone(target: String, text: String, done: Bool)
    // Phase C — delegation: hand a repo-technical question to an agent CLI and
    // relay its answer. `target` nil means "pick or spawn an agent".
    case delegate(question: String, target: String?)
    // Agent memory: relay one agent's recent output to another; brief an agent on
    // what the others are doing.
    case relayBetweenAgents(from: String, to: String)
    case briefAgent(target: String)
}
