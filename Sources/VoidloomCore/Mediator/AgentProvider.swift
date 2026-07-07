import Foundation

/// The user's primary agent CLI — what Sunday launches in a terminal card and
/// delegates deep questions to. Claude and Codex ship first (default Claude);
/// more (Gemini, local Ollama agents, a custom command) come later. Only this
/// enum changes which CLI runs; the spawn and delegation flows are provider-
/// agnostic. Persisted as the `agent.provider` setting.
public enum AgentProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude
    case codex

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// The bare CLI that opens an interactive session inside a terminal card.
    public var launchCommand: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }

    /// A one-shot, non-interactive command whose stdout is the whole answer —
    /// used for delegation so there is no TUI to parse. The question is wrapped
    /// in single quotes with embedded quotes escaped, so it is shell-safe.
    public func printCommand(question: String) -> String {
        let escaped = question.replacingOccurrences(of: "'", with: "'\\''")
        switch self {
        case .claude: return "claude -p '\(escaped)'"
        case .codex: return "codex exec '\(escaped)'"
        }
    }

    public static let `default`: AgentProvider = .claude

    /// Resolves the persisted setting; falls back to the default for an unknown
    /// or absent value, so a corrupt setting never breaks delegation.
    public static func resolve(_ rawValue: String?) -> AgentProvider {
        rawValue.flatMap(AgentProvider.init(rawValue:)) ?? .default
    }
}
