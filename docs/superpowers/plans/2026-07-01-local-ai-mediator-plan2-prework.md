# Local AI Mediator — Plan 2 Pre-Work Notes

> **STATUS (2026-07-02):** Plan 2 (typed command path) is COMPLETE — every obligation below was discharged or explicitly re-deferred; see the Plan 2b section at the bottom for the current carry-overs.

Carry-overs from Plan 1's final whole-branch review (base 255cab8). Read this before writing Plan 2 (tier-2 brain + typed input). Items marked FIXED were resolved in the final-review fix wave; the rest are Plan 2 obligations.

## Resolved in Plan 1's fix wave (for context)

- `.retile` Codable round-trip coverage — FIXED.
- `switchSpace` now verifies `library.selectedWorkspaceID` changed before narrating success, and narrates the matched (not spoken) name — FIXED.
- `.createCard(kind: .agent)` routes through `spawnAgents(count: 1)` so a brain can never create a session-less agent card — FIXED.
- `MediatorEffect.scheduleTimeout` documented as REPLACING any prior timer; `.executing`'s no-watchdog rationale documented on the state — FIXED (docs only; see obligations below).

## Plan 2 obligations (design-level)

1. **Coordinator timer semantics:** implement `scheduleTimeout` as a single replaceable timer (or add a generation token to the effect). Independent per-effect timers WILL misfire: a stale 15s capture timer firing during `awaitingConfirmation` — where `.timeout` is a valid event — cancels a pending confirmation.
2. **`.executing` watchdog:** the machine deliberately has none because `CommandExecutor` is synchronous. The Plan 2 coordinator must run the async BRAIN call inside `.parsing` (which has a 10s watchdog + cancel path), never inside `.executing`. If execution ever becomes async, add watchdog/cancel arms first.
3. **Wire-format freeze:** grammar generation locks the `MediatorCommand` JSON shape. Before generating: decide whether `.arrange(style: .grid)` and `.retile` stay distinct cases (currently identical behavior and narration) or collapse.
4. **Spec deltas to honor or amend:** spec's flow example says spawn "triggers re-tile" — not implemented; decide in Plan 2 (probably: coordinator issues `arrange(.retile)` after spawn in Spaces mode). Spec's `wakeArmed` state was deliberately collapsed into `idle` (KWS is always armed) — Plan 3 note.
5. **`transcriptDelta` semantics:** it REPLACES the transcript (full-hypothesis updates), despite the name. Wire real transcribers accordingly (Plan 3), or rename.

## Plan 2 obligations (deferred Minors, triaged by final review)

- `AgentNamePool`: trim + filter whitespace-only entries when Settings exposes custom packs (a `[""]` pack currently bypasses the empty-pack fallback).
- `MediatorTargetResolver`: `editDistance` → `private static`; trim with `.whitespacesAndNewlines` (typed HUD input can contain newlines).
- `CommandExecutor` narration pass (narrations become user-facing HUD text in Plan 2): singular/plural spawn narration; `readOutput` empty-output phrasing; lowercase the `existing` name set in `spawnAgents` (reachable once users rename cards to mixed case in the UI).
- `MediatorSessionMachine.parsing(_:)`/`.executing(_:)` seam constructors: tighten `public` → `internal` if the coordinator doesn't need them.
- `WorkspaceStore`: fold the duplicated 6-line center/cascade placement block (`addCard(kind:)` + `addTitledCard`) into a shared private helper next time the store is touched.

## Plan 2b carry-overs (from Plan 2's final whole-branch review, 2026-07-02)

Read BEFORE writing Plan 2b (llama.cpp + Qwen brain):

1. **Cancel-during-parsing becomes load-bearing.** `(.parsing, .cancelRequested)` returns to idle with no effects — the coordinator's `timeoutTask` stays armed and `parseTask` uncancelled. Moot for the instant `FastPathBrain`, but a hung `LlamaBrain` won't be cancelled on user-cancel, and Plan 3 makes `cancel()` voice-reachable. Emit explicit cancel effects (or have the coordinator cancel both tasks on any idle transition) before shipping a slow brain.
2. **Busy affordance.** `submitTyped` during `.parsing`/`.executing` silently drops input (machine `default` arm). Fine at instant speeds; with a slow brain, show a busy state or queue one pending utterance.
3. **`parseFailed` payload is swallowed** — the machine always narrates the generic rephrase. Surface brain-specific failures ("model not loaded", "model downloading") distinctly in 2b.
4. **Schema precision:** add an `.agentKind` `Parameter.Kind` (currently `.string` for `spawnAgents.kind`) so the generated GBNF constrains kind to {claude, shell} instead of any string.
5. **FastPathBrain `words.contains("shell")`** flips kind for an agent literally named "shell" — fix when the brain layering (fast path in front of LLM) is built.
6. `WorkspaceStore` placement-block fold (duplicated 6-liner) — still parked for "next time the store is touched."

## Dropped (final-review triage, do not re-raise)

- Unused `import Foundation` in AgentNamePool (house style).
- Unused test var `c` in resolver tests.
- Splitting state/event/effect/machine into separate files (one reducer contract).
- Dedicated `(.awaitingConfirmation, .cancelRequested)` unit test (same clause as tested branches; coordinator tests will cover end-to-end).
