# Local AI Mediator — Plan 4: Apple Intelligence tier (macOS 26)

> **Workflow:** lead coordinates + reviews; each task implemented by a fresh `cursor-agent --yolo --model composer-2.5`. Sequential, one commit per task (+fixes).
>
> **Grounding (binding):**
> - This machine runs macOS 26 with Apple Intelligence — real runs are possible, but ALL Apple-tier code is `#available(macOS 26, *)`-gated AND checks `SystemLanguageModel.default.availability` at RUNTIME (Apple Intelligence can be disabled/undownloaded on macOS 26; device eligibility varies). Unavailable → the existing llama/fast-path tiers, never an error.
> - App floor stays macOS 14: nothing in this plan may raise any deployment target. FoundationModels / Speech(Analyzer) imports live ONLY in the app target (`VoidloomApp/AI/Apple/`), same isolation discipline as llama and FluidAudio. Core/`VoidloomAI` gain only pure logic.
> - `MediatorCommand` lives in Core, which cannot import FoundationModels — so tier-1 tool/guided types are MIRROR `@Generable` structs in the app layer, and drift is prevented BY TESTS (spec's "tests, not construction" rule): a parity test asserts every mirror ↔ enum case in both directions, mirroring the GBNF freeze approach.
> - Quality ladder for chat: Foundation Models (best) > Qwen3-1.7B > stub. Command parsing default: measure before choosing — the spec explicitly suspects FM guided generation (~3B + tool schema) may be SLOWER than the grammar-constrained 0.6B llama path (spike: warm 0.15–0.26s). The benchmark decides the default; both paths remain selectable.

## Existing seams (do not re-invent)

- `MediatorBrain` (Core): `command(for:) async throws -> MediatorCommand`; `BrainError` taxonomy incl. `.backendFailure`; `TieredBrain(fast:fallback:)`.
- `MediatorTierResolver` (Core): `Capabilities(commandModelReady:)` → `.fastPathOnly | .fastPathWithLLM` — this plan EXTENDS it.
- `MediatorBrainFactory` (app, `VoidloomApp/AI/Local/MediatorBrainFactory.swift`): builds the brain at launch from asset state — this plan extends its branching.
- `SpeechTranscribing`/`TranscriberEvent` (Core) + `ParakeetTranscriber` (app) + `RootView` voice wiring with `voice.mode`/`voice.wakePhrase` AppStorage.
- `LocalResponseProvider` (VoidloomAI) for 1.7B chat; `ConversationStore(provider:)` selection in `VoidloomApp.init`.
- `MediatorCommandSchema` (Core): frozen case/parameter descriptors + samples — the parity test's source of truth.

---

## Task 1 — Core tier matrix (headless)

**Modify:** `Sources/VoidloomCore/Mediator/MediatorTierResolver.swift`; tests append to `Tests/VoidloomTests/MediatorTierResolverTests.swift`.

- `Capabilities` gains `foundationModelsAvailable: Bool` (default `false` in a new init overload so ALL existing call sites compile unchanged — keep the old `init(commandModelReady:)`).
- `MediatorTier` gains `.appleFoundationModels`. Matrix: FM available → `.appleFoundationModels`; else command model ready → `.fastPathWithLLM`; else `.fastPathOnly`.
- Tests: all four capability combinations.

**Acceptance:** full `swift test` green (245 baseline + new); Core imports unchanged.

## Task 2 — FoundationModelsBrain + @Generable mirrors + parity tests

**Create:** `VoidloomApp/AI/Apple/FoundationModelsBrain.swift`, `VoidloomApp/AI/Apple/MediatorToolMirrors.swift`; gated tests in `VoidloomAppTests/FoundationModelsParityTests.swift` (+ registration).

- Everything wrapped in `#available(macOS 26, *)` (files compile on the macOS 14 floor via availability annotations on the types).
- `MediatorToolMirrors`: one `@Generable` struct per `MediatorCommand` case (field names/types matching the frozen wire schema, incl. `agentKind` constrained via `@Guide` to `MediatorCommandSchema.agentKindValues` where the macro supports it), plus a top-level generable "one of" command container per FoundationModels idiom (guided generation of a single command). Each mirror has `toCommand() -> MediatorCommand`.
- `FoundationModelsBrain: MediatorBrain`: checks `SystemLanguageModel.default.availability` (unavailable → throw `BrainError.modelNotReady(<reason string from the availability case>)`); pre-warmed `LanguageModelSession` with a short system prompt (reuse LlamaBrain's few-shot examples); `respond(generating:)` guided generation → mirror → `toCommand()`; errors → `.backendFailure`, content-policy/guardrail refusals → `.unparseable(utterance)` (so the HUD says "didn't catch that", not a scary backend error).
- **Adapt to the REAL macOS 26 FoundationModels API on this machine** (inspect the SDK: `swift-ide` not needed — check `xcrun --show-sdk-path` headers/swiftinterface for FoundationModels; the exact spellings of `@Generable`, `@Guide`, `LanguageModelSession.respond(to:generating:)`, `SystemLanguageModel.default.availability` MUST be verified, not recalled). List every drift adaptation in the report.
- Parity tests (VoidloomAppTests, `XCTSkip` unless macOS 26 + FM available): (a) every `MediatorCommandSchema.cases` name has a mirror and vice versa (this half must run even WITHOUT FM availability — it's pure reflection over the mirror registry; only live-generation tests skip); (b) each mirror's `toCommand()` output round-trips through the frozen Codable samples' shapes; (c) ONE live guided-generation smoke test ("switch to research") when FM is actually available.

**Acceptance:** `swift test` untouched-green; `xcodebuild build` + `xcodebuild -only-testing:VoidloomAppTests test` green (skips where gated). Report documents SDK API drift.

## Task 3 — Factory/tier integration + SpeechAnalyzer transcriber + benchmark + Settings copy

**Modify:** `MediatorBrainFactory`, `RootView` (transcriber choice), `LocalAISettingsSection`/`VoiceSettingsSection` (tier copy), `VoidloomApp.init` (chat ladder). **Create:** `VoidloomApp/AI/Apple/SpeechAnalyzerTranscriber.swift`, benchmark test in `VoidloomAppTests`.

- Factory: resolve with `foundationModelsAvailable` (runtime check, macOS-26-gated); `.appleFoundationModels` → `TieredBrain(fast: FastPathBrain(), fallback: FoundationModelsBrain())`. A user-facing default override lives in Settings ("Prefer Apple Intelligence when available" toggle, default ON pending benchmark) so the llama path stays reachable on macOS 26.
- Chat ladder in `VoidloomApp.init`: FM available → an FM-backed `ResponseProvider` (simple streaming session per workspace, same cancellation semantics as `LocalResponseProvider` — new small provider in `VoidloomApp/AI/Apple/`); else 1.7B; else stub.
- `SpeechAnalyzerTranscriber: SpeechTranscribing` (macOS 26): volatile results → `.partial`, finalized → `.final`, asset-pending → `.unavailable`; `RootView` picks it over Parakeet when available (Parakeet stays the fallback — and the wake-phrase/continuous mode must keep working with whichever transcriber is active; if SpeechAnalyzer continuous mode is materially harder, keep Parakeet for always-listening and use SpeechAnalyzer for PTT only — document the choice).
- Benchmark (gated app test): warm end-of-utterance→command latency, FM vs llama (when both available), printed + asserted ≤1s each; report records which default the numbers justify.
- Settings: tier status line reflects "Apple Intelligence" when active; voice section notes which engine is in use.

**Acceptance:** `swift test` green; `xcodebuild build` green; gated app tests pass/skip cleanly; manual QA checklist in the report.

## Deferred (not in this plan)

Mid-session tier re-resolution (still launch-time); FM tool-calling (guided generation of the command container is sufficient v1); non-English; visionOS/iOS.

## Closeout (after Task 3)

Lead reviews each diff; then: cross-plan final verification (full suite + build + gated tests), ledger, docs commit (`git add -f` plans 3+4 + remaining-work update), memory update, and the completion report to the user.
