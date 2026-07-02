# Local AI Mediator — Plan 1: Core Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-logic mediator foundation in VoidloomCore — command schema, terminal-control seam, name pool, target resolution, executor, and pipeline state machine — plus the App-layer stub conformance and Settings cleanup, all TDD.

**Architecture:** Everything here is Plan 1 of 4 from `docs/superpowers/specs/2026-07-01-local-ai-mediator-design.md` (rev 2). Models are NOT involved yet: this plan delivers the typed `MediatorCommand` world and the state machine that later plans feed from brains/ASR. Plan 2 = tier-2 brain + downloads + typed input UI; Plan 3 = voice stack; Plan 4 = tier-1 Apple stack.

**Tech Stack:** Swift 6 SPM package (`VoidloomCore` target + `VoidloomTests`), XCTest, macOS 14 floor. No new dependencies in this plan.

## Global Constraints

- Platform floor: `.macOS(.v14)` (Package.swift) — no macOS-26-only APIs in this plan.
- `Sources/VoidloomCore/` must not import SwiftUI, AppKit, AVFoundation, or any model runtime.
- Value-type models are `Codable, Equatable, Sendable`; `WorkspaceStore` is `@MainActor`.
- Views mutate state ONLY via `WorkspaceStore` methods; never persist from a view.
- One responsibility per file; new core types get their own file under `Sources/VoidloomCore/Mediator/`.
- TDD: failing test → run → minimal implementation → run → commit. Test commands below.
- Conventional Commits (`feat(mediator): …`, `refactor(settings): …`).
- Agent name pool: generic dictionary words only; never reference Valorant/Overwatch; no coined names (KAY/O, Zenyatta, Widowmaker).
- Do not break legacy migration (`workspace.json` → `library.json` + `workspaces/<id>.json`).
- Test commands: `swift test --filter MediatorCommandTests` (etc. per task), full suite `swift test`, app build `xcodebuild -scheme Voidloom -destination 'platform=macOS' build`.

---

### Task 1: MediatorCommand schema types

**Files:**
- Create: `Sources/VoidloomCore/Mediator/MediatorCommand.swift`
- Test: `Tests/VoidloomTests/MediatorCommandTests.swift` (new file)

**Interfaces:**
- Consumes: `CardKind` (`Sources/VoidloomCore/Workspace/WorkspaceModels.swift:3` — `agent/note/todo/browser`).
- Produces: `MediatorCommand`, `MediatorAgentKind`, `ArrangeStyle`, `MediatorBackgroundSpec` — the tool schema every later plan constrains brains to. Wire format is Swift's synthesized enum Codable: `{"sendPrompt":{"target":"jerry","text":"hi"}}`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/VoidloomTests/MediatorCommandTests.swift
import XCTest
@testable import VoidloomCore

final class MediatorCommandTests: XCTestCase {
    private func roundTrip(_ command: MediatorCommand) throws -> MediatorCommand {
        let data = try JSONEncoder().encode(command)
        return try JSONDecoder().decode(MediatorCommand.self, from: data)
    }

    func testEveryCaseRoundTripsThroughCodable() throws {
        let commands: [MediatorCommand] = [
            .spawnAgents(count: 4, kind: .claudeCode, names: nil),
            .spawnAgents(count: 2, kind: .shell, names: ["viper", "sage"]),
            .sendPrompt(target: "jerry", text: "look into the API errors"),
            .readOutput(target: "viper"),
            .closeTerminal(target: "omen"),
            .arrange(style: .grid),
            .arrange(style: .focus(target: "sage")),
            .createCard(kind: .note, content: "standup notes"),
            .createCard(kind: .todo, content: nil),
            .switchSpace(name: "voidloom"),
            .setBackground(spec: .atmosphere),
            .setBackground(spec: .solid(hex: "#102030FF")),
        ]
        for command in commands {
            XCTAssertEqual(try roundTrip(command), command)
        }
    }

    func testWireFormatIsStableForBrainGrammars() throws {
        // Later plans generate grammars against exactly this shape — a failure
        // here means the brain contract changed and grammars must be regenerated.
        let json = #"{"sendPrompt":{"target":"jerry","text":"hi"}}"#
        let decoded = try JSONDecoder().decode(MediatorCommand.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, .sendPrompt(target: "jerry", text: "hi"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MediatorCommandTests`
Expected: FAIL — `cannot find 'MediatorCommand' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/VoidloomCore/Mediator/MediatorCommand.swift
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
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MediatorCommandTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator/MediatorCommand.swift Tests/VoidloomTests/MediatorCommandTests.swift
git commit -m "feat(mediator): add MediatorCommand tool schema types"
```

---

### Task 2: AgentTerminalControlling seam + App stub conformance

**Files:**
- Create: `Sources/VoidloomCore/Mediator/AgentTerminalControlling.swift`
- Modify: `VoidloomApp/Agent/AgentSessionManager.swift` (47-line echo stub — add conformance at the bottom)
- Test: `Tests/VoidloomTests/MediatorExecutionTests.swift` (new file; mock lives here and is reused by Task 6)

**Interfaces:**
- Produces: `AgentTerminalControlling` protocol — the seam the Round-4 PTY manager will conform to later with zero mediator changes (spec: Dependencies & sequencing). `MockAgentTerminals` for Core tests.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/VoidloomTests/MediatorExecutionTests.swift
import XCTest
@testable import VoidloomCore

@MainActor
final class MockAgentTerminals: AgentTerminalControlling {
    var spawned: [(cardID: UUID, kind: MediatorAgentKind)] = []
    var sent: [(text: String, cardID: UUID)] = []
    var terminated: [UUID] = []
    var outputByCard: [UUID: [String]] = [:]

    func spawn(cardID: UUID, kind: MediatorAgentKind) { spawned.append((cardID, kind)) }
    func send(text: String, to cardID: UUID) { sent.append((text, cardID)) }
    func recentOutput(of cardID: UUID, maxLines: Int) -> [String] {
        Array((outputByCard[cardID] ?? []).suffix(maxLines))
    }
    func terminate(cardID: UUID) { terminated.append(cardID) }
}

@MainActor
final class AgentTerminalControllingTests: XCTestCase {
    func testMockRecordsInteractionsAndClampsOutput() {
        let mock = MockAgentTerminals()
        let id = UUID()
        mock.outputByCard[id] = ["a", "b", "c", "d"]

        mock.spawn(cardID: id, kind: .claudeCode)
        mock.send(text: "hello", to: id)

        XCTAssertEqual(mock.spawned.first?.kind, .claudeCode)
        XCTAssertEqual(mock.sent.first?.text, "hello")
        XCTAssertEqual(mock.recentOutput(of: id, maxLines: 2), ["c", "d"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AgentTerminalControllingTests`
Expected: FAIL — `cannot find type 'AgentTerminalControlling' in scope`.

- [ ] **Step 3: Write the protocol**

```swift
// Sources/VoidloomCore/Mediator/AgentTerminalControlling.swift
import Foundation

/// Core-side seam for agent terminal sessions, keyed by card UUID.
/// The App layer's AgentSessionManager conforms (echo stub today; the
/// SwiftTerm PTY manager conforms identically when it lands).
@MainActor
public protocol AgentTerminalControlling: AnyObject {
    func spawn(cardID: UUID, kind: MediatorAgentKind)
    func send(text: String, to cardID: UUID)
    func recentOutput(of cardID: UUID, maxLines: Int) -> [String]
    func terminate(cardID: UUID)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AgentTerminalControllingTests`
Expected: PASS.

- [ ] **Step 5: Add the App-layer conformance (build-verified, no unit test per project convention)**

Append to `VoidloomApp/Agent/AgentSessionManager.swift`:

```swift
extension AgentSessionManager: AgentTerminalControlling {
    func spawn(cardID: UUID, kind: MediatorAgentKind) {
        // Stub sessions have no process; kind becomes meaningful when PTY lands.
        startSession(cardID: cardID)
    }

    func send(text: String, to cardID: UUID) {
        submitInput(cardID: cardID, input: text)
    }

    func recentOutput(of cardID: UUID, maxLines: Int) -> [String] {
        Array((session(for: cardID)?.outputLines ?? []).suffix(maxLines))
    }

    func terminate(cardID: UUID) {
        terminateSession(cardID: cardID)
    }
}
```

Add `import VoidloomCore` at the top of the file if not already present.

- [ ] **Step 6: Verify the app builds**

Run: `xcodebuild -scheme Voidloom -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED (the `Metadata extraction skipped, no AppIntents.framework` note is harmless).

- [ ] **Step 7: Commit**

```bash
git add Sources/VoidloomCore/Mediator/AgentTerminalControlling.swift Tests/VoidloomTests/MediatorExecutionTests.swift VoidloomApp/Agent/AgentSessionManager.swift
git commit -m "feat(mediator): add AgentTerminalControlling seam; stub manager conforms"
```

---

### Task 3: AgentNamePool

**Files:**
- Create: `Sources/VoidloomCore/Mediator/AgentNamePool.swift`
- Test: `Tests/VoidloomTests/MediatorExecutionTests.swift` (append)

**Interfaces:**
- Produces: `AgentNamePool` with `nextNames(count:existing:) -> [String]`, used by Task 6's executor for `spawnAgents(names: nil)`.

- [ ] **Step 1: Write the failing tests** (append to `MediatorExecutionTests.swift`)

```swift
final class AgentNamePoolTests: XCTestCase {
    func testAssignsFirstUnusedNamesCaseInsensitively() {
        let pool = AgentNamePool()
        let names = pool.nextNames(count: 2, existing: ["Ember", "SLATE"])
        XCTAssertEqual(names, ["nova", "drift"])
    }

    func testExhaustedPoolAppendsNumericSuffixes() {
        let pool = AgentNamePool(names: ["fox", "owl"])
        let names = pool.nextNames(count: 3, existing: ["fox"])
        XCTAssertEqual(names, ["owl", "fox-2", "owl-2"])
    }

    func testCustomPackReplacesDefaults() {
        let pool = AgentNamePool(names: ["maple", "fox"])
        XCTAssertEqual(pool.nextNames(count: 1, existing: []), ["maple"])
    }

    func testEmptyCustomPackFallsBackToDefaults() {
        let pool = AgentNamePool(names: [])
        XCTAssertEqual(pool.nextNames(count: 1, existing: []), ["ember"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AgentNamePoolTests`
Expected: FAIL — `cannot find 'AgentNamePool' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/VoidloomCore/Mediator/AgentNamePool.swift
import Foundation

/// Deterministic agent-card naming. The built-in pack is generic tactical
/// callsigns (ordinary dictionary words only — never game-branded, no coined
/// names). Users can substitute any custom pack.
public struct AgentNamePool: Equatable, Sendable {
    public static let defaultCallsigns = [
        "ember", "slate", "nova", "drift", "ridge", "quartz",
        "wren", "vale", "flint", "cove", "sage", "echo",
    ]

    private let names: [String]

    public init(names: [String] = AgentNamePool.defaultCallsigns) {
        let cleaned = names.map { $0.lowercased() }
        self.names = cleaned.isEmpty ? Self.defaultCallsigns : cleaned
    }

    /// First `count` names not present in `existing` (case-insensitive),
    /// wrapping with "-2", "-3", … suffixes once the pack is exhausted.
    public func nextNames(count: Int, existing: Set<String>) -> [String] {
        let taken = Set(existing.map { $0.lowercased() })
        var result: [String] = []
        var round = 1
        while result.count < count {
            for base in names where result.count < count {
                let candidate = round == 1 ? base : "\(base)-\(round)"
                if !taken.contains(candidate) && !result.contains(candidate) {
                    result.append(candidate)
                }
            }
            round += 1
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AgentNamePoolTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator/AgentNamePool.swift Tests/VoidloomTests/MediatorExecutionTests.swift
git commit -m "feat(mediator): add AgentNamePool callsign assignment"
```

---

### Task 4: WorkspaceStore titled-card API

**Files:**
- Modify: `Sources/VoidloomCore/Workspace/WorkspaceStore.swift` (next to `addCard(kind:)`, `WorkspaceStore.swift:194`)
- Test: `Tests/VoidloomTests/MediatorExecutionTests.swift` (append)

**Interfaces:**
- Consumes: existing private `Self.makeCard(kind:index:)` (`WorkspaceStore.swift:1029`), `state.nonOverlappingOrigin(for:centeredAt:)`, `state.addCard(_:)`, `persist()`.
- Produces: `@discardableResult func addTitledCard(kind: CardKind, title: String, content: String = "") -> UUID` — the executor's card-creation entry point (spec finding 12: existing `addCard` variants take no title/content).

- [ ] **Step 1: Write the failing test** (append; follow the store-construction pattern at `WorkspaceModelTests.swift:168` — temp URLs, `persistenceDelay: 60`)

```swift
@MainActor
final class AddTitledCardTests: XCTestCase {
    func testAddTitledCardSetsTitleContentAndReturnsID() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WorkspaceStore(
            state: WorkspaceState(viewport: CanvasViewport(origin: .zero, scale: 1), cards: []),
            storageURL: url,
            persistenceDelay: 60
        )

        let id = store.addTitledCard(kind: .agent, title: "viper")
        let noteID = store.addTitledCard(kind: .note, content: "standup notes")

        let agent = store.state.cards.first { $0.id == id }
        XCTAssertEqual(agent?.title, "viper")
        XCTAssertEqual(agent?.kind, .agent)
        let note = store.state.cards.first { $0.id == noteID }
        XCTAssertEqual(note?.content, "standup notes")
        XCTAssertNotEqual(agent?.position, note?.position) // cascade, no stacking
    }
}
```

This construction matches `WorkspaceModelTests.swift:173` verbatim (verified on this branch).

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AddTitledCardTests`
Expected: FAIL — `value of type 'WorkspaceStore' has no member 'addTitledCard'`.

- [ ] **Step 3: Write the implementation** (place directly after `addCard(kind:)` in the Cards section)

```swift
/// Adds a card with a caller-chosen title (and optional content), placed by
/// the same count-index + cascade rules as `addCard(kind:)`. Used by the
/// mediator so named agent spawns are a single atomic, persisted add.
@discardableResult
public func addTitledCard(kind: CardKind, title: String = "", content: String = "") -> UUID {
    var card = Self.makeCard(kind: kind, index: state.cards.count)
    if !title.isEmpty { card.title = title }
    if !content.isEmpty { card.content = content }
    let center = CanvasPoint(
        x: card.position.x + card.size.width / 2,
        y: card.position.y + card.size.height / 2
    )
    card.position = state.nonOverlappingOrigin(for: card.size, centeredAt: center)
    state.addCard(card)
    persist()
    return card.id
}
```

Note: `WorkspaceCard.content` exists (`WorkspaceModels.swift:18`). If `makeCard` sets a default title, only override when `title` is non-empty (as written).

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AddTitledCardTests`
Expected: PASS. Also run `swift test --filter WorkspaceModelTests` — expected: PASS (no regressions in card placement).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Workspace/WorkspaceStore.swift Tests/VoidloomTests/MediatorExecutionTests.swift
git commit -m "feat(workspace): add addTitledCard for atomic named card creation"
```

---

### Task 5: MediatorTargetResolver

**Files:**
- Create: `Sources/VoidloomCore/Mediator/MediatorTargetResolver.swift`
- Test: `Tests/VoidloomTests/MediatorExecutionTests.swift` (append)

**Interfaces:**
- Produces: `TargetResolution` (`.match(UUID)` / `.ambiguous([String])` / `.none(suggestion: String?)`) and `MediatorTargetResolver.resolve(_:in:)`, consumed by Task 6. Candidates are `(id: UUID, name: String)` pairs — agent-card titles or workspace names; resolution is scoped by the CALLER to the active workspace (spec: target resolution rules).

- [ ] **Step 1: Write the failing tests** (append)

```swift
final class MediatorTargetResolverTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID()

    func testExactCaseInsensitiveMatchWins() {
        let r = MediatorTargetResolver.resolve("Jerry", in: [(a, "jerry"), (b, "sage")])
        XCTAssertEqual(r, .match(a))
    }

    func testDuplicateNamesAreAmbiguous() {
        let r = MediatorTargetResolver.resolve("untitled", in: [(a, "Untitled"), (b, "Untitled")])
        XCTAssertEqual(r, .ambiguous(["Untitled", "Untitled"]))
    }

    func testUniquePrefixMatches() {
        let r = MediatorTargetResolver.resolve("phoe", in: [(a, "phoenix"), (b, "sage")])
        XCTAssertEqual(r, .match(a))
    }

    func testCloseMisspellingMatchesWithinDistanceTwo() {
        // ASR often drops/mangles a character or two.
        let r = MediatorTargetResolver.resolve("jery", in: [(a, "jerry"), (b, "sage")])
        XCTAssertEqual(r, .match(a))
    }

    func testFarMissReturnsNoneWithNearestSuggestion() {
        // "jasper" is edit-distance 5 from "jerry" — far beyond the match
        // threshold, but the mediator still offers the nearest name as a
        // question rather than silently failing (spec flow example).
        let r = MediatorTargetResolver.resolve("jasper", in: [(a, "jerry")])
        XCTAssertEqual(r, TargetResolution.none(suggestion: "jerry"))
    }

    func testEmptyCandidatesReturnsNoneWithoutSuggestion() {
        let r = MediatorTargetResolver.resolve("jerry", in: [])
        XCTAssertEqual(r, TargetResolution.none(suggestion: nil))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MediatorTargetResolverTests`
Expected: FAIL — `cannot find 'MediatorTargetResolver' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/VoidloomCore/Mediator/MediatorTargetResolver.swift
import Foundation

public enum TargetResolution: Equatable, Sendable {
    case match(UUID)
    case ambiguous([String])
    case none(suggestion: String?)
}

/// Resolves a spoken/typed name against candidate (id, name) pairs.
/// Ladder: exact (case-insensitive) → unique prefix → unique small
/// misspelling (edit distance ≤ 2) → no match with nearest suggestion.
/// Never guesses on ties: duplicates are surfaced as ambiguous.
public enum MediatorTargetResolver {
    public static func resolve(
        _ spoken: String,
        in candidates: [(id: UUID, name: String)]
    ) -> TargetResolution {
        let query = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        guard !candidates.isEmpty, !query.isEmpty else { return .none(suggestion: nil) }

        let exact = candidates.filter { $0.name.lowercased() == query }
        if exact.count == 1 { return .match(exact[0].id) }
        if exact.count > 1 { return .ambiguous(exact.map(\.name)) }

        let prefixed = candidates.filter { $0.name.lowercased().hasPrefix(query) }
        if prefixed.count == 1 { return .match(prefixed[0].id) }
        if prefixed.count > 1 { return .ambiguous(prefixed.map(\.name)) }

        let scored = candidates
            .map { (candidate: $0, distance: editDistance(query, $0.name.lowercased())) }
            .sorted { $0.distance < $1.distance }
        let best = scored[0]
        if best.distance <= 2 {
            let ties = scored.filter { $0.distance == best.distance }
            if ties.count == 1 { return .match(best.candidate.id) }
            return .ambiguous(ties.map(\.candidate.name))
        }
        // Too far to auto-match, but always offer the nearest name as a
        // question — "did you mean X?" beats a dead-end for voice input.
        return .none(suggestion: best.candidate.name)
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MediatorTargetResolverTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator/MediatorTargetResolver.swift Tests/VoidloomTests/MediatorExecutionTests.swift
git commit -m "feat(mediator): add fuzzy target resolver with no-guess semantics"
```

---

### Task 6: ExecutionResult + CommandExecutor

**Files:**
- Create: `Sources/VoidloomCore/Mediator/CommandExecutor.swift`
- Modify (only if absent): `Sources/VoidloomCore/Workspace/WorkspaceStore.swift` — a `selectCard(id:)` passthrough (see Step 3 note)
- Test: `Tests/VoidloomTests/MediatorExecutionTests.swift` (append)

**Interfaces:**
- Consumes: `MediatorCommand` (Task 1), `AgentTerminalControlling` + `MockAgentTerminals` (Task 2), `AgentNamePool` (Task 3), `addTitledCard` (Task 4), `MediatorTargetResolver` (Task 5); existing store APIs verified on this branch: `deleteCard(id:)` (`WorkspaceStore.swift:101`), `setSpaceBackground(_:)` (`:394`), `setSpaceTiling(_:)` (`:399`), `switchWorkspace(id:)` (`:502`), `library.workspaces` (`[WorkspaceSummary]`, each with `.id`/`.name`), `SpaceBackground` (`.atmosphere/.solid(hex:)/.image(fileName:)`), `SpaceTiling()` default.
- Produces: `ExecutionResult` and `CommandExecutor.execute(_:confirmed:) -> ExecutionResult` — what `MediatorSession` (Task 7) and every brain plan dispatches into.

- [ ] **Step 1: Write the failing tests** (append)

```swift
@MainActor
final class CommandExecutorTests: XCTestCase {
    private func makeStore() -> WorkspaceStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return WorkspaceStore(
            state: WorkspaceState(viewport: CanvasViewport(origin: .zero, scale: 1), cards: []),
            storageURL: url,
            persistenceDelay: 60
        )
    }

    private func makeExecutor(_ store: WorkspaceStore, _ terminals: MockAgentTerminals) -> CommandExecutor {
        CommandExecutor(store: store, terminals: terminals, namePool: AgentNamePool())
    }

    func testSpawnAgentsCreatesTitledCardsAndSessions() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let result = makeExecutor(store, terminals).execute(.spawnAgents(count: 2, kind: .claudeCode, names: nil))

        let agents = store.state.cards.filter { $0.kind == .agent }
        XCTAssertEqual(agents.map(\.title), ["ember", "slate"])
        XCTAssertEqual(terminals.spawned.count, 2)
        XCTAssertEqual(result, .success(narration: "Spawned 2 claude agents: ember, slate"))
    }

    func testSpawnCountOutsideLimitsIsRefused() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let result = makeExecutor(store, terminals).execute(.spawnAgents(count: 9, kind: .claudeCode, names: nil))
        XCTAssertEqual(result, .refused(reason: "I can spawn between 1 and 8 agents at once."))
        XCTAssertTrue(store.state.cards.isEmpty)
    }

    func testSendPromptRoutesToResolvedAgentCard() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let id = store.addTitledCard(kind: .agent, title: "jerry")
        let result = makeExecutor(store, terminals).execute(.sendPrompt(target: "jery", text: "look into the API errors"))

        XCTAssertEqual(terminals.sent.first?.cardID, id)
        XCTAssertEqual(terminals.sent.first?.text, "look into the API errors")
        XCTAssertEqual(result, .success(narration: "→ jerry"))
    }

    func testSendPromptToUnknownTargetAsksForClarification() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        store.addTitledCard(kind: .agent, title: "jerry")
        let result = makeExecutor(store, terminals).execute(.sendPrompt(target: "jasper", text: "hi"))
        XCTAssertEqual(result, .needsClarification(question: "I don't see a jasper — did you mean jerry?"))
        XCTAssertTrue(terminals.sent.isEmpty)
    }

    func testCloseTerminalRequiresConfirmationThenDeletes() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let id = store.addTitledCard(kind: .agent, title: "omen")
        let executor = makeExecutor(store, terminals)

        let first = executor.execute(.closeTerminal(target: "omen"))
        XCTAssertEqual(first, .needsConfirmation(
            prompt: "Close omen and its session?",
            pending: .closeTerminal(target: "omen")
        ))
        XCTAssertTrue(store.state.cards.contains { $0.id == id })

        let second = executor.execute(.closeTerminal(target: "omen"), confirmed: true)
        XCTAssertEqual(second, .success(narration: "Closed omen"))
        XCTAssertEqual(terminals.terminated, [id])
        XCTAssertFalse(store.state.cards.contains { $0.id == id })
    }

    func testReadOutputReturnsRecentLinesInNarration() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let id = store.addTitledCard(kind: .agent, title: "viper")
        terminals.outputByCard[id] = (1...30).map { "line \($0)" }
        let result = makeExecutor(store, terminals).execute(.readOutput(target: "viper"))
        guard case .success(let narration) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertTrue(narration.contains("line 30"))
        XCTAssertFalse(narration.contains("line 5")) // clamped to last 25
    }

    func testCreateCardAndSetBackgroundAndArrange() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let executor = makeExecutor(store, terminals)

        XCTAssertEqual(
            executor.execute(.createCard(kind: .note, content: "standup notes")),
            .success(narration: "Created a note")
        )
        XCTAssertEqual(store.state.cards.first?.content, "standup notes")

        XCTAssertEqual(
            executor.execute(.setBackground(spec: .solid(hex: "#102030FF"))),
            .success(narration: "Background updated")
        )
        XCTAssertEqual(store.state.space?.background, .solid(hex: "#102030FF"))

        XCTAssertEqual(executor.execute(.arrange(style: .retile)), .success(narration: "Re-tiled the space"))
    }

    func testSwitchSpaceWithDuplicateNamesAsksForClarification() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        // Two workspaces named identically → never guess (spec finding 13).
        store.createWorkspace(named: "research")
        store.createWorkspace(named: "research")
        let result = makeExecutor(store, terminals).execute(.switchSpace(name: "research"))
        XCTAssertEqual(result, .needsClarification(
            question: "There are 2 spaces named research — rename one to switch by voice."
        ))
    }
}
```

APIs verified on this branch: `createWorkspace(named:)` (`WorkspaceStore.swift:470`), `WorkspaceState.space: SpaceConfig?` (`WorkspaceModels.swift:45`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CommandExecutorTests`
Expected: FAIL — `cannot find 'CommandExecutor' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/VoidloomCore/Mediator/CommandExecutor.swift
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
```

Note on `store.selectCard(id:)`: `WorkspaceState.selectCard(id:)` exists (used inside `addCard(kind:fromCorner:toCorner:)`, `WorkspaceStore.swift:247`). If the STORE has no public passthrough, add one next to the other selection methods:

```swift
public func selectCard(id: UUID) {
    state.selectCard(id: id)
    schedulePersistence()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CommandExecutorTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator/CommandExecutor.swift Sources/VoidloomCore/Workspace/WorkspaceStore.swift Tests/VoidloomTests/MediatorExecutionTests.swift
git commit -m "feat(mediator): add CommandExecutor with validation and no-guess routing"
```

---

### Task 7: MediatorSession state machine

**Files:**
- Create: `Sources/VoidloomCore/Mediator/MediatorSessionMachine.swift`
- Test: `Tests/VoidloomTests/MediatorSessionTests.swift` (new file)

**Interfaces:**
- Consumes: `MediatorCommand` (Task 1), `ExecutionResult` (Task 6).
- Produces: `MediatorState`, `MediatorEvent`, `MediatorEffect`, and `MediatorSessionMachine.handle(_:) -> [MediatorEffect]` — a pure reducer. Plans 2–4 wrap it in an `@MainActor` observable coordinator that performs effects (start/stop capture, run brain, run executor, schedule timeouts) and feeds results back as events; the HUD renders `state`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/VoidloomTests/MediatorSessionTests.swift
import XCTest
@testable import VoidloomCore

final class MediatorSessionTests: XCTestCase {
    func testWakeStartsCaptureAndTranscriptFlowsToParse() {
        var machine = MediatorSessionMachine()
        XCTAssertEqual(machine.handle(.wakeDetected), [.startCapture, .scheduleTimeout(seconds: 15)])
        XCTAssertEqual(machine.state, .capturing(transcript: ""))

        XCTAssertEqual(machine.handle(.transcriptDelta("ask jerry")), [])
        XCTAssertEqual(machine.state, .capturing(transcript: "ask jerry"))

        XCTAssertEqual(
            machine.handle(.transcriptFinal("ask jerry to fix the build")),
            [.stopCapture, .parse(transcript: "ask jerry to fix the build"), .scheduleTimeout(seconds: 10)]
        )
        XCTAssertEqual(machine.state, .parsing(transcript: "ask jerry to fix the build"))
    }

    func testCommandProducedExecutesAndResultNarrates() {
        var machine = MediatorSessionMachine.parsing("ask jerry to fix the build")
        let command = MediatorCommand.sendPrompt(target: "jerry", text: "fix the build")

        XCTAssertEqual(machine.handle(.commandProduced(command)), [.execute(command, confirmed: false)])
        XCTAssertEqual(machine.state, .executing(command))

        XCTAssertEqual(
            machine.handle(.executionFinished(.success(narration: "→ jerry"))),
            [.narrate("→ jerry")]
        )
        XCTAssertEqual(machine.state, .idle)
    }

    func testConfirmationFlowConfirmAndCancelAndTimeout() {
        let pending = MediatorCommand.closeTerminal(target: "omen")

        var machine = MediatorSessionMachine.executing(pending)
        XCTAssertEqual(
            machine.handle(.executionFinished(.needsConfirmation(prompt: "Close omen?", pending: pending))),
            [.scheduleTimeout(seconds: 10)]
        )
        XCTAssertEqual(machine.state, .awaitingConfirmation(prompt: "Close omen?", pending: pending))

        // confirm → re-execute confirmed, no wake word needed
        var confirmed = machine
        XCTAssertEqual(confirmed.handle(.confirmReceived(true)), [.execute(pending, confirmed: true)])
        XCTAssertEqual(confirmed.state, .executing(pending))

        // cancel → idle
        var cancelled = machine
        XCTAssertEqual(cancelled.handle(.confirmReceived(false)), [.narrate("Cancelled")])
        XCTAssertEqual(cancelled.state, .idle)

        // timeout → idle
        var timedOut = machine
        XCTAssertEqual(timedOut.handle(.timeout), [.narrate("Cancelled")])
        XCTAssertEqual(timedOut.state, .idle)
    }

    func testParseFailureNarratesRephrasePrompt() {
        var machine = MediatorSessionMachine.parsing("mumble mumble")
        XCTAssertEqual(machine.handle(.parseFailed("no valid command")),
                       [.narrate("Didn't catch that — try rephrasing.")])
        XCTAssertEqual(machine.state, .idle)
    }

    func testOverlappingTriggerRestartsCaptureButNeverInterruptsExecution() {
        // during capture: push-to-talk restarts the capture window
        var capturing = MediatorSessionMachine()
        _ = capturing.handle(.wakeDetected)
        _ = capturing.handle(.transcriptDelta("half a command"))
        XCTAssertEqual(capturing.handle(.pushToTalkPressed),
                       [.stopCapture, .startCapture, .scheduleTimeout(seconds: 15)])
        XCTAssertEqual(capturing.state, .capturing(transcript: ""))

        // during execution: triggers are ignored (single pending command)
        let command = MediatorCommand.arrange(style: .grid)
        var executing = MediatorSessionMachine.executing(command)
        XCTAssertEqual(executing.handle(.wakeDetected), [])
        XCTAssertEqual(executing.state, .executing(command))
    }

    func testCaptureTimeoutAndCancelReturnToIdle() {
        var machine = MediatorSessionMachine()
        _ = machine.handle(.wakeDetected)
        XCTAssertEqual(machine.handle(.timeout), [.stopCapture, .narrate("Didn't catch that — try rephrasing.")])
        XCTAssertEqual(machine.state, .idle)

        var cancelled = MediatorSessionMachine()
        _ = cancelled.handle(.wakeDetected)
        XCTAssertEqual(cancelled.handle(.cancelRequested), [.stopCapture])
        XCTAssertEqual(cancelled.state, .idle)
    }

    func testStaleEventsInIdleAreIgnored() {
        var machine = MediatorSessionMachine()
        XCTAssertEqual(machine.handle(.transcriptFinal("late transcript")), [])
        XCTAssertEqual(machine.handle(.timeout), [])
        XCTAssertEqual(machine.state, .idle)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MediatorSessionTests`
Expected: FAIL — `cannot find 'MediatorSessionMachine' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/VoidloomCore/Mediator/MediatorSessionMachine.swift
import Foundation

public enum MediatorState: Equatable, Sendable {
    case idle
    case capturing(transcript: String)
    case parsing(transcript: String)
    case executing(MediatorCommand)
    case awaitingConfirmation(prompt: String, pending: MediatorCommand)
}

public enum MediatorEvent: Equatable, Sendable {
    case wakeDetected
    case pushToTalkPressed
    case transcriptDelta(String)
    case transcriptFinal(String)
    case commandProduced(MediatorCommand)
    case parseFailed(String)
    case executionFinished(ExecutionResult)
    case confirmReceived(Bool)
    case timeout
    case cancelRequested
}

public enum MediatorEffect: Equatable, Sendable {
    case startCapture
    case stopCapture
    case parse(transcript: String)
    case execute(MediatorCommand, confirmed: Bool)
    case scheduleTimeout(seconds: Double)
    case narrate(String)
}

/// Pure reducer for the mediator pipeline. Owns every lifecycle rule from
/// the spec: capture windows and timeouts, single pending command,
/// confirmation without a wake word, overlapping-trigger semantics.
/// An @MainActor coordinator (Plan 2) performs effects and feeds events back.
public struct MediatorSessionMachine: Equatable, Sendable {
    public static let captureTimeout: Double = 15
    public static let confirmationTimeout: Double = 10
    public static let parseTimeout: Double = 10
    static let rephrasePrompt = "Didn't catch that — try rephrasing."

    public private(set) var state: MediatorState = .idle

    public init() {}
    /// Test/coordination conveniences for entering mid-pipeline states.
    public static func parsing(_ transcript: String) -> Self {
        var m = Self(); m.state = .parsing(transcript: transcript); return m
    }
    public static func executing(_ command: MediatorCommand) -> Self {
        var m = Self(); m.state = .executing(command); return m
    }

    public mutating func handle(_ event: MediatorEvent) -> [MediatorEffect] {
        switch (state, event) {
        case (.idle, .wakeDetected), (.idle, .pushToTalkPressed):
            state = .capturing(transcript: "")
            return [.startCapture, .scheduleTimeout(seconds: Self.captureTimeout)]

        case (.capturing, .wakeDetected), (.capturing, .pushToTalkPressed):
            state = .capturing(transcript: "")
            return [.stopCapture, .startCapture, .scheduleTimeout(seconds: Self.captureTimeout)]

        case (.capturing, .transcriptDelta(let text)):
            state = .capturing(transcript: text)
            return []

        case (.capturing, .transcriptFinal(let text)):
            state = .parsing(transcript: text)
            // The parse watchdog frees the machine if a brain call hangs.
            return [.stopCapture, .parse(transcript: text), .scheduleTimeout(seconds: Self.parseTimeout)]

        case (.capturing, .timeout):
            state = .idle
            return [.stopCapture, .narrate(Self.rephrasePrompt)]

        case (.capturing, .cancelRequested):
            state = .idle
            return [.stopCapture]

        case (.parsing, .commandProduced(let command)):
            state = .executing(command)
            return [.execute(command, confirmed: false)]

        case (.parsing, .parseFailed), (.parsing, .timeout):
            state = .idle
            return [.narrate(Self.rephrasePrompt)]

        case (.parsing, .cancelRequested):
            state = .idle
            return []

        case (.executing, .executionFinished(let result)):
            return finish(result)

        case (.awaitingConfirmation(_, let pending), .confirmReceived(true)):
            state = .executing(pending)
            return [.execute(pending, confirmed: true)]

        case (.awaitingConfirmation, .confirmReceived(false)),
             (.awaitingConfirmation, .timeout),
             (.awaitingConfirmation, .cancelRequested):
            state = .idle
            return [.narrate("Cancelled")]

        default:
            return [] // stale or irrelevant events never disturb the pipeline
        }
    }

    private mutating func finish(_ result: ExecutionResult) -> [MediatorEffect] {
        switch result {
        case .success(let narration):
            state = .idle
            return [.narrate(narration)]
        case .needsClarification(let question):
            state = .idle
            return [.narrate(question)]
        case .needsConfirmation(let prompt, let pending):
            state = .awaitingConfirmation(prompt: prompt, pending: pending)
            return [.scheduleTimeout(seconds: Self.confirmationTimeout)]
        case .refused(let reason):
            state = .idle
            return [.narrate(reason)]
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MediatorSessionTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator/MediatorSessionMachine.swift Tests/VoidloomTests/MediatorSessionTests.swift
git commit -m "feat(mediator): add MediatorSessionMachine pipeline reducer"
```

---

### Task 8: Settings cleanup + brain protocol + full verification

**Files:**
- Create: `Sources/VoidloomCore/Mediator/MediatorBrain.swift`
- Modify: `VoidloomApp/Shell/SettingsView.swift:377-390` (the "Connection" section)

**Interfaces:**
- Produces: `MediatorBrain` protocol — the seam Plan 2's `LlamaBrain` and Plan 4's `FoundationModelsBrain` implement. Removing the fake Anthropic fields is the user-visible point of this whole effort's first slice.

- [ ] **Step 1: Add the brain protocol (compile-only; implementations and their golden tests are Plan 2/4)**

```swift
// Sources/VoidloomCore/Mediator/MediatorBrain.swift
import Foundation

/// Text in, one validated command out. Implementations are schema-constrained
/// (FoundationModels tools / GBNF) so anything else is structurally impossible;
/// unparseable utterances throw and surface as `parseFailed`.
public protocol MediatorBrain: AnyObject, Sendable {
    func command(for utterance: String) async throws -> MediatorCommand
}
```

- [ ] **Step 2: Replace the Connection section in SettingsView**

In `VoidloomApp/Shell/SettingsView.swift`, replace the `Section("Connection") { … }` block (lines 377–390: the disabled `https://api.anthropic.com` endpoint field, disabled API-key field, disabled persist toggle, and caption) with:

```swift
Section("Local AI") {
    LabeledContent("Status", value: "Not yet available in this build")
    Text("Voidloom's AI runs entirely on this Mac — no endpoints, no API keys. Model setup arrives with the mediator.")
        .font(.callout)
        .foregroundStyle(.secondary)
    Toggle("Persist conversations to disk", isOn: $persistConversations)
        .disabled(true)
}
```

Delete the now-unused `@State private var apiEndpoint` / `apiKey` properties in the same view struct.

- [ ] **Step 3: Verify everything**

Run: `swift test`
Expected: PASS — full suite, including all pre-existing tests (171+ on this branch's lineage) plus the ~27 new mediator tests.

Run: `xcodebuild -scheme Voidloom -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Sources/VoidloomCore/Mediator/MediatorBrain.swift VoidloomApp/Shell/SettingsView.swift
git commit -m "feat(mediator): add MediatorBrain seam; replace Anthropic settings with Local AI"
```

---

## Follow-on plans (not in this document)

- **Plan 2 — tier-2 brain + typed input:** llama.cpp SPM dep, Qwen3-0.6B, `MediatorCommandSchema` descriptor + GBNF generation + grammar↔Codable round-trip tests, `ModelAssetManager`, `@MainActor` session coordinator performing `MediatorEffect`s, HUD with typed command input, `LocalResponseProvider` for chat, real Settings "Local AI" management.
- **Plan 3 — voice:** `AudioCaptureService`, shared KWS wake word (spike first), FluidAudio Parakeet transcriber, HUD voice states, permission flows.
- **Plan 4 — tier 1:** `FoundationModelsBrain` (@Generable mirrors + parity tests), SpeechAnalyzer transcriber, `MediatorTierResolver` full matrix, latency benchmarks vs the ≲1s bar.
