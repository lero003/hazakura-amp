# Handoff

## Current State
- Hazakura Amp is a menu-bar system audio boost utility with a Safari YouTube companion remote.
- Current version: **v0.4.1** (build 7).
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

## Distribution
- `main` includes v0.4.1.
- GitHub prereleases: `v0.4.1-dev` (Apple Development) and `v0.4.1-developer-id` (Developer ID, not notarized).
- **Single entry:** `cd spike/core-audio-tap && ./scripts/build_dist.sh`
  - `check` — identities + distribution profile preflight
  - `release` (default) — Developer ID zip for other Macs → `dist/HazakuraAmp-v0.4.1-developer-id.zip`
  - `notarized` — release + notarytool + staple → `dist/HazakuraAmp-v0.4.1-notarized.zip`
  - `dev` — Apple Development team preview (registered Macs only)
- Shared helpers: `scripts/lib/dist_common.sh`. Legacy script names are thin wrappers.
- Release config in `project.yml` pins `PROVISIONING_PROFILE_SPECIFIER` to Developer ID distribution profiles ("Hazakura Amp dev" / "Hazakura Amp safari-extension dev", `ProvisionsAllDevices`).
- Notary credentials: `HAZAKURA_NOTARY_APPLE_ID` / `HAZAKURA_NOTARY_TEAM_ID` / `HAZAKURA_NOTARY_PASSWORD`, or interactive prompt.
- Next distribution upgrade: run `./scripts/build_dist.sh notarized` (needs App-Specific Password), then consider Notarized DMG + Sparkle auto-update.

## Next Actions
1. Run `./scripts/build_dist.sh notarized` with an App-Specific Password; confirm `spctl --assess` reports `accepted / source=Notarized Developer ID`.
2. Local smoke: presets, EQ, gain ramp feel, device switch reconnect.
3. Safari smoke: speed, captions, video-end reset to 100%, boost remote.
4. Optional product: persist gain/EQ, launch-at-login.

## Avoid
- Do not add ad blocking, sponsor skipping, downloads, or Web Audio as the primary boost path.
- Do not expand into a full YouTube suite or app-level mixer without an explicit product decision.
