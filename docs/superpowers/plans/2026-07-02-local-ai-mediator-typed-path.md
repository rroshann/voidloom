# Local AI Mediator — Plan 2: Typed Command Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the mediator user-visible: a typed command bar (HUD) drives the full Plan-1 pipeline via a deterministic fast-path brain and a new session coordinator — "start 2 claude agents" typed into the app actually spawns named agent cards.

**Architecture:** Plan 2 of the Local AI Mediator (spec `docs/superpowers/specs/2026-07-01-local-ai-mediator-design.md`; carry-over obligations in `docs/superpowers/plans/2026-07-01-local-ai-mediator-plan2-prework.md` — read both). Everything model-shaped stays out: `FastPathBrain` is a deterministic parser (the spec's sanctioned "grammar fast-path", permanent, not throwaway), and `MediatorSessionCoordinator` performs `MediatorEffect`s around the pure machine. **Plan 2b** (llama.cpp + Qwen + `ModelAssetManager` + `LocalResponseProvider`, after a llama.cpp spike) plugs into the same seams with zero HUD/coordinator changes.

**Tech Stack:** Swift 6 SPM (`VoidloomCore` + `VoidloomTests`), SwiftUI (`VoidloomApp`), XCTest. No new dependencies.

## Global Constraints

- Platform floor `.macOS(.v14)`; Apple Silicon assumptions stay out of this plan (nothing model-shaped lands here).
- `Sources/VoidloomCore/` imports Foundation (and Combine where `WorkspaceStore` already does) — never SwiftUI, AppKit, AVFoundation, or model runtimes.
- The executor remains the only component that mutates state; brains only produce `MediatorCommand`; failure mode is always a typed result or thrown parse error — never a partial action.
- **Timer contract (prework #1):** the coordinator keeps AT MOST ONE timeout task; every `scheduleTimeout` REPLACES the previous one.
- **Sync-executor assumption (prework #2):** async brain work runs inside `.parsing` (watchdogged); `.execute` effects are performed synchronously.
- **Wire-format freeze (prework #3, decided):** `.grid` and `.retile` remain DISTINCT schema cases (expected to diverge: grid may force `.auto` tiling; re-tile re-derives the current mode). `MediatorCommandSchema` freezes the wire JSON; Plan 2b generates GBNF from it.
- Spawn does NOT explicitly re-tile (prework #4 resolved): Spaces tiling is derived from the card list, so new cards re-tile automatically; document, don't code.
- TDD for Core; UI verified by build + manual QA. Conventional Commits. One responsibility per file.
- Test commands: `swift test --filter <Class>`, full `swift test` (expect 188 green at start), app build `xcodebuild -scheme Voidloom -destination 'platform=macOS' build`.
- New `VoidloomApp` files must be registered in `Voidloom.xcodeproj/project.pbxproj` (manual A2-prefixed 24-hex-char IDs; four entries per file — see Task 5).

---

### Task 1: Prework cleanup pass

**Files:**
- Modify: `Sources/VoidloomCore/Mediator/MediatorTargetResolver.swift` (trim + visibility)
- Modify: `Sources/VoidloomCore/Mediator/AgentNamePool.swift` (blank-entry filtering)
- Modify: `Sources/VoidloomCore/Mediator/CommandExecutor.swift` (narration plural, lowercased existing set)
- Modify: `Sources/VoidloomCore/Mediator/MediatorSessionMachine.swift` (seam ctors → internal)
- Test: `Tests/VoidloomTests/MediatorExecutionTests.swift` (append + one expectation update)

**Interfaces:**
- Consumes: everything from Plan 1 as-is.
- Produces: no signature changes visible to later tasks except `MediatorSessionMachine.parsing(_:)`/`.executing(_:)` become `internal` (only tests use them, via `@testable`).

- [ ] **Step 1: Write the failing tests** (append to `MediatorExecutionTests.swift`)

```swift
final class PreworkCleanupTests: XCTestCase {
    func testWhitespaceOnlyPackFallsBackToDefaultsAndEntriesAreTrimmed() {
        XCTAssertEqual(AgentNamePool(names: ["  ", ""]).nextNames(count: 1, existing: []), ["ember"])
        XCTAssertEqual(AgentNamePool(names: [" Fox "]).nextNames(count: 1, existing: []), ["fox"])
    }

    func testResolverTrimsNewlinesFromTypedInput() {
        let id = UUID()
        let r = MediatorTargetResolver.resolve("ember\n", in: [(id, "ember")])
        XCTAssertEqual(r, .match(id))
    }
}
```

Also append to `CommandExecutorTests`:

```swift
    func testSpawnCollisionCheckIsCaseInsensitiveAgainstRenamedCards() {
        let store = makeStore(); let terminals = MockAgentTerminals()
        store.addTitledCard(kind: .agent, title: "Ember") // user renamed via UI
        let result = makeExecutor(store, terminals).execute(.spawnAgents(count: 1, kind: .claudeCode, names: ["ember"]))
        XCTAssertEqual(result, .needsClarification(question: "An agent named ember already exists — pick a different name."))
    }
```

And UPDATE one existing expectation in `testCreateAgentCardRoutesThroughSpawnMachinery` (singular noun now):

```swift
        XCTAssertEqual(result, .success(narration: "Spawned 1 claude agent: ember"))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreworkCleanupTests` and `swift test --filter CommandExecutorTests`
Expected: FAIL — trimming not applied, collision check case-sensitive, narration still plural.

- [ ] **Step 3: Implement the four cleanups**

`MediatorTargetResolver.swift`: change the query trim (line ~19) and `editDistance` visibility:

```swift
        let query = spoken.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
```
```swift
    private static func editDistance(_ a: String, _ b: String) -> Int {
```

`AgentNamePool.swift`: replace the initializer body:

```swift
    public init(names: [String] = AgentNamePool.defaultCallsigns) {
        let cleaned = names
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.names = cleaned.isEmpty ? Self.defaultCallsigns : cleaned
    }
```

`CommandExecutor.swift`, in `spawnAgents`: lowercase the existing set and pluralize correctly:

```swift
        let existing = Set(agentCards().map { $0.name.lowercased() })
```
```swift
        let noun = count == 1 ? "agent" : "agents"
        return .success(narration: "Spawned \(count) \(kind.rawValue) \(noun): \(finalNames.joined(separator: ", "))")
```

`MediatorSessionMachine.swift`: drop `public` on both seam constructors:

```swift
    /// Test/coordination conveniences for entering mid-pipeline states.
    static func parsing(_ transcript: String) -> Self {
        var m = Self(); m.state = .parsing(transcript: transcript); return m
    }
    static func executing(_ command: MediatorCommand) -> Self {
        var m = Self(); m.state = .executing(command); return m
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS — full suite (188 + 3 new = 191), including the updated narration expectation. `MediatorSessionTests` still passes (uses `@testable`, internal is enough).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator Tests/VoidloomTests/MediatorExecutionTests.swift
git commit -m "refactor(mediator): prework cleanup — trims, blank packs, case-safe collisions, narration"
```

---

### Task 2: MediatorCommandSchema (wire-format freeze)

**Files:**
- Create: `Sources/VoidloomCore/Mediator/MediatorCommandSchema.swift`
- Test: `Tests/VoidloomTests/MediatorCommandTests.swift` (append)

**Interfaces:**
- Consumes: `MediatorCommand` Codable wire shape (synthesized enum encoding, e.g. `{"sendPrompt":{"target":…,"text":…}}`; caseless nested enums encode as `{"grid":{}}`).
- Produces: `MediatorCommandSchema.cases: [Case]` (name + parameters) and `MediatorCommandSchema.samples: [String: String]` — the freeze fixtures Plan 2b's GBNF generation and tier-1 tool parity tests build on.

- [ ] **Step 1: Write the failing tests** (append to `MediatorCommandTests.swift`)

```swift
final class MediatorCommandSchemaTests: XCTestCase {
    func testSchemaFreezesTheEightCommandCasesInOrder() {
        XCTAssertEqual(
            MediatorCommandSchema.cases.map(\.name),
            ["spawnAgents", "sendPrompt", "readOutput", "closeTerminal",
             "arrange", "createCard", "switchSpace", "setBackground"]
        )
    }

    func testEverySchemaCaseHasADecodableSampleAndViceVersa() throws {
        XCTAssertEqual(
            Set(MediatorCommandSchema.cases.map(\.name)),
            Set(MediatorCommandSchema.samples.keys)
        )
        for (name, json) in MediatorCommandSchema.samples {
            let decoded = try JSONDecoder().decode(MediatorCommand.self, from: Data(json.utf8))
            let reencoded = try JSONEncoder().encode(decoded)
            let top = try XCTUnwrap(JSONSerialization.jsonObject(with: reencoded) as? [String: Any])
            XCTAssertEqual(top.keys.first, name, "wire top-level key drifted for \(name)")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MediatorCommandSchemaTests`
Expected: FAIL — `cannot find 'MediatorCommandSchema' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/VoidloomCore/Mediator/MediatorCommandSchema.swift
import Foundation

/// The frozen wire contract for `MediatorCommand`. Plan 2b generates the
/// llama.cpp GBNF grammar from `cases`, and tier-1 tool definitions are
/// parity-tested against it; `samples` are the freeze fixtures proving the
/// descriptor and Swift's synthesized Codable cannot drift apart.
/// Decision (2026-07-02): `.grid` and `.retile` stay DISTINCT wire cases —
/// identical behavior today, expected to diverge (grid may force `.auto`
/// tiling; re-tile re-derives the current mode).
public enum MediatorCommandSchema {
    public struct Parameter: Equatable, Sendable {
        public enum Kind: String, Sendable {
            case string, integer, stringArray, arrangeStyle, cardKind, backgroundSpec
        }
        public let name: String
        public let kind: Kind
        public let required: Bool

        public init(name: String, kind: Kind, required: Bool) {
            self.name = name; self.kind = kind; self.required = required
        }
    }

    public struct Case: Equatable, Sendable {
        public let name: String
        public let parameters: [Parameter]

        public init(name: String, parameters: [Parameter]) {
            self.name = name; self.parameters = parameters
        }
    }

    public static let cases: [Case] = [
        Case(name: "spawnAgents", parameters: [
            Parameter(name: "count", kind: .integer, required: true),
            Parameter(name: "kind", kind: .string, required: true),
            Parameter(name: "names", kind: .stringArray, required: false),
        ]),
        Case(name: "sendPrompt", parameters: [
            Parameter(name: "target", kind: .string, required: true),
            Parameter(name: "text", kind: .string, required: true),
        ]),
        Case(name: "readOutput", parameters: [
            Parameter(name: "target", kind: .string, required: true),
        ]),
        Case(name: "closeTerminal", parameters: [
            Parameter(name: "target", kind: .string, required: true),
        ]),
        Case(name: "arrange", parameters: [
            Parameter(name: "style", kind: .arrangeStyle, required: true),
        ]),
        Case(name: "createCard", parameters: [
            Parameter(name: "kind", kind: .cardKind, required: true),
            Parameter(name: "content", kind: .string, required: false),
        ]),
        Case(name: "switchSpace", parameters: [
            Parameter(name: "name", kind: .string, required: true),
        ]),
        Case(name: "setBackground", parameters: [
            Parameter(name: "spec", kind: .backgroundSpec, required: true),
        ]),
    ]

    /// One canonical wire sample per case. Every sample must decode into
    /// `MediatorCommand` and re-encode under the same top-level key (tested).
    public static let samples: [String: String] = [
        "spawnAgents": #"{"spawnAgents":{"count":2,"kind":"claude","names":["ember","slate"]}}"#,
        "sendPrompt": #"{"sendPrompt":{"target":"ember","text":"fix the build"}}"#,
        "readOutput": #"{"readOutput":{"target":"ember"}}"#,
        "closeTerminal": #"{"closeTerminal":{"target":"ember"}}"#,
        "arrange": #"{"arrange":{"style":{"focus":{"target":"ember"}}}}"#,
        "createCard": #"{"createCard":{"kind":"note","content":"standup"}}"#,
        "switchSpace": #"{"switchSpace":{"name":"research"}}"#,
        "setBackground": ##"{"setBackground":{"spec":{"solid":{"hex":"#102030FF"}}}}"##,
    ]
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MediatorCommandSchemaTests` then `swift test --filter MediatorCommandTests`
Expected: PASS (2 new + 2 existing).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator/MediatorCommandSchema.swift Tests/VoidloomTests/MediatorCommandTests.swift
git commit -m "feat(mediator): freeze wire format in MediatorCommandSchema"
```

---

### Task 3: FastPathBrain (deterministic parser)

**Files:**
- Create: `Sources/VoidloomCore/Mediator/FastPathBrain.swift`
- Test: `Tests/VoidloomTests/FastPathBrainTests.swift` (new file)

**Interfaces:**
- Consumes: `MediatorBrain` protocol (`func command(for utterance: String) async throws -> MediatorCommand`), `MediatorCommand` + support enums.
- Produces: `FastPathBrain` (class, `MediatorBrain`) and `BrainError.unparseable(String)` — Task 4's coordinator takes any `MediatorBrain`; Plan 2b's `LlamaBrain` will sit behind this fast path.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/VoidloomTests/FastPathBrainTests.swift
import XCTest
@testable import VoidloomCore

final class FastPathBrainTests: XCTestCase {
    private func parse(_ utterance: String) async throws -> MediatorCommand {
        try await FastPathBrain().command(for: utterance)
    }

    func testSpawnPhrasings() async throws {
        let a = try await parse("start 4 claude agents")
        XCTAssertEqual(a, .spawnAgents(count: 4, kind: .claudeCode, names: nil))
        let b = try await parse("spawn two shell terminals named fox and owl")
        XCTAssertEqual(b, .spawnAgents(count: 2, kind: .shell, names: ["fox", "owl"]))
        let c = try await parse("open a claude agent")
        XCTAssertEqual(c, .spawnAgents(count: 1, kind: .claudeCode, names: nil))
    }

    func testPromptRoutingPhrasings() async throws {
        let a = try await parse("ask ember to look into the api errors")
        XCTAssertEqual(a, .sendPrompt(target: "ember", text: "look into the api errors"))
        let b = try await parse("tell slate run the tests")
        XCTAssertEqual(b, .sendPrompt(target: "slate", text: "run the tests"))
    }

    func testReadCloseAndFocus() async throws {
        let read = try await parse("show ember's output")
        XCTAssertEqual(read, .readOutput(target: "ember"))
        let close = try await parse("close ember")
        XCTAssertEqual(close, .closeTerminal(target: "ember"))
        let focus = try await parse("focus on slate")
        XCTAssertEqual(focus, .arrange(style: .focus(target: "slate")))
    }

    func testArrangeSwitchBackgroundAndCards() async throws {
        let retile = try await parse("re-tile")
        XCTAssertEqual(retile, .arrange(style: .retile))
        let grid = try await parse("arrange in a grid")
        XCTAssertEqual(grid, .arrange(style: .grid))
        let sw = try await parse("switch to research")
        XCTAssertEqual(sw, .switchSpace(name: "research"))
        let solid = try await parse("background #102030FF")
        XCTAssertEqual(solid, .setBackground(spec: .solid(hex: "#102030FF")))
        let atmo = try await parse("background atmosphere")
        XCTAssertEqual(atmo, .setBackground(spec: .atmosphere))
        let note = try await parse("note: buy milk")
        XCTAssertEqual(note, .createCard(kind: .note, content: "buy milk"))
        let todo = try await parse("todo")
        XCTAssertEqual(todo, .createCard(kind: .todo, content: nil))
    }

    func testUnparseableUtterancesThrow() async {
        for bad in ["", "do the thing", "spawn zero agents", "ask", "switch"] {
            do {
                _ = try await parse(bad)
                XCTFail("expected unparseable for: \(bad)")
            } catch let error as BrainError {
                if case .unparseable = error { continue }
                XCTFail("wrong error for: \(bad)")
            } catch {
                XCTFail("unexpected error type for: \(bad)")
            }
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FastPathBrainTests`
Expected: FAIL — `cannot find 'FastPathBrain' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/VoidloomCore/Mediator/FastPathBrain.swift
import Foundation

public enum BrainError: Error, Equatable {
    case unparseable(String)
}

/// Deterministic command parser — the instant, zero-model fast path the spec
/// reserves in front of the LLM brains, and the only brain in the typed-input
/// build. Grammar is intentionally narrow: on any doubt it throws and the HUD
/// asks to rephrase, per the no-guess rule. Word order: verb first.
public final class FastPathBrain: MediatorBrain {
    public init() {}

    public func command(for utterance: String) async throws -> MediatorCommand {
        guard let command = Self.parse(utterance) else {
            throw BrainError.unparseable(utterance)
        }
        return command
    }

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4,
        "five": 5, "six": 6, "seven": 7, "eight": 8,
    ]

    static func parse(_ utterance: String) -> MediatorCommand? {
        let text = utterance.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = text.split(separator: " ").map(String.init)
        guard let rawHead = words.first else { return nil }
        // "note: buy milk" tokenizes with the colon attached to the verb.
        let head = rawHead.hasSuffix(":") ? String(rawHead.dropLast()) : rawHead

        switch head {
        case "spawn", "start", "open", "launch":
            return parseSpawn(Array(words.dropFirst()))
        case "ask", "tell", "prompt":
            return parseSendPrompt(Array(words.dropFirst()))
        case "read", "show":
            guard words.count >= 2 else { return nil }
            return .readOutput(target: strippedName(words[1]))
        case "close", "kill", "terminate":
            guard words.count >= 2 else { return nil }
            return .closeTerminal(target: strippedName(words[1]))
        case "focus":
            let rest = words.dropFirst().filter { $0 != "on" }
            guard let name = rest.first else { return nil }
            return .arrange(style: .focus(target: strippedName(name)))
        case "retile", "re-tile", "tile":
            return .arrange(style: .retile)
        case "grid":
            return .arrange(style: .grid)
        case "arrange":
            return text.contains("grid") ? .arrange(style: .grid) : .arrange(style: .retile)
        case "switch", "go":
            let rest = words.dropFirst().filter { $0 != "to" }
            guard !rest.isEmpty else { return nil }
            return .switchSpace(name: rest.joined(separator: " "))
        case "background":
            return parseBackground(Array(words.dropFirst()))
        case "note", "todo", "browser":
            let kind: CardKind = head == "note" ? .note : (head == "todo" ? .todo : .browser)
            let content = text.dropFirst(head.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            return .createCard(kind: kind, content: content.isEmpty ? nil : content)
        default:
            return nil
        }
    }

    private static func parseSpawn(_ words: [String]) -> MediatorCommand? {
        guard let first = words.first else { return nil }
        let count = Int(first) ?? numberWords[first] ?? 0
        guard count > 0 else { return nil }
        let kind: MediatorAgentKind = words.contains("shell") ? .shell : .claudeCode
        var names: [String]? = nil
        if let namedIdx = words.firstIndex(where: { $0 == "named" || $0 == "called" }) {
            let raw = words[(namedIdx + 1)...]
                .flatMap { $0.split(separator: ",").map(String.init) }
                .filter { $0 != "and" && !$0.isEmpty }
            if !raw.isEmpty { names = raw }
        }
        return .spawnAgents(count: count, kind: kind, names: names)
    }

    private static func parseSendPrompt(_ words: [String]) -> MediatorCommand? {
        guard words.count >= 2 else { return nil }
        let target = strippedName(words[0])
        var rest = Array(words.dropFirst())
        if rest.first == "to" { rest.removeFirst() }
        guard !rest.isEmpty else { return nil }
        return .sendPrompt(target: target, text: rest.joined(separator: " "))
    }

    private static func parseBackground(_ words: [String]) -> MediatorCommand? {
        if let hex = words.first(where: { $0.hasPrefix("#") }) {
            return .setBackground(spec: .solid(hex: hex.uppercased()))
        }
        if words.contains("atmosphere") {
            return .setBackground(spec: .atmosphere)
        }
        return nil
    }

    private static func strippedName(_ word: String) -> String {
        var name = word
        if name.hasSuffix("'s") { name.removeLast(2) }
        return name.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FastPathBrainTests`
Expected: PASS (5 tests). Note the hex test: `"background #102030ff"` is lowercased by `parse`, then `.uppercased()` restores `#102030FF` — matching the test's expectation.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator/FastPathBrain.swift Tests/VoidloomTests/FastPathBrainTests.swift
git commit -m "feat(mediator): add FastPathBrain deterministic parser"
```

---

### Task 4: MediatorSessionCoordinator

**Files:**
- Create: `Sources/VoidloomCore/Mediator/MediatorSessionCoordinator.swift`
- Test: `Tests/VoidloomTests/MediatorCoordinatorTests.swift` (new file)

**Interfaces:**
- Consumes: `MediatorSessionMachine` (`handle(_:) -> [MediatorEffect]`, `state`), `MediatorBrain`, `CommandExecutor.execute(_:confirmed:) -> ExecutionResult`.
- Produces: `MediatorSessionCoordinator` — `@MainActor ObservableObject` with `@Published state: MediatorState`, `@Published narration: String`, `init(brain:executor:timeoutScale:)`, `submitTyped(_:)`, `confirm(_:)`, `cancel()`. Task 5's HUD observes exactly this.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/VoidloomTests/MediatorCoordinatorTests.swift
import XCTest
@testable import VoidloomCore

@MainActor
final class MediatorCoordinatorTests: XCTestCase {
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

    private func makeCoordinator(_ store: WorkspaceStore, _ terminals: MockAgentTerminals,
                                 timeoutScale: Double = 1) -> MediatorSessionCoordinator {
        MediatorSessionCoordinator(
            brain: FastPathBrain(),
            executor: CommandExecutor(store: store, terminals: terminals, namePool: AgentNamePool()),
            timeoutScale: timeoutScale
        )
    }

    private func waitForIdle(_ c: MediatorSessionCoordinator) async {
        for _ in 0..<2000 {
            if c.state == .idle, !c.narration.isEmpty { return }
            await Task.yield()
        }
    }

    func testTypedSpawnFlowsThroughBrainExecutorAndNarrates() async {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let c = makeCoordinator(store, terminals)

        c.submitTyped("start 2 claude agents")
        await waitForIdle(c)

        XCTAssertEqual(store.state.cards.filter { $0.kind == .agent }.count, 2)
        XCTAssertEqual(terminals.spawned.count, 2)
        XCTAssertEqual(c.narration, "Spawned 2 claude agents: ember, slate")
        XCTAssertEqual(c.state, .idle)
    }

    func testUnparseableTypedInputNarratesRephrase() async {
        let c = makeCoordinator(makeStore(), MockAgentTerminals())
        c.submitTyped("do the thing")
        await waitForIdle(c)
        XCTAssertEqual(c.narration, "Didn't catch that — try rephrasing.")
    }

    func testDestructiveCommandAwaitsThenExecutesTypedConfirmation() async {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let c = makeCoordinator(store, terminals)
        let id = store.addTitledCard(kind: .agent, title: "ember")

        c.submitTyped("close ember")
        for _ in 0..<2000 {
            if case .awaitingConfirmation = c.state { break }
            await Task.yield()
        }
        guard case .awaitingConfirmation = c.state else {
            return XCTFail("expected awaitingConfirmation, got \(c.state)")
        }
        XCTAssertTrue(store.state.cards.contains { $0.id == id })

        c.submitTyped("confirm")
        await waitForIdle(c)
        XCTAssertEqual(terminals.terminated, [id])
        XCTAssertFalse(store.state.cards.contains { $0.id == id })
        XCTAssertEqual(c.narration, "Closed ember")
    }

    func testConfirmationTimesOutViaSingleReplaceableTimer() async {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let c = makeCoordinator(store, terminals, timeoutScale: 0.01) // 10s -> 100ms; generous enough that the parse watchdog can't race the instant brain
        store.addTitledCard(kind: .agent, title: "ember")

        c.submitTyped("close ember")
        for _ in 0..<4000 {
            if c.state == .idle, c.narration == "Cancelled" { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.narration, "Cancelled")
        XCTAssertTrue(terminals.terminated.isEmpty) // never executed
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MediatorCoordinatorTests`
Expected: FAIL — `cannot find 'MediatorSessionCoordinator' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// Sources/VoidloomCore/Mediator/MediatorSessionCoordinator.swift
import Combine
import Foundation

/// Performs `MediatorEffect`s around the pure `MediatorSessionMachine`:
/// runs the brain, dispatches the executor synchronously, and keeps AT MOST
/// ONE timeout task — every `scheduleTimeout` REPLACES the previous timer
/// (the machine's effects assume this; independent timers would misfire
/// across states). Capture effects are no-ops until the voice plan lands.
@MainActor
public final class MediatorSessionCoordinator: ObservableObject {
    @Published public private(set) var state: MediatorState = .idle
    @Published public private(set) var narration: String = ""

    private var machine = MediatorSessionMachine()
    private let brain: MediatorBrain
    private let executor: CommandExecutor
    private let timeoutScale: Double
    private var timeoutTask: Task<Void, Never>?
    private var parseTask: Task<Void, Never>?

    public init(brain: MediatorBrain, executor: CommandExecutor, timeoutScale: Double = 1) {
        self.brain = brain
        self.executor = executor
        self.timeoutScale = timeoutScale
    }

    /// Typed input: drives the machine through capture instantly. While a
    /// confirmation is pending, "confirm"/"yes"/"cancel"/"no" resolve it.
    public func submitTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if case .awaitingConfirmation = machine.state {
            let word = trimmed.lowercased()
            if ["confirm", "yes", "cancel", "no"].contains(word) {
                send(.confirmReceived(word == "confirm" || word == "yes"))
                return
            }
        }
        send(.pushToTalkPressed)
        send(.transcriptFinal(trimmed))
    }

    public func confirm(_ accepted: Bool) { send(.confirmReceived(accepted)) }
    public func cancel() { send(.cancelRequested) }

    private func send(_ event: MediatorEvent) {
        let effects = machine.handle(event)
        state = machine.state
        for effect in effects { perform(effect) }
    }

    private func perform(_ effect: MediatorEffect) {
        switch effect {
        case .startCapture, .stopCapture:
            break // audio capture arrives with the voice plan

        case .parse(let transcript):
            parseTask?.cancel()
            parseTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let command = try await self.brain.command(for: transcript)
                    guard !Task.isCancelled else { return }
                    self.send(.commandProduced(command))
                } catch {
                    guard !Task.isCancelled else { return }
                    self.send(.parseFailed(String(describing: error)))
                }
            }

        case .execute(let command, let confirmed):
            send(.executionFinished(executor.execute(command, confirmed: confirmed)))

        case .scheduleTimeout(let seconds):
            timeoutTask?.cancel()
            let delay = UInt64(seconds * timeoutScale * 1_000_000_000)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                self?.send(.timeout)
            }

        case .narrate(let text):
            timeoutTask?.cancel()
            narration = text
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MediatorCoordinatorTests` then full `swift test`
Expected: PASS (4 new; full suite green).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator/MediatorSessionCoordinator.swift Tests/VoidloomTests/MediatorCoordinatorTests.swift
git commit -m "feat(mediator): add session coordinator with single replaceable timer"
```

---

### Task 5: Mediator HUD + app wiring

**Files:**
- Create: `VoidloomApp/Shell/MediatorHUDView.swift`
- Modify: `VoidloomApp/Shell/RootView.swift` (add coordinator + overlay)
- Modify: `VoidloomApp/Shell/SettingsView.swift` (Local AI status line)
- Modify: `Voidloom.xcodeproj/project.pbxproj` (register the new file)

**Interfaces:**
- Consumes: `MediatorSessionCoordinator` (Task 4), `FastPathBrain` (Task 3), `CommandExecutor`/`AgentNamePool` (Plan 1), `AgentSessionManager: AgentTerminalControlling` (Plan 1). `RootView` currently declares four `@ObservedObject` properties and uses the memberwise initializer (`RootView.swift:8-13`); `RootThemeHost` in `VoidloomApp/App/VoidloomApp.swift:71-76` calls it.
- Produces: the user-visible typed mediator. UI verified by build + manual QA (no unit tests, per project convention).

- [ ] **Step 1: Create the HUD view**

```swift
// VoidloomApp/Shell/MediatorHUDView.swift
import SwiftUI
import VoidloomCore

/// Bottom-center mediator pill: typed command input, live pipeline state,
/// result narration, and confirm/cancel for destructive commands. Voice
/// states light up when the voice plan lands — same coordinator, same view.
struct MediatorHUDView: View {
    @ObservedObject var mediator: MediatorSessionCoordinator
    @State private var input = ""

    var body: some View {
        VStack(spacing: 8) {
            if !mediator.narration.isEmpty {
                Text(mediator.narration)
                    .font(.callout)
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            if case .awaitingConfirmation(let prompt, _) = mediator.state {
                HStack(spacing: 10) {
                    Text(prompt).font(.callout)
                    Button("Confirm") { mediator.confirm(true) }
                        .keyboardShortcut(.defaultAction)
                    Button("Cancel") { mediator.confirm(false) }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 8) {
                Image(systemName: stateIcon)
                    .foregroundStyle(.secondary)
                TextField("Ask the mediator — try \"start 2 claude agents\"", text: $input)
                    .textFieldStyle(.plain)
                    .onSubmit(submit)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 420)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var stateIcon: String {
        switch mediator.state {
        case .idle: "waveform"
        case .capturing: "dot.radiowaves.left.and.right"
        case .parsing: "brain"
        case .executing: "gearshape"
        case .awaitingConfirmation: "questionmark.circle"
        }
    }

    private func submit() {
        mediator.submitTyped(input)
        input = ""
    }
}
```

- [ ] **Step 2: Wire the coordinator into RootView**

In `VoidloomApp/Shell/RootView.swift`, add a `@StateObject` and an explicit initializer (the memberwise one disappears), and mount the HUD as an overlay on the existing `ZStack`:

```swift
struct RootView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sessionManager: AgentSessionManager
    @ObservedObject var conversationStore: ConversationStore
    @ObservedObject var interaction: CanvasInteractionModel
    @StateObject private var mediator: MediatorSessionCoordinator

    @AppStorage("app.mode") private var appMode: AppMode = .canvas

    init(store: WorkspaceStore,
         sessionManager: AgentSessionManager,
         conversationStore: ConversationStore,
         interaction: CanvasInteractionModel) {
        self.store = store
        self.sessionManager = sessionManager
        self.conversationStore = conversationStore
        self.interaction = interaction
        _mediator = StateObject(wrappedValue: MediatorSessionCoordinator(
            brain: FastPathBrain(),
            executor: CommandExecutor(store: store, terminals: sessionManager, namePool: AgentNamePool())
        ))
    }
```

(`store` and `sessionManager` are app-lifetime `@StateObject`s in `VoidloomApp`, so capturing them in the `StateObject` autoclosure is safe.)

Then append to the `ZStack`'s modifiers, after `.animation(...)`:

```swift
        .overlay(alignment: .bottom) {
            MediatorHUDView(mediator: mediator)
                .padding(.bottom, 84)
        }
```

(84pt keeps the pill above the bottom ToolDock in both shells.)

- [ ] **Step 3: Update the Settings status line**

In `VoidloomApp/Shell/SettingsView.swift`, in the `Section("Local AI")` added by Plan 1, change:

```swift
    LabeledContent("Status", value: "Typed commands — instant local parser")
```

(replacing `"Not yet available in this build"`).

- [ ] **Step 4: Register MediatorHUDView.swift in the Xcode project**

`Voidloom.xcodeproj/project.pbxproj` uses manual registration — four entries per file, mirroring `CommandBar.swift` (found at pbxproj lines ~20, ~80, ~192, ~307). First `grep A2000000000000000000009 Voidloom.xcodeproj/project.pbxproj` (and any candidate ID) to confirm uniqueness, then add, using two new unique 24-hex-char IDs (suggested: `A200000000000000000000A7` for the build file, `A200000000000000000000B7` for the file reference):

1. In the `PBXBuildFile` section (next to the CommandBar entry):
```
		A200000000000000000000A7 /* MediatorHUDView.swift in Sources */ = {isa = PBXBuildFile; fileRef = A200000000000000000000B7 /* MediatorHUDView.swift */; };
```
2. In the `PBXFileReference` section:
```
		A200000000000000000000B7 /* MediatorHUDView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Shell/MediatorHUDView.swift; sourceTree = "<group>"; };
```
3. In the group children list containing `CommandBar.swift` (~line 192):
```
				A200000000000000000000B7 /* MediatorHUDView.swift */,
```
4. In the `PBXSourcesBuildPhase` files list containing `CommandBar.swift in Sources` (~line 307):
```
				A200000000000000000000A7 /* MediatorHUDView.swift in Sources */,
```

- [ ] **Step 5: Verify**

Run: `swift test`
Expected: full suite green (Core untouched by this task beyond usage).

Run: `xcodebuild -scheme Voidloom -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add VoidloomApp/Shell/MediatorHUDView.swift VoidloomApp/Shell/RootView.swift VoidloomApp/Shell/SettingsView.swift Voidloom.xcodeproj/project.pbxproj
git commit -m "feat(mediator): typed-input HUD wired to session coordinator"
```

---

## Manual QA script (post-plan, user-run — launch the freshly built .app, not a stale binary)

1. Type "start 2 claude agents" → two agent cards named ember and slate appear (auto-tiled in Spaces mode); narration confirms.
2. "ask ember to echo hello" → ember's card shows the echoed input (stub sessions).
3. "close ember" → confirmation appears; Return confirms; card disappears.
4. "do the thing" → "Didn't catch that — try rephrasing."
5. "switch to <other workspace name>" → workspace switches; misspell it → "did you mean …?".
6. Settings → AI shows "Typed commands — instant local parser".

## Follow-on (Plan 2b — not in this document)

llama.cpp spike (SPM integration, GBNF from `MediatorCommandSchema`, Qwen3-0.6B eval) → `LlamaBrain` behind `FastPathBrain` fallback → `ModelAssetManager` downloads → `LocalResponseProvider` for chat cards → Settings model management. Then Plan 3 (voice) and Plan 4 (Apple tier) per the spec.
