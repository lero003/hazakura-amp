#!/usr/bin/env bash
# Build a Developer ID Application signed Release candidate zip.
#
# Requires:
#   - Developer ID Application certificate
#   - Developer ID provisioning profiles for:
#       dev.hazakura-amp
#       dev.hazakura-amp.safari-extension
#     with App Group group.dev.hazakura-amp
#
# If those profiles are missing, use ./scripts/build_dev_distribution.sh instead
# (Apple Development / team preview only).
#
# Notarization is intentionally not submitted here.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_DIR/build}"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/Hazakura Amp.app"
ENTITLEMENTS_PATH="$DIST_DIR/HazakuraAmp-release.entitlements.plist"

cd "$PROJECT_DIR"

set +e
xcodebuild \
  -project CoreAudioTapPoC.xcodeproj \
  -scheme CoreAudioTapPoC \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  clean build
BUILD_STATUS=$?
set -e

if [[ $BUILD_STATUS -ne 0 ]]; then
  cat >&2 <<'EOF'
Release / Developer ID build failed.

Common cause: missing Developer ID provisioning profiles for the sandboxed
app + Safari extension (App Group group.dev.hazakura-amp).

Workarounds:
  1) Create/download Developer ID profiles in the Apple Developer portal, or
  2) Ship a team-only preview with:
       ./scripts/build_dev_distribution.sh
EOF
  exit "$BUILD_STATUS"
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
ZIP_PATH="$DIST_DIR/HazakuraAmp-v${APP_VERSION}-developer-id.zip"

codesign --verify --strict --deep --verbose=2 "$APP_PATH"

mkdir -p "$DIST_DIR"
codesign -d --entitlements "$ENTITLEMENTS_PATH" "$APP_PATH" 2>/dev/null || true
if /usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$ENTITLEMENTS_PATH" >/dev/null 2>&1; then
  if [[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$ENTITLEMENTS_PATH")" == "true" ]]; then
    echo "Release candidate unexpectedly has get-task-allow=true." >&2
    exit 1
  fi
fi

codesign -dvvv --entitlements :- "$APP_PATH" 2>&1 | sed -n '1,140p'

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo
echo "Release candidate app: $APP_PATH"
echo "Developer ID zip: $ZIP_PATH"
echo "Notarization is intentionally not submitted by this script."
