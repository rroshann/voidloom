# Agent memory & inter-agent awareness (v1)

Goal (user): agent terminals — whatever model they run — should have context on
what the OTHER agents are doing, and be able to talk to each other when asked.

## v1 scope (clean, no terminal pollution)

1. **AgentMemory (Core)** — records each agent card's latest activity (spawned,
   asked to X, delegated Q), keyed by card UUID (survives renames, per-workspace
   via the live card list). Kind-aware (claude/shell/…).
2. **Sunday knows it** — AssistantContextProvider extends each agent card's detail
   from "running/idle" to "running · asked to fix the build", so "what is slate
   doing?" is answerable, and Sunday can brief agents.
3. **Relay command** `relayBetweenAgents(from, to)` — reads `from`'s recent
   terminal output and sends it to `to` ("ember said: …"), the explicit
   "agents talk to each other" path. FastPath: "relay ember to slate",
   "have ember tell slate"; llama covers natural phrasings.
4. **Brief command** `briefAgent(target)` — sends the roster of what the OTHER
   agents are doing into `target` (only meaningful for AI agents), so an agent
   gets shared context on demand without auto-polluting every prompt.

## Not in v1
- Auto-injecting the roster into every prompt (intrusive; shell noise). On demand
  via briefAgent instead.
- Cross-workspace memory (keyed by live card UUIDs of the current workspace).

## Pipeline
Both new commands go through schema → grammar (regen golden + live re-validate) →
FM mirror + parity → FastPath verbs → executor, and the executor records to
AgentMemory on spawn/sendPrompt/relay.
