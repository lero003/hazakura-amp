# Hazakura Amp v0.4.1 (developer preview)

Patch release on top of v0.4.0 for shared testing on other Macs.

## Changes since v0.4.0

- **停止ボタン**がダークモードで読めない問題を修正
- 診断パネル展開時に上部操作が押し出される問題を修正（ポップオーバーをスクロール可能に）
- YouTube **字幕ボタンが OFF にできない**問題を修正（プレイヤー API + 確実なトグル）
- 診断イベントログのネスト ScrollView を解消し、スクロール競合を緩和

## Install (dev zip)

1. Download `HazakuraAmp-v0.4.1-dev.zip` and optional `HazakuraAmp-v0.4.1-dev.SHA256SUMS`
2. Verify (optional):

   ```bash
   shasum -a 256 -c HazakuraAmp-v0.4.1-dev.SHA256SUMS
   ```

3. Unzip and move `Hazakura Amp.app` to `/Applications`
4. First launch: right-click → **Open** if Gatekeeper warns
5. Allow **system audio** access (not microphone)
6. Optional: enable Safari extension under Settings → Extensions

## Signing note (important for other Macs)

This prerelease is signed with **Apple Development** + a team provisioning profile (App Group enabled).

- It is **not notarized**
- It may refuse to launch on Macs that are **not registered** in the development provisioning profile
- If another Mac cannot open it:
  1. Register that Mac’s hardware UUID in the Apple Developer portal (Devices), regenerate the development profile, rebuild — or
  2. Create **Developer ID** profiles for `dev.hazakura-amp` and `dev.hazakura-amp.safari-extension`, then use `./scripts/build_release_candidate.sh` + notarization

## Build locally

```bash
cd spike/core-audio-tap
xcodegen generate
./scripts/build_dev_distribution.sh
```

Outputs under `dist/`:

- `HazakuraAmp-v0.4.1-dev.zip`
- `HazakuraAmp-v0.4.1-dev.SHA256SUMS`
- `HazakuraAmp-v0.4.1-dev-INSTALL.txt`

## Smoke checklist

- [ ] Menu bar icon appears; Start / Stop readable in dark mode
- [ ] Boost presets + slider work
- [ ] Diagnostics open → can scroll back to Start/Stop
- [ ] YouTube remote: boost, speed, captions ON then OFF, video-end → 100%
