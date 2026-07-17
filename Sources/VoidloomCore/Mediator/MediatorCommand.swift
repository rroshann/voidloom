import Foundation

/// What an agent terminal runs: one of the supported AI agent CLIs, or a bare
/// shell. The rawValue is the spoken/wire keyword ("claude", "codex", …).
public enum MediatorAgentKind: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case claudeCode = "claude"
    case codex
    case grok
    case opencode
    case cursor
    case shell

    public var id: String { rawValue }

    /// The AI agent kinds (everything but a plain shell) — for provider pickers.
    public static let aiKinds: [MediatorAgentKind] = allCases.filter { $0 != .shell }

    public var isAI: Bool { self != .shell }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .opencode: return "OpenCode"
        case .cursor: return "Cursor"
        case .shell: return "Shell"
        }
    }

    /// The default CLI launched for an interactive session in a spawned terminal.
    /// nil for a bare shell. The app may override this per kind in Settings.
    public var defaultLaunchCommand: String? {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .grok: return "grok"
        case .opencode: return "opencode"
        case .cursor: return "cursor-agent"
        case .shell: return nil
        }
    }

    /// A one-shot, non-interactive command whose stdout is the whole answer, for
    /// delegation. nil for a shell. The question is single-quote-escaped.
    public func printCommand(question: String) -> String? {
        guard isAI else { return nil }
        let escaped = question.replacingOccurrences(of: "'", with: "'\\''")
        switch self {
        case .claudeCode: return "claude -p '\(escaped)'"
        case .codex: return "codex exec '\(escaped)'"
        case .grok: return "grok -p '\(escaped)'"
        case .opencode: return "opencode run '\(escaped)'"
        case .cursor: return "cursor-agent -p '\(escaped)'"
        case .shell: return nil
        }
    }

    /// Resolves a persisted provider setting to an AI kind, defaulting to Claude
    /// for an unknown/absent/shell value so delegation never breaks.
    public static func resolveProvider(_ rawValue: String?) -> MediatorAgentKind {
        let resolved = rawValue.flatMap(MediatorAgentKind.init(rawValue:))
        return (resolved?.isAI == true) ? resolved! : .claudeCode
    }
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
