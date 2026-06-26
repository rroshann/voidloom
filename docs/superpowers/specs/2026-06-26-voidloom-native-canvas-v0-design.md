# Voidloom Native Canvas V0 Design

## Goal

Build a native macOS v0 of Voidloom that proves the core spatial workspace: an infinite-feeling canvas with pan, zoom, draggable cards, and local persistence. Voice control, real agent subprocesses, embedded browsers, remote canvases, and shared memory are intentionally out of scope for this first version.

## Platform

Use a dependency-light SwiftUI macOS app scaffolded as a Swift Package executable. This keeps the prototype native and easy to build from the command line while avoiding Xcode project-file churn.

## User Experience

The app opens to a dark atmospheric workspace with a subtle grid, a top floating toolbar, a left tool rail, several seed cards, and a bottom command bar. Users can pan the canvas, zoom in and out, drag cards around, add new placeholder cards, reset the viewport, and relaunch the app without losing card positions.

## Core Features

- Infinite-feeling pan and zoom viewport.
- Draggable workspace cards for agents, notes, todos, and browser placeholders.
- Canvas-space coordinate model so dragging behaves correctly under zoom.
- Local JSON persistence for viewport and cards.
- Distinct original visual identity that avoids copying CNVS names, exact palette, or agent naming conventions.

## Non-Goals

- No voice commands.
- No real terminal subprocess management.
- No embedded WKWebView browser in v0.
- No agent-to-agent orchestration.
- No remote VPS state sync.
- No licensing, onboarding game, or app distribution packaging.

## Testing

Use TDD for non-UI behavior:

- Viewport screen/canvas coordinate transforms.
- Moving cards under a zoomed viewport.
- Workspace JSON encoding/decoding.

SwiftUI rendering will be verified by build success and manual launch readiness.
