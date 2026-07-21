#!/usr/bin/env bash
# Notarize a Developer ID signed Hazakura Amp zip and staple the ticket.
#
# Produces a notarized, stapled distribution zip that launches on any Mac
# without per-device registration or certificate installation.
#
# Prereq: a Developer ID zip from:
#   ./scripts/build_dist.sh release
#   (legacy: ./scripts/build_release_candidate.sh)
#
# One-shot alternative (build + notarize):
#   ./scripts/build_dist.sh notarized
#
# Credentials (in priority order):
#   1. Env vars: HAZAKURA_NOTARY_APPLE_ID / HAZAKURA_NOTARY_TEAM_ID /
#      HAZAKURA_NOTARY_PASSWORD
#   2. Keychain profile: HAZAKURA_NOTARY_KEYCHAIN_PROFILE (from
#      `xcrun notarytool store-credentials`)
#   3. Local env file (gitignored), first match:
#        spike/core-audio-tap/.env.notary
#        repo-root/.env.notary
#   4. Interactive prompt (password via read -s, not echoed or saved to history)
#
# Optional App Store Connect API key auth (instead of Apple ID password):
#   HAZAKURA_NOTARY_KEY_ID / HAZAKURA_NOTARY_ISSUER / HAZAKURA_NOTARY_KEY_PATH
#
# Outputs under dist/:
#   HazakuraAmp-v<ver>-notarized.zip       (notarized + stapled app, re-zipped)
#   HazakuraAmp-v<ver>-notarized.SHA256SUMS
#   HazakuraAmp-v<ver>-notarized-INSTALL.txt
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/dist_common.sh
source "$SCRIPT_DIR/lib/dist_common.sh"
DEFAULT_TEAM_ID="8BNUB2R9C8"
DEFAULT_APPLE_ID="${HAZAKURA_NOTARY_APPLE_ID_DEFAULT:-lero003@gmail.com}"
# PROJECT_DIR is spike/core-audio-tap; repo root is one level up.
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"

load_notary_env_file() {
  local f
  for f in \
    "${HAZAKURA_NOTARY_ENV_FILE:-}" \
    "$PROJECT_DIR/.env.notary" \
    "$REPO_ROOT/.env.notary"
  do
    [[ -n "$f" && -f "$f" ]] || continue
    echo "==> Loading notary credentials from $f" >&2
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1090
    source "$f"
    set +a
    return 0
  done
  return 1
}

load_notary_env_file || true

ZIP_PATH="${1:-}"
if [[ -z "$ZIP_PATH" ]]; then
  # Pick the most recent developer-id zip if none was given.
  ZIP_PATH="$(ls -t "$DIST_DIR"/HazakuraAmp-v*-developer-id.zip 2>/dev/null | head -n 1 || true)"
  if [[ -z "$ZIP_PATH" ]]; then
    echo "No Developer ID zip found under $DIST_DIR." >&2
    echo "Run ./scripts/build_dist.sh release first, or pass the zip path:" >&2
    echo "  $0 path/to/HazakuraAmp-vX.Y.Z-developer-id.zip" >&2
    exit 1
  fi
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Zip not found: $ZIP_PATH" >&2
  exit 1
fi

# Workdir for unzip/staple. Cleaned on exit.
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Unzipping $(basename "$ZIP_PATH") for pre-flight signature check"
ditto -x -k "$ZIP_PATH" "$WORK_DIR"
APP_PATH="$(find "$WORK_DIR" -maxdepth 2 -name 'Hazakura Amp.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Could not find 'Hazakura Amp.app' inside the zip." >&2
  exit 1
fi

echo "==> Verifying Developer ID Application signature before notarization"
if ! codesign --verify --strict --deep --verbose=2 "$APP_PATH" >/dev/null 2>&1; then
  echo "Signature verification failed for $APP_PATH." >&2
  echo "Rebuild with ./scripts/build_dist.sh release." >&2
  exit 1
fi
# codesign emits the Authority lines with leading whitespace/CR; strip both.
SIGNING_AUTHORITY="$(codesign -dvvv "$APP_PATH" 2>&1 | tr -d '\r' | awk -F'=[ \t]*' '/Authority=/ {print $2; exit}')"
if [[ "$SIGNING_AUTHORITY" != Developer\ ID\ Application* ]]; then
  echo "App is not signed with Developer ID Application (got: $SIGNING_AUTHORITY)." >&2
  echo "This script only notarizes Developer ID builds." >&2
  exit 1
fi
echo "    signed by: $SIGNING_AUTHORITY"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
NOTARIZED_ZIP_NAME="HazakuraAmp-v${APP_VERSION}-notarized.zip"
NOTARIZED_ZIP_PATH="$DIST_DIR/$NOTARIZED_ZIP_NAME"
CHECKSUM_PATH="$DIST_DIR/HazakuraAmp-v${APP_VERSION}-notarized.SHA256SUMS"
NOTES_PATH="$DIST_DIR/HazakuraAmp-v${APP_VERSION}-notarized-INSTALL.txt"

# --- Credentials -------------------------------------------------------------
APPLE_ID="${HAZAKURA_NOTARY_APPLE_ID:-}"
TEAM_ID="${HAZAKURA_NOTARY_TEAM_ID:-$DEFAULT_TEAM_ID}"
PASSWORD="${HAZAKURA_NOTARY_PASSWORD:-}"
KEYCHAIN_PROFILE="${HAZAKURA_NOTARY_KEYCHAIN_PROFILE:-}"
KEY_ID="${HAZAKURA_NOTARY_KEY_ID:-}"
ISSUER="${HAZAKURA_NOTARY_ISSUER:-}"
KEY_PATH="${HAZAKURA_NOTARY_KEY_PATH:-}"

# Prefer non-interactive auth modes first (agents / CI).
AUTH_MODE=""
if [[ -n "$KEYCHAIN_PROFILE" ]]; then
  AUTH_MODE="keychain-profile"
elif [[ -n "$KEY_ID" && -n "$ISSUER" && -n "$KEY_PATH" ]]; then
  AUTH_MODE="api-key"
  if [[ ! -f "$KEY_PATH" ]]; then
    echo "App Store Connect API key not found: $KEY_PATH" >&2
    exit 1
  fi
else
  if [[ -z "$APPLE_ID" ]]; then
    if [[ -t 0 ]]; then
      read -r -p "Apple ID (email) [$DEFAULT_APPLE_ID]: " APPLE_ID
      APPLE_ID="${APPLE_ID:-$DEFAULT_APPLE_ID}"
    else
      APPLE_ID="$DEFAULT_APPLE_ID"
    fi
  fi
  if [[ -z "$PASSWORD" ]]; then
    if [[ -t 0 ]]; then
      echo "App-Specific Password (create at https://appleid.apple.com → Sign-In and Security → App-Specific Passwords):"
      read -rs -p "Password: " PASSWORD
      echo
    fi
  fi
  if [[ -n "$APPLE_ID" && -n "$PASSWORD" ]]; then
    AUTH_MODE="apple-id"
  fi
fi

if [[ -z "$AUTH_MODE" ]]; then
  cat >&2 <<EOF
error: No notarization credentials available.

GitHub downloads need Developer ID + notarization for Safari extensions.
Provide credentials in one of these ways, then re-run:

  1) Env vars (current shell):
       export HAZAKURA_NOTARY_APPLE_ID='$DEFAULT_APPLE_ID'
       export HAZAKURA_NOTARY_TEAM_ID='$DEFAULT_TEAM_ID'
       export HAZAKURA_NOTARY_PASSWORD='xxxx-xxxx-xxxx-xxxx'
       ./scripts/build_dist.sh notarized

  2) Local file (gitignored):
       cp scripts/env.notary.example .env.notary
       # edit .env.notary, then:
       ./scripts/build_dist.sh notarized

  3) Keychain profile (one-time):
       xcrun notarytool store-credentials hazakura-notary \\
         --apple-id '$DEFAULT_APPLE_ID' --team-id '$DEFAULT_TEAM_ID'
       export HAZAKURA_NOTARY_KEYCHAIN_PROFILE=hazakura-notary
       ./scripts/build_dist.sh notarized

  4) App Store Connect API key:
       export HAZAKURA_NOTARY_KEY_ID=...
       export HAZAKURA_NOTARY_ISSUER=...
       export HAZAKURA_NOTARY_KEY_PATH=/path/to/AuthKey_XXX.p8
EOF
  exit 1
fi

# --- Submit ------------------------------------------------------------------
mkdir -p "$DIST_DIR"

echo "==> Submitting to notarization service via $AUTH_MODE (this can take several minutes)"
SUBMIT_OUTPUT="$WORK_DIR/submit.txt"
set +e
case "$AUTH_MODE" in
  keychain-profile)
    xcrun notarytool submit "$ZIP_PATH" \
      --keychain-profile "$KEYCHAIN_PROFILE" \
      --wait > "$SUBMIT_OUTPUT" 2>&1
    ;;
  api-key)
    xcrun notarytool submit "$ZIP_PATH" \
      --key "$KEY_PATH" \
      --key-id "$KEY_ID" \
      --issuer "$ISSUER" \
      --wait > "$SUBMIT_OUTPUT" 2>&1
    ;;
  apple-id)
    xcrun notarytool submit "$ZIP_PATH" \
      --apple-id "$APPLE_ID" \
      --team-id "$TEAM_ID" \
      --password "$PASSWORD" \
      --wait > "$SUBMIT_OUTPUT" 2>&1
    ;;
esac
SUBMIT_STATUS=$?
set -e

cat "$SUBMIT_OUTPUT"

if [[ $SUBMIT_STATUS -ne 0 ]]; then
  SUBMISSION_ID="$(awk -F'[: ]+' '/id:/ {print $2; exit}' "$SUBMIT_OUTPUT" || true)"
  echo >&2
  echo "Notarization did not complete successfully." >&2
  if [[ -n "$SUBMISSION_ID" ]]; then
    echo "Fetch the detailed log with:" >&2
    case "$AUTH_MODE" in
      keychain-profile)
        echo "  xcrun notarytool log '$SUBMISSION_ID' --keychain-profile '$KEYCHAIN_PROFILE'" >&2
        ;;
      api-key)
        echo "  xcrun notarytool log '$SUBMISSION_ID' --key '$KEY_PATH' --key-id '$KEY_ID' --issuer '$ISSUER'" >&2
        ;;
      *)
        echo "  xcrun notarytool log '$SUBMISSION_ID' \\" >&2
        echo "    --apple-id '$APPLE_ID' --team-id '$TEAM_ID' --password <password>" >&2
        ;;
    esac
  fi
  exit "$SUBMIT_STATUS"
fi

STATUS_LINE="$(grep -E 'status:' "$SUBMIT_OUTPUT" | tail -n 1 || true)"
if [[ "$STATUS_LINE" != *Accepted* ]]; then
  echo "Notarization finished but status was not Accepted: $STATUS_LINE" >&2
  exit 1
fi

# --- Staple ------------------------------------------------------------------
echo "==> Stapling notarization ticket to the app"
# Staple is applied to the unzipped .app, not the submitted zip.
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Gatekeeper assessment"
spctl --assess --type execute --verbose "$APP_PATH"

# --- Repackage ---------------------------------------------------------------
echo "==> Repackaging notarized + stapled app"
rm -f "$NOTARIZED_ZIP_PATH" "$CHECKSUM_PATH" "$NOTES_PATH"
# Use package_zip so plain-unzip clients (GitHub zip downloads) do not get
# AppleDouble `._*` files that break the code signature / Safari extension.
package_zip "$APP_PATH" "$NOTARIZED_ZIP_PATH"
write_checksum "$NOTARIZED_ZIP_PATH" "$CHECKSUM_PATH"

cat > "$NOTES_PATH" <<EOF
Hazakura Amp v${APP_VERSION} (build ${APP_BUILD}) — notarized release

What this is
- Developer ID Application signed + Apple notarized + ticket stapled
- Runs on any Mac (macOS 26+) without per-device registration
- Double-click to open; no Gatekeeper "right-click → Open" workaround needed
- Includes Safari YouTube remote extension inside the app bundle

Install
1. Unzip this archive (Finder double-click or `unzip` are both OK for this build)
2. Move "Hazakura Amp.app" to /Applications (recommended for Safari extension discovery)
3. Launch by double-clicking (first launch may still ask for system audio access)
4. Enable Safari extension: Safari → Settings → Extensions → Hazakura Amp
   (no Develop menu / "Allow unsigned extensions" needed)

Safari extension notes
- Extension is embedded in the app; enable it after the first app launch
- If SFErrorDomain:1 appears, reinstall a fresh unzip to /Applications, launch once, restart Safari

Verify signature (optional)
  codesign --verify --strict --deep --verbose=2 "Hazakura Amp.app"
  spctl --assess --type execute --verbose "Hazakura Amp.app"
  # expect: accepted / source=Notarized Developer ID

Uninstall
- Delete "Hazakura Amp.app" from /Applications
- Optionally remove ~/Library/Group Containers/group.dev.hazakura-amp
  if you enabled the Safari extension

Checksum
- See $(basename "$CHECKSUM_PATH")
EOF

echo
echo "Notarized app:        $APP_PATH"
echo "Notarized zip:        $NOTARIZED_ZIP_PATH"
echo "Checksums:            $CHECKSUM_PATH"
echo "Install notes:        $NOTES_PATH"
echo
echo "Signing kind: Developer ID Application + notarized + stapled (any Mac, no cert install)"
