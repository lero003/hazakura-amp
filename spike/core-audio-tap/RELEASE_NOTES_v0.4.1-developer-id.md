# Hazakura Amp v0.4.1 — Developer ID preview

Product version is still **v0.4.1 (build 7)**. This release upgrades packaging so the app can be shared beyond registered development Macs.

## What’s new in this packaging release

- Single packaging entry: `./scripts/build_dist.sh`
  - `check` — identities + distribution profiles
  - `release` (default) — Developer ID Application zip
  - `notarized` — release + notarytool + staple
  - `dev` — Apple Development team preview
- Release signing uses distribution provisioning profiles with `ProvisionsAllDevices` and a secure codesign timestamp (notarization-ready).
- Legacy `build_release_candidate.sh` / `build_dev_distribution.sh` remain as thin wrappers.

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

1. Unzip the archive
2. Move `Hazakura Amp.app` to `/Applications`
3. First launch: right-click → Open if Gatekeeper warns
4. Optional: enable Safari extension under Settings → Extensions

### Verify (optional)

```bash
codesign --verify --strict --deep --verbose=2 "Hazakura Amp.app"
codesign -dv --verbose=2 "Hazakura Amp.app"
# expect: Developer ID Application
```

## Rebuild locally

```bash
cd spike/core-audio-tap
./scripts/build_dist.sh check
./scripts/build_dist.sh
# optional full any-Mac path:
./scripts/build_dist.sh notarized
```

## Packaging note (Safari extension / SFErrorDomain:1)

Early GitHub zip assets packaged with plain `ditto -c -k --keepParent` could embed AppleDouble `._*` files for extended attributes. After a plain `unzip`, those files appear inside the signed bundle, **break codesign**, and Safari returns `SFErrorDomain:1` for the embedded Web Extension. “Allow unsigned extensions” is not a reliable fix (Develop menu only; resets when Safari quits).

Fixed packaging (`package_zip` in `scripts/lib/dist_common.sh`):
- strip resource forks / xattrs (`--norsrc --noextattr`, `xattr -cr`)
- regression-check with plain `unzip` + `codesign --verify --strict --deep`

Rebuild / re-upload the zip before sharing again:

```bash
cd spike/core-audio-tap
./scripts/build_dist.sh release
# or: ./scripts/build_dist.sh notarized
```

## Not in this release

- Notarized / stapled zip (run `./scripts/build_dist.sh notarized` when App-Specific Password is available)
- Notarized DMG / Sparkle auto-update
- App Store distribution
