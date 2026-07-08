import Foundation

/// Records what each agent terminal is doing so the assistant — and, on request,
/// the other agents — can stay aware regardless of which model each one runs.
/// Keyed by card UUID (survives renames); the roster is always built from the
/// live card list, so it reflects only the current workspace's agents.
@MainActor
public final class AgentMemory {
    public enum Action: Equatable, Sendable {
        case spawned
        case received(String)     // a prompt was sent to it
        case delegated(String)    // a delegated question is being answered
        case relayed(from: String)

        /// Short present-tense description for a roster line / card detail.
        public var phrase: String {
            switch self {
            case .spawned: return "just started"
            case .received(let text): return "asked to \(Self.trim(text))"
            case .delegated(let question): return "looking into \(Self.trim(question))"
            case .relayed(let from): return "briefed by \(from)"
            }
        }

        private static func trim(_ text: String, max: Int = 60) -> String {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.count > max ? String(clean.prefix(max)) + "…" : clean
        }
    }

    private var latest: [UUID: Action] = [:]
    /// Agents already given a one-time cross-agent briefing (see briefingPrefix).
    private var briefed: Set<UUID> = []

    public init() {}

    public func record(cardID: UUID, action: Action) { latest[cardID] = action }
    public func forget(cardID: UUID) { latest[cardID] = nil; briefed.remove(cardID) }

    /// The most recent activity for one agent, or nil if none recorded.
    public func activity(for cardID: UUID) -> String? { latest[cardID]?.phrase }

    /// A compact roster of what the given agents are doing, optionally excluding
    /// one (the recipient). Agents with no recorded activity read as "idle".
    public func roster(for agents: [(id: UUID, name: String)], excluding: UUID? = nil) -> String {
        agents
            .filter { $0.id != excluding }
            .map { "\($0.name): \(latest[$0.id]?.phrase ?? "idle")" }
            .joined(separator: "; ")
    }

    /// A one-time context preamble for an agent's FIRST task: what the OTHER agents
    /// are doing, so every agent — whatever model it runs — starts work aware of the
    /// others without the user asking. Returns "" once the agent has been briefed, and
    /// while it is the only agent (so it is still briefed the first time others exist).
    public func briefingPrefix(for cardID: UUID, amongst agents: [(id: UUID, name: String)]) -> String {
        guard !briefed.contains(cardID) else { return "" }
        let others = roster(for: agents, excluding: cardID)
        guard !others.isEmpty else { return "" }
        briefed.insert(cardID)
        return "For context, the other agents in this workspace — \(others).\n\n"
    }
}
