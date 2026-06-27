# Voidloom

Voidloom is a native macOS v0 for a canvas-first agent workspace. This prototype focuses on the spatial shell: pan/zoom canvas, draggable cards, multi-workspace sidebar, and local JSON persistence.

## What Works In V0

- Infinite-feeling SwiftUI canvas with grid background.
- Pan, pinch-zoom, and trackpad two-finger pan (when no card is selected).
- Draggable agent, note, todo, and preview/browser cards with per-kind styling and selection feedback.
- **Multi-workspace sidebar:** create, rename, delete, drag-to-reorder, and switch workspaces.
- **Top toolbar:** sidebar toggle, active workspace name, and card count (does not shift when sidebar opens).
- **Bottom tool dock:** add Agent / Note / Todo / Preview cards, reset viewport, AI icon (toggles command hint bar).
- **Bottom-right zoom controls:** +/−, zoom %, focus/unfocus selected card.
- **Command hint bar:** display-only hints above the dock (toggled by AI dock icon); persistence errors surface in the same strip.
- Local JSON persistence (see Storage below).

## Shell Layout

```text
zIndex 0  Canvas (full bleed) + atmosphere background
zIndex 1  Workspace sidebar (slides in from left)
zIndex 2  Bottom chrome: ToolDock (center), command hint bar (toggle), zoom controls (bottom-right)
zIndex 3  Top toolbar (top left)
```

Workspace switching lives in the sidebar, not the bottom dock. Zoom controls stay pinned bottom-right when the command bar opens.

## Storage

Multi-workspace data is stored under `~/Library/Application Support/Voidloom/`:

```text
library.json                          # workspace index + selected workspace ID
workspaces/<workspace-id>.json        # per-workspace canvas state (cards, viewport)
```

On first launch, a legacy single-file `workspace.json` (if present) is migrated automatically into the library layout.

## Out Of Scope For V0

- Voice commands.
- Real agent or terminal subprocesses (stub terminal UI is planned/in progress; no PTY yet).
- Remote canvas sync.
- Shared cross-agent memory.
- App Store packaging / signing polish.

**In scope (roadmap):** embedded browser WebView on preview cards, editable note/todo content, header hover chrome (maximize + close), card resize, and inline title edit.

## Run

Voidloom is a native Xcode macOS app backed by a local Swift package (`Sources/VoidloomCore/`).

**Launch from Xcode:**

```bash
open Voidloom.xcodeproj
```

Select the `Voidloom` scheme and press `Cmd+R`.

**Build from the command line:**

```bash
xcodebuild -scheme Voidloom -destination 'platform=macOS' build
```

**Run core tests:**

```bash
swift test --filter WorkspaceModelTests
```

`swift run Voidloom` is not the primary app path. The app bundle, previews, assets, and archive workflow live in `Voidloom.xcodeproj`.
