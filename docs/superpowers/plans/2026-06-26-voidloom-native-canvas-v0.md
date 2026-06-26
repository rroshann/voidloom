# Voidloom Native Canvas V0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI v0 that proves an infinite-feeling canvas with pan, zoom, draggable cards, seeded content, and local persistence.

**Architecture:** Create a Swift Package executable named `Voidloom` plus a `VoidloomCore` library target. Keep pure model logic in focused core files so tests can cover coordinate transforms, card movement, and persistence independently from SwiftUI rendering. Build the app UI from a `RootView`, `CanvasWorkspaceView`, reusable card views, and a local JSON-backed store.

**Tech Stack:** Swift 6-compatible package, SwiftUI for macOS, XCTest, Foundation JSON encoding.

## Global Constraints

- Native macOS v0.
- Canvas-first scope; do not center the build on voice commands.
- No CNVS product name, logo, exact palette, Paw Patrol names, or copied marketing text.
- No external dependencies for v0.
- No real terminal subprocesses, embedded browser, remote sync, shared memory, or licensing.

---

## File Structure

- `Package.swift`: Swift Package configuration for a core library, executable app, and tests.
- `Sources/Voidloom/VoidloomApp.swift`: macOS app entry point.
- `Sources/VoidloomCore/WorkspaceModels.swift`: Codable workspace, cards, card kinds, viewport, and movement logic.
- `Sources/VoidloomCore/WorkspaceStore.swift`: ObservableObject state owner with seed data and JSON persistence.
- `Sources/Voidloom/RootView.swift`: App shell, background, toolbar, tool rail, canvas, and command bar.
- `Sources/Voidloom/CanvasWorkspaceView.swift`: Pan/zoom surface and card placement.
- `Sources/Voidloom/WorkspaceCardView.swift`: Reusable visual card renderer.
- `Tests/VoidloomTests/WorkspaceModelTests.swift`: XCTest coverage for transforms, zoom-aware movement, and Codable persistence.

## Task 1: Package And Workspace Model

**Files:**
- Create: `Package.swift`
- Create: `Sources/VoidloomCore/WorkspaceModels.swift`
- Test: `Tests/VoidloomTests/WorkspaceModelTests.swift`

**Interfaces:**
- Produces: `CanvasViewport`, `WorkspaceCard`, `WorkspaceState`, `CardKind`, `moveCard(id:screenTranslation:)`, `canvasPoint(forScreenPoint:)`, `screenPoint(forCanvasPoint:)`

- [ ] **Step 1: Create package configuration**

Create `Package.swift` with macOS platform support, one executable target, and one test target.

- [ ] **Step 2: Write failing model tests**

Add XCTest cases for coordinate round-trip, moving a card under `scale = 2`, and JSON encode/decode preserving card data.

- [ ] **Step 3: Run tests to verify failure**

Run: `swift test`

Expected: FAIL because `Voidloom` model types do not exist yet.

- [ ] **Step 4: Implement minimal model**

Add Codable model types and pure movement/coordinate functions only.

- [ ] **Step 5: Run tests to verify pass**

Run: `swift test`

Expected: PASS.

## Task 2: Persistence Store

**Files:**
- Create: `Sources/VoidloomCore/WorkspaceStore.swift`
- Modify: `Tests/VoidloomTests/WorkspaceModelTests.swift`

**Interfaces:**
- Consumes: `WorkspaceState`
- Produces: `WorkspaceStore`, `makeSeedState()`, `load(from:)`, `save(to:)`, `addCard(kind:)`, `resetViewport()`

- [ ] **Step 1: Write failing store tests**

Add tests that saving then loading a workspace returns the same cards and that seed state contains at least one agent, note, todo, and browser placeholder card.

- [ ] **Step 2: Run tests to verify failure**

Run: `swift test`

Expected: FAIL because `WorkspaceStore` does not exist yet.

- [ ] **Step 3: Implement minimal store**

Add an `ObservableObject` store with JSON persistence helpers, seed data, card creation, and viewport reset.

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test`

Expected: PASS.

## Task 3: SwiftUI App Shell

**Files:**
- Create: `Sources/Voidloom/VoidloomApp.swift`
- Create: `Sources/Voidloom/RootView.swift`
- Create: `Sources/Voidloom/CanvasWorkspaceView.swift`
- Create: `Sources/Voidloom/WorkspaceCardView.swift`

**Interfaces:**
- Consumes: `WorkspaceStore`, `WorkspaceState`, `WorkspaceCard`, `CardKind`
- Produces: a launchable macOS SwiftUI app with pan, zoom, draggable cards, add-card controls, reset, and command bar placeholder.

- [ ] **Step 1: Implement app entry**

Create a SwiftUI `@main` app that opens `RootView`.

- [ ] **Step 2: Implement shell layout**

Create the background, top toolbar, left rail, and bottom command bar.

- [ ] **Step 3: Implement canvas interactions**

Create a scaled/translated `ZStack` canvas with drag-to-pan, magnification-to-zoom, and per-card drag gestures that update canvas coordinates using the current scale.

- [ ] **Step 4: Implement cards**

Render agent, note, todo, and browser placeholder cards with original Voidloom styling.

- [ ] **Step 5: Build the app**

Run: `swift build`

Expected: PASS.

## Task 4: Verification

**Files:**
- Modify only files created above if verification finds issues.

- [ ] **Step 1: Run tests**

Run: `swift test`

Expected: PASS.

- [ ] **Step 2: Run build**

Run: `swift build`

Expected: PASS.

- [ ] **Step 3: Read lints**

Use IDE diagnostics for `Sources/Voidloom` and `Tests/VoidloomTests`.

Expected: no introduced errors in edited files.

## Self-Review

- Spec coverage: every v0 requirement maps to a task.
- Placeholder scan: no implementation placeholders are required for the agent executing this plan.
- Type consistency: model, store, and UI names are consistent across tasks.
