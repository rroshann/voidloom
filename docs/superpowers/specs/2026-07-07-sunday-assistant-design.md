# Sunday — the Voidloom assistant (design)

Working name: **Sunday**. One assistant, one mind, four abilities: it **hears** (mic or typing),
**knows** (workspace context), **acts** (commands over every card kind), and **delegates**
(hands deep project questions to the user's Claude agents and reports back). Local-first:
Sunday's own brain never leaves the Mac; the agents it commands are the user's own tools.

## Where we are (shipped, verified)

- Command path: FastPath → grammar-constrained Qwen3-0.6B → Apple Intelligence fallback; typed + voice.
- Conversational pill: utterances that aren't commands route to the chat backend (FM → Qwen3-1.7B → stub)
  and the reply narrates in the HUD. 30s chat watchdog (cold FM exceeded the 10s parse window).
- Real PTY terminals; mediator spawn/send/read/close operate on live shells in the project folder.
- Sidebar chat streams from the same provider. `context: String?` plumbing exists end-to-end but is always nil.

## The four gaps this design closes

1. Sunday is **amnesiac**: neither chat surface knows what's on the canvas, the project folder, or git state.
2. Sunday's **hands are incomplete**: it can spawn/close terminals and create cards, but can't rename,
   edit, delete non-terminal cards, or manage todos.
3. Sunday can't **delegate**: "how does persistence debouncing work in this repo?" deserves a Claude agent's
   answer, not a 1.7B guess. Prerequisite: agent cards must actually launch the `claude` CLI (today: bare shell).
4. Sunday has no **presence**: no thinking animation, no streaming in the pill, no voice replies.

## Provider abstraction (future)

Delegation targets the user's own agent CLI. The primary provider is a Setting
(Phase C): **Claude** and **Codex** ship first (default Claude), more later
(Gemini, local Ollama-backed agents, custom command). Locked to Claude for this
repo's owner. The provider only changes which CLI `spawn` launches and how a
delegated question is phrased; the delegation flow itself is provider-agnostic.

## Phase A — Sunday knows (context + streaming + persona)

**Grammar abstain (root cause of "hi doesn't work").** With the command model
present, the GBNF grammar *forced* llama to emit some command for every input, so
chat-like utterances were mangled into commands instead of reaching chat. Fixed by
adding a `cmd-none` alternative ({"none":{}}) the model picks for non-commands; it
has no `MediatorCommand` case, so it surfaces as `.unparseable` → conversational
path. Verified live: the 0.6B model abstains on "hi"/"what cards are open"/"thanks"
while real commands still parse and stay ≤1s.


**WorkspaceContextBuilder (Core, pure, TDD)** produces a capped (~1,500 chars) structured snapshot:

```
Workspace "QA" — folder /…/dungeness (git: master, clean)
Cards: ember (terminal, running), nova (terminal, running), Git (git),
       New Note (note: "qa checklist in progress"), … and N more
Mode: Spaces · Brain: fast path + local LLM · Recent: "Spawned 1 claude agent: ember"
```

- Injected into BOTH surfaces: sidebar `submit(context:)` and the pill's `chatFallback` (both pass nil today).
- Rebuilt per message (cheap, always fresh). Card list capped at 20 with "and N more". Note bodies
  truncated to first line. Nothing leaves the Mac.
- FM system prompt gains the persona: name, capabilities, honest limits ("I can create/close cards,
  run agents…"), so "what can you do" answers truthfully.
- **Streaming into the pill**: the chatFallback currently ignores `onStreamChunk`; narration updates
  incrementally instead of waiting for `onComplete` (cap bubble at ~8 lines, "…" while streaming).
- Rename surface strings: "Ask Sunday — try 'start 2 claude agents'".
- Edge cases: no workspace open → context is just app-level; retry path passes nil context today (fix);
  context must never push FM over its window (hard cap + truncation is the guarantee).

## Phase B — Sunday's hands (full card CRUD)

New `MediatorCommand` cases, each threaded through schema → GBNF grammar (regenerate golden +
re-validate live against llama) → FM `@Generable` mirrors (parity tests) → FastPath verbs:

- `renameCard(target, newName)` — "rename ember to scout"
- `deleteCard(target)` — destructive → existing confirmation flow (covers notes/todos/browser/git;
  terminals keep `closeTerminal`). Routed through `WorkspaceStore` so **snapshot undo works** (⌘Z undoes Sunday).
- `editNote(target, content, mode: replace|append)` — "append 'ship it' to my QA note"
- `addTodoItem(target, text)` / `setTodoItemDone(target, text, done)`
- Edge cases: ambiguous targets use the existing resolver + did-you-mean; case preservation
  already fixed for payloads; editing a card the user is typing in — apply via store, never steal focus;
  spawn-limit-style refusals for nonsense counts.

## Phase C — Delegation (the Jarvis move)

**C0 prerequisite — agent cards run real agents.** `spawn(kind: .claudeCode)` launches the CLI in the
PTY after the shell starts (settings: per-kind launch command, default `claude`). Missing CLI detected
(`which claude` in the login shell) → card banner + narration hint instead of a dead prompt.

**C1 — the `delegate(question, target?)` flow:**
1. Routing v1 is explicit and predictable: "ask ember …", "ask an agent …", "deep dive …" verbs, plus a
   chat-side escape hatch (Sunday's persona says: for repo-specific questions suggest delegating).
   v2 (later): the chat model self-assesses "this needs the repo" and offers.
2. Target pick: named agent → that one; else an idle claude agent; else auto-spawn one (narrated, not
   silently). Busy agents are never hijacked.
3. Ask: v1 uses print-mode (`claude -p "<question>"`) in the target PTY — bounded output, no TUI to parse.
4. Harvest: watch the terminal buffer until the shell prompt returns, or quiet-for-5s; hard timeout 120s
   → partial answer + "ember is still working — check its card". Strip ANSI. Cap relayed answer
   (~30 lines) with "full answer in ember's card".
5. Present: reply streams into pill/sidebar attributed as **"ember:"**; delegation is visible (C2).
- Edge cases: CLI missing → graceful refusal + hint; user closes the agent mid-delegation → cancel cleanly,
  narrate; concurrent delegations → queue (depth 1, newest wins — matches mediator policy); the agent asks
  a question back (interactive prompt) → detected as "still working", surfaced to user with the card focused;
  cost honesty — narrate that the user's Claude account/CLI is doing the work (Sunday's own brain stays local).

## Phase D — Presence (animation + voice replies)

**Papercut found in Phase B QA:** after Sunday creates a card, the new card
auto-grabs keyboard focus (autoFocusNew), so chaining another typed pill command
needs ⌘J or a click first. Consider: mediator-created cards should NOT steal focus
from the pill (the user is mid-conversation with Sunday, not editing the card).


- **Pill states, animated**: idle calm waveform · listening = live level-reactive waveform (mic buffers
  already flow through AudioCaptureService) · thinking = soft pulsing ring · executing = brief flash ·
  delegating = animated dashed beam from pill to the target card + card border glow while Sunday reads it.
  All gated on `accessibilityReduceMotion`.
- **Sunday speaks** (opt-in): AVSpeechSynthesizer (on-device) reads narrations/replies. Never while the mic
  is open (feedback loop); barge-in — push-to-talk or wake phrase stops speech instantly; long replies speak
  ~2 sentences then "more on screen".
- Wake phrase default becomes **"hey sunday"** (editable; matcher exists).

## Sequencing & risk

A → B → C → D. A is small and immediately felt. B grows the grammar (golden + live llama re-validation
gates exist). C0 is the riskiest single item (CLI lifecycle in PTYs); C1 rides on it. D is polish + TTS.
Known tensions: FM context limits (hard cap owns this); llama 0.6B never chats (unchanged); delegation
uses the user's Claude account (explicit, narrated, opt-out by simply not asking).
