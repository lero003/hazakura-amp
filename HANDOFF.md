# Handoff

## Current State
- Hazakura Amp is a menu-bar system audio boost utility with a Safari YouTube companion remote.
- Current version: **v0.4.0** (build 6).
- Native app owns all system audio processing. YouTube content script does not use Web Audio for boost.
- Audio path: Core Audio process tap (mute) + ScreenCaptureKit capture + ring buffer + gain ramp + soft limiter + 3-band EQ + AVAudioEngine output.

## Recent Changes (v0.4.0 feature expansion)

### System-wide audio quality / utility
- **~50ms gain ramp** toward target (snap on stop/shutdown for safety).
- **Improved soft limiter** (knee + tanh compression, ceiling 0.98).
- **Presets**: 標準 100% / 動画 160% / 講義 220% / 最大 300%.
- **3-band EQ**: 低/中/高 ±6 dB via `AVAudioUnitEQ` (no noise reduction / advanced DSP).
- **Output device change auto-reconnect** with retries; falls back to manual Start if reconnect fails.

### YouTube remote
- **Playback speed** 0.75 / 1 / 1.25 / 1.5 / 2x on the current `video` element (page-local).
- **Captions toggle** clicks YouTube’s existing subtitles button only.
- **Video ended → boost 100%** (skipped when Repeat is on).
- Existing boost slider/presets/repeat/disconnect handling retained.

## Tests
- `xcodebuild ... test` — **66 tests, 0 failures** (last run).
- Also: `node --check YouTubeRemoteExtension/content.js`, `xcodegen generate`.

## Risks / Unknowns
- YouTube DOM for captions button can change; selectors are best-effort.
- Video-ended boost reset depends on `ended` events and SPA navigation rebinding.
- EQ + high boost can still clip; limiter reduces but does not eliminate distortion.
- Safari manual E2E still required for extension packaging/signing path.

## Next Actions
1. Local smoke: presets, EQ, gain ramp feel, device switch reconnect.
2. Safari smoke: speed, captions, video-end reset to 100%, boost remote.
3. Optional: persist gain/EQ across launches, launch-at-login, notarized DMG.

## Avoid
- Do not add ad blocking, sponsor skipping, downloads, or Web Audio as the primary boost path.
- Do not expand into a full YouTube suite or app-level mixer without an explicit product decision.
