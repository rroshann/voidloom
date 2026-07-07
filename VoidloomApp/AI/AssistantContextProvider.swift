import Foundation
import VoidloomAI
import VoidloomCore

/// Gathers the live workspace snapshot that grounds the assistant, and feeds it
/// to the pure `WorkspaceContextBuilder`. Everything but git is read fresh at
/// call time from the live store/session manager; git shells out, so its summary
/// is cached and refreshed opportunistically (on appear, folder change, after
/// commands). A stale-or-missing git line self-heals within a refresh.
@MainActor
final class AssistantContextProvider: ObservableObject {
    private let store: WorkspaceStore
    private let sessionManager: AgentSessionManager
    private let modelAssets: ModelAssetManager
    private let agentMemory: AgentMemory

    @Published private(set) var gitSummary: String?
    private var lastGitFolder: String?

    /// Supplies a compact recap of the recent conversation for the active
    /// workspace (set by the shell). Gives Sunday continuity across launches
    /// without unbounded context — the recap itself is bounded by the store.
    var recentConversation: (() -> String?)?

    init(store: WorkspaceStore, sessionManager: AgentSessionManager,
         modelAssets: ModelAssetManager, agentMemory: AgentMemory = AgentMemory()) {
        self.store = store
        self.sessionManager = sessionManager
        self.modelAssets = modelAssets
        self.agentMemory = agentMemory
    }

    /// The full context string. Synchronous and always current except for git,
    /// which reflects the last `refreshGit()`.
    func snapshot(selectedCardContext: String? = nil) -> String {
        var context = WorkspaceContextBuilder.build(.init(
            workspaceName: workspaceName,
            mode: modeLabel,
            folderPath: store.state.space?.folderPath,
            gitSummary: gitSummary,
            brainTier: brainTier,
            cards: cardLines(),
            recentActivity: nil,
            selectedCardContext: selectedCardContext))
        if let recap = recentConversation?(), !recap.isEmpty {
            context += "\n\nRecent conversation (for continuity, may span past sessions):\n" + recap
        }
        return context
    }

    /// Refresh the cached git summary for the current project folder. Cheap
    /// (~tens of ms) and safe to call redundantly; a non-repo folder clears it.
    func refreshGit() async {
        guard let path = store.state.space?.folderPath, !path.isEmpty else {
            gitSummary = nil; lastGitFolder = nil; return
        }
        lastGitFolder = path
        let dir = URL(fileURLWithPath: path)
        let branchResult = await Git.run(["rev-parse", "--abbrev-ref", "HEAD"], in: dir)
        // Folder changed while we were awaiting — a newer refresh owns the cache.
        guard lastGitFolder == path else { return }
        guard branchResult.code == 0 else { gitSummary = nil; return }
        let branch = branchResult.out.trimmingCharacters(in: .whitespacesAndNewlines)
        let statusResult = await Git.run(["status", "--porcelain"], in: dir)
        guard lastGitFolder == path else { return }
        let changes = statusResult.out.split(separator: "\n", omittingEmptySubsequences: true).count
        gitSummary = changes == 0
            ? "\(branch), clean"
            : "\(branch), \(changes) change\(changes == 1 ? "" : "s")"
    }

    // MARK: - Live inputs

    private var workspaceName: String {
        store.library.workspaces.first { $0.id == store.library.selectedWorkspaceID }?.name ?? "Workspace"
    }

    private var modeLabel: String {
        (UserDefaults.standard.string(forKey: "app.mode") == "spaces") ? "Spaces" : "Canvas"
    }

    private var brainTier: String {
        var parts = ["fast path"]
        if modelAssets.state(of: LocalModelManifest.commandModel) == .ready { parts.append("local LLM") }
        if AppleTierAvailability.foundationModelsAvailable { parts.append("Apple Intelligence") }
        return parts.joined(separator: " + ")
    }

    private func cardLines() -> [WorkspaceContextBuilder.CardLine] {
        store.state.cards.map { card in
            WorkspaceContextBuilder.CardLine(
                title: card.title,
                kind: Self.kindLabel(card.kind),
                detail: detail(for: card))
        }
    }

    private func detail(for card: WorkspaceCard) -> String? {
        switch card.kind {
        case .agent:
            let state = sessionManager.session(for: card.id)?.isRunning == true ? "running" : "idle"
            // Fold in what the agent is doing (from AgentMemory) so Sunday can
            // answer "what is slate up to?" and reason about the whole team.
            if let activity = agentMemory.activity(for: card.id) {
                return "\(state) · \(activity)"
            }
            return state
        case .note, .todo:
            let text = card.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        case .browser, .fileBrowser, .git:
            return nil
        }
    }

    private static func kindLabel(_ kind: CardKind) -> String {
        switch kind {
        case .agent: return "terminal"
        case .note: return "note"
        case .todo: return "todo"
        case .browser: return "browser"
        case .fileBrowser: return "file browser"
        case .git: return "git"
        }
    }
}
