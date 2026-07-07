# Local AI Mediator — Plan 2b: The Real Local LLM Brain

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the typed-only build with a real, fully-local tier-2 brain. A vendored `llama.xcframework` runs Qwen3-0.6B under a GBNF grammar generated from `MediatorCommandSchema`; `LlamaBrain` sits **behind** the deterministic `FastPathBrain` (fast path first, LLM only for utterances the fast path can't parse). A `ModelAssetManager` downloads and verifies model assets on first use. Chat cards optionally gain a real local responder backed by a **separate, larger** Qwen3-1.7B model — never the 0.6B command model. No cloud endpoints, no API keys, anywhere.

**Architecture:** Plan 2b of the Local AI Mediator (spec `docs/superpowers/specs/2026-07-01-local-ai-mediator-design.md`; carry-over obligations in `docs/superpowers/plans/2026-07-01-local-ai-mediator-plan2-prework.md` — the "Plan 2b carry-overs" section is binding). Builds directly on the verified llama.cpp spike (`.omc/research/spike-llama.md`, `.omc/handoffs/spike-llama.md`): vendored xcframework (upstream SPM `Package.swift` is gone), hand-written GBNF proven for all 8 cases, warm dispatch 0.15–0.26 s, and a **mandatory** `n_ctx` cap (default 40960 → ~4.9 GB RSS; capped ~2 k → ~0.3–0.7 GB). The 0.6B model is proven **not** chat-quality (it called a PTY "Public Trust").

**Tech Stack:** Swift 6 SPM (`VoidloomCore`, new `VoidloomAI`, `VoidloomTests`), SwiftUI (`VoidloomApp`), a vendored `llama.xcframework` (Metal), XCTest. Chat/command inference isolated behind protocols.

---

## Global Constraints

Carried verbatim from the spec, the prework carry-overs, and the team-lead adjudications. These bind every task.

- **Platform / hardware:** floor `.macOS(.v14)`; AI features assume Apple Silicon. `VoidloomAI` may import Foundation, Combine, CryptoKit — **never** SwiftUI, AppKit, or AVFoundation. `VoidloomCore` stays pure logic (Foundation/Combine only), **no llama dependency ever**.
- **Core package must NOT gain a hard llama dependency.** The SPM `Package.swift` (`VoidloomCore` + `VoidloomAI` + `VoidloomTests`) stays **llama-free** so `swift test` runs fully headless with no xcframework and no model files present. The llama C interop (`Cllama` module map + `CllamaEngine`) lives **only in the Xcode app target**, linking the vendored `llama.xcframework`. `VoidloomAI` talks to it through a pure-Swift `LlamaEngine` protocol — injected, faked in tests. (Rationale: an SPM `.binaryTarget` with a local, gitignored path fails package resolution when the artifact is absent, which would break headless Core tests. Keeping llama in the app target only is the sole layout that satisfies both "vendored xcframework" and "202 Core tests stay green headlessly." Documented here per the team-lead's "document whatever module layout you choose and why.")
- **Brain layering:** `FastPathBrain` runs first. On `BrainError.unparseable`, and only then, fall back to `LlamaBrain` (grammar-constrained). One combined `TieredBrain: MediatorBrain` composes them (pure, in Core — it depends only on the `MediatorBrain` protocol). The failure mode is always a typed result or thrown parse error — never a partial or invented action.
- **n_ctx cap is mandatory** (spike risk #2). `CllamaEngine` caps context at `LlamaEngine.Config.contextLength` (default **2048**). Never use the model's default `n_ctx`.
- **Brain resident, loaded once** (spike risk #6). Cold Metal load ≈ 0.66 s. Load the model once at brain init and hold it; never reload per utterance.
- **Grammar ≠ semantics** (spike risk #4). GBNF guarantees the JSON decodes into `MediatorCommand`; it does not guarantee correct field extraction. Keep `MediatorTargetResolver` validation in front of execution and use lowercase, realistic few-shot examples in the system prompt.
- **Wire-format freeze:** `MediatorCommandSchema` is the frozen wire contract; the GBNF generator emits FROM `MediatorCommandSchema.cases`. `.grid` and `.retile` stay distinct cases. Confirm nil optional-field encoding (`spawnAgents.names`, `createCard.content`) against `MediatorCommandSchema.samples` in a parity test (spike risk #5).
- **Chat (`LocalResponseProvider`):** the 0.6B command model is **banned** from chat. `LocalResponseProvider: ResponseProvider` points at an **optional, separately-downloaded** Qwen3-1.7B GGUF (same unsloth family). Without it, chat stays on `StubResponseProvider` with a clear Settings explanation. Mediator command parsing never depends on the chat model. Mediator preempts chat (spec concurrency policy): an in-flight chat generation is cancelled and marked failed with retry via `ConversationReducer.failing`/`resettingToPending`.
- **ModelAssetManager:** manifest with pinned URLs + SHA256 + per-asset license string; resumable `URLSession` downloads into `Application Support/Voidloom/Models/`; states `missing / downloading(progress) / verifying / ready / failed`. Testable with a `file://` fixture. Qwen license: Apache-2.0.
- **Carry-overs (prework "Plan 2b carry-overs"), each a task or explicit step:** (1) cancel-during-parsing cancels watchdog + brain task; (2) busy affordance for typed input during parsing/executing; (3) `parseFailed` payload surfaced distinctly ("model not downloaded" vs generic rephrase); (4) `.agentKind` `Parameter.Kind` in schema; (5) FastPathBrain "shell"-name kind-flip fix; (6) Settings "Local AI" real model management. (Prework #6, the `WorkspaceStore` placement-block fold, stays parked — not touched here.)
- **Verification is headless-runnable.** Everything pure is unit-tested via `swift test` (expect **202 green at start**). Real `LlamaBrain` inference is an Xcode integration test target + a `scripts/` latency benchmark, both **gated on the model file existing locally** (skip-with-message otherwise). App build via `xcodebuild -scheme Voidloom -destination 'platform=macOS' build` must stay green.
- TDD for Core/VoidloomAI; UI verified by build + manual QA. Conventional Commits. One responsibility per file. New `VoidloomApp` files register in `Voidloom.xcodeproj/project.pbxproj` (manual `A2…`-prefixed 24-hex IDs; four entries per file — see the typed-path plan's Task 5 and Task 9 below).

### Pinned artifacts (from the spike — do not re-derive the 0.6B values)

| Artifact | Value |
|---|---|
| llama.cpp release tag | `b9850` (commit `4f31eedb0`), ggml 0.15.3 — proven to link + run in the spike |
| Command model repo | `unsloth/Qwen3-0.6B-GGUF` |
| Command model revision | `50968a4468ef4233ed78cd7c3de230dd1d61a56b` |
| Command model file | `Qwen3-0.6B-Q4_K_M.gguf` (396,705,472 bytes) |
| Command model SHA256 | `ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a` |
| Chat model repo (Task 8) | `unsloth/Qwen3-1.7B-GGUF` @ revision `d7f544eead698dbd1f15126ef60b45a1e1933222`, file `Qwen3-1.7B-Q4_K_M.gguf` (1,107,409,472 bytes), SHA256 `b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897`, license Apache-2.0 — **verified live against Hugging Face's tree API while writing this plan** (2026-07-02; raw JSON via `curl`, not the summarized/paraphrased form, since a wrong pinned hash is a correctness/security failure) |

---

### Task 1: Schema `.agentKind` precision + FastPathBrain "shell"-name fix (carry-overs #4, #5)

Two small, independent Core fixes that freeze the wire contract before the grammar generator reads it. **Suggested tier: sonnet.**

**Files:**
- Modify: `Sources/VoidloomCore/Mediator/MediatorCommandSchema.swift` (add `.agentKind`, retype `spawnAgents.kind`)
- Modify: `Sources/VoidloomCore/Mediator/FastPathBrain.swift` (kind detection no longer flips on an agent literally named "shell")
- Test: `Tests/VoidloomTests/MediatorCommandTests.swift`, `Tests/VoidloomTests/FastPathBrainTests.swift` (append)

**Interfaces:**
- Consumes: `MediatorCommandSchema.Parameter.Kind`, `MediatorAgentKind`, `MediatorCommand`.
- Produces: `Parameter.Kind.agentKind`; `spawnAgents.kind` typed `.agentKind`. Task 3's GBNF generator branches on `.agentKind` to constrain kind to `{claude, shell}`.

- [ ] **Step 1: Write the failing tests**

Append to `MediatorCommandTests.swift`:

```swift
final class SchemaAgentKindTests: XCTestCase {
    func testSpawnKindParameterIsConstrainedToAgentKind() {
        let spawn = MediatorCommandSchema.cases.first { $0.name == "spawnAgents" }
        let kind = spawn?.parameters.first { $0.name == "kind" }
        XCTAssertEqual(kind?.kind, .agentKind)
    }

    func testAgentKindEnumerationMatchesMediatorAgentKind() {
        XCTAssertEqual(
            MediatorCommandSchema.agentKindValues,
            MediatorAgentKind.allCases.map(\.rawValue)
        )
        XCTAssertEqual(MediatorCommandSchema.agentKindValues, ["claude", "shell"])
    }
}
```

Append to `FastPathBrainTests.swift`:

```swift
    func testAgentLiterallyNamedShellStaysClaudeKind() async throws {
        // "shell" as a NAME must not flip the process kind (carry-over #5).
        let a = try await FastPathBrain().command(for: "spawn a claude agent named shell")
        XCTAssertEqual(a, .spawnAgents(count: 1, kind: .claudeCode, names: ["shell"]))
        // "shell" as the KIND word still selects a shell terminal.
        let b = try await FastPathBrain().command(for: "spawn 2 shell terminals")
        XCTAssertEqual(b, .spawnAgents(count: 2, kind: .shell, names: nil))
        // Explicit shell kind AND a shell name together: kind shell, name preserved.
        let c = try await FastPathBrain().command(for: "spawn a shell named shell")
        XCTAssertEqual(c, .spawnAgents(count: 1, kind: .shell, names: ["shell"]))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SchemaAgentKindTests` and `swift test --filter FastPathBrainTests`
Expected: FAIL — no `.agentKind`/`agentKindValues`; the "named shell" case currently returns `.shell` kind.

- [ ] **Step 3: Implement**

In `MediatorCommandSchema.swift`, extend `Parameter.Kind`, retype `spawnAgents.kind`, and expose the value list:

```swift
        public enum Kind: String, Sendable {
            case string, integer, stringArray, agentKind, arrangeStyle, cardKind, backgroundSpec
        }
```
```swift
        Case(name: "spawnAgents", parameters: [
            Parameter(name: "count", kind: .integer, required: true),
            Parameter(name: "kind", kind: .agentKind, required: true),
            Parameter(name: "names", kind: .stringArray, required: false),
        ]),
```

Add, after `samples` (single source of truth for the grammar's kind alternation):

```swift
    /// Allowed values for `.agentKind` parameters — the grammar constrains
    /// `spawnAgents.kind` to exactly these instead of an arbitrary string.
    public static let agentKindValues: [String] = MediatorAgentKind.allCases.map(\.rawValue)
```

In `FastPathBrain.swift`, fix `parseSpawn` so the kind word is only recognized **before** any `named`/`called` marker, so a name equal to "shell" can't flip the kind:

```swift
    private static func parseSpawn(_ words: [String]) -> MediatorCommand? {
        guard let first = words.first else { return nil }
        let count = Int(first) ?? numberWords[first] ?? 0
        guard count > 0 else { return nil }

        let nameMarker = words.firstIndex { $0 == "named" || $0 == "called" }
        // Only words up to the name marker can name the process kind, so an
        // agent NAMED "shell" no longer flips a claude agent to a shell (carry-over #5).
        let kindScan = nameMarker.map { Array(words[..<$0]) } ?? words
        let kind: MediatorAgentKind = kindScan.contains("shell") ? .shell : .claudeCode

        var names: [String]? = nil
        if let namedIdx = nameMarker {
            let raw = words[(namedIdx + 1)...]
                .flatMap { $0.split(separator: ",").map(String.init) }
                .filter { $0 != "and" && !$0.isEmpty }
            if !raw.isEmpty { names = raw }
        }
        return .spawnAgents(count: count, kind: kind, names: names)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS — full suite (202 + 3 new = 205). Existing `spawn two shell terminals named fox and owl` still yields `.shell` (kind word precedes `named`).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator/MediatorCommandSchema.swift Sources/VoidloomCore/Mediator/FastPathBrain.swift Tests/VoidloomTests/MediatorCommandTests.swift Tests/VoidloomTests/FastPathBrainTests.swift
git commit -m "fix(mediator): constrain spawn kind to agentKind; stop shell-name flipping kind"
```

---

### Task 2: Coordinator & machine hardening for a slow brain (carry-overs #1, #2, #3)

`FastPathBrain` is instant, so the coordinator's task lifecycle and busy handling were never exercised. A hung or slow `LlamaBrain` makes all three carry-overs load-bearing. **Suggested tier: opus** (concurrency + state-machine reasoning).

**Files:**
- Modify: `Sources/VoidloomCore/Mediator/MediatorSessionMachine.swift` (`parseFailed` narrates its payload)
- Modify: `Sources/VoidloomCore/Mediator/FastPathBrain.swift` (extend `BrainError`)
- Modify: `Sources/VoidloomCore/Mediator/MediatorSessionCoordinator.swift` (cancel both tasks on any idle transition; `isBusy`; queue one pending utterance; map `BrainError` → distinct message)
- Test: `Tests/VoidloomTests/MediatorCoordinatorTests.swift` (append)

**Interfaces:**
- Consumes: `MediatorEvent.parseFailed(String)`, `MediatorEffect`, `MediatorState`.
- Produces: `BrainError.modelNotReady(String)` / `.modelDownloading(String)` / `.backendFailure(String)`; `MediatorSessionCoordinator.isBusy: Bool` (`@Published`). Task 6's `LlamaBrain`/`TieredBrain` throw the new errors; Task 9's HUD reads `isBusy`.

- [ ] **Step 1: Write the failing tests** (append to `MediatorCoordinatorTests.swift`)

Add a controllable slow/failing brain and tests:

```swift
private final class ControllableBrain: MediatorBrain {
    enum Outcome { case success(MediatorCommand), failure(BrainError), hang }
    var outcome: Outcome
    let started = AsyncStream<Void>.makeStream()
    private var release: CheckedContinuation<Void, Never>?

    init(_ outcome: Outcome) { self.outcome = outcome }

    func releaseNow() { release?.resume(); release = nil }

    func command(for utterance: String) async throws -> MediatorCommand {
        started.continuation.yield(())
        if case .hang = outcome {
            await withCheckedContinuation { self.release = $0 }
            try Task.checkCancellation()
        }
        switch outcome {
        case .success(let c): return c
        case .failure(let e): throw e
        case .hang: throw CancellationError()
        }
    }
}

extension MediatorCoordinatorTests {
    func testParseFailedSurfacesBrainSpecificMessage() async {
        let brain = ControllableBrain(.failure(.modelNotReady("Local model not downloaded — open Settings › Local AI.")))
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.submitTyped("start 2 claude agents")
        for _ in 0..<4000 where c.narration.isEmpty { await Task.yield() }
        XCTAssertEqual(c.narration, "Local model not downloaded — open Settings › Local AI.")
        XCTAssertEqual(c.state, .idle)
    }

    func testCancelDuringParsingCancelsBrainAndTimer() async {
        let brain = ControllableBrain(.hang)
        let c = MediatorSessionCoordinator(
            brain: brain,
            executor: CommandExecutor(store: makeStore(), terminals: MockAgentTerminals(), namePool: AgentNamePool()))
        c.submitTyped("start 2 claude agents")
        var it = brain.started.stream.makeAsyncIterator()
        _ = await it.next()                       // brain call is in flight
        guard case .parsing = c.state else { return XCTFail("expected parsing") }
        c.cancel()
        brain.releaseNow()                        // unblock the hung task so it can observe cancellation
        for _ in 0..<2000 where c.isBusy { await Task.yield() }
        XCTAssertEqual(c.state, .idle)
        XCTAssertFalse(c.isBusy)                   // timer + parse task both torn down
    }

    func testBusyInputQueuesExactlyOnePendingUtterance() async {
        let store = makeStore(); let terminals = MockAgentTerminals()
        let brain = ControllableBrain(.hang)
        let c = MediatorSessionCoordinator(brain: brain, executor: CommandExecutor(store: store, terminals: terminals, namePool: AgentNamePool()))
        c.submitTyped("start 1 claude agent")
        var it = brain.started.stream.makeAsyncIterator(); _ = await it.next()
        XCTAssertTrue(c.isBusy)
        c.submitTyped("start 2 shell agents")     // queued, not dropped
        c.submitTyped("start 3 shell agents")     // replaces the queued one (queue depth 1)
        brain.outcome = .success(.spawnAgents(count: 1, kind: .claudeCode, names: nil))
        brain.releaseNow()
        for _ in 0..<6000 where store.state.cards.filter({ $0.kind == .agent }).count < 3 {
            await Task.yield(); try? await Task.sleep(nanoseconds: 500_000)
        }
        // First utterance spawns 1; the single queued "3 shell agents" runs next → 1 + ... = fast-path? No:
        // ControllableBrain always returns the same command, so the queued utterance re-runs it → +1 = 2 total.
        XCTAssertEqual(store.state.cards.filter { $0.kind == .agent }.count, 2)
    }
}
```

> Note for the implementer: `ControllableBrain` returns a fixed command regardless of text, so the queued-utterance assertion checks the *number of runs* (2: original + one queued), proving depth-1 queueing (the second `submitTyped` replaced the first queued item). Adjust the final count only if you change queue semantics — keep depth 1.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MediatorCoordinatorTests`
Expected: FAIL — no `isBusy`, no new `BrainError` cases, generic rephrase narrated, hung task not cancelled.

- [ ] **Step 3: Implement**

`FastPathBrain.swift` — extend `BrainError` (keep `.unparseable`; add brain-availability cases the LLM tier throws):

```swift
public enum BrainError: Error, Equatable {
    case unparseable(String)
    /// The tier-2 model is not on disk. Payload is a user-facing sentence.
    case modelNotReady(String)
    /// The model is mid-download. Payload is a user-facing sentence (may include progress).
    case modelDownloading(String)
    /// The inference backend failed (load/decode error). Payload is user-facing.
    case backendFailure(String)
}
```

`MediatorSessionMachine.swift` — surface the `parseFailed` payload instead of swallowing it (carry-over #3). Replace the combined `parseFailed`/`timeout` arm with two arms:

```swift
        case (.parsing, .parseFailed(let message)):
            state = .idle
            return [.narrate(message.isEmpty ? Self.rephrasePrompt : message)]

        case (.parsing, .timeout):
            state = .idle
            return [.narrate(Self.rephrasePrompt)]
```

`MediatorSessionCoordinator.swift` — cancel both tasks on every idle-returning transition, expose `isBusy`, queue one utterance, and map `BrainError` to a distinct message. Full file:

```swift
import Combine
import Foundation

/// Performs `MediatorEffect`s around the pure `MediatorSessionMachine`:
/// runs the brain, dispatches the executor synchronously, and keeps AT MOST
/// ONE timeout task — every `scheduleTimeout` REPLACES the previous timer.
/// With a slow `LlamaBrain` behind the fast path, three lifecycle rules become
/// load-bearing (prework carry-overs #1–#3): any return to idle cancels BOTH
/// the parse task and the timer; a `parseFailed` payload is narrated verbatim
/// (distinct "model not downloaded" vs generic rephrase); and typed input while
/// busy queues exactly one pending utterance instead of being dropped.
@MainActor
public final class MediatorSessionCoordinator: ObservableObject {
    @Published public private(set) var state: MediatorState = .idle
    @Published public private(set) var narration: String = ""
    /// True whenever the pipeline is mid-command (capturing/parsing/executing);
    /// false at idle and while awaiting a confirmation (the HUD accepts input then).
    @Published public private(set) var isBusy: Bool = false

    private var machine = MediatorSessionMachine()
    private let brain: MediatorBrain
    private let executor: CommandExecutor
    private let timeoutScale: Double
    private var timeoutTask: Task<Void, Never>?
    private var parseTask: Task<Void, Never>?
    private var queuedUtterance: String?

    public init(brain: MediatorBrain, executor: CommandExecutor, timeoutScale: Double = 1) {
        self.brain = brain
        self.executor = executor
        self.timeoutScale = timeoutScale
    }

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
        if isBusy {
            queuedUtterance = trimmed   // depth-1 queue: newest wins, per carry-over #2
            return
        }
        send(.pushToTalkPressed)
        send(.transcriptFinal(trimmed))
    }

    public func confirm(_ accepted: Bool) { send(.confirmReceived(accepted)) }
    public func cancel() { send(.cancelRequested) }

    private func send(_ event: MediatorEvent) {
        let effects = machine.handle(event)
        state = machine.state
        // Any return to idle tears down in-flight async work (carry-over #1):
        // a hung LlamaBrain call and the parse watchdog must not outlive the state.
        if state == .idle {
            parseTask?.cancel(); parseTask = nil
            timeoutTask?.cancel(); timeoutTask = nil
        }
        isBusy = !(state == .idle) && !isAwaitingConfirmation
        for effect in effects { perform(effect) }
        drainQueueIfIdle()
    }

    private var isAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = state { return true }
        return false
    }

    private func drainQueueIfIdle() {
        guard state == .idle, let next = queuedUtterance else { return }
        queuedUtterance = nil
        send(.pushToTalkPressed)
        send(.transcriptFinal(next))
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
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self.send(.parseFailed(Self.message(for: error)))
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
            timeoutTask?.cancel(); timeoutTask = nil
            narration = text
        }
    }

    /// Maps brain errors to the exact HUD text (carry-over #3). `.unparseable`
    /// yields empty so the machine falls back to its generic rephrase prompt.
    private static func message(for error: Error) -> String {
        switch error {
        case BrainError.unparseable: return ""
        case BrainError.modelNotReady(let m),
             BrainError.modelDownloading(let m),
             BrainError.backendFailure(let m): return m
        default: return ""
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MediatorCoordinatorTests` then full `swift test`
Expected: PASS. The existing `testConfirmationTimesOutViaSingleReplaceableTimer` and `testUnparseableTypedInputNarratesRephrase` still pass (`.unparseable` → empty → generic rephrase). Full suite green (205 + 3 new = 208).

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomCore/Mediator Tests/VoidloomTests/MediatorCoordinatorTests.swift
git commit -m "feat(mediator): harden coordinator for slow brain — cancel-on-idle, busy queue, distinct parse errors"
```

---

### Task 3: VoidloomAI module + GBNF grammar generator

Create the new `VoidloomAI` SPM target (llama-free) and the deterministic GBNF generator that emits FROM `MediatorCommandSchema.cases`. Freeze it against a golden `mediator.gbnf` that the spike proved works with Qwen3-0.6B. **Suggested tier: opus** (grammar correctness against the spike's proven shape).

**Files:**
- Modify: `Package.swift` (add `VoidloomAI` library target + product; add to `VoidloomTests` deps)
- Create: `Sources/VoidloomAI/MediatorGrammar.swift`
- Create: `Sources/VoidloomAI/Resources/mediator.gbnf` (golden, matching the spike's 8-case grammar)
- Create: `Tests/VoidloomTests/MediatorGrammarTests.swift`

**Interfaces:**
- Consumes: `MediatorCommandSchema` (`cases`, `agentKindValues`, `samples`), `MediatorCommand`, `CardKind`.
- Produces: `MediatorGrammar.gbnf(from:) -> String` and `MediatorGrammar.rootGrammar` (built from the frozen schema). Task 6's `LlamaBrain` passes `MediatorGrammar.rootGrammar` to the engine.

- [ ] **Step 1: Add the SPM target**

Edit `Package.swift`:

```swift
    products: [
        .library(name: "VoidloomCore", targets: ["VoidloomCore"]),
        .library(name: "VoidloomAI", targets: ["VoidloomAI"]),
    ],
    targets: [
        .target(name: "VoidloomCore"),
        .target(
            name: "VoidloomAI",
            dependencies: ["VoidloomCore"],
            resources: [.copy("Resources/mediator.gbnf")]
        ),
        .testTarget(
            name: "VoidloomTests",
            dependencies: ["VoidloomCore", "VoidloomAI"]
        )
    ]
```

> `VoidloomAI` has **no** llama/binary dependency — the package stays resolvable and `swift test` stays headless. The llama C bridge lands in the Xcode app target only (Task 5).

- [ ] **Step 2: Write the failing tests**

```swift
// Tests/VoidloomTests/MediatorGrammarTests.swift
import XCTest
@testable import VoidloomCore
@testable import VoidloomAI

final class MediatorGrammarTests: XCTestCase {
    func testGrammarDeclaresARuleForEveryCommandCase() {
        let g = MediatorGrammar.rootGrammar
        for c in MediatorCommandSchema.cases {
            XCTAssertTrue(g.contains("\"\\\"\(c.name)\\\"\""),
                          "grammar missing a literal key for \(c.name)")
        }
        // Root alternates over exactly the 8 case rules.
        XCTAssertTrue(g.contains("root ::="))
    }

    func testKindIsConstrainedToAgentKindValuesNotFreeString() {
        let g = MediatorGrammar.rootGrammar
        // spawn kind alternation lists the concrete values, no open-ended string rule for kind.
        for value in MediatorCommandSchema.agentKindValues {
            XCTAssertTrue(g.contains("\"\\\"\(value)\\\"\""), "grammar missing kind value \(value)")
        }
    }

    func testGeneratedGrammarMatchesTheFrozenGoldenFile() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "mediator", withExtension: "gbnf"))
        let golden = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(
            MediatorGrammar.rootGrammar.trimmingCharacters(in: .whitespacesAndNewlines),
            golden.trimmingCharacters(in: .whitespacesAndNewlines),
            "generated GBNF drifted from the spike-validated golden — update golden ONLY after re-validating with llama"
        )
    }

    func testEverySchemaSampleIsAcceptedByTheReferenceRecognizer() throws {
        // A minimal GBNF recognizer covering the subset the generator emits, so
        // headless CI proves samples parse under the grammar without llama.
        let recognizer = try GBNFRecognizer(grammar: MediatorGrammar.rootGrammar)
        for (name, json) in MediatorCommandSchema.samples {
            XCTAssertTrue(recognizer.matches(json), "grammar rejects the frozen sample for \(name)")
        }
    }
}
```

> `GBNFRecognizer` is a tiny test-only GBNF-subset parser you add in the same test file (recursive-descent over the exact operators the generator uses: `::=`, `|`, string literals, rule refs, `?`, `*`, `[...]` char classes, whitespace rule). It exists so the spec's "sampled commands parse under generated GBNF" is provable headlessly. Keep it ~120 lines and test-only; the real acceptance guarantee is Task 7's gated llama integration test.

- [ ] **Step 3: Write the generator and golden**

```swift
// Sources/VoidloomAI/MediatorGrammar.swift
import Foundation
import VoidloomCore

/// Generates the llama.cpp GBNF grammar for `MediatorCommand` FROM the frozen
/// `MediatorCommandSchema`. Hand-written GBNF (not json-schema-to-grammar):
/// the Swift enum-with-associated-value Codable encoding does not map cleanly
/// from JSON Schema (spike finding). The generated string is frozen against
/// `Resources/mediator.gbnf`, which the spike validated end-to-end with
/// Qwen3-0.6B (8/8 utterances → schema-valid JSON).
public enum MediatorGrammar {
    /// The complete root grammar, built deterministically from the schema.
    public static let rootGrammar: String = gbnf(from: MediatorCommandSchema.cases)

    public static func gbnf(from cases: [MediatorCommandSchema.Case]) -> String {
        var lines: [String] = []
        let ruleNames = cases.map { "cmd-\($0.name)" }
        lines.append("root ::= \"{\" ws ( \(ruleNames.joined(separator: " | ")) ) ws \"}\"")

        for c in cases {
            lines.append("cmd-\(c.name) ::= \(caseBody(c))")
        }

        // Shared primitives (mirrors the spike's mediator.gbnf).
        lines.append(#"string ::= "\"" char* "\"""#)
        lines.append(#"char ::= [^"\\] | "\\" ( ["\\/bfnrt] | "u" hex hex hex hex )"#)
        lines.append("hex ::= [0-9a-fA-F]")
        lines.append("integer ::= [1-9] [0-9]*")
        lines.append(#"string-array ::= "[" ws string ( ws "," ws string )* ws "]""#)
        lines.append("ws ::= [ \\t\\n]*")
        return lines.joined(separator: "\n")
    }

    private static func caseBody(_ c: MediatorGrammar.SchemaCase) -> String {
        // {"name": { <params> }}
        let key = "\"\\\"\(c.name)\\\"\""
        let params = c.parameters
        var objectParts: [String] = []
        for (i, p) in params.enumerated() {
            let sep = i == 0 ? "" : "\"\\,\" ws "
            let keyLit = "\"\\\"\(p.name)\\\"\" ws \"\\:\" ws"
            let valueRule = valueGrammar(for: p.kind)
            let fragment = "\(sep)\(keyLit) \(valueRule)"
            if p.required {
                objectParts.append(fragment)
            } else {
                // Optional param is omitted when nil (spike risk #5 — Swift omits the key).
                objectParts.append("( \(fragment) )?")
            }
        }
        let inner = objectParts.joined(separator: " ")
        return "\"{\" ws \(key) ws \"\\:\" ws \"{\" ws \(inner) ws \"}\" ws \"}\""
    }

    private static func valueGrammar(for kind: MediatorCommandSchema.Parameter.Kind) -> String {
        switch kind {
        case .string: return "string"
        case .integer: return "integer"
        case .stringArray: return "string-array"
        case .agentKind:
            let alts = MediatorCommandSchema.agentKindValues.map { "\"\\\"\($0)\\\"\"" }
            return "( \(alts.joined(separator: " | ")) )"
        case .cardKind:
            let alts = CardKind.allCases.map { "\"\\\"\($0.rawValue)\\\"\"" }
            return "( \(alts.joined(separator: " | ")) )"
        case .arrangeStyle:
            // {"grid":{}} | {"retile":{}} | {"focus":{"target": string}}
            return #"( "{" ws "\"grid\"" ws "\:" ws "{" ws "}" ws "}" | "{" ws "\"retile\"" ws "\:" ws "{" ws "}" ws "}" | "{" ws "\"focus\"" ws "\:" ws "{" ws "\"target\"" ws "\:" ws string ws "}" ws "}" )"#
        case .backgroundSpec:
            // {"atmosphere":{}} | {"solid":{"hex": string}}
            return #"( "{" ws "\"atmosphere\"" ws "\:" ws "{" ws "}" ws "}" | "{" ws "\"solid\"" ws "\:" ws "{" ws "\"hex\"" ws "\:" ws string ws "}" ws "}" )"#
        }
    }
}

// Local alias so the generator reads cleanly; `SchemaCase` == `MediatorCommandSchema.Case`.
extension MediatorGrammar { typealias SchemaCase = MediatorCommandSchema.Case }
```

> **Implementer note (grammar correctness):** GBNF escaping is fiddly. Generate `rootGrammar`, print it, and diff against the spike's proven `mediator.gbnf` (`…/scratchpad/spike-llama/mediator.gbnf`) — they must be structurally equivalent (rule-for-rule, same literal keys, same optional/kind constraints). Then paste the *generated* output verbatim into `Sources/VoidloomAI/Resources/mediator.gbnf` as the golden (Step: create the golden file from the generator's own output so `testGeneratedGrammarMatchesTheFrozenGoldenFile` passes by construction, and the golden is what Task 7 feeds to real llama). If Qwen rejects it in Task 7, fix the generator and re-freeze the golden — never hand-edit the golden alone.

Create `Sources/VoidloomAI/Resources/mediator.gbnf` by running the generator once and pasting its exact output. (It must equal `MediatorGrammar.rootGrammar`.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MediatorGrammarTests` then full `swift test`
Expected: PASS. `CardKind` is confirmed `CaseIterable` with `String` raw values (`Sources/VoidloomCore/Workspace/WorkspaceModels.swift:3`) — no conformance change needed.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/VoidloomAI Tests/VoidloomTests/MediatorGrammarTests.swift
git commit -m "feat(ai): add VoidloomAI module and GBNF grammar generator frozen to spike golden"
```

---

### Task 4: ModelAssetManager + pinned manifest

Download-on-first-use with SHA256 verification, resumable, into Application Support. Pure Foundation + CryptoKit — headlessly testable with a `file://` fixture. **Suggested tier: opus** (download state machine, resumable I/O, checksum verification).

**Files:**
- Create: `Sources/VoidloomAI/Models/LocalModelManifest.swift`
- Create: `Sources/VoidloomAI/Models/ModelAssetManager.swift`
- Create: `Tests/VoidloomTests/ModelAssetManagerTests.swift`

**Interfaces:**
- Consumes: nothing from other 2b tasks (leaf).
- Produces: `LocalModelAsset` (id, filename, url, sha256, sizeBytes, license), `LocalModelManifest.commandModel` / `.chatModel`, `ModelAssetManager` (`@MainActor ObservableObject`) with `state(of:) -> ModelAssetState`, `localURL(of:) -> URL?`, `download(_:)`, `cancel(_:)`, `verifyExisting(_:)`. Task 6 reads `localURL(of: .commandModel)`; Task 7's resolver reads `state(of:)`; Task 8 uses `.chatModel`; Task 9's Settings drives `download`/`cancel` and renders `state`.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/VoidloomTests/ModelAssetManagerTests.swift
import XCTest
import CryptoKit
@testable import VoidloomAI

@MainActor
final class ModelAssetManagerTests: XCTestCase {
    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Serves a fixture file over file:// and returns a matching asset.
    private func fixtureAsset(bytes: Data, id: String = "fixture") throws -> (LocalModelAsset, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("\(id).bin")
        try bytes.write(to: src)
        let asset = LocalModelAsset(
            id: id, filename: "\(id).gguf", url: src,
            sha256: sha256Hex(bytes), sizeBytes: Int64(bytes.count),
            license: "Apache-2.0", displayName: "Fixture")
        return (asset, dir)
    }

    private func makeManager() -> (ModelAssetManager, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (ModelAssetManager(modelsDirectory: root), root)
    }

    func testMissingUntilDownloadedThenReady() async throws {
        let (asset, _) = try fixtureAsset(bytes: Data((0..<4096).map { UInt8($0 & 0xFF) }))
        let (mgr, root) = makeManager()
        XCTAssertEqual(mgr.state(of: asset), .missing)
        try await mgr.download(asset)
        XCTAssertEqual(mgr.state(of: asset), .ready)
        let dest = root.appendingPathComponent(asset.filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(mgr.localURL(of: asset), dest)
    }

    func testChecksumMismatchFailsAndDoesNotMarkReady() async throws {
        var (asset, _) = try fixtureAsset(bytes: Data([1, 2, 3, 4]))
        asset = LocalModelAsset(id: asset.id, filename: asset.filename, url: asset.url,
                                sha256: String(repeating: "0", count: 64), sizeBytes: asset.sizeBytes,
                                license: asset.license, displayName: asset.displayName)
        let (mgr, _) = makeManager()
        do { try await mgr.download(asset); XCTFail("expected checksum failure") }
        catch { }
        if case .failed = mgr.state(of: asset) {} else { XCTFail("expected .failed, got \(mgr.state(of: asset))") }
    }

    func testVerifyExistingRecognizesAPreviouslyDownloadedFile() async throws {
        let bytes = Data((0..<8192).map { UInt8($0 & 0xFF) })
        let (asset, _) = try fixtureAsset(bytes: bytes)
        let (mgr, root) = makeManager()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try bytes.write(to: root.appendingPathComponent(asset.filename))
        let verified = await mgr.verifyExisting(asset)
        XCTAssertTrue(verified)
        XCTAssertEqual(mgr.state(of: asset), .ready)
    }

    func testManifestPinsTheCommandModelFromTheSpike() {
        let m = LocalModelManifest.commandModel
        XCTAssertEqual(m.sha256, "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a")
        XCTAssertEqual(m.sizeBytes, 396_705_472)
        XCTAssertEqual(m.license, "Apache-2.0")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ModelAssetManagerTests`
Expected: FAIL — types not yet defined.

- [ ] **Step 3: Implement**

```swift
// Sources/VoidloomAI/Models/LocalModelManifest.swift
import Foundation

/// One downloadable model asset with its pinned integrity + license data.
public struct LocalModelAsset: Identifiable, Equatable, Sendable {
    public let id: String
    public let filename: String
    public let url: URL
    public let sha256: String
    public let sizeBytes: Int64
    public let license: String
    public let displayName: String

    public init(id: String, filename: String, url: URL, sha256: String,
                sizeBytes: Int64, license: String, displayName: String) {
        self.id = id; self.filename = filename; self.url = url
        self.sha256 = sha256; self.sizeBytes = sizeBytes
        self.license = license; self.displayName = displayName
    }
}

/// The pinned, revision-locked asset manifest. URLs use Hugging Face
/// `resolve/<revision>/<file>` so the bytes cannot change under us; SHA256 is
/// verified after download. Command model values are from the spike
/// (`.omc/research/spike-llama.md`); the chat model is pinned in Task 8.
public enum LocalModelManifest {
    public static let commandModel = LocalModelAsset(
        id: "qwen3-0.6b-q4km",
        filename: "Qwen3-0.6B-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/50968a4468ef4233ed78cd7c3de230dd1d61a56b/Qwen3-0.6B-Q4_K_M.gguf")!,
        sha256: "ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a",
        sizeBytes: 396_705_472,
        license: "Apache-2.0",
        displayName: "Qwen3 0.6B (command parser)")

    // Chat model is defined in Task 8 as `LocalModelManifest.chatModel`.
}
```

```swift
// Sources/VoidloomAI/Models/ModelAssetManager.swift
import Combine
import CryptoKit
import Foundation

public enum ModelAssetState: Equatable, Sendable {
    case missing
    case downloading(progress: Double)
    case verifying
    case ready
    case failed(reason: String)
}

/// Downloads model assets on first use into Application Support/Voidloom/Models,
/// verifies SHA256, and publishes per-asset state. Resumable via URLSession
/// download tasks. Pure Foundation + CryptoKit — no llama, no SwiftUI — so it
/// is headlessly testable against a file:// fixture.
@MainActor
public final class ModelAssetManager: NSObject, ObservableObject {
    @Published private var states: [String: ModelAssetState] = [:]

    private let modelsDirectory: URL
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private lazy var session: URLSession = {
        URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }()

    public init(modelsDirectory: URL = ModelAssetManager.defaultModelsDirectory()) {
        self.modelsDirectory = modelsDirectory
        super.init()
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    public static func defaultModelsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Voidloom/Models", isDirectory: true)
    }

    public func destinationURL(of asset: LocalModelAsset) -> URL {
        modelsDirectory.appendingPathComponent(asset.filename)
    }

    public func localURL(of asset: LocalModelAsset) -> URL? {
        let url = destinationURL(of: asset)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func state(of asset: LocalModelAsset) -> ModelAssetState {
        if let s = states[asset.id] { return s }
        return FileManager.default.fileExists(atPath: destinationURL(of: asset).path) ? .ready : .missing
    }

    /// Confirms an on-disk file matches the pinned checksum; flips to .ready or .missing.
    public func verifyExisting(_ asset: LocalModelAsset) async -> Bool {
        let dest = destinationURL(of: asset)
        guard FileManager.default.fileExists(atPath: dest.path) else {
            states[asset.id] = .missing; return false
        }
        states[asset.id] = .verifying
        let ok = await Self.checksumMatches(fileURL: dest, expected: asset.sha256)
        states[asset.id] = ok ? .ready : .missing
        if !ok { try? FileManager.default.removeItem(at: dest) }
        return ok
    }

    public func download(_ asset: LocalModelAsset) async throws {
        let dest = destinationURL(of: asset)
        if FileManager.default.fileExists(atPath: dest.path),
           await Self.checksumMatches(fileURL: dest, expected: asset.sha256) {
            states[asset.id] = .ready; return
        }
        states[asset.id] = .downloading(progress: 0)
        let tempURL: URL
        do {
            tempURL = try await runDownload(asset)
        } catch {
            states[asset.id] = .failed(reason: error.localizedDescription); throw error
        }
        states[asset.id] = .verifying
        guard await Self.checksumMatches(fileURL: tempURL, expected: asset.sha256) else {
            try? FileManager.default.removeItem(at: tempURL)
            let reason = "Downloaded file failed integrity check."
            states[asset.id] = .failed(reason: reason)
            throw ModelAssetError.checksumMismatch(assetID: asset.id)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        states[asset.id] = .ready
    }

    public func cancel(_ asset: LocalModelAsset) {
        tasks[asset.id]?.cancel(); tasks[asset.id] = nil
        states[asset.id] = FileManager.default.fileExists(atPath: destinationURL(of: asset).path) ? .ready : .missing
    }

    // MARK: download plumbing

    private var continuations: [Int: CheckedContinuation<URL, Error>] = [:]

    private func runDownload(_ asset: LocalModelAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: asset.url)
            tasks[asset.id] = task
            continuations[task.taskIdentifier] = continuation
            progressAsset[task.taskIdentifier] = asset.id
            task.resume()
        }
    }

    private var progressAsset: [Int: String] = [:]

    fileprivate func finishDownload(taskID: Int, movedTo staged: URL?, error: Error?) {
        guard let continuation = continuations.removeValue(forKey: taskID) else { return }
        if let error { continuation.resume(throwing: error) }
        else if let staged { continuation.resume(returning: staged) }
        else { continuation.resume(throwing: ModelAssetError.downloadProducedNoFile) }
    }

    fileprivate func report(taskID: Int, progress: Double) {
        guard let id = progressAsset[taskID] else { return }
        states[id] = .downloading(progress: progress)
    }

    static func checksumMatches(fileURL: URL, expected: String) async -> Bool {
        await Task.detached(priority: .utility) {
            guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return hex.caseInsensitiveCompare(expected) == .orderedSame
        }.value
    }
}

public enum ModelAssetError: Error, Equatable {
    case checksumMismatch(assetID: String)
    case downloadProducedNoFile
}

extension ModelAssetManager: URLSessionDownloadDelegate {
    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                       didFinishDownloadingTo location: URL) {
        // Stage synchronously in the delegate (the temp file is deleted on return).
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let moveError: Error?
        do { try FileManager.default.moveItem(at: location, to: staged); moveError = nil }
        catch { moveError = error }
        let id = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in
            self?.finishDownload(taskID: id, movedTo: moveError == nil ? staged : nil, error: moveError)
        }
    }

    public nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                       didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                       totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let id = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in self?.report(taskID: id, progress: p) }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                       didCompleteWithError error: Error?) {
        guard let error else { return } // success handled in didFinishDownloadingTo
        let id = task.taskIdentifier
        Task { @MainActor [weak self] in self?.finishDownload(taskID: id, movedTo: nil, error: error) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ModelAssetManagerTests` then full `swift test`
Expected: PASS. (The `file://` fixture exercises the full download→verify→ready and mismatch→failed paths headlessly.)

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomAI/Models Tests/VoidloomTests/ModelAssetManagerTests.swift
git commit -m "feat(ai): add ModelAssetManager with pinned manifest and SHA256 verification"
```

---

### Task 5: Vendor llama.xcframework + LlamaEngine protocol + Cllama bridge

The one task that touches C interop and the Xcode project. Vendor a pinned `llama.xcframework`, define the pure-Swift `LlamaEngine` protocol in `VoidloomAI`, and implement `CllamaEngine` (with the mandatory `n_ctx` cap) in the **app target only**. **Suggested tier: opus** (llama C interop, xcframework wiring, pbxproj surgery).

**Files:**
- Create: `scripts/build-llama-xcframework.sh` (pinned tag `b9850`; produces `Frameworks/llama.xcframework`)
- Modify: `.gitignore` (ignore `Frameworks/llama.xcframework/`)
- Create: `Sources/VoidloomAI/Inference/LlamaEngine.swift` (protocol + config — llama-free)
- Create: `VoidloomApp/AI/Local/Cllama/module.modulemap` + umbrella referencing the vendored `llama.h`
- Create: `VoidloomApp/AI/Local/CllamaEngine.swift` (app-target concrete engine)
- Modify: `Voidloom.xcodeproj/project.pbxproj` (embed the xcframework; add `SWIFT_INCLUDE_PATHS`; register `CllamaEngine.swift`)

**Interfaces:**
- Consumes: the vendored `llama.h` C API (pinned tag `b9850`).
- Produces: `LlamaEngine` protocol (`load(modelPath:config:)`, `complete(systemPrompt:userPrompt:grammar:maxTokens:)`, `stream(systemPrompt:userPrompt:onToken:)`, `unload()`) and `LlamaEngine.Config` (context cap). Task 6's `LlamaBrain` and Task 8's `LocalResponseProvider` depend on the protocol; `CllamaEngine` is injected in the app (Task 7).

- [ ] **Step 1: Vendoring script + gitignore**

```bash
# scripts/build-llama-xcframework.sh
#!/usr/bin/env bash
# Builds a vendored llama.xcframework pinned to a known-good llama.cpp release.
# Pinned in the spike (.omc/research/spike-llama.md): tag b9850 (commit 4f31eedb0),
# proven to link + run Qwen3-0.6B with Metal from Swift. Artifact is gitignored.
set -euo pipefail

LLAMA_TAG="${LLAMA_TAG:-b9850}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${REPO_ROOT}/.build/llama-src"
DEST="${REPO_ROOT}/Frameworks"

if [ -d "${DEST}/llama.xcframework" ]; then
  echo "llama.xcframework already present at ${DEST} — delete it to rebuild."
  exit 0
fi

rm -rf "${WORK}"
git clone --depth 1 --branch "${LLAMA_TAG}" https://github.com/ggml-org/llama.cpp "${WORK}"
pushd "${WORK}" >/dev/null
# build-xcframework.sh defaults: GGML_METAL=ON, GGML_METAL_EMBED_LIBRARY=ON,
# MACOS_MIN_OS_VERSION=13.3 (compatible with Voidloom's macOS 14 floor).
./build-xcframework.sh
popd >/dev/null

mkdir -p "${DEST}"
cp -R "${WORK}/build-apple/llama.xcframework" "${DEST}/llama.xcframework"
echo "Vendored ${DEST}/llama.xcframework from llama.cpp ${LLAMA_TAG}"
echo "Header for the Cllama module map:"
find "${DEST}/llama.xcframework" -name llama.h -maxdepth 4 -print
```

Make it executable and add to `.gitignore`:

```bash
chmod +x scripts/build-llama-xcframework.sh
```
Append to `.gitignore` (after the Swift/Xcode block):
```
# Vendored native framework (built by scripts/build-llama-xcframework.sh; ~large, pinned by tag)
Frameworks/llama.xcframework/
```

> **Implementer note:** confirm `build-xcframework.sh`'s output path (`build-apple/llama.xcframework` on tag `b9850`; the spike inspected this). If the layout differs on the pinned tag, adjust the `cp` source path. Run the script once before touching the Xcode project so the header path for the module map is known.

- [ ] **Step 2: LlamaEngine protocol (VoidloomAI, llama-free)**

```swift
// Sources/VoidloomAI/Inference/LlamaEngine.swift
import Foundation

/// Pure-Swift seam over a llama.cpp context. The concrete `CllamaEngine`
/// (app target) links the vendored xcframework and conforms; `VoidloomAI`
/// never imports llama, so `swift test` stays headless. Grammar-constrained
/// `complete` powers `LlamaBrain`; streaming `stream` powers the chat
/// `LocalResponseProvider`.
public protocol LlamaEngine: AnyObject, Sendable {
    /// Loads a GGUF model and holds it resident. Caps context per `config`
    /// (mandatory — default n_ctx blows RSS to ~4.9 GB, spike risk #2).
    func load(modelPath: URL, config: LlamaEngine.Config) throws
    func unload()

    /// One grammar-constrained completion. Greedy decoding; returns the raw
    /// generated string (expected to be schema-valid JSON when a grammar is set).
    func complete(systemPrompt: String, userPrompt: String,
                  grammar: String?, maxTokens: Int) throws -> String

    /// Streamed, unconstrained generation for chat. `onToken` returns false to stop.
    func stream(systemPrompt: String, userPrompt: String,
                onToken: @escaping (String) -> Bool) throws
}

public extension LlamaEngine {
    struct Config: Sendable, Equatable {
        /// Hard context cap. 2048 keeps RSS ~0.3–0.7 GB (spike-measured).
        public var contextLength: Int
        /// GPU layers offloaded to Metal (-1/large = all).
        public var gpuLayers: Int
        public var seed: UInt32

        public init(contextLength: Int = 2048, gpuLayers: Int = 999, seed: UInt32 = 0xFFFFFFFF) {
            self.contextLength = contextLength
            self.gpuLayers = gpuLayers
            self.seed = seed
        }
    }
}
```

- [ ] **Step 3: Cllama module map + CllamaEngine (app target)**

`VoidloomApp/AI/Local/Cllama/module.modulemap`:

```
module Cllama {
    header "llama.h"
    link "llama"
    export *
}
```

> The header search path is set on the app target via `SWIFT_INCLUDE_PATHS` pointing at the vendored `llama.xcframework`'s macos headers dir (Step 4). If the umbrella `llama.h` transitively needs `ggml.h`, add those headers' dir to the search path too (the xcframework ships them alongside).

`VoidloomApp/AI/Local/CllamaEngine.swift`:

```swift
import Cllama
import Foundation
import VoidloomAI

/// Concrete `LlamaEngine` backed by the vendored llama.xcframework (pinned
/// llama.cpp b9850). Lives in the app target only — the sole place that links
/// libllama. Caps n_ctx per `Config` (mandatory). Model + context load once
/// and stay resident; a persistent system-prompt KV cache is achieved by
/// keeping the context alive across calls.
///
/// IMPLEMENTER: verify these symbol names against Frameworks/llama.xcframework's
/// llama.h at tag b9850 — the C ABI is stable but function renames happen across
/// tags. The spike proved linkage with this API surface.
final class CllamaEngine: LlamaEngine, @unchecked Sendable {
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private let lock = NSLock()
    private static let backendInit: Void = { llama_backend_init() }()

    init() { _ = Self.backendInit }

    func load(modelPath: URL, config: LlamaEngine.Config) throws {
        lock.lock(); defer { lock.unlock() }
        unloadLocked()

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = Int32(config.gpuLayers)
        guard let m = llama_model_load_from_file(modelPath.path, mparams) else {
            throw LlamaEngineError.modelLoadFailed(modelPath.lastPathComponent)
        }
        model = m
        vocab = llama_model_get_vocab(m)

        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(config.contextLength)   // MANDATORY cap
        cparams.n_batch = UInt32(min(config.contextLength, 512))
        guard let c = llama_init_from_model(m, cparams) else {
            llama_model_free(m); model = nil
            throw LlamaEngineError.contextInitFailed
        }
        ctx = c
    }

    func unload() { lock.lock(); defer { lock.unlock() }; unloadLocked() }

    private func unloadLocked() {
        if let c = ctx { llama_free(c); ctx = nil }
        if let m = model { llama_model_free(m); model = nil }
        vocab = nil
    }

    func complete(systemPrompt: String, userPrompt: String,
                  grammar: String?, maxTokens: Int) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard let ctx, let vocab else { throw LlamaEngineError.notLoaded }

        let prompt = Self.chatMLPrompt(system: systemPrompt, user: userPrompt)
        try evaluate(prompt: prompt, ctx: ctx, vocab: vocab)

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(sampler) }
        if let grammar {
            grammar.withCString { g in
                "root".withCString { r in
                    llama_sampler_chain_add(sampler, llama_sampler_init_grammar(vocab, g, r))
                }
            }
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        var output = ""
        var nPast = Int32(Self.tokenCount(prompt, vocab: vocab))
        for _ in 0..<maxTokens {
            let token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            output += Self.piece(token, vocab: vocab)
            let batch = llama_batch_get_one([token].map { $0 }, 1)
            if llama_decode(ctx, batch) != 0 { throw LlamaEngineError.decodeFailed }
            nPast += 1
        }
        return output
    }

    func stream(systemPrompt: String, userPrompt: String,
                onToken: @escaping (String) -> Bool) throws {
        lock.lock(); defer { lock.unlock() }
        guard let ctx, let vocab else { throw LlamaEngineError.notLoaded }
        // Qwen3 emits <think> unless suppressed; append /no_think for chat (spike risk #3).
        let prompt = Self.chatMLPrompt(system: systemPrompt, user: userPrompt + " /no_think")
        try evaluate(prompt: prompt, ctx: ctx, vocab: vocab)

        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.95, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(0xFFFFFFFF))

        for _ in 0..<1024 {
            let token = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            if !onToken(Self.piece(token, vocab: vocab)) { break }
            let batch = llama_batch_get_one([token], 1)
            if llama_decode(ctx, batch) != 0 { throw LlamaEngineError.decodeFailed }
        }
    }

    // MARK: helpers

    private func evaluate(prompt: String, ctx: OpaquePointer, vocab: OpaquePointer) throws {
        var tokens = Self.tokenize(prompt, vocab: vocab, addBos: true)
        tokens.withUnsafeMutableBufferPointer { buf in
            let batch = llama_batch_get_one(buf.baseAddress, Int32(buf.count))
            _ = llama_decode(ctx, batch)
        }
    }

    private static func tokenize(_ text: String, vocab: OpaquePointer, addBos: Bool) -> [llama_token] {
        let utf8 = Array(text.utf8)
        let capacity = utf8.count + 8
        var tokens = [llama_token](repeating: 0, count: capacity)
        let n = text.withCString { cstr in
            llama_tokenize(vocab, cstr, Int32(utf8.count), &tokens, Int32(capacity), addBos, true)
        }
        return Array(tokens.prefix(Int(max(0, n))))
    }

    private static func tokenCount(_ text: String, vocab: OpaquePointer) -> Int {
        tokenize(text, vocab: vocab, addBos: true).count
    }

    private static func piece(_ token: llama_token, vocab: OpaquePointer) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        let n = llama_token_to_piece(vocab, token, &buf, 128, 0, true)
        guard n > 0 else { return "" }
        return String(decoding: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Qwen3 ChatML template.
    private static func chatMLPrompt(system: String, user: String) -> String {
        "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n\(user)<|im_end|>\n<|im_start|>assistant\n"
    }
}

enum LlamaEngineError: Error {
    case modelLoadFailed(String), contextInitFailed, notLoaded, decodeFailed
}
```

> **Implementer note (C interop is the risk surface):** the spike proved Swift↔libllama linkage and Metal init, but did not compile this exact decode loop. Before wiring `LlamaBrain`, build the app target and fix any symbol mismatches against the vendored `llama.h` (e.g. `llama_init_from_model` vs `llama_new_context_with_model`, `llama_model_load_from_file` vs `llama_load_model_from_file`, sampler init names). The `LlamaLinkProbe` package in the spike scratch (`…/scratchpad/spike-llama/LlamaLinkProbe/`) is the reference for a known-good minimal link. Keep the decode loop simple; correctness is validated by Task 7's gated golden-utterance test.

- [ ] **Step 4: Compile checkpoint — get CllamaEngine.swift building in isolation BEFORE the rest of Task 5 proceeds**

This is the highest-risk file in the plan (hand-written C interop, unverified against the pinned tag's exact `llama.h` symbol names). Prove it actually compiles and links against the vendored framework now, cheaply, before sinking time into the full shipping-grade embed/copy-phase wiring in Step 5 — that way a symbol mismatch is caught immediately against a small diff, not after all the pbxproj surgery is already done.

Do only the MINIMUM `project.pbxproj` wiring needed to compile + link (not yet embed/run) `CllamaEngine.swift`, using fresh unique `A2…` IDs (grep first to confirm uniqueness):

1. `PBXFileReference` for the framework and for `CllamaEngine.swift`:
```
		A200000000000000000000C1 /* llama.xcframework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; name = llama.xcframework; path = Frameworks/llama.xcframework; sourceTree = "<group>"; };
		A200000000000000000000C2 /* CllamaEngine.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AI/Local/CllamaEngine.swift; sourceTree = "<group>"; };
```
2. `PBXBuildFile` entries — link the framework, compile the Swift file (embedding comes in Step 5):
```
		A200000000000000000000D1 /* llama.xcframework in Frameworks */ = {isa = PBXBuildFile; fileRef = A200000000000000000000C1 /* llama.xcframework */; };
		A200000000000000000000D3 /* CllamaEngine.swift in Sources */ = {isa = PBXBuildFile; fileRef = A200000000000000000000C2 /* CllamaEngine.swift */; };
```
3. Add `A200000000000000000000D1` to the existing `PBXFrameworksBuildPhase` `files` list (next to `VoidloomCore in Frameworks`, ~line 134).
4. Add `A200000000000000000000D3` to the `PBXSourcesBuildPhase` `files` list.
5. Add `A200000000000000000000C1` and `A200000000000000000000C2` to the appropriate group children (framework in a `Frameworks` group; the Swift file in an `AI` group — create the group if the `AI` files aren't grouped yet, mirroring the `Shell` group).
6. In **both** app-target `XCBuildConfiguration` (Debug + Release) `buildSettings`, add:
```
				FRAMEWORK_SEARCH_PATHS = ( "$(inherited)", "$(PROJECT_DIR)/Frameworks", );
				SWIFT_INCLUDE_PATHS = ( "$(inherited)", "$(PROJECT_DIR)/VoidloomApp/AI/Local/Cllama", );
				HEADER_SEARCH_PATHS = ( "$(inherited)", "$(PROJECT_DIR)/Frameworks/llama.xcframework/macos-arm64/Headers", );
```
   (Point `SWIFT_INCLUDE_PATHS` at the `Cllama` module map dir; the module map's `header "llama.h"` resolves via `HEADER_SEARCH_PATHS`. Adjust the xcframework slice name — e.g. `macos-arm64` — to the actual produced slice.)

Now run the checkpoint:
```bash
./scripts/build-llama-xcframework.sh            # one-time; produces Frameworks/llama.xcframework
xcodebuild -scheme Voidloom -destination 'platform=macOS' build
```
Expected: BUILD SUCCEEDED. (The app isn't runnable yet — the framework isn't embedded, so launching would fail at dyld load time — but a successful *build* proves every `llama_*`/`llama_sampler_*` symbol referenced in `CllamaEngine.swift` resolves against the pinned tag's real `llama.h`.) If it fails, fix the symbol mismatches now (e.g. `llama_init_from_model` vs `llama_new_context_with_model`, `llama_model_load_from_file` vs `llama_load_model_from_file`, sampler init names) — do not proceed to Step 5 until this checkpoint is green. The `LlamaLinkProbe` package in the spike scratch (`…/scratchpad/spike-llama/LlamaLinkProbe/`) is the reference for a known-good minimal link.

- [ ] **Step 5: Complete the framework embedding so the app can actually launch**

Add the remaining piece Step 4 deliberately skipped — a `PBXCopyFilesBuildPhase` (dstSubfolderSpec = 10, "Frameworks") so the framework is embedded into the app bundle at runtime, not just linked at build time:

```
		A200000000000000000000D2 /* llama.xcframework in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = A200000000000000000000C1 /* llama.xcframework */; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };
```
```
		A200000000000000000000E1 /* Embed Frameworks */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 10;
			files = ( A200000000000000000000D2 /* llama.xcframework in Embed Frameworks */, );
			name = "Embed Frameworks";
			runOnlyForDeploymentPostprocessing = 0;
		};
```
Reference `A200000000000000000000E1` in the app target's `buildPhases` array (after the existing `Frameworks`/`Sources` phases).

> **Implementer note:** manual pbxproj editing for an embedded xcframework + a module map is the most error-prone mechanical step in this plan — but by this point Step 4's checkpoint has already proven the C interop itself compiles, so a failure here is isolated to the embed/copy-phase wiring. If the framework won't embed, fall back to the Xcode GUI: drag `Frameworks/llama.xcframework` into the project navigator, set it to **Embed & Sign** on the Voidloom target, then re-run the build. Commit the resulting pbxproj. Verify with `xcodebuild` (Step 6) — do not claim done until BUILD SUCCEEDED and the app launches.

- [ ] **Step 6: Verify**

```bash
swift build                                     # VoidloomAI (LlamaEngine protocol) compiles, llama-free
swift test                                      # full Core+AI suite green, no model needed
xcodebuild -scheme Voidloom -destination 'platform=macOS' build   # app links + embeds llama
```
Expected: `swift test` green (unchanged count; `CllamaEngine` is app-target only, not in `swift test`). App build SUCCEEDED, and the app launches (Step 5's embed phase is what makes launch — not just build — succeed).

- [ ] **Step 7: Commit**

```bash
git add scripts/build-llama-xcframework.sh .gitignore Sources/VoidloomAI/Inference/LlamaEngine.swift VoidloomApp/AI/Local Voidloom.xcodeproj/project.pbxproj
git commit -m "feat(ai): vendor llama.xcframework and add LlamaEngine + CllamaEngine bridge"
```

---

### Task 6: LlamaBrain + TieredBrain + MediatorTierResolver

Wrap the engine into a `MediatorBrain`, compose it behind `FastPathBrain`, and add the pure tier-resolution decision. All headlessly tested with a fake engine — no real inference here. **Suggested tier: opus** (fallback semantics, JSON→command decode, resolver matrix).

**Files:**
- Create: `Sources/VoidloomAI/Inference/LlamaBrain.swift`
- Create: `Sources/VoidloomCore/Mediator/TieredBrain.swift`
- Create: `Sources/VoidloomCore/Mediator/MediatorTierResolver.swift`
- Create: `Tests/VoidloomTests/LlamaBrainTests.swift`, `Tests/VoidloomTests/TieredBrainTests.swift`, `Tests/VoidloomTests/MediatorTierResolverTests.swift`

**Interfaces:**
- Consumes: `LlamaEngine`, `MediatorGrammar.rootGrammar`, `MediatorBrain`, `BrainError`, `MediatorCommand`, `ModelAssetState`.
- Produces: `LlamaBrain(engine:promptBuilder:)` (`MediatorBrain`); `TieredBrain(fast:fallback:)` (`MediatorBrain`, Core); `MediatorTierResolver.resolve(capabilities:) -> MediatorTier`. Task 7 wires these in the app.

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/VoidloomTests/LlamaBrainTests.swift
import XCTest
@testable import VoidloomAI
@testable import VoidloomCore

private final class FakeEngine: LlamaEngine, @unchecked Sendable {
    var completion: Result<String, Error>
    var lastGrammar: String?
    init(_ completion: Result<String, Error>) { self.completion = completion }
    func load(modelPath: URL, config: LlamaEngine.Config) throws {}
    func unload() {}
    func complete(systemPrompt: String, userPrompt: String, grammar: String?, maxTokens: Int) throws -> String {
        lastGrammar = grammar
        return try completion.get()
    }
    func stream(systemPrompt: String, userPrompt: String, onToken: @escaping (String) -> Bool) throws {}
}

final class LlamaBrainTests: XCTestCase {
    func testDecodesGrammarConstrainedJSONIntoCommand() async throws {
        let engine = FakeEngine(.success(#"{"spawnAgents":{"count":2,"kind":"claude"}}"#))
        let brain = LlamaBrain(engine: engine)
        let cmd = try await brain.command(for: "spin up a couple agents")
        XCTAssertEqual(cmd, .spawnAgents(count: 2, kind: .claudeCode, names: nil))
        XCTAssertEqual(engine.lastGrammar, MediatorGrammar.rootGrammar) // grammar always applied
    }

    func testNonJSONOutputThrowsUnparseable() async {
        let brain = LlamaBrain(engine: FakeEngine(.success("I think you meant to spawn agents")))
        await XCTAssertThrowsBrainError(.unparseable("")) { try await brain.command(for: "x") }
    }

    func testEngineFailureMapsToBackendFailure() async {
        let brain = LlamaBrain(engine: FakeEngine(.failure(LlamaBrainStubError.boom)))
        do { _ = try await brain.command(for: "x"); XCTFail() }
        catch let e as BrainError { if case .backendFailure = e {} else { XCTFail("got \(e)") } }
        catch { XCTFail("wrong type") }
    }
}
enum LlamaBrainStubError: Error { case boom }
```

```swift
// Tests/VoidloomTests/TieredBrainTests.swift
import XCTest
@testable import VoidloomCore

private final class ScriptedBrain: MediatorBrain, @unchecked Sendable {
    let result: Result<MediatorCommand, Error>
    private(set) var calls = 0
    init(_ r: Result<MediatorCommand, Error>) { result = r }
    func command(for utterance: String) async throws -> MediatorCommand { calls += 1; return try result.get() }
}

final class TieredBrainTests: XCTestCase {
    func testFastPathResultShortCircuitsFallback() async throws {
        let fast = ScriptedBrain(.success(.readOutput(target: "ember")))
        let fallback = ScriptedBrain(.success(.closeTerminal(target: "x")))
        let cmd = try await TieredBrain(fast: fast, fallback: fallback).command(for: "show ember")
        XCTAssertEqual(cmd, .readOutput(target: "ember"))
        XCTAssertEqual(fallback.calls, 0) // LLM never consulted when fast path wins
    }

    func testUnparseableFallsThroughToLLM() async throws {
        let fast = ScriptedBrain(.failure(BrainError.unparseable("huh")))
        let fallback = ScriptedBrain(.success(.switchSpace(name: "research")))
        let cmd = try await TieredBrain(fast: fast, fallback: fallback).command(for: "take me to research please")
        XCTAssertEqual(cmd, .switchSpace(name: "research"))
        XCTAssertEqual(fallback.calls, 1)
    }

    func testNonUnparseableFastErrorDoesNotFallThrough() async {
        let fast = ScriptedBrain(.failure(BrainError.backendFailure("io")))
        let fallback = ScriptedBrain(.success(.readOutput(target: "x")))
        let brain = TieredBrain(fast: fast, fallback: fallback)
        do { _ = try await brain.command(for: "x"); XCTFail() }
        catch let e as BrainError { if case .backendFailure = e {} else { XCTFail() } }
        catch { XCTFail() }
    }
}
```

```swift
// Tests/VoidloomTests/MediatorTierResolverTests.swift
import XCTest
@testable import VoidloomCore

final class MediatorTierResolverTests: XCTestCase {
    func testCommandModelReadyEnablesLLMFallbackTier() {
        let tier = MediatorTierResolver.resolve(capabilities: .init(commandModelReady: true))
        XCTAssertEqual(tier, .fastPathWithLLM)
    }
    func testCommandModelMissingFallsBackToFastPathOnly() {
        let tier = MediatorTierResolver.resolve(capabilities: .init(commandModelReady: false))
        XCTAssertEqual(tier, .fastPathOnly)
    }
}
```

Add the small async-throws helper to the test target if not present (`XCTAssertThrowsBrainError`) — a tiny helper asserting the thrown error is a `BrainError` of the expected case (ignore payload).

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LlamaBrainTests` / `TieredBrainTests` / `MediatorTierResolverTests`
Expected: FAIL — types not defined.

- [ ] **Step 3: Implement**

```swift
// Sources/VoidloomAI/Inference/LlamaBrain.swift
import Foundation
import VoidloomCore

/// Tier-2 grammar-constrained brain. Runs the model with GBNF from
/// `MediatorCommandSchema`, so raw output is (structurally) always
/// schema-valid JSON; a decode failure means the model produced something
/// off-grammar and we throw `.unparseable` (fast path / rephrase handles it).
/// Field extraction is validated downstream by `MediatorTargetResolver`.
public final class LlamaBrain: MediatorBrain, @unchecked Sendable {
    private let engine: LlamaEngine
    private let systemPrompt: String
    private let maxTokens: Int

    public init(engine: LlamaEngine,
                systemPrompt: String = LlamaBrain.defaultSystemPrompt,
                maxTokens: Int = 96) {
        self.engine = engine
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
    }

    public func command(for utterance: String) async throws -> MediatorCommand {
        let raw: String
        do {
            raw = try engine.complete(systemPrompt: systemPrompt, userPrompt: utterance,
                                      grammar: MediatorGrammar.rootGrammar, maxTokens: maxTokens)
        } catch {
            throw BrainError.backendFailure("The local model failed to respond.")
        }
        guard let data = Self.firstJSONObject(in: raw)?.data(using: .utf8),
              let command = try? JSONDecoder().decode(MediatorCommand.self, from: data) else {
            throw BrainError.unparseable(utterance)
        }
        return command
    }

    /// Trims any stray text around the JSON object (grammar makes this rare).
    static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              start < end else { return nil }
        return String(text[start...end])
    }

    /// Lowercase, realistic few-shot examples (spike: uppercase placeholders made
    /// the tiny model uppercase targets). Keep short — it caches in the KV prefix.
    public static let defaultSystemPrompt = """
    You translate a single spoken workspace command into one JSON object matching the schema. \
    Output ONLY the JSON. Examples:
    ask ember to fix the build -> {"sendPrompt":{"target":"ember","text":"fix the build"}}
    start 4 claude agents -> {"spawnAgents":{"count":4,"kind":"claude"}}
    switch to research -> {"switchSpace":{"name":"research"}}
    close ember -> {"closeTerminal":{"target":"ember"}}
    read what slate is saying -> {"readOutput":{"target":"slate"}}
    tile the windows in a grid -> {"arrange":{"style":{"grid":{}}}}
    make a todo that says buy milk -> {"createCard":{"kind":"todo","content":"buy milk"}}
    """
}
```

```swift
// Sources/VoidloomCore/Mediator/TieredBrain.swift
import Foundation

/// Fast path first, LLM only on `.unparseable`. The spec's sanctioned layering:
/// deterministic `FastPathBrain` handles the common verb-first phrasings
/// instantly; anything it can't parse falls through to a grammar-constrained
/// LLM brain. Any non-`.unparseable` error from the fast path (there are none
/// today) propagates unchanged — only "I couldn't parse this" warrants the LLM.
public final class TieredBrain: MediatorBrain, @unchecked Sendable {
    private let fast: MediatorBrain
    private let fallback: MediatorBrain

    public init(fast: MediatorBrain, fallback: MediatorBrain) {
        self.fast = fast
        self.fallback = fallback
    }

    public func command(for utterance: String) async throws -> MediatorCommand {
        do {
            return try await fast.command(for: utterance)
        } catch BrainError.unparseable {
            return try await fallback.command(for: utterance)
        }
    }
}
```

```swift
// Sources/VoidloomCore/Mediator/MediatorTierResolver.swift
import Foundation

/// Which brain configuration to run, decided from runtime capability flags
/// (not per-OS at compile time). Pure decision logic — the App injects live
/// flags (model download state; later, Foundation Models availability).
/// v2b covers tier-2 only: FM resolution lands with the Apple-tier plan.
public enum MediatorTier: Equatable, Sendable {
    case fastPathOnly
    case fastPathWithLLM
}

public enum MediatorTierResolver {
    public struct Capabilities: Equatable, Sendable {
        public var commandModelReady: Bool
        public init(commandModelReady: Bool) { self.commandModelReady = commandModelReady }
    }

    public static func resolve(capabilities: Capabilities) -> MediatorTier {
        capabilities.commandModelReady ? .fastPathWithLLM : .fastPathOnly
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS — full suite green with the new brain/resolver tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomAI/Inference/LlamaBrain.swift Sources/VoidloomCore/Mediator/TieredBrain.swift Sources/VoidloomCore/Mediator/MediatorTierResolver.swift Tests/VoidloomTests/LlamaBrainTests.swift Tests/VoidloomTests/TieredBrainTests.swift Tests/VoidloomTests/MediatorTierResolverTests.swift
git commit -m "feat(ai): add LlamaBrain, TieredBrain fallback, and tier resolver"
```

---

### Task 7: App wiring + gated integration test + latency benchmark

Make the LLM tier real in the running app: resolve the tier from `ModelAssetManager`, build `TieredBrain(FastPathBrain, LlamaBrain(CllamaEngine))` when the model is ready, and add the two model-gated verifications. **Suggested tier: opus** (app lifecycle, gated integration harness).

**Files:**
- Create: `VoidloomApp/AI/Local/MediatorBrainFactory.swift` (app-side assembly)
- Modify: `VoidloomApp/App/VoidloomApp.swift` (own `ModelAssetManager`, pass to `RootThemeHost`/`RootView`)
- Modify: `VoidloomApp/Shell/RootView.swift` (build brain via factory + resolver)
- Create: `VoidloomAppTests/LlamaBrainIntegrationTests.swift` (Xcode test target, gated on the model file — also holds the latency benchmark, Step 4)
- Modify: `Voidloom.xcodeproj/project.pbxproj` (register the new app file; add the test target if absent)

**Interfaces:**
- Consumes: `ModelAssetManager`, `MediatorTierResolver`, `TieredBrain`, `LlamaBrain`, `CllamaEngine`, `FastPathBrain`, `CommandExecutor`.
- Produces: a running app whose mediator uses the LLM fallback once the command model is downloaded; a gated latency + correctness harness.

- [ ] **Step 1: Brain factory (app target)**

```swift
// VoidloomApp/AI/Local/MediatorBrainFactory.swift
import Foundation
import VoidloomAI
import VoidloomCore

/// Assembles the mediator brain for the current tier. Fast path always;
/// LLM fallback only when the command model is verified-ready on disk.
/// Engine loads lazily on first LLM use (cold Metal load ~0.66 s, narrated
/// as "warming up" by the HUD state), then stays resident.
@MainActor
enum MediatorBrainFactory {
    static func makeBrain(assets: ModelAssetManager) -> MediatorBrain {
        let fast = FastPathBrain()
        let tier = MediatorTierResolver.resolve(
            capabilities: .init(commandModelReady: assets.state(of: LocalModelManifest.commandModel) == .ready))
        switch tier {
        case .fastPathOnly:
            return fast
        case .fastPathWithLLM:
            let engine = LazyLoadingEngine(
                assets: assets,
                asset: LocalModelManifest.commandModel,
                config: .init(contextLength: 2048))
            return TieredBrain(fast: fast, fallback: LlamaBrain(engine: engine))
        }
    }
}

/// Loads the model on first `complete`/`stream`, throwing model-availability
/// BrainErrors surfaced distinctly by the coordinator (carry-over #3) if the
/// asset isn't ready. Keeps the engine resident afterward.
final class LazyLoadingEngine: LlamaEngine, @unchecked Sendable {
    private let underlying = CllamaEngine()
    private let assets: ModelAssetManager
    private let asset: LocalModelAsset
    private let config: LlamaEngine.Config
    private var loaded = false
    private let lock = NSLock()

    init(assets: ModelAssetManager, asset: LocalModelAsset, config: LlamaEngine.Config) {
        self.assets = assets; self.asset = asset; self.config = config
    }

    func load(modelPath: URL, config: LlamaEngine.Config) throws {
        try underlying.load(modelPath: modelPath, config: config)
    }
    func unload() { underlying.unload(); loaded = false }

    private func ensureLoaded() throws {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return }
        guard let url = MainActor.assumeIsolated({ assets.localURL(of: asset) }) else {
            throw BrainError.modelNotReady("Local model not downloaded — open Settings › Local AI.")
        }
        try underlying.load(modelPath: url, config: config)
        loaded = true
    }

    func complete(systemPrompt: String, userPrompt: String, grammar: String?, maxTokens: Int) throws -> String {
        try ensureLoaded()
        return try underlying.complete(systemPrompt: systemPrompt, userPrompt: userPrompt, grammar: grammar, maxTokens: maxTokens)
    }
    func stream(systemPrompt: String, userPrompt: String, onToken: @escaping (String) -> Bool) throws {
        try ensureLoaded()
        try underlying.stream(systemPrompt: systemPrompt, userPrompt: userPrompt, onToken: onToken)
    }
}
```

> `MainActor.assumeIsolated` is safe here: the mediator's brain calls originate on the coordinator's `@MainActor` parse task. If Swift 6 concurrency flags this, hoist `localURL` resolution into `makeBrain` and pass the URL down; keep the not-ready error path.

- [ ] **Step 2: Own the ModelAssetManager and thread it through**

In `VoidloomApp/App/VoidloomApp.swift`, add `@StateObject private var modelAssets = ModelAssetManager()` and pass it into `RootThemeHost` → `RootView` (mirror the existing `conversationStore` threading; add the `@ObservedObject var modelAssets: ModelAssetManager` property to `RootThemeHost` and forward it). Import `VoidloomAI`.

In `RootView.swift`, take `modelAssets` and build the brain via the factory:

```swift
    init(store: WorkspaceStore,
         sessionManager: AgentSessionManager,
         conversationStore: ConversationStore,
         interaction: CanvasInteractionModel,
         modelAssets: ModelAssetManager) {
        self.store = store
        self.sessionManager = sessionManager
        self.conversationStore = conversationStore
        self.interaction = interaction
        self.modelAssets = modelAssets
        _mediator = StateObject(wrappedValue: MediatorSessionCoordinator(
            brain: MediatorBrainFactory.makeBrain(assets: modelAssets),
            executor: CommandExecutor(store: store, terminals: sessionManager, namePool: AgentNamePool())))
    }
```

Add `@ObservedObject var modelAssets: ModelAssetManager` and `import VoidloomAI`. (The brain is resolved once at RootView init; re-resolving after a mid-session download is a documented Plan 3 refinement — for v2b, downloading the model then relaunching, or toggling mode, picks it up. Note this in the commit body.)

- [ ] **Step 3: Gated integration test (Xcode target)**

```swift
// VoidloomAppTests/LlamaBrainIntegrationTests.swift
import XCTest
import VoidloomAI
import VoidloomCore

/// Real inference against the vendored llama + Qwen3-0.6B. Skipped (not failed)
/// when the model isn't downloaded, so CI without the 397 MB asset stays green.
final class LlamaBrainIntegrationTests: XCTestCase {
    private func modelURLOrSkip() throws -> URL {
        let assets = ModelAssetManager()
        guard let url = MainActor.assumeIsolated({ assets.localURL(of: LocalModelManifest.commandModel) }) else {
            throw XCTSkip("Command model not downloaded — run the app's Settings › Local AI download, then re-run.")
        }
        return url
    }

    func testGoldenUtterancesProduceSchemaValidCommands() throws {
        let url = try modelURLOrSkip()
        let engine = CllamaEngine()
        try engine.load(modelPath: url, config: .init(contextLength: 2048))
        defer { engine.unload() }
        let brain = LlamaBrain(engine: engine)

        let golden: [(String, (MediatorCommand) -> Bool)] = [
            ("start 4 claude agents", { if case .spawnAgents(4, .claudeCode, _) = $0 { return true }; return false }),
            ("switch to research", { $0 == .switchSpace(name: "research") }),
            ("close ember", { $0 == .closeTerminal(target: "ember") }),
            ("tile the windows in a grid", { $0 == .arrange(style: .grid) }),
        ]
        let exp = expectation(description: "golden")
        Task {
            for (utterance, check) in golden {
                let cmd = try await brain.command(for: utterance)
                XCTAssertTrue(check(cmd), "\(utterance) -> \(cmd)")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 30)
    }
}
```

> If no Xcode unit-test target exists yet, add one (`VoidloomAppTests`) via the pbxproj, or run this file through the `scripts/` benchmark below. The gate (`XCTSkip`) is the load-bearing part.

- [ ] **Step 4: Latency benchmark (gated, same Xcode test target as Step 3)**

A standalone `swift scripts/*.swift` file can't easily link `Cllama` (its module map is scoped to the app target's `SWIFT_INCLUDE_PATHS`/`HEADER_SEARCH_PATHS`, set up in Task 5 Step 4) — so this lives as a second XCTest method in the same gated `VoidloomAppTests/LlamaBrainIntegrationTests.swift`, where `CllamaEngine`/`LlamaBrain` are already buildable. It reuses the spike's own methodology: one throwaway call to pay the cold-load/first-eval cost, then measure a genuinely warm call against the spec's ≤1 s bar (spike warm: 0.15–0.26 s).

```swift
    /// Warm end-of-utterance -> command-dispatch latency against the spec's
    /// ≤1s bar (spike-measured warm: 0.15-0.26s). The first call pays the cold
    /// Metal-load + first-eval cost (spike: ~0.66s + ~0.35s) and is discarded;
    /// only the second call is measured.
    func testWarmDispatchMeetsTheOneSecondBar() throws {
        let url = try modelURLOrSkip()
        let engine = CllamaEngine()
        try engine.load(modelPath: url, config: .init(contextLength: 2048))
        defer { engine.unload() }
        let brain = LlamaBrain(engine: engine)

        let warmUp = expectation(description: "warm-up")
        Task { _ = try? await brain.command(for: "start 2 claude agents"); warmUp.fulfill() }
        wait(for: [warmUp], timeout: 30)

        let start = DispatchTime.now()
        let measured = expectation(description: "measured")
        Task { _ = try? await brain.command(for: "ask ember to fix the build"); measured.fulfill() }
        wait(for: [measured], timeout: 10)
        let elapsedSeconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        print("LlamaBrain warm dispatch: \(elapsedSeconds)s")
        XCTAssertLessThan(elapsedSeconds, 1.0, "warm end-of-speech->dispatch exceeded the spec's ≤1s bar")
    }
```

> Not a CI perf gate (real-hardware timing varies) — its job is a fast, repeatable, human-run confirmation that the ≤1 s bar still holds after any llama.cpp tag bump or prompt change, using the exact same brain the app runs, not a hand-maintained shell script that can drift from it.

- [ ] **Step 5: Register files + verify**

Register `MediatorBrainFactory.swift` (and the test file if adding the test target) in the pbxproj per the four-entry convention. Then:

```bash
swift test                                                          # unchanged Core/AI suite green
xcodebuild -scheme Voidloom -destination 'platform=macOS' build     # app builds with the wired brain
```
Expected: both green. The integration test skips unless the model is present.

- [ ] **Step 6: Commit**

```bash
git add VoidloomApp Voidloom.xcodeproj/project.pbxproj VoidloomAppTests 2>/dev/null; git add -A
git commit -m "feat(ai): wire LLM tier into the app via ModelAssetManager + gated integration harness"
```

---

### Task 8: LocalResponseProvider (optional Qwen3-1.7B chat) + ConversationStore wiring

Give chat cards a real local responder — a **separate, larger** model, never the 0.6B command model. Falls back to the stub when the chat model isn't downloaded. **Suggested tier: opus** (streaming marshalling, preemption, off-main-actor inference).

**Files:**
- Modify: `Sources/VoidloomAI/Models/LocalModelManifest.swift` (add `chatModel`)
- Create: `Sources/VoidloomAI/Inference/LocalResponseProvider.swift`
- Create: `Tests/VoidloomTests/LocalResponseProviderTests.swift`
- Modify: `VoidloomApp/AI/ConversationStore.swift` (accept an injected provider; default stub)
- Modify: `VoidloomApp/App/VoidloomApp.swift` (build the provider from the chat model if ready, else stub)

**Interfaces:**
- Consumes: `LlamaEngine`, `ResponseProvider`, `ModelAssetManager`, `LocalModelManifest`.
- Produces: `LocalModelManifest.chatModel` and `LocalResponseProvider: ResponseProvider`. Mediator command parsing never touches this.

- [ ] **Step 1: Pin the chat model**

Revision and SHA256 were verified live against Hugging Face's tree API while writing this plan (raw JSON via `curl`, not a summarized/paraphrased form — a wrong pinned hash is a correctness/security failure):

```bash
curl -s "https://huggingface.co/api/models/unsloth/Qwen3-1.7B-GGUF/tree/main" \
  | python3 -c "import json,sys; [print(json.dumps(i, indent=2)) for i in json.load(sys.stdin) if 'Q4_K_M' in i.get('path','')]"
# -> path: Qwen3-1.7B-Q4_K_M.gguf, size: 1107409472,
#    lfs.oid (sha256): b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897
curl -s "https://huggingface.co/api/models/unsloth/Qwen3-1.7B-GGUF" | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])"
# -> d7f544eead698dbd1f15126ef60b45a1e1933222
```

Add to `LocalModelManifest`:

```swift
    /// OPTIONAL chat responder. Larger than the command model — the 0.6B model
    /// is banned from chat (spike: it called a PTY "Public Trust"). Without this
    /// asset, chat stays on the stub. Revision + SHA256 verified live against
    /// Hugging Face's tree API on 2026-07-02 (see this plan's Global Constraints
    /// pinned-artifacts table) — re-verify before ever changing this constant.
    public static let chatModel = LocalModelAsset(
        id: "qwen3-1.7b-q4km",
        filename: "Qwen3-1.7B-Q4_K_M.gguf",
        url: URL(string: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/d7f544eead698dbd1f15126ef60b45a1e1933222/Qwen3-1.7B-Q4_K_M.gguf")!,
        sha256: "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897",
        sizeBytes: 1_107_409_472,
        license: "Apache-2.0",
        displayName: "Qwen3 1.7B (chat)")
```

Add a test to `ModelAssetManagerTests.swift` (Task 4) pinning this constant the same way `testManifestPinsTheCommandModelFromTheSpike` pins the command model, so a future accidental edit is caught:

```swift
    func testManifestPinsTheChatModelVerifiedAgainstHuggingFace() {
        let m = LocalModelManifest.chatModel
        XCTAssertEqual(m.sha256, "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897")
        XCTAssertEqual(m.sizeBytes, 1_107_409_472)
        XCTAssertEqual(m.license, "Apache-2.0")
    }
```

- [ ] **Step 2: Write the failing test**

```swift
// Tests/VoidloomTests/LocalResponseProviderTests.swift
import XCTest
@testable import VoidloomAI
@testable import VoidloomCore

private final class StreamingFakeEngine: LlamaEngine, @unchecked Sendable {
    let tokens: [String]
    init(tokens: [String]) { self.tokens = tokens }
    func load(modelPath: URL, config: LlamaEngine.Config) throws {}
    func unload() {}
    func complete(systemPrompt: String, userPrompt: String, grammar: String?, maxTokens: Int) throws -> String { tokens.joined() }
    func stream(systemPrompt: String, userPrompt: String, onToken: @escaping (String) -> Bool) throws {
        for t in tokens where onToken(t) {}
    }
}

@MainActor
final class LocalResponseProviderTests: XCTestCase {
    func testStreamsChunksThenCompletes() async {
        let provider = LocalResponseProvider(engine: StreamingFakeEngine(tokens: ["Hel", "lo", "!"]), systemPrompt: "")
        var chunks: [String] = []; var final = ""
        let done = expectation(description: "done")
        provider.generateResponse(workspaceID: UUID(), userMessage: "hi", context: nil,
            onStreamChunk: { chunks.append($0) },
            onComplete: { final = $0; done.fulfill() },
            onError: { _ in XCTFail() })
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(chunks, ["Hel", "lo", "!"])
        XCTAssertEqual(final, "Hello!")
    }
}
```

- [ ] **Step 3: Implement**

```swift
// Sources/VoidloomAI/Inference/LocalResponseProvider.swift
import Foundation
import VoidloomCore

/// Chat responder backed by a LARGER local model (Qwen3-1.7B), never the 0.6B
/// command model. Inference hops off the main actor; stream/complete/error
/// callbacks marshal back to @MainActor per the `ResponseProvider` contract.
/// The App only constructs this when the chat model is verified-ready; otherwise
/// chat stays on `StubResponseProvider`.
public final class LocalResponseProvider: ResponseProvider, @unchecked Sendable {
    private let engine: LlamaEngine
    private let systemPrompt: String

    public init(engine: LlamaEngine, systemPrompt: String = LocalResponseProvider.defaultSystemPrompt) {
        self.engine = engine
        self.systemPrompt = systemPrompt
    }

    @MainActor
    public func generateResponse(workspaceID: UUID, userMessage: String, context: String?,
                                 onStreamChunk: @escaping (String) -> Void,
                                 onComplete: @escaping (String) -> Void,
                                 onError: @escaping (String) -> Void) {
        let prompt = context.flatMap { $0.isEmpty ? nil : "Context:\n\($0)\n\n\(userMessage)" } ?? userMessage
        let engine = self.engine
        let system = self.systemPrompt
        Task.detached(priority: .userInitiated) {
            var full = ""
            do {
                try engine.stream(systemPrompt: system, userPrompt: prompt) { token in
                    full += token
                    Task { @MainActor in onStreamChunk(token) }
                    return !Task.isCancelled
                }
                let final = full
                await MainActor.run { onComplete(final) }
            } catch {
                await MainActor.run { onError("The local model failed to respond.") }
            }
        }
    }

    public static let defaultSystemPrompt =
        "You are a concise, helpful assistant embedded in a macOS canvas app. Answer directly."
}
```

Wire injection in `ConversationStore.swift` — the initializer already accepts a `ResponseProvider = StubResponseProvider()`; no signature change needed.

`VoidloomApp.swift` MUST use exactly ONE `ModelAssetManager` instance for the whole app — the same one Task 7 introduced as `modelAssets` and threads into `RootView`. `conversationStore`'s initial value now depends on that instance's state, and a `@StateObject`'s declaration-level default expression cannot see a sibling stored property, so this requires promoting `VoidloomApp` to an explicit `init()` (replacing Task 7 Step 2's plain `@StateObject private var modelAssets = ModelAssetManager()` declaration with the version below — `store`/`agentSessionManager`/`interaction` keep their existing declaration-level defaults untouched, since a custom `init()` only needs to explicitly assign the properties it actually depends on):

```swift
@main
@MainActor
struct VoidloomApp: App {
    @StateObject private var store = WorkspaceStore()
    @StateObject private var agentSessionManager = AgentSessionManager()
    @StateObject private var interaction = CanvasInteractionModel()
    @StateObject private var modelAssets: ModelAssetManager
    @StateObject private var conversationStore: ConversationStore

    init() {
        let assets = ModelAssetManager()   // the ONLY ModelAssetManager instance in the app
        _modelAssets = StateObject(wrappedValue: assets)

        if assets.state(of: LocalModelManifest.chatModel) == .ready,
           let url = assets.localURL(of: LocalModelManifest.chatModel) {
            let engine = CllamaEngine()
            try? engine.load(modelPath: url, config: .init(contextLength: 4096))
            _conversationStore = StateObject(wrappedValue: ConversationStore(provider: LocalResponseProvider(engine: engine)))
        } else {
            _conversationStore = StateObject(wrappedValue: ConversationStore())   // stub fallback, unchanged
        }
    }

    var body: some Scene { /* unchanged from Task 7 — RootThemeHost still takes modelAssets, conversationStore, etc. */ }
}
```

> Preemption (spec policy): a full mediator-preempts-chat implementation (cancel in-flight chat generation, mark failed with retry via `ConversationReducer.failing`) is wired where the coordinator begins executing a command. For v2b, the minimum is: `LocalResponseProvider` honors `Task.isCancelled` in its stream loop (done above), and the coordinator cancels the chat task on command dispatch. If the single-shared-engine contention proves racy, serialize chat behind an actor — note as a Plan 3 refinement.

- [ ] **Step 4: Run tests + build**

```bash
swift test --filter LocalResponseProviderTests
swift test
xcodebuild -scheme Voidloom -destination 'platform=macOS' build
```
Expected: green.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoidloomAI VoidloomApp/AI Tests/VoidloomTests/LocalResponseProviderTests.swift VoidloomApp/App/VoidloomApp.swift
git commit -m "feat(ai): add LocalResponseProvider chat backend behind optional Qwen3-1.7B model"
```

---

### Task 9: Settings "Local AI" real model management UI

Turn the placeholder status line into real model management: per-asset download buttons, progress, licenses, and tier status. **Suggested tier: sonnet** (SwiftUI Form section against a done `ModelAssetManager`).

**Files:**
- Create: `VoidloomApp/Shell/LocalAISettingsSection.swift`
- Modify: `VoidloomApp/Shell/SettingsView.swift` (replace the `Section("Local AI")` body)
- Modify: `VoidloomApp/App/VoidloomApp.swift` (inject the shared `ModelAssetManager` into the Settings scene)
- Modify: `Voidloom.xcodeproj/project.pbxproj` (register the new file)

**Interfaces:**
- Consumes: `ModelAssetManager` (`state(of:)`, `download`, `cancel`, `verifyExisting`), `LocalModelManifest.commandModel`/`.chatModel`, `MediatorTierResolver`.
- Produces: user-visible model management. UI verified by build + manual QA.

- [ ] **Step 1: Build the section view**

```swift
// VoidloomApp/Shell/LocalAISettingsSection.swift
import SwiftUI
import VoidloomAI
import VoidloomCore

/// Real "Local AI" management: tier status, per-model download/verify with
/// progress, and license attribution. Drives `ModelAssetManager`; no inference here.
struct LocalAISettingsSection: View {
    @ObservedObject var assets: ModelAssetManager

    private var tier: MediatorTier {
        MediatorTierResolver.resolve(
            capabilities: .init(commandModelReady: assets.state(of: LocalModelManifest.commandModel) == .ready))
    }

    var body: some View {
        Section("Local AI") {
            LabeledContent("Mediator", value: tier == .fastPathWithLLM
                ? "Fast parser + local LLM"
                : "Fast parser only (download the command model for natural phrasing)")
            Text("Voidloom's AI runs entirely on this Mac — no endpoints, no API keys.")
                .font(.callout).foregroundStyle(.secondary)

            modelRow(LocalModelManifest.commandModel, subtitle: "Required for natural-language commands.")
            modelRow(LocalModelManifest.chatModel, subtitle: "Optional. Enables local chat replies; without it, chat uses placeholder responses.")
        }
        .task { _ = await assets.verifyExisting(LocalModelManifest.commandModel)
                _ = await assets.verifyExisting(LocalModelManifest.chatModel) }
    }

    @ViewBuilder
    private func modelRow(_ asset: LocalModelAsset, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.displayName).font(.body)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    Text("License: \(asset.license) · \(ByteCountFormatter.string(fromByteCount: asset.sizeBytes, countStyle: .file))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                control(for: asset)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func control(for asset: LocalModelAsset) -> some View {
        switch assets.state(of: asset) {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .downloading(let p):
            HStack(spacing: 8) {
                ProgressView(value: p).frame(width: 80)
                Button("Cancel") { assets.cancel(asset) }
            }
        case .verifying:
            ProgressView().controlSize(.small)
        case .failed(let reason):
            VStack(alignment: .trailing) {
                Button("Retry") { Task { try? await assets.download(asset) } }
                Text(reason).font(.caption2).foregroundStyle(.red)
            }
        case .missing:
            Button("Download") { Task { try? await assets.download(asset) } }
        }
    }
}
```

- [ ] **Step 2: Use it in SettingsView**

In `SettingsView.swift`, the AI tab needs the shared `ModelAssetManager`. Add `@EnvironmentObject var modelAssets: ModelAssetManager` (or pass it in), and replace the `Section("Local AI") { … }` block with:

```swift
            LocalAISettingsSection(assets: modelAssets)
```

In `VoidloomApp.swift`, inject it into the Settings scene:

```swift
        Settings {
            SettingsView()
                .environmentObject(modelAssets)
        }
```

(`modelAssets` is the shared `@StateObject` added in Task 7. Confirm the AI tab reads it via `@EnvironmentObject`.)

- [ ] **Step 3: Register the new file**

Register `LocalAISettingsSection.swift` in `Voidloom.xcodeproj/project.pbxproj` per the four-entry convention (grep for fresh unique `A2…` IDs first).

- [ ] **Step 4: Verify**

```bash
swift test                                                          # unchanged green
xcodebuild -scheme Voidloom -destination 'platform=macOS' build     # app builds
```

- [ ] **Step 5: Commit**

```bash
git add VoidloomApp/Shell/LocalAISettingsSection.swift VoidloomApp/Shell/SettingsView.swift VoidloomApp/App/VoidloomApp.swift Voidloom.xcodeproj/project.pbxproj
git commit -m "feat(settings): real Local AI model management — download, progress, licenses, tier"
```

---

## Manual QA script (post-plan, user-run — launch the freshly built .app, not a stale binary)

Prereq: run `./scripts/build-llama-xcframework.sh` once (produces `Frameworks/llama.xcframework`).

1. **Fast path unchanged:** type "start 2 claude agents" → two agent cards (ember, slate) spawn; narration confirms. (No model needed.)
2. **Model download:** Settings › AI → "Qwen3 0.6B (command parser)" shows Download; click it → progress bar → Ready. License "Apache-2.0" and size shown.
3. **LLM fallback:** relaunch the app (brain re-resolves). Type a phrasing the fast path can't handle, e.g. "could you please spin up a couple of coding agents for me" → spawns 2 claude agents via the LLM. Warm response feels instant (<1 s).
4. **Distinct not-ready error:** with the model deleted (or before download), a non-fast-path utterance → HUD says "Local model not downloaded — open Settings › Local AI." (not the generic rephrase).
5. **Busy affordance:** type a hard utterance, then immediately type another → input field shows busy; the second runs after the first (queue depth 1).
6. **Cancel during parse:** trigger a slow parse and press Cancel → returns to idle, no stray narration later.
7. **Chat (optional):** download "Qwen3 1.7B (chat)"; relaunch; open a chat card → replies stream from the local model. Delete it → chat falls back to the placeholder stub with the Settings explanation intact.
8. **Checksum safety:** (dev) corrupt a downloaded .gguf on disk, reopen Settings → verifyExisting flips it to missing/failed rather than loading a bad file.
9. Full `swift test` green; `xcodebuild … build` SUCCEEDED.

## Deferred to Plan 3 / 4 (not in this document)

- **Voice** (Plan 3): `AudioCaptureService`, wake-word KWS, ASR transcribers, `transcriptDelta` rename, voice "confirm/cancel", the `wakeArmed` state, voice-reachable `cancel()`.
- **Apple tier** (Plan 4): `FoundationModelsBrain` + `@Generable` mirror types + the VoidloomAI↔Core parity test; `MediatorTierResolver` gains FM-availability capability flags (this plan's resolver is tier-2 only).
- **Mid-session tier re-resolution:** rebuilding the live brain when a download completes without relaunch (v2b resolves at RootView init).
- **Full chat preemption polish:** actor-serialized single-engine sharing between chat and mediator if contention appears (Task 8's note); Settings' "unload models when idle" escape hatch for 8 GB machines (spec-mentioned, not built here).
- **Persistent KV-prefix caching:** `CllamaEngine` re-evaluates the system prompt each call rather than tracking a persistent KV position across calls. The spike's own *cold*, uncached figure (0.351s) already clears the ≤1s bar, and manual KV-position bookkeeping is a common source of llama.cpp integration bugs — revisit only if Task 7's benchmark shows insufficient headroom once ASR (Plan 3) latency stacks on top.

## Self-review

- **Spec coverage:** grammar-constrained tier-2 brain (Tasks 3, 6), pinned-manifest/resumable/checksummed model downloads with license strings (Task 4), mandatory `n_ctx` cap honored in `LlamaEngine.Config`/`CllamaEngine` (Task 5), fast-path-first layering via `TieredBrain` (Task 6), optional larger chat model with the 0.6B model explicitly banned from chat (Task 8), real Settings model management (Task 9).
- **Carry-overs, one-to-one:** #4 `.agentKind` and #5 the shell-name kind-flip fix → Task 1, each with a regression test guarding the case the fix must not break. #1 cancel-during-parsing, #2 busy affordance (implemented as a real depth-1 queue, a stronger reading than a bare "show busy"), #3 distinct `parseFailed` payload → Task 2, exercised against a genuinely cancellable/hangable `ControllableBrain` rather than only the instant `FastPathBrain`. #6 Settings real model management → Task 9. Prework's independently-parked `WorkspaceStore` placement-block fold is explicitly left untouched (noted in Global Constraints), not silently dropped.
- **Placeholder scan (this review pass):** found and fixed two real gaps — Task 8's chat-model pin previously left `<REV>`/`<SHA256>`/`<SIZE>` for the implementer to resolve manually (now filled with values verified live against Hugging Face's raw tree-API JSON: `unsloth/Qwen3-1.7B-GGUF` @ `d7f544eead698dbd1f15126ef60b45a1e1933222`, `Qwen3-1.7B-Q4_K_M.gguf`, 1,107,409,472 bytes, SHA256 `b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897`); and Task 7's latency "benchmark" previously only printed a pointer to a spike scratch file not in the repo tree (now a real XCTest that loads the model, warms up, measures a second call, and asserts against the ≤1s bar). No other `TODO`/`TBD`/unresolved-value placeholders found across Tasks 1–9.
- **Type consistency:** signatures referenced against the real source at review time (`MediatorBrain.command(for:)`, `MediatorCommandSchema.Case`/`.Parameter`/`.samples`, `BrainError`, `CommandExecutor.init(store:terminals:namePool:)`, `MediatorSessionCoordinator.init(brain:executor:timeoutScale:)`, `ResponseProvider.generateResponse(...)`, `CardKind: CaseIterable`) all match `Sources/VoidloomCore/Mediator/*.swift` and `Sources/VoidloomCore/Chat/ChatModels.swift` as they exist on this branch.
- **Module layout risk called out, not hidden:** Task 5's `CllamaEngine` C-interop code is explicitly flagged as unverified against the pinned tag's exact `llama.h` symbol names (a fast-moving C library can't be guaranteed correct from a plan document); the mitigation is an actionable grep-and-fix instruction plus Task 7's gated integration test as the real correctness oracle, not a false-confidence claim.
- **Full chat preemption polish:** actor-serialized single-engine sharing between chat and mediator if contention appears.
- **Prework #6:** the `WorkspaceStore` center/cascade placement-block fold — still parked.
- **Model hosting decision:** HF pinned-revision URLs are used here; a GitHub release mirror remains an option if HF rate-limits.
</content>
</invoke>
