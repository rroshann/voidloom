# Contributing to Voidloom

Thanks for your interest. Voidloom is a native macOS SwiftUI app; this file covers the mechanics. For the architecture and design rules, see the [Contributing section of the README](README.md#contributing).

## Before you start

For anything non-trivial, **open an issue first** so we can agree on the approach before you invest time. Small, focused pull requests are much easier to review and merge than large ones.

## Requirements

- **To build:** Xcode 26+ (macOS 26 SDK) and Swift 6 — some views use `#available(macOS 26.0, *)` APIs.
- **To run:** macOS 14.0 or later.

## Build, run, and test

```bash
swift test                                          # run the VoidloomCore test suite
xcodebuild -scheme Voidloom -destination 'platform=macOS' build   # build the app
open Voidloom.xcodeproj                              # then press Cmd+R to run
```

## Ground rules

- **Layering:** logic goes in `Sources/VoidloomCore/` (no SwiftUI imports); views go in `VoidloomApp/`. Views mutate state only through `WorkspaceStore` methods — never persist or mutate models directly from a view.
- **TDD for core:** add a failing test in `Tests/VoidloomTests/`, implement, then wire the UI. UI is verified by build + manual QA.
- **One responsibility per file**, named for what it contains. New card kinds go in `VoidloomApp/Cards/*CardContentView.swift`.
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org/) — `feat(scope):`, `fix(scope):`, `refactor(scope):`.

## Pull requests

`master` is protected: every change lands via a pull request. CI runs the core test suite and the app build, and both must pass before a PR can merge. Branch off `master`, push your branch, and open a PR.

## License

By contributing, you agree that your contributions are licensed under the project's [AGPL-3.0](LICENSE) license.
