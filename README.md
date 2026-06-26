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

This project is a Swift Package with a native SwiftUI executable:

```bash
swift run Voidloom
```

Run tests with:

```bash
swift test
```

The current machine has Command Line Tools selected but no full Xcode installation. SwiftPM is failing before compilation because the selected toolchain is missing `BuildServerProtocol.framework`, and direct SwiftUI type-checking is missing `SwiftUIMacros`. Install full Xcode or repair/reinstall Command Line Tools, then rerun the commands above.
