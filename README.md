# Voidloom

Voidloom is a native macOS v0 for a canvas-first agent workspace. This prototype focuses on the spatial layer: pan, zoom, draggable cards, seeded workspace content, and local JSON persistence.

## What Works In V0

- Infinite-feeling SwiftUI canvas with grid background.
- Pan and zoom gestures.
- Draggable agent, note, todo, and preview cards.
- Left rail for adding placeholder cards and resetting the viewport.
- Top status toolbar and bottom command placeholder.
- Workspace persistence at `~/Library/Application Support/Voidloom/workspace.json`.

## Out Of Scope For V0

- Voice commands.
- Real agent or terminal subprocesses.
- Embedded browser views.
- Remote canvas sync.
- Shared cross-agent memory.

## Run

Voidloom is now a native Xcode macOS app backed by a local Swift package for reusable core logic.

Run the app from Xcode beta:

```bash
open Voidloom.xcodeproj
```

Then select the `Voidloom` scheme and press `Cmd+R`.

You can also build the app from the command line:

```bash
xcodebuild -scheme Voidloom -destination 'platform=macOS' build
```

Run core tests with SwiftPM:

```bash
swift test
```

`swift run Voidloom` is no longer the primary app path. The app bundle, previews, assets, signing, and future archive/export workflow live in `Voidloom.xcodeproj`.
