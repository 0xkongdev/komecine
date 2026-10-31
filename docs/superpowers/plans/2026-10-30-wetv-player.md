# WeTV-style Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Ship KomeCine's custom AVPlayer controls and viewing features based on the observed WeTV player.
**Architecture:** One PlaybackCoordinator owns the player. SwiftUI controls share a stable AVPlayerLayer with native PiP, AirPlay, orientation and volume bridges. HLS metadata, WebVTT captions and account-owned offline downloads live in focused services.
**Tech Stack:** Swift 5, SwiftUI, AVFoundation/AVKit, MediaPlayer, Swift Testing, XCTest.
**Spec:** `docs/superpowers/specs/2026-10-30-wetv-player-design.md` (approved by user's “tiếp”).

## Global Constraints
- Keep app minimum iOS 17; no new third-party player dependency or backend schema change.
- Retain KomeCine branding, account separation, cloud's latest progress per movie and a single AVPlayer across layout changes.
- Quality/subtitle choices reflect actual source capabilities; no fake 4K or bilingual toggles.
- Downloads stay local and belong to their original account; guest ownership migrates once at sign-in.

## Review Focus
- Old async metadata/seek responses must not change a newly selected episode.
- Paused playback and chosen speed survive temporary fast playback, seeking and layout changes.
- Relative HLS URIs, missing resolutions and timestamp maps do not create invalid quality/caption choices.
- Account changes cannot write old playback/download progress into the new account.
- Fullscreen, PiP and minimized state share a mounted video layer and restore sensible orientation.

## Verification command
`xcodebuild test -project ios/KomeCine/KomeCine.xcodeproj -scheme KomeCine -destination 'platform=iOS Simulator,id=73FB8A5F-1CE1-4DAE-8580-DA883AC9F2DF' -only-testing:KomeCineTests -quiet`

### Task 1: Source metadata and player interaction rules
**Files:** Create `ios/KomeCine/KomeCine/PlayerModels.swift`, `HLSMetadata.swift`, `WebVTTCaptions.swift`; test `ios/KomeCine/KomeCineTests/PlayerFeatureTests.swift`.
**Interfaces:** Produce `PlayerInteractionState` (panel, locked, visible, reveal, lock, autoHide), `PlaybackMath.clamp(_:duration:)`, `HLSMetadata.parse(_:baseURL:)`, `SubtitleCue` and `WebVTT.parse(_:segmentStart:)`.
- [x] Write tests: seek clamps nonfinite/negative/over-duration; lock closes panel; panel prevents auto-hide; relative HLS quality/audio/subtitle URLs resolve; a media playlist has no invented variants; timestamp-mapped VTT cues align and strip cue markup.
- [x] Run verification; expect feature APIs missing before implementation.
- [x] Implement focused value models and parsers; test actual parsed outputs, not internal calls.
- [x] Run verification; expect all unit tests passing. Commit task.

### Task 2: Observable playback, tracks and per-episode progress
**Files:** Modify `PlaybackCoordinator.swift`, `LocalLibrary.swift`, `CloudSync.swift`; create `SubtitleController.swift`; extend `PlayerFeatureTests.swift`.
**Interfaces:** Consume Task 1. Produce coordinator published time/duration/buffer/isPlaying/error, selectedSpeed, quality and track lists, `seek(to:)`, `skip(_:)`, `setSpeed(_:)`, `beginBoost()`, `endBoost()`, `changeServer(to:)`, `retry()`, subtitle selection and screenshot actions. LocalLibrary adds `episodeProgress(movieID:source:)`.
- [x] Test local per-episode resume independently of latest-per-movie cloud record; guest migration/account isolation; speed survives pause/boost and invalid speeds rejected; retry/close cancels stale source work.
- [x] Watch tests fail, implement source-scoped observers/tasks, seeking guards and progressive metadata loading; add dual WebVTT renderer model with cancellation and clock-based cue lookup.
- [x] Preserve live player during minimize/layout; change server retains position and episode change uses saved target position.
- [x] Run verification; expect all unit tests passing. Commit task.

### Task 3: Offline downloads and account ownership
**Files:** Create `OfflineDownloads.swift`, `DownloadsView.swift`; modify `ContentView.swift`, `KomeCineApp.swift`; extend `PlayerFeatureTests.swift`.
**Interfaces:** Produce `OfflineDownloads` with published records, `setAccount(_:)`, `download(movie:source:)`, `cancel(_:)`, `remove(_:)`, `localURL(for:)`; support background session app delegate completion.
- [x] Test persisted record ownership, one-time guest adoption, monotonic bounded progress, missing cached files not reported ready, old-owner callbacks never change active owner, and local URL lookup keyed by movie/server/episode.
- [x] Watch tests fail; implement AVAssetDownloadURLSession delegate and persisted records with system-owned asset URLs, cancellation cleanup and errors.
- [x] Add Library downloads screen, open offline source with metadata, integrate stop-before-account-switch and guest adoption. Do not publish local paths to cloud.
- [x] Run verification; expect all unit tests passing. Commit task.

### Task 4: Custom WeTV-style controls and native bridges
**Files:** Replace `PlayerScreen.swift`; create `PlayerSurface.swift`, `PlayerPanels.swift`, `PlayerGestures.swift`; modify mini player in `ContentView.swift`; test `KomeCineUITests/CustomPlayerUITests.swift`.
**Interfaces:** Consume Tasks 1–3. Surface publishes native PiP/orientation/volume actions; controls call the coordinator and use PlayerInteractionState.
- [x] Write UI tests against controlled launch fixture: speed panel and selection, quality availability, lock blocking menus, double-tap seek, portrait/fullscreen return, minimized play/pause. Expect missing custom identifiers before UI work.
- [x] Implement a stable video host; native gestures discriminate controls and scroll panels. Use existing UI test accessibility labels where practical.
- [x] Implement portrait and landscape layouts, progress scrubber, one right panel at a time, speed/quality/CC/episode/server/more panels, screenshot sharing, local intro skip setting, download action and caption overlay.
- [x] Implement PiP restore, explicit fullscreen geometry request, native AirPlay picker and volume slider; restore screen brightness when leaving.
- [x] Run unit tests and focused custom UI tests; expect passing. Commit task.

### Task 5: End-to-end validation and review
**Files:** Update `README.md`, this checklist and spec status; fix implementation as needed.
- [x] Run complete iOS test suite and build for simulator; report any existing network-dependent failures by name. (Full run plus targeted reruns recorded in validation report.)
- [x] Inspect portrait/landscape screenshots using computer tools, exercise a real HLS source and download/offline capability where available. (Direct layout checks and live HLS UI tests passed; physical offline path unverified.)
- [x] Try physical device build/run if connected; otherwise report the unavailable device as a validation limitation, continue all simulator checks.
- [x] Request one whole-change code review with spec, plan, tests and Review Focus; address material issues with regression coverage.
- [x] Verify final diff, document supported features/actual validation, commit and report result without claiming untested TV/PiP/real-device success.
