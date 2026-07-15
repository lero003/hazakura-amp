# Hazakura Amp v0.4.0 (developer preview)

Developer preview for team / registered testers. **Not notarized.**

Current GitHub prerelease ships the **Apple Development** zip
(`HazakuraAmp-v0.4.0-dev.zip`) because this machine has team development
profiles for App Groups, but not Developer ID profiles yet. That zip runs on
Macs enrolled in the development provisioning profile. Wider distribution
needs Developer ID profiles + `./scripts/build_release_candidate.sh` + notarization.

## Highlights

### Audio quality (system-wide)
- Smooth ~50 ms gain ramp when changing boost
- Soft limiter tuned for high boost without hard clip spikes
- Fixed presets: 標準 100% / 動画 160% / 講義 220% / 最大 300%
- Simple 3-band EQ (low / mid / high, ±6 dB)
- Auto-reconnect when the default output device changes

### YouTube floating remote (Safari extension)
- Boost control still goes through the native Hazakura Amp app
- Playback speed: 0.75x / 1x / 1.25x / 1.5x / 2x
- Captions toggle via YouTube’s own control
- On video end, boost returns to 100% (does not auto-start capture)
- Repeat remains page-local (`video.loop`)

### Product UI
- Status chips, menu-bar toolTips, folded diagnostics
- Japanese product copy; accessibility labels stay English

## Install (dev / direct zip)

1. Download `HazakuraAmp-v0.4.0-dev.zip` (and optional `.SHA256SUMS`) from the GitHub Release.
2. Optionally verify: `shasum -a 256 -c HazakuraAmp-v0.4.0-dev.SHA256SUMS`
3. Unzip, then move `Hazakura Amp.app` to `/Applications` (recommended).
4. First open: right-click the app → **Open** → confirm if Gatekeeper warns.
5. Grant **System Audio** access when prompted (not microphone).
6. Optional: enable the Safari Web Extension from diagnostics or Safari Settings → Extensions.

If the app refuses to launch on another Mac, that machine is likely not covered by the development provisioning profile. Register the Mac in the Apple Developer portal and rebuild, or move to Developer ID distribution.

## Build locally

Team / registered-Mac preview:

```bash
cd spike/core-audio-tap
xcodegen generate
./scripts/build_dev_distribution.sh
```

Output:
- App: `build/Build/Products/Debug/Hazakura Amp.app`
- Zip: `dist/HazakuraAmp-v0.4.0-dev.zip`
- Checksums: `dist/HazakuraAmp-v0.4.0-dev.SHA256SUMS`

Developer ID Release candidate (needs Developer ID profiles):

```bash
./scripts/build_release_candidate.sh
```

Notarization is intentionally **not** run by either script.

## Known limits

- macOS 26+ only
- Notarized DMG / auto-update not included
- Safari E2E depends on enabling the extension after install
- High boost can still distort; limiter reduces but does not eliminate clipping
- No ad blocking, sponsor skip, or Web Audio boost path

## Verify

```bash
codesign --verify --strict --deep --verbose=2 "/path/to/Hazakura Amp.app"
codesign -dv --verbose=2 "/path/to/Hazakura Amp.app"
```

Expect Developer ID Application signing and App Group `group.dev.hazakura-amp` when profiles allow.
