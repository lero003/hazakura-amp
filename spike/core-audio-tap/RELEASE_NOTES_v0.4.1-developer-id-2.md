# Hazakura Amp v0.4.1 — Developer ID preview (packaging fix)

Product version is still **v0.4.1 (build 7)**. This is a **patch re-release** of the Developer ID zip. The previous tag `v0.4.1-developer-id` is left immutable; use this release instead.

## Why this re-release

The earlier Developer ID zip embedded AppleDouble `._*` files (from extended attributes). After a plain `unzip` (common for GitHub downloads), those files appeared inside the signed app bundle, **broke codesign**, and Safari returned:

```text
SFErrorDomain:1 The operation couldn’t be completed. (SFErrorDomain error 1.)
```

“Allow unsigned extensions” in Safari’s Develop menu does **not** fix this reliably (resets when Safari quits). A correctly sealed Developer ID build should not need that menu.

## What’s fixed

- `package_zip` strips resource forks / xattrs (`--norsrc --noextattr`, `xattr -cr`)
- Packaging regression gate: plain `unzip` + `codesign --verify --strict --deep`
- Clearer in-app guidance when Safari reports `SFErrorDomain:1`
- Install notes recommend `/Applications` and enabling the embedded Safari extension without Develop menu workarounds

## Asset

- `HazakuraAmp-v0.4.1-developer-id.zip`
- `HazakuraAmp-v0.4.1-developer-id.SHA256SUMS`
- `HazakuraAmp-v0.4.1-developer-id-INSTALL.txt`

## Signing / install expectations

- **Signed with:** Developer ID Application
- **Not notarized yet.** Gatekeeper may still require first launch via right-click → Open
- Target Macs do **not** need to be registered in the Apple Developer portal
- After install, allow system audio access when prompted (not microphone)

### Install

1. Unzip the archive (Finder or `unzip` are both OK)
2. Move `Hazakura Amp.app` to `/Applications`
3. First launch: right-click → Open if Gatekeeper warns
4. Enable Safari extension: Safari → Settings → Extensions → Hazakura Amp  
   (no Develop menu / “Allow unsigned extensions” needed)

### Verify (optional)

```bash
codesign --verify --strict --deep --verbose=2 "Hazakura Amp.app"
codesign -dv --verbose=2 "Hazakura Amp.app"
# expect: Developer ID Application
# after plain unzip there must be no ._* files inside the bundle
```

## Rebuild locally

```bash
cd spike/core-audio-tap
./scripts/build_dist.sh check
./scripts/build_dist.sh
# optional full any-Mac path:
./scripts/build_dist.sh notarized
```

## Not in this release

- Notarized / stapled zip (run `./scripts/build_dist.sh notarized` when App-Specific Password is available)
- Notarized DMG / Sparkle auto-update
- App Store distribution

## Supersedes

- [`v0.4.1-developer-id`](https://github.com/lero003/hazakura-amp/releases/tag/v0.4.1-developer-id) — do not use that zip for Safari extension installs
