# Local AI Mediator — Plan 3: Voice (push-to-talk + opt-in wake phrase)

> **Workflow:** lead (this session) coordinates and reviews; each task is implemented by a fresh `cursor-agent --yolo --model composer-2.5` from a per-task brief + notes. Sequential; one commit per task (+fix commits).
>
> **Grounding (binding, from `.omc/research/spike-voice.md` + lead adjudications):**
> - NO pretrained openWakeWord heads (CC-BY-NC-SA — not shippable under AGPL). v1 wake word = opt-in always-listening streaming ASR + keyword match on the transcript. A self-trained CoreML KWS model is a separate, deferred plan.
> - ASR: **FluidAudio, pinned v0.15.4** (Apache-2.0 — the spec's "MIT" note is wrong), macOS 14 floor compile-proven. Use **`StreamingEouAsrManager`** (built-in end-of-utterance detection). Model `parakeet-realtime-eou-120m-coreml`, **NVIDIA Open Model License** (record per-asset; FluidAudio downloads its own models from HF on first use).
> - First `swift package resolve` of FluidAudio can take ~30 minutes (full-history clone). Expected; do not abandon.
> - FluidAudio joins the **Xcode app target only** (like llama) so `swift test` stays headless and dependency-free. Voice impl files live under `VoidloomApp/AI/Voice/`; Core gains only pure protocols/logic.
> - Voice is **English-only in v1**; always-listening keeps the macOS orange mic indicator on (say so in UI copy).

## Existing seams (do not re-invent)

- `MediatorSessionMachine` events already exist: `.wakeDetected`, `.pushToTalkPressed`, `.transcriptDelta(String)` (REPLACES the transcript — full-hypothesis updates), `.transcriptFinal(String)`, `.cancelRequested`. Capture watchdog (15s) and parse watchdog (10s) exist.
- `MediatorSessionCoordinator.perform(_:)` currently no-ops `.startCapture`/`.stopCapture` — Plan 3 fills exactly these. `cancel()` becomes voice-reachable (cancel-during-parsing already cancels watchdog + brain task).
- Typed confirmation ("confirm"/"yes"/"cancel"/"no" while `awaitingConfirmation`) lives in `submitTyped` — the voice path must route final transcripts through the SAME logic (extract a shared helper; do not duplicate).
- HUD (`MediatorHUDView`) already renders all `MediatorState` cases including `.capturing` with a live transcript.

---

## Task 1 — Core voice seams + coordinator capture wiring (headless)

**Create:** `Sources/VoidloomCore/Mediator/SpeechTranscribing.swift`; modify `MediatorSessionCoordinator`; tests in `Tests/VoidloomTests/MediatorVoiceTests.swift` (new).

- Protocol (Core, pure): `public protocol SpeechTranscribing: AnyObject { @MainActor func startUtterance() ; @MainActor func stopUtterance() ; @MainActor var onEvent: ((TranscriberEvent) -> Void)? { get set } }` with `public enum TranscriberEvent: Equatable, Sendable { case partial(String); case final(String); case unavailable(String) }`. (Names are binding for later tasks.)
- Coordinator: `init` gains optional `transcriber: SpeechTranscribing? = nil`. `perform(.startCapture)` → `transcriber?.startUtterance()`; `.stopCapture` → `stopUtterance()`. Transcriber events map: `.partial` → `send(.transcriptDelta(_))`, `.final` → shared confirmation-aware submit path (same branch typed input uses while `awaitingConfirmation`; otherwise `send(.transcriptFinal(_))`), `.unavailable(msg)` → cancel capture + narrate msg.
- Public entry points: `pushToTalkPressed()` (sends the event) and `wakeDetected()`.
- Tests (all headless, fake transcriber): start/stop called on capture effects; partial→delta replaces; final→parse pipeline end-to-end to executor via FastPathBrain; final "confirm" while awaitingConfirmation confirms (shared path proven); `.unavailable` narrates and returns to idle; no transcriber (nil) keeps typed path working (all 233 existing tests stay green).

**Acceptance:** full `swift test` green (233 + new); no new imports in Core beyond Foundation/Combine.

## Task 2 — FluidAudio + AudioCaptureService + ParakeetTranscriber (app target)

**Modify:** `Voidloom.xcodeproj/project.pbxproj` (add `XCRemoteSwiftPackageReference` for `https://github.com/FluidInference/FluidAudio` pinned exactly to v0.15.4 + product dep on the app target — mirror how SwiftTerm was added on the sibling branch if visible, else standard Xcode SPM entries; A2-pattern for new file refs). **Create:** `VoidloomApp/AI/Voice/AudioCaptureService.swift`, `VoidloomApp/AI/Voice/ParakeetTranscriber.swift`.

- `AudioCaptureService`: sole owner of `AVAudioEngine` input tap; converts to 16kHz mono Float32 via `AVAudioConverter`; start/stop idempotent; surfaces mic-permission state (`AVCaptureDevice.authorizationStatus(for: .audio)` request-on-first-use); no SwiftUI.
- `ParakeetTranscriber: SpeechTranscribing`: wraps `StreamingEouAsrManager` fed by the capture service; EOU → `.final`; hypothesis updates → `.partial`; model-not-yet-downloaded / init failure → `.unavailable("Voice model still preparing — try again shortly.")` (FluidAudio manages its own model download; first use may take minutes — surface, don't block).
- Record the NVIDIA Open Model License string wherever Settings copy lists licenses (extend in Task 4).

**Acceptance:** `swift test` untouched-green (no SPM changes to Package.swift); `xcodebuild` BUILD SUCCEEDED with FluidAudio resolved; report documents any FluidAudio API drift from the spike (verify against the pinned tag's real API, adapt, and list).

## Task 3 — Push-to-talk UX end-to-end

**Modify:** `MediatorHUDView` (+ wiring in `RootView`).

- Hold-to-talk mic button on the HUD pill (press-and-hold: `pushToTalkPressed()` on press; release → `transcriber.stopUtterance()` which yields the final). Keyboard: hold **⌥Space** while the app is active (in-app `NSEvent.addLocalMonitor` — NOT a global monitor; no Accessibility permission).
- First voice use triggers the mic permission prompt (via capture service); denial narrates "Microphone access denied — voice is off; typing still works." and the mic button shows a disabled state.
- Transcriber/coordinator assembled in `RootView.init` alongside the brain (transcriber only constructed when mic hardware exists).

**Acceptance:** build green; suite green; report includes a manual QA checklist (hold, speak "start two claude agents", release → agents spawn).

## Task 4 — Opt-in always-listening wake phrase + Settings voice section

**Modify:** `ParakeetTranscriber`/`AudioCaptureService` (continuous mode), coordinator (`wakeDetected` arming), `LocalAISettingsSection` or a new `VoiceSettingsSection`.

- Settings: "Voice" group — mode picker (Off / Push-to-talk / Always listening), wake phrase text field (default "hey voidloom", lowercase keyword match), honesty copy: "Always listening keeps the microphone (and the orange indicator) on whenever Voidloom runs. Audio never leaves this Mac." + English-only note + Parakeet license attribution.
- Always-listening: continuous transcription; a rolling window of finals/partials is keyword-matched against the wake phrase; on match → `wakeDetected()` (machine opens the capture window; the transcript that follows the phrase becomes the command — simplest correct v1: discard pre-phrase text, treat post-phrase text in the same final as the utterance start).
- Voice confirm already works via Task 1's shared path.

**Acceptance:** build + suite green; manual QA checklist in the report (toggle modes; wake phrase arms; mic indicator behavior described).

## Deferred (do NOT build in Plan 3)

Self-trained CoreML KWS wake-word model (separate plan); non-English voice; global push-to-talk hotkey; TTS responses; transcriptDelta rename (documented at the transcriber boundary instead).

## Closeout

Lead reviews each task diff (as in 2b); after Task 4: ledger, docs commit (`git add -f` this plan), remaining-work doc update, then Plan 4.
