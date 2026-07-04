# Plan 3 Task 3 — Push-to-talk UX end-to-end

**Date:** 2026-07-04  
**Commit message:** `feat(voice): hold-to-talk mic button and key with permission-aware HUD`

## Summary

Wired push-to-talk from HUD and keyboard through the existing coordinator/transcriber seam:

- **`MediatorSessionCoordinator`**: `pushToTalkReleased()` calls `transcriber?.stopUtterance()`; `isMicPermissionDenied` + `setMicPermissionDenied(_:)` for HUD state.
- **`ParakeetTranscriber`**: on mic permission denial emits `.unavailable("Microphone access denied — voice is off; typing still works.")` and notifies `onMicPermissionDeniedChanged`.
- **`MediatorHUDView`**: hold-to-talk mic button (disabled/muted appearance when permission denied); shown only when mic hardware exists.
- **`VoicePushToTalkKeyMonitor`**: in-app `NSEvent.addLocalMonitor` for hold **⌥Space** (keyDown/keyUp + option release via flagsChanged).
- **`RootView`**: constructs `ParakeetTranscriber` when `AVCaptureDevice.default(for: .audio) != nil`, injects into coordinator, wires permission callback and key monitor.

## Review fix (carried)

`ParakeetTranscriber.startUtterance` no longer returns silently on permission denial — emits the binding unavailable message above.

## Verification

| Check | Result |
|-------|--------|
| `swift test` | **240 tests**, 0 failures (239 baseline + `testPushToTalkReleasedStopsUtterance`) |
| `xcodebuild -scheme Voidloom -destination 'platform=macOS' build` | **BUILD SUCCEEDED** |

## Files changed

- `Sources/VoidloomCore/Mediator/MediatorSessionCoordinator.swift`
- `VoidloomApp/AI/Voice/ParakeetTranscriber.swift`
- `VoidloomApp/Shell/MediatorHUDView.swift`
- `VoidloomApp/Shell/RootView.swift`
- `VoidloomApp/Shell/VoicePushToTalkKeyMonitor.swift` (new)
- `Tests/VoidloomTests/MediatorVoiceTests.swift`
- `Voidloom.xcodeproj/project.pbxproj`

## Manual QA checklist

- [ ] Launch Voidloom (Cmd+R). HUD pill shows mic button left of the waveform icon when this Mac has a microphone.
- [ ] **First use — allow mic:** hold mic button → macOS mic permission prompt → Allow → speak **"start two claude agents"** → release → live transcript updates while holding → narration **"Spawned 2 claude agents: …"** and two agent cards appear.
- [ ] **Keyboard PTT:** with Voidloom focused, hold **⌥Space**, speak the same phrase, release → same spawn result.
- [ ] **Deny mic:** reset mic permission (`tccutil reset Microphone <bundle-id>`) or deny on prompt → hold mic → narration **"Microphone access denied — voice is off; typing still works."** → mic button looks disabled (muted/gray); typing in the text field still spawns agents.
- [ ] **⌥Space when denied:** no capture starts; typed path still works.
- [ ] **Other apps:** ⌥Space in another app does not trigger Voidloom (local monitor only).
- [ ] **Release without speech:** hold and release quickly → no crash; may time out with rephrase prompt (acceptable v1).
- [ ] **Model not ready:** if Parakeet models still downloading, hold mic → **"Voice model still preparing — try again shortly."**

## Notes for Task 4

- Always-listening mode and Settings voice section are out of scope here.
- `isMicHeld` UI state is button-local; keyboard PTT does not tint the mic icon (acceptable for v1).
