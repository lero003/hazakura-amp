#!/usr/bin/env bash
# Build a shareable *developer preview* zip of Hazakura Amp.
#
# This uses Apple Development signing + team provisioning profiles that already
# exist for App Groups. It is intended for:
#   - the developer's registered Macs
#   - team / friend testers whose Mac UDIDs are in the development profile
#
# It is NOT a notarized public release. For wider distribution, install a
# Developer ID provisioning profile for both app IDs, then use
# ./scripts/build_release_candidate.sh and notarize separately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_DIR/build}"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-8BNUB2R9C8}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Hazakura Amp.app"

cd "$PROJECT_DIR"

if [[ ! -f "$PROJECT_DIR/CoreAudioTapPoC.xcodeproj/project.pbxproj" ]]; then
  echo "Xcode project missing. Run: xcodegen generate" >&2
  exit 1
fi

echo "==> Building $CONFIGURATION with Automatic Apple Development signing"
# Prefer a clean product so prior unit-test host embeds (*.xctest) are not shipped.
rm -rf "$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
xcodebuild \
  -project CoreAudioTapPoC.xcodeproj \
  -scheme CoreAudioTapPoC \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY='Apple Development' \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

# Safety: never ship unit-test bundles accidentally embedded by TEST_HOST runs.
if compgen -G "$APP_PATH/Contents/PlugIns/"*.xctest >/dev/null; then
  echo "Removing embedded test bundles from app before packaging:" >&2
  rm -rf "$APP_PATH/Contents/PlugIns/"*.xctest
  codesign --force --deep --sign "Apple Development" --options runtime --timestamp=none "$APP_PATH"
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
ZIP_NAME="HazakuraAmp-v${APP_VERSION}-dev.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
CHECKSUM_PATH="$DIST_DIR/HazakuraAmp-v${APP_VERSION}-dev.SHA256SUMS"
NOTES_PATH="$DIST_DIR/HazakuraAmp-v${APP_VERSION}-dev-INSTALL.txt"

echo "==> Verifying signature"
codesign --verify --strict --deep --verbose=2 "$APP_PATH"
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | sed -n '1,80p'

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$CHECKSUM_PATH" "$NOTES_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
(
  cd "$DIST_DIR"
  shasum -a 256 "$ZIP_NAME" > "$(basename "$CHECKSUM_PATH")"
)

cat > "$NOTES_PATH" <<EOF
Hazakura Amp v${APP_VERSION} (build ${APP_BUILD}) — developer preview

What this is
- Apple Development signed build for registered team Macs
- Not notarized
- Includes Safari YouTube remote extension inside the app bundle

Install
1. Unzip this archive
2. Move "Hazakura Amp.app" to /Applications
3. First launch: right-click → Open (if Gatekeeper warns)
4. Allow system audio access when prompted (not microphone)
5. Optional: enable Safari extension under Settings → Extensions

Limits
- Macs not registered in the development provisioning profile may refuse to launch
- For public-ish distribution you need Developer ID profiles + notarization
  (see scripts/build_release_candidate.sh)

Checksum
- See $(basename "$CHECKSUM_PATH")
EOF

echo
echo "Dev distribution app:  $APP_PATH"
echo "Dev distribution zip:  $ZIP_PATH"
echo "Checksums:             $CHECKSUM_PATH"
echo "Install notes:         $NOTES_PATH"
echo
echo "Signing kind: Apple Development (team preview — not Developer ID / not notarized)"
