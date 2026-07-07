# Local AI Mediator — Design

**Date:** 2026-07-01 (rev 2, post Fable design review)
**Status:** Approved; revised per adversarial review (verdict: major revisions — all findings folded in)
**Branch context:** `rroshann/dungeness`

## Summary

Replace the (stubbed) Anthropic backend with a fully local, on-device AI subsystem. Its centerpiece is a **voice-first mediator**: the user says "hey \<keyword\>" followed by a natural-language command, and the mediator orchestrates the workspace — spawning named agent terminals, routing prompts to them by name, arranging cards, and controlling spaces. Chat cards ride the same local brain. No cloud endpoints, no API keys, anywhere.

This is Voidloom's open-source answer to CNVS's voice orchestration (see `references/cnvs-research.md` in the legacy checkout). Differentiators: wake-word activation, a fully local LLM brain (CNVS's local mode is grammar-only; its smart mode is cloud), and AGPL.

The mediator is **voice-in, text-out**: results are narrated in the HUD as text. There is no TTS component in v1.

## Decisions (locked in brainstorming, 2026-07-01)

| Decision | Choice |
|---|---|
| Input mode | Voice from day one: wake word ("hey \<keyword\>") + push-to-talk. Typed command input as the degraded/no-mic path. |
| OS tiers | User runs macOS 26; feature must work on macOS 14+. Tiered providers behind protocols; tier 2 is **first-class on macOS 26 too** (see Tier resolution). |
| Hardware | AI features require Apple Silicon on all tiers. Intel Macs never see the mediator. |
| Older-tier models | App-managed downloads into Application Support (checksummed, resumable). No Ollama dependency, no models in the app bundle. |
| Command scope (v1) | Terminal orchestration (spawn N named agents, send prompt by name, read recent output, close, arrange) **plus** workspace control (create note/todo cards, switch spaces, set backgrounds). Terminal commands are built against a protocol seam and activate fully when real PTY terminals land (see Dependencies & sequencing). |
| Chat cards | Point at the same local brain via a `LocalResponseProvider`. Stub remains the model-missing fallback. Anthropic endpoint/key placeholders removed from Settings. |
| Brain strategy | **Approach A:** LLM tool-calling on both tiers, schema-constrained so invalid output is rejected structurally; executor designed so a deterministic grammar fast-path can be added in front later without changes. |
| Tier-2 ASR | Parakeet via FluidAudio (MIT, CoreML, streaming) — matches CNVS's proven sub-300ms local stack. whisper.cpp only if FluidAudio integration disappoints. **English-only in v1 on both tiers** (Parakeet v2 is English-only; tier 1 is capped to match so behavior is uniform). |
| Wake word | One shared MB-scale keyword-spotting (KWS) model on **both** tiers — macOS has no public keyword-spotting API (SpeechAnalyzer provides transcription + VAD only), and a single implementation beats running full ASR 24/7 for power. Verify with a spike; fallback is continuous-transcription keyword matching on tier 1 only. |
| Wake keyword | v1 ships a small **curated set of pre-trained keyword assets** to choose from (KWS models are trained offline; free-text keywords would require cloud training — contradicts local-only). Free-text keyword only if the transcription-matching fallback is used. |
| Module layout | New third module `Sources/VoidloomAI/` for concrete model providers (depends on Core, no SwiftUI). Amends CLAUDE.md's two-layer rule; approved by user. |
| Agent naming | Built-in pool of generic "tactical callsign" dictionary words (may overlap with Valorant/Overwatch names where those are ordinary words: Viper, Omen, Phoenix, Sage, Echo, …). Never branded as such; no distinctive coined names (KAY/O, Zenyatta, Widowmaker). User-configurable custom name packs; cards renamable. |
| Latency bar | Measured interval: **end-of-speech → command dispatched to executor**, target ≲1s warm. Mandated mitigations: persistent prompt-prefix/KV cache for `LlamaBrain`, pre-warmed Foundation Models session. Latency benchmarks are part of the test plan. |
| Push-to-talk | **In-app hotkey only in v1** (no global monitor — avoids the Accessibility/Input Monitoring permission prompt). Global hotkey is a later opt-in. |
| Mic reality | An always-on KWS detector means the orange mic indicator is on **whenever the app runs with wake word enabled** — not just after the wake word fires. Stated honestly in UI; Settings offers a push-to-talk-only mode that keeps the mic closed until the hotkey is held. |

## Dependencies & sequencing

On this branch, `VoidloomApp/Agent/AgentSessionManager.swift` is an **echo stub** — no PTY, no process spawning. The real SwiftTerm PTY layer exists only as uncommitted Round-4 work on a separate worktree, awaiting user QA.

Consequence: the four terminal commands (`spawnAgents`, `sendPrompt`, `readOutput`, `closeTerminal`) are specced against a Core protocol seam, `AgentTerminalControlling` (below). The current stub conforms today (commands "work" against echo sessions); the Round-4 PTY manager conforms when it lands, activating real terminals with **zero mediator changes**. Implementation phases order workspace-control commands (which run against real code now) ahead of terminal-command polish.

## Architecture

One pipeline, tiered providers, every stage behind a Core protocol. Audio stays in VoidloomAI; Core sees only events and strings.

```
                    VoidloomAI                                VoidloomCore                                  App/Core state
┌─────────────────────────────────────────────┐   ┌──────────────────────────────────────┐   ┌─────────────────────────────────┐
│ AudioCaptureService (sole mic owner)        │   │ MediatorSession (state machine)      │   │ WorkspaceStore (Core)           │
│   ├→ WakeWordDetector  ──wakeDetected──────────→│   orchestrates the stages below      │   │ AgentTerminalControlling impl   │
│   └→ SpeechTranscriber ──transcript deltas──────→│                                      │   │   (App: stub now, PTY later)   │
│ MediatorBrain (tiered) ──MediatorCommand───────→│ CommandExecutor ──validated calls──────→ │                                 │
└─────────────────────────────────────────────┘   └──────────────────────────────────────┘   └─────────────────────────────────┘
```

| Stage | Tier 1 (macOS 26 + FM available) | Tier 2 (macOS 14+, Apple Silicon, downloaded models) |
|---|---|---|
| Wake word | Shared KWS model (MB-scale, downloaded asset) | Same — no tier split at this stage |
| ASR | Apple SpeechAnalyzer (English-capped in v1) | Parakeet via FluidAudio (CoreML, ~600MB download) |
| Brain | Apple Foundation Models (tool calling, pre-warmed session) | Qwen3-0.6B GGUF via llama.cpp, grammar-constrained (~500MB download) |

**Load-bearing rule:** models never touch app state. A brain's only output is a `MediatorCommand`; plain Swift validates and executes it. The failure mode is "command rejected, please rephrase" — never a partial or invented action.

### Tier resolution

`MediatorTierResolver` selects per-stage at runtime, not per-OS at compile time:

1. macOS 26 **and** `SystemLanguageModel` reports available (Apple Intelligence enabled, model downloaded, device eligible) → tier-1 brain; else
2. Apple Silicon and downloaded models ready → tier-2 stack (**including on macOS 26** — FM can be disabled/undownloaded there); else
3. Typed-input-only mode with a pointer to Settings.

Same per-stage logic for ASR (SpeechAnalyzer asset downloads can be pending → Parakeet fallback if ready).

### Module layout

- `Sources/VoidloomCore/Mediator/` — pure logic: `MediatorCommand` + schema descriptor, `MediatorSession` state machine, `CommandExecutor`, target resolution, `AgentNamePool`, and the `MediatorBrain` / `WakeWordDetector` / `SpeechTranscriber` / `AgentTerminalControlling` protocols. No SwiftUI, no AVFoundation, no model runtimes. Full TDD.
- `Sources/VoidloomAI/` — **new module.** Concrete providers: `FoundationModelsBrain`, `LlamaBrain`, transcribers, KWS detector, `AudioCaptureService`, `ModelAssetManager`, `MediatorTierResolver`, `LocalResponseProvider`. Depends on VoidloomCore. No SwiftUI.
- `VoidloomApp/` — SwiftUI only: mediator HUD, Settings "Local AI" tab, confirmation UI; `AgentSessionManager` conforms to `AgentTerminalControlling`.

## Components

### VoidloomCore (TDD-first)

- **`MediatorCommand`** — Codable enum with labeled associated values (default Codable JSON like `{"sendPrompt":{"target":…,"text":…}}` is the wire/grammar target):
  - `spawnAgents(count: Int, kind: AgentKind, names: [String]?)`
  - `sendPrompt(target: String, text: String)`
  - `readOutput(target: String)`
  - `closeTerminal(target: String)`
  - `arrange(ArrangeStyle)` (grid / re-tile / focus target)
  - `createCard(kind: CardKind, content: String?)`
  - `switchSpace(name: String)`
  - `setBackground(BackgroundSpec)`
- **`MediatorCommandSchema`** — an explicit, hand-maintained schema descriptor (JSON-Schema-shaped) for the enum. **Honest drift story:** Swift cannot reflect over Codable structure, and tier-1 tools must be `@Generable` mirror types in VoidloomAI (Core can't import FoundationModels). So `MediatorCommand` is the *semantic* source of truth and drift is prevented **by tests, not by construction**: (a) GBNF is generated from the schema descriptor (via `json_schema_to_grammar`-equivalent); round-trip tests assert sampled commands encoded via Codable parse under the grammar and vice versa; (b) a VoidloomAI parity test asserts every tier-1 tool maps onto an enum case and every case has a tool.
- **`MediatorSession`** — the pipeline state machine; pure and event-driven. Owns: idle → wakeArmed → capturing (with silence timeout) → parsing → executing / awaitingConfirmation (destructive commands; timeout ~10s; voice "confirm/cancel" heard **without** a wake word while in this state) → narrating result → idle. Semantics: single pending command; overlapping triggers (push-to-talk during in-flight command) cancel-and-restart capture but never interrupt an executing command; cancellation of a half-heard command via timeout or "cancel". Inputs are events (`wakeDetected`, `transcriptDelta/Final`, `commandProduced(Result)`, `confirmReceived`, `timeout`); output is an observable state the HUD renders and VoidloomAI acts on. Fully TDD-able.
- **`CommandExecutor`** — resolves spoken targets to card UUIDs (case-insensitive, fuzzy match with a confidence floor), validates parameters (count limits, known kinds), then calls `WorkspaceStore` and an injected `AgentTerminalControlling`. Returns a typed `ExecutionResult` (success narration / `.needsClarification` / `.needsConfirmation` / refusal). Mode-blind: state changes always apply; the HUD narrates when an effect is only visible in Spaces mode.
- **`AgentTerminalControlling`** (protocol) — `spawn(cardID:kind:)`, `send(text:to:)`, `recentOutput(of:maxLines:)`, `terminate(cardID:)`, keyed by card UUID. The App-layer `AgentSessionManager` (stub today, PTY later) conforms; Core tests use a mock.
- **`AgentNamePool`** — deterministic name assignment from the active pack (built-in callsigns or user pack), skipping names already on the canvas.
- **New `WorkspaceStore` methods (deliverables, tested):** add-card-with-title/content variants (existing `addCard(kind:)` takes neither), needed for atomic named-agent spawn and `createCard(content:)`.
- **Target resolution rules:** scoped to the active workspace/library. `switchSpace` resolves against workspace names via the existing `switchWorkspace(id:)` path; duplicate names (e.g. two "Untitled") → `.needsClarification`, never a guess.

### VoidloomAI

- **`AudioCaptureService`** — the single owner of the microphone (AVAudioEngine tap); fans buffers to whichever stage is active (KWS always when wake word enabled; transcriber during capture windows). Core protocols never see audio types.
- **`FoundationModelsBrain`** (tier 1) — pre-warmed FM session; `@Generable` mirror types per command case, mapped to `MediatorCommand` (parity-tested, see schema component).
- **`LlamaBrain`** (tier 2) — llama.cpp (Swift package) with Qwen3-0.6B; GBNF generated from `MediatorCommandSchema`; persistent system-prompt KV cache. 1.7B is the quality fallback (Open item).
- **Shared KWS `WakeWordDetector`** — one implementation, both tiers; curated pre-trained keyword assets as downloads. Runtime (ONNX vs CoreML conversion) resolved in an implementation spike.
- **Transcribers** — SpeechAnalyzer (tier 1) / FluidAudio Parakeet (tier 2), silence endpointing feeding `transcriptFinal`.
- **`ModelAssetManager`** — download-on-first-use into `Application Support/Voidloom/Models/`: manifest with **revision-pinned URLs** (Hugging Face pinned revisions and/or GitHub release mirrors — hosting decision recorded at implementation time) + SHA256, resumable `URLSession` downloads, states `missing / downloading(progress) / verifying / ready / failed`. Licenses recorded in-app and in README: Parakeet CC-BY-4.0 (attribution shown), Qwen3 Apache-2.0, FluidAudio/llama.cpp MIT — all AGPL-compatible.
- **Residency & memory policy:** KWS model always resident (MB-scale). ASR + brain lazy-load on first mediator use, then stay resident (first command after launch pays a multi-second warm-up, narrated in the HUD as "warming up…"). Full tier-2 resident set ≈ 1.5–2 GB; documented, with a Settings "unload models when idle" escape hatch for 8 GB machines.
- **Brain concurrency (chat vs mediator):** one brain instance, **mediator preempts chat** — an in-flight chat generation is cancelled (message marked failed with a retry affordance, wired through the existing `ConversationReducer.failing`/`resettingToPending`); chat requests queue behind an executing voice command. `ResponseProvider.generateResponse` is `@MainActor` — `LocalResponseProvider` hops inference off the main actor and marshals callbacks back.
- **`MediatorTierResolver`** — per the Tier resolution section; re-evaluated on relevant changes (FM availability, download completion), not just at launch.

### VoidloomApp

- **Mediator HUD** — floating pill/orb rendering `MediatorSession` state: idle → wake heard → live transcript → command echo + result narration → clarification/confirmation (inline confirm/cancel buttons mirroring the voice path) → error. `readOutput` results render in an **expandable panel** (last 25 lines from `recentOutput(of:maxLines:)`); the pill itself never grows. Also accepts typed commands (the no-mic path). Single-display anchored in v1 (multi-display placement deferred, listed).
- **Settings → AI (reworked)** — remove disabled Anthropic endpoint/key fields (`SettingsView.swift` Connection section). Add: tier status ("Apple on-device AI" / "Downloaded local models" / "Unavailable on this Mac"), model download management with license attributions, wake-keyword picker (curated assets), wake-word vs push-to-talk-only mode, in-app push-to-talk hotkey, name-pack editor, "unload models when idle".
- Mic (and tier-1 speech) permission prompts triggered lazily on first voice use; denial degrades to typed-only with a clear explanation.

## Flow example

"Hey \<keyword\>, ask jerry to look into the API errors":

1. KWS fires → `MediatorSession` enters capturing; HUD lights. (Mic indicator was already on — always-listening reality, see Decisions.)
2. Transcriber streams "ask jerry to look into the API errors"; silence endpointing emits `transcriptFinal`.
3. Brain emits `sendPrompt(target: "jerry", text: "look into the API errors")` — constrained output.
4. `CommandExecutor` fuzzy-matches "jerry" against agent-card names in the active workspace → jerry's card UUID → `AgentTerminalControlling.send(text:to:)` (stub echo today; real PTY when Round-4 lands).
5. HUD flashes "→ jerry"; session returns to idle.

No match → `.needsClarification("I don't see a jerry — did you mean jasper?")`. "Close jerry's terminal" → `.needsConfirmation`, session awaits "confirm"/"cancel" (no wake word needed) or HUD buttons, 10s timeout.

"Start 4 claude agents" → `spawnAgents(count: 4, kind: .claudeCode, names: nil)` → executor creates 4 titled terminal cards via the new store API + `AgentTerminalControlling.spawn`, triggers re-tile.

## Error handling

- Malformed/unparseable brain output → one retry with the parse error in context, then "didn't catch that". Never a partial action.
- Ambiguous or unknown target (agents *and* spaces) → clarification, not a guess.
- Destructive commands → confirmation state with timeout, voice or buttons.
- Models missing/downloading → HUD shows download state with one-click start; commands fail fast with the reason (no queueing).
- FM unavailable on macOS 26 → silent fallback to tier 2 (or typed-only), surfaced in Settings tier status.
- Mic/speech permission denied → typed command input fully works.
- Chat cards with no brain available → stub responses, unchanged from today.
- Chat generation preempted by a voice command → message marked failed with retry, per concurrency policy.

## Testing

- **Core (TDD, `swift test`):** `MediatorCommand` Codable round-trips; **grammar↔Codable round-trip** (sampled commands parse under generated GBNF and vice versa); **`MediatorSession` state machine** (every transition: timeouts, cancellation, confirmation, overlapping triggers); `CommandExecutor` against in-memory store + mock `AgentTerminalControlling` (target resolution exact/fuzzy/ambiguous/missing/duplicate-space, parameter validation, confirmation flow, every command case, new store methods); `AgentNamePool` exhaustion and custom packs; **tier-resolver fallback matrix** (pure decision logic extracted to Core or tested via injected capability flags).
- **VoidloomAI (integration, local dev machines — honestly not CI-able where they need Apple Intelligence enabled or downloaded models):** golden utterance→command set against each brain; **VoidloomAI↔Core parity test** (every FM tool ↔ enum case); `ModelAssetManager` state machine with a local file-server fixture; **latency benchmarks** measuring end-of-speech → dispatch against the ≲1s bar, warm and cold.
- **App:** build + manual QA per project convention (wake word, HUD states, permission denial, mode toggles).

## Explicitly out of scope (v1)

- Agent-to-agent control (agents spawning/prompting agents, MCP/CLI bridge) — CNVS parity item, later phase.
- Remote/VPS canvases, shared cross-agent memory, autonomous loops.
- Conversational multi-turn mediator ("what did jerry find?" follow-ups). (The confirmation exchange is deliberately minimal state in `MediatorSession`, not conversation.)
- TTS / spoken responses.
- Non-English speech; global push-to-talk hotkey; multi-display HUD placement.
- Cloud model options of any kind.

## Open items

- KWS runtime spike: ONNX vs CoreML-converted, and whether the tier-1 continuous-transcription fallback is ever needed.
- Qwen3-0.6B vs 1.7B on tier 2: benchmark with the golden set during implementation.
- Model hosting: pinned HF revisions vs GitHub release mirror (decide when `ModelAssetManager` lands; record in manifest).
- Wake keyword final choice (user decision; curated-set architecture makes it swappable).
