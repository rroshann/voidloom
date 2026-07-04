# Local AI Mediator — Remaining Work (as of 2026-07-03, HEAD `7df32db`)

> Status snapshot: Plans 1, 2 complete. Plan 2b tasks 1–7 of 9 complete (230/230 tests, app builds, llama vendored + wired). Everything below is NOT yet started unless marked otherwise.
>
> **Workflow in effect (user directive):** lead session plans + personally reviews; a fresh `cursor-agent --yolo --model composer-2.5` in an Orca terminal implements each task; sequential; one agent per task, closed after approval. Resume mechanics: the `RESUME HERE` block + trailing task lines in `.superpowers/sdd/progress.md`.

---

## 1. Plan 2b — Task 8: Local chat (`LocalResponseProvider` + optional Qwen3-1.7B)

**What:** Give the existing chat cards a real local backend, without ever letting the 0.6B command model answer chat (it hallucinates — spike-verified ban).

**Source of exact steps:** `docs/superpowers/plans/2026-07-02-local-ai-mediator-plan2b-llm-brain.md` § Task 8 (lines ~1772+), already critic-patched to thread ONE shared `ModelAssetManager` (the `@StateObject` added in Task 7 — no second instance anywhere).

**Pieces:**
- `LocalResponseProvider: ResponseProvider` (protocol at `Sources/VoidloomCore/Chat/ChatModels.swift:70` — `@MainActor generateResponse(workspaceID:userMessage:context:onStreamChunk:onComplete:onError:)`). Streams tokens from the engine off the main actor, marshals callbacks back.
- Chat model asset: Qwen3-1.7B GGUF, pinned `unsloth/Qwen3-1.7B-GGUF @ d7f544eead698dbd1f15126ef60b45a1e1933222`, SHA256 `b139949c…81897` (full value in the plan), ~1.1GB, Apache-2.0. Manifest entry `LocalModelManifest.chatModel` (the manifest structure from Task 4 already supports it).
- Wiring in `VoidloomApp.swift`: `ConversationStore(provider:)` gets `LocalResponseProvider` when the chat asset is `.ready`, else keeps `StubResponseProvider` (`ConversationStore.init(provider: ResponseProvider = StubResponseProvider())` — no signature change).
- **Spec obligation (concurrency policy, spec § brain concurrency):** the mediator preempts chat — an in-flight chat generation is cancelled (message marked failed with retry via the existing `ConversationReducer.failing`/`resettingToPending`); chat requests queue behind an executing voice/typed command. Chat and command models are separate engine instances, so "preemption" here means: don't let a chat stream starve the command path; implement the cancel path at minimum.
- **Interface drift to carry into the cursor notes file (same as Tasks 6/7):** top-level `LlamaEngineConfig`; `import llama` app-target-only; engine stateless-per-call; SPM layers stay llama-free; `LazyLoadingEngine` (Task 7, `VoidloomApp/AI/Local/MediatorBrainFactory.swift`) is reusable for the chat engine — model URL resolved on the MainActor at wiring time, never from a background thread.

**Acceptance:** unit tests for the provider against a fake engine (stream chunks → onStreamChunk order, error → onError with failed-message reducer path, cancel mid-stream); full `swift test` green; `xcodebuild` BUILD SUCCEEDED; chat card manually answers only when the 1.7B model is downloaded, stub otherwise. Suggested tier: complex (careful with actor hops + cancellation).

## 2. Plan 2b — Task 9: Settings "Local AI" model management UI

**What:** Replace the static "Local AI" section in `VoidloomApp/Shell/SettingsView.swift` with real management: per-model rows (command 0.6B, chat 1.7B) with state (missing/downloading %/verifying/ready/failed), Download/Cancel buttons, sizes, license attributions (Apache-2.0), and a tier-status line ("Fast path only" / "Fast path + local LLM" / "+ local chat"), plus the relaunch note (brain re-resolves at launch — Task 7's documented limitation).

**Source:** plan § Task 9 (lines ~1967+). Uses ONLY the shared `ModelAssetManager` instance (threaded from `VoidloomApp.swift`; `SettingsView` currently constructs nothing — it will need the instance passed in or injected via environment; the plan shows the pattern).

**Acceptance:** build green; suite green (UI is build+manual-QA per project convention); downloading a model from Settings actually produces progress and lands `.ready` (manual QA — real 397MB/1.1GB downloads); cancel works mid-download (Task 4's clean-cancel semantics are already tested). Suggested tier: simple.

## 3. Plan 2b — closeout

1. **Whole-branch review** of `6542a5e..HEAD` (all 9 tasks + fixes) — lead-run under the current workflow. Feed it the deferred-Minors list (§6 below) for triage.
2. **Fix wave** for anything Critical/Important it finds.
3. **Manual QA script** (plan's § Manual QA): download command model in Settings → relaunch → type an utterance FastPathBrain can't parse (e.g. "get ember looking at those api errors from earlier") → verify the LLM parses it and the command executes; verify "model downloading (N%)" narration mid-download; run the gated integration tests once the model exists (`xcodebuild -only-testing:VoidloomAppTests test` — golden utterances + ≤1s warm-latency bar).
4. **Commit the docs** (`git add -f docs/superpowers/plans/2026-07-02-local-ai-mediator-plan2b-llm-brain.md docs/superpowers/plans/2026-07-03-remaining-work.md` + this file's future updates — `docs/` is gitignored, force-add is the established pattern).
5. Ledger + project-memory update.

## 4. Plan 3 — Voice (plan NOT yet written)

**Author the plan first** (same critic-gate as 2b). Ground it in `.omc/research/spike-voice.md` + `.omc/handoffs/spike-voice.md`. Locked adjudications:

- **Wake word v1 = NO pretrained openWakeWord heads** — they are CC-BY-NC-SA (not shippable in an AGPL app). V1 ships: (a) push-to-talk (in-app hotkey, exists as a machine event already), and (b) an OPT-IN always-listening mode that runs streaming ASR continuously and keyword-matches the wake phrase in the transcript (power cost surfaced in Settings; orange mic indicator always on — spec documents this honestly). A self-trained CoreML KWS classifier (openWakeWord architecture, Apache-2.0 pipeline) is a SEPARATE deferred plan — it is an ML training lift, not app code.
- **ASR:** FluidAudio pinned v0.15.4 (Apache-2.0 — note: spec says MIT, correct it), macOS 14 floor compile-proven. Use `StreamingEouAsrManager` (built-in end-of-utterance/silence detection → feeds `transcriptFinal`). Model: `parakeet-realtime-eou-120m-coreml`, NVIDIA Open Model License (record per-asset license — it is NOT CC-BY-4.0 like the batch models). First `swift package resolve` of FluidAudio can take ~30 min (full-history clone) — warn the implementer.
- **`AudioCaptureService`** (VoidloomAI or app layer per plan's choice): sole owner of the AVAudioEngine input tap; feeds ASR (and later KWS); AVAudioConverter to 16kHz mono; mic permission lazy-requested on first voice use; denial degrades to typed-only (already works).
- **Machine/coordinator hooks already exist:** `wakeDetected`/`pushToTalkPressed`/`transcriptDelta`/`transcriptFinal` events; capture effects are currently no-ops in the coordinator — Plan 3 fills them. Two carry-overs become load-bearing: `transcriptDelta` REPLACES (rename or document at the transcriber boundary); `cancel()` becomes voice-reachable (cancel-during-parsing already cancels watchdog+brain since 2b Task 2).
- **HUD:** voice states already render (`capturing` icon etc.); add push-to-talk key UX + always-listening toggle + "voice is English-only in v1" note.

**Acceptance shape:** unit tests for everything pure (capture-window plumbing via fake transcriber events); FluidAudio integration gated/manual (mic can't run headless); build green; manual QA script for push-to-talk end-to-end.

## 5. Plan 4 — Apple Intelligence tier (plan NOT yet written; this Mac runs macOS 26)

- `FoundationModelsBrain` behind `#available(macOS 26,*)` + `SystemLanguageModel` RUNTIME availability check (Apple Intelligence can be off/undownloaded on macOS 26 — spec's tier-resolution section). `@Generable` mirror types per `MediatorCommand` case in the app/AI layer (Core can't import FoundationModels) + a parity test asserting every mirror ↔ enum case both ways (drift is test-enforced, mirroring the GBNF approach).
- `SpeechAnalyzer`/`SpeechTranscriber` transcriber implementation (macOS 26) behind the same transcriber protocol Plan 3 defines; volatile partials → `transcriptDelta`, finals → `transcriptFinal`.
- Extend `MediatorTierResolver.Capabilities` (Core, currently just `commandModelReady`) with `foundationModelsAvailable` and encode the full matrix from the spec: FM available → FM brain; else model ready → llama tier; else fast-path-only. Factory (`MediatorBrainFactory`) branches accordingly.
- Latency benchmark vs the ≤1s bar on the FM path (spec fears FM guided generation may be SLOWER than the 0.6B llama path — measure, and pick the default per machine honestly).
- Chat: `LocalResponseProvider` prefers FM when available (quality >> 1.7B), else 1.7B, else stub.

## 6. Deferred Minors (feed to the 2b whole-branch review for triage)

- Task 2: `ControllableBrain` release-window flake risk; no direct `.modelDownloading`/`.backendFailure` machine test; non-confirm utterance during `awaitingConfirmation` silently swallowed (UX).
- Task 5: `piece()` fixed 128-byte buffer (long tokens dropped); `stream()` holds NSLock across `onToken` (re-entrancy/deadlock design note).
- Task 6: `backendFailure` discards the underlying error detail (debugging).
- Cross-cutting: `WorkspaceStore` duplicated 6-line placement block (parked since Plan 1); HUD "busy" affordance exists (`isBusy`) — verify Task 9/HUD actually renders it.

## 7. Known limitations to carry into README/QA (not bugs)

- Brain tier re-resolves at app LAUNCH only — download a model, then relaunch (documented in factory + plan; mid-session re-resolution is future work).
- Chat requires the optional 1.7B download; 0.6B never chats.
- Voice v1 will be English-only; always-listening shows the persistent orange mic indicator (macOS behavior).
- Teammates/CI must run `scripts/build-llama-xcframework.sh` once (artifact gitignored; pinned to llama.cpp commit `4f31eedb0…`).
