# Voidloom

**A canvas-first agent workspace for macOS.**

Voidloom is a native SwiftUI app built around one idea: your work should live on an infinite canvas, not in a stack of windows. You pan and zoom across draggable cards (terminals, notes, todos, browsers, file trees, git status) organized into workspaces that persist between launches. An AI assistant sits alongside the canvas, and every terminal card is a real shell.

The long-term goal is more ambitious: an app you talk to. Tell it what you want and it rearranges itself around you, JARVIS-style. More on that in the [roadmap](#roadmap-your-own-jarvis).

> **Status:** early development (v0). The spatial shell, terminal cards, and AI assistant work today; the fully local AI layer is being built now.

---

## Features

### Two presentation modes

The same workspace renders in either mode; switching is lossless and instant, from the dock or the View menu.

- **Canvas** — free pan/zoom surface. Trackpad two-finger pan, pinch-zoom, draggable and resizable cards, marquee multi-select, and a minimap overview you can toggle on.
- **Spaces** — auto-tiled presentation: a paginated grid (arrow keys to page) or a free-arrange layout with persisted per-card frames. A Space can point at a project folder, which unlocks the file browser and git cards.

### Cards

| Card | What it does |
|------|--------------|
| **Terminal** | A real PTY-backed shell (SwiftTerm). Sessions can be restarted when the shell exits. |
| **Note** | Editable free-form text |
| **Todo** | Checkable task list |
| **Browser** | Embedded web view (`WKWebView`) |
| **File browser** | Folder tree for the Space's project folder (added from the Spaces dock) |
| **Git** | Git status for the Space's project folder (added from the Spaces dock) |

Cards support inline rename, resizing from handles, and header hover actions (rename, focus, close). Cards can be connected with visible edges, duplicated, copied, cut, and pasted. Undo/redo covers canvas actions.

### AI assistant

- Per-workspace conversation threads in a sidebar, opened from the dock's sparkles button or the bottom command bar.
- The selected card and its connected neighbors are sent along as context.
- Powered today by the Anthropic API: bring your own key (stored in the macOS Keychain, never in preferences) and pick a Claude model in Settings. A fully local, no-API-key engine is what's being built next — see the roadmap.

### Canvas tools

The bottom dock is the control surface: mode switch, workspace menu, card tools, drawing tools, and zoom controls in one capsule.

- Place cards by clicking (arm, then click the canvas) or double-clicking (instant), or use the right-click context menu.
- **Connect** links two cards with an edge; edges can be selected and deleted.
- **Brush** and **Eraser** draw and erase strokes directly on the canvas.
- **Text** places free-floating text elements with font, size, and color options.
- Reset viewport, minimap toggle, zoom in/out with percentage, and a focus mode that zooms into the selected card and back out.

### Command palette and shortcuts

- **⌘K** opens a command palette: create cards, switch or create workspaces, jump to any card by name, zoom, open Settings or the AI conversation, switch modes.
- Menu shortcuts include ⌘⇧A/N/T/B for new cards, ⌘Z / ⇧⌘Z undo/redo, ⌘X/C/V/D clipboard and duplicate, ⌘+/−/0 zoom, and toggles for mode and minimap.

### Workspaces and launcher

- The app opens to a launcher listing your workspaces with search, recents, create, and delete.
- Inside a workspace, switch or create workspaces from the dock menu without going back to the launcher.
- Each workspace remembers its own cards, connections, drawings, and viewport.

### Settings

Eight tabs: General (launch behavior, default card, delete confirmation), Appearance (theme, accent color, canvas background), Canvas (zoom and pan behavior), Spaces, Cards, AI (API key and model), Storage, and About.

---

## Getting started

### Requirements
- **To build:** Xcode 26+ (macOS 26 SDK) and Swift 6 — some views use `#available(macOS 26.0, *)` APIs, and the core package requires `swift-tools-version: 6.0`.
- **To run:** macOS 14.0 or later (Apple Silicon or Intel).

### Installation

There are no prebuilt releases yet, so you build from source:

```bash
git clone https://github.com/rroshann/voidloom.git
cd voidloom
```

### Build and run

```bash
open Voidloom.xcodeproj
```

Select the `Voidloom` scheme and press `Cmd+R`.

Or from the command line:

```bash
xcodebuild -scheme Voidloom -destination 'platform=macOS' build
```

> `swift run Voidloom` is not the app path. The app bundle, assets, and archive workflow live in `Voidloom.xcodeproj`. If you see a `Metadata extraction skipped, no AppIntents.framework` note during the build, ignore it; it's harmless.

### Tests

Core logic lives in a pure Swift package and is tested with `swift test`:

```bash
swift test                                    # all core tests
swift test --filter WorkspaceModelTests       # workspace model suite only
```

CI runs the full core test suite and the app build on pushes to master and on every pull request.

---

## Architecture

Logic and UI are kept strictly apart:

```text
Sources/VoidloomCore/    Pure logic: models, viewport math, space tiling, store,
                         JSON persistence (no SwiftUI imports, fully unit-testable)
VoidloomApp/             SwiftUI views, organized by area: Shell, Canvas, Cards,
                         Spaces, Agent (terminal sessions), AI, CommandPalette
Tests/VoidloomTests/     Core test suite
```

Canvas shell layering, back to front:

```text
Canvas + atmosphere background
AI conversation sidebar (slides in from the right)
Bottom chrome: dock capsule, command bar, tool option panels
Minimap (bottom-right, toggleable)
Command palette overlay (⌘K)
```

### Storage

Workspace data is local. It lives under `~/Library/Application Support/Voidloom/`:

```text
library.json                    # workspace index + selected workspace ID
workspaces/<workspace-id>.json  # per-workspace canvas state (cards, viewport)
```

If you have an old single-file `workspace.json`, it migrates automatically on first launch. High-frequency actions (pan, drag, typing) are saved on a debounce; structural changes (adding or deleting a card) are saved immediately.

The one thing that leaves your machine is the optional AI assistant, which calls the Anthropic API with your own key. Skip the key and the app is fully offline.

---

## Roadmap: your own JARVIS

Here's where this is going. Tony Stark doesn't click through menus; he tells JARVIS what he wants and the room responds. That's the bar for Voidloom. "Spin up an agent next to my research notes." "Clear the board and start a new sprint." You say it, the canvas does it.

Eventually you shouldn't even need to manage the agents yourself. You give the app a goal, it spins up the agents it needs, they coordinate with each other, and you watch the work happen on the canvas. One conversation with the app; the app handles the orchestration.

The AI assistant today uses the Anthropic cloud API. The next step, in active development, replaces that with a fully local, on-device engine, so the whole experience runs on your Mac with no API keys, no subscription, and nothing leaving your machine:

- **Local AI mediator.** Type plain English into the command bar ("spawn an agent next to my notes", "add a todo card") and it runs as validated, typed canvas commands.
- **On-device inference.** A small local LLM via an embedded `llama.cpp` engine, with grammar-constrained (GBNF) output so the model can only emit valid commands.
- **Tiered brain.** A deterministic fast-path parser handles common commands; the local model handles anything fuzzier. Ambiguous targets get rejected rather than misrouted, so the mediator never guesses.
- **Model asset manager.** Automatic model download with a pinned manifest, SHA256 verification, and visible progress.
- **Agent callsigns and spawning.** Named agent cards you create and address through the mediator.

Further out (not started yet):

- **Voice control.** The full JARVIS experience: talk to your canvas hands-free.
- **Agent-to-agent collaboration.** Agents on the canvas that talk to each other, hand off work, and share context, with the app orchestrating them so you only ever have one conversation: yours.
- Remote canvas sync and shared cross-agent memory.
- App Store packaging and signing polish.

---

## Contributing

Contributions are welcome. A few ground rules keep the codebase easy to navigate:

- **Stack:** Swift + SwiftUI, macOS only. AppKit bridges (`NSViewRepresentable`, `NSEvent`) only where SwiftUI genuinely can't do the job, kept small and isolated.
- **Layering:** logic goes in `Sources/VoidloomCore/` (no SwiftUI imports), views in `VoidloomApp/`. Views mutate state only through `WorkspaceStore` methods.
- **TDD for core:** add a failing test in `Tests/VoidloomTests/`, implement, then wire the UI.
- **One responsibility per file**, named for what it contains. New card kinds go in `VoidloomApp/Cards/*CardContentView.swift`.
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/): `feat(scope):`, `fix(scope):`, `refactor(scope):`.

For anything non-trivial, open an issue first so we can talk through the approach before you invest time.

---

## License

Voidloom is licensed under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0). You're free to use, modify, and distribute it, but any distributed or network-served modified version must also be released under AGPL-3.0 with source available.
