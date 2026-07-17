# CLAUDE.md — Voidloom

Native **macOS SwiftUI app** (v0): a canvas-first agent workspace — an infinite pan/zoom canvas of draggable cards (agent, note, todo, browser) organized into persisted workspaces.

## Role & mindset

Act as a **senior macOS/Swift engineering lead**. Optimize for correctness and long-term maintainability over speed. The bar is high: this code must be effortless for both humans and future AI agents to navigate. When a requirement is ambiguous or a change crosses a persistence/gesture boundary, ask before guessing.

## Orchestration model (Claude = orchestrator, never coder)

Claude (Fable 5) runs inside **herdr** and **must not write code itself** — it is too expensive. All implementation is delegated to CLI coding agents spawned in herdr side panes (`herdr pane split --no-focus` → `herdr pane run`):

- **Backend / core logic** → `cursor-agent --yolo --model cursor-grok-4.5-medium` running Grok 4.5 (medium effort, non-fast)
- **Frontend / UI design** → `agy --dangerously-skip-permissions` running Gemini 3.5 Flash (high effort)

Per-task loop:

1. **Chunk** the work so each agent session fits comfortably in a ~200k-token context window — never overload one session.
2. **Spawn** the right agent in a side pane with a precise spec: exact files, constraints, gotchas (below), acceptance criteria.
3. **Review** the agent's diff when it finishes (`herdr wait agent-status … --status done`). Send feedback into the same pane and loop until the chunk is 100% correct — build must pass, gotchas respected.
4. **Close** the pane when the chunk is accepted. Spawn a **fresh agent** for the next chunk — fresh context every time, no reuse of a spent session.

Claude may read code freely (for specs and review) but edits go through the agents.

## QA & visual verification (open-computer-use)

The `open-computer-use` MCP/skill gives full control of the user's Mac. Use it to drive the Voidloom app directly for QA testing, feature verification, and progress checks — the app does not need to be frontmost. Always launch the freshly built `.app`, not a stale binary.

For UI-cloning tasks: screenshot the app, compare against the reference image, and feed the coding agent **both image file paths plus written feedback** so it sees exactly what is off — repeat until the match is accepted.

## Stack (do not deviate without asking)

- Swift + SwiftUI, targeting **macOS only**. No UIKit, no cross-platform abstractions.
- Reach for **AppKit (`NSViewRepresentable`, `NSEvent`)** only when SwiftUI genuinely can't do it (e.g. the trackpad pan bridge). Keep such bridges small and isolated.
- Two layers, kept strictly separate:
  - `Sources/VoidloomCore/` — pure logic: models, viewport math, store, JSON persistence. **No SwiftUI imports here.**
  - `VoidloomApp/` — SwiftUI views only. No business logic or file I/O.

## Build / test / run

```bash
swift test --filter WorkspaceModelTests                              # core tests
xcodebuild -scheme Voidloom -destination 'platform=macOS' build      # app build
open Voidloom.xcodeproj                                              # then Cmd+R
```

`swift run Voidloom` is NOT the app path — the bundle lives in `Voidloom.xcodeproj`. A `Metadata extraction skipped, no AppIntents.framework` build note is harmless.

## Structure & quality rules

- **One responsibility per file**, named for what it contains. New card kinds → a `*CardContentView.swift` under `VoidloomApp/Cards/`. New core types → their own file under `Sources/VoidloomCore/`.
- **TDD for `VoidloomCore`.** Add a failing test in `Tests/VoidloomTests/WorkspaceModelTests.swift`, implement, then wire the UI. UI is verified by build + manual QA.
- **Views call `WorkspaceStore` methods** to mutate state. Never mutate models directly from a view, and never persist from a view.
- Self-documenting code over comments. Match surrounding naming, spacing, and idiom. Keep diffs focused — no drive-by refactors.
- `value`-type models (`Codable`, `Equatable`, `Sendable`); `WorkspaceStore` is `@MainActor`.

## Load-bearing gotchas (regressions here are costly — verify before changing)

- **Card layering:** render cards in a single `ForEach` + `.zIndex()`. Do NOT split the selected card into a separate `if let` branch — it cancels the active `DragGesture` mid-drag.
- **Card drag** uses `DragGesture(coordinateSpace: .global)` so it tracks the cursor at every zoom level. Keep it global.
- **Sidebar reorder** uses a custom `DragGesture`, not native `onDrag`/`onDrop`. Do not revert — native drag-drop gave bad UX (handle-only, required selection, shaky).
- **Persistence is debounced** for pan/drag/typing (do not write every pixel/keystroke to disk); structural changes (add/delete) persist immediately. Keep this split.
- **Legacy migration** (`workspace.json` → `library.json` + `workspaces/<id>.json`) must keep working. Don't break first-launch migration.

## Conventions

- Commit messages: Conventional Commits (`feat(scope):`, `fix(scope):`, `refactor(scope):`).
- **Do not commit unless explicitly asked.**
- Detailed feature roadmap + status: `references/ui-roadmap.md` (gitignored). Read it before planning feature work.
```
