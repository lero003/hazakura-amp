#!/usr/bin/env bash
# Shared helpers for Hazakura Amp distribution packaging scripts.
# shellcheck shell=bash

# Expected to be sourced after SCRIPT_DIR is set to .../scripts
: "${SCRIPT_DIR:?SCRIPT_DIR must be set before sourcing dist_common.sh}"

PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_DIR/build}"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-8BNUB2R9C8}"

# Release profile names (must match project.yml PROVISIONING_PROFILE_SPECIFIER).
APP_PROFILE_NAME="${APP_PROFILE_NAME:-Hazakura Amp dev}"
EXTENSION_PROFILE_NAME="${EXTENSION_PROFILE_NAME:-Hazakura Amp safari-extension dev}"

APP_BUNDLE_ID="dev.hazakura-amp"
EXTENSION_BUNDLE_ID="dev.hazakura-amp.safari-extension"
APP_PRODUCT_NAME="Hazakura Amp"

die() {
  echo "error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

ensure_project() {
  local pbxproj="$PROJECT_DIR/CoreAudioTapPoC.xcodeproj/project.pbxproj"
  if [[ -f "$pbxproj" ]]; then
    return 0
  fi
  if command -v xcodegen >/dev/null 2>&1; then
    info "Xcode project missing — running xcodegen generate"
    (cd "$PROJECT_DIR" && xcodegen generate)
  else
    die "Xcode project missing and xcodegen not installed. Run: brew install xcodegen && xcodegen generate"
  fi
  [[ -f "$pbxproj" ]] || die "xcodegen did not produce $pbxproj"
}

# List installed provisioning profile Names (Xcode 16+ uses .provisionprofile).
list_profile_names() {
  local dir f xml name
  for dir in \
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
    "$HOME/Library/MobileDevice/Provisioning Profiles"
  do
    [[ -d "$dir" ]] || continue
    shopt -s nullglob
    for f in "$dir"/*.provisionprofile "$dir"/*.mobileprovision; do
      xml="$(security cms -D -i "$f" 2>/dev/null)" || continue
      name="$(printf '%s' "$xml" | plutil -extract Name raw - 2>/dev/null)" || continue
      [[ -n "$name" ]] && printf '%s\n' "$name"
    done
    shopt -u nullglob
  done
}

has_profile() {
  local want="$1" name
  # Avoid `cmd | grep -q` under pipefail: early grep exit can SIGPIPE the producer
  # and make the whole check fail even when the name is present.
  while IFS= read -r name; do
    [[ "$name" == "$want" ]] && return 0
  done < <(list_profile_names)
  return 1
}

has_codesign_identity() {
  local needle="$1"
  local line
  while IFS= read -r line; do
    [[ "$line" == *"$needle"* ]] && return 0
  done < <(security find-identity -v -p codesigning 2>/dev/null || true)
  return 1
}

app_path_for_configuration() {
  local configuration="$1"
  printf '%s\n' "$DERIVED_DATA_PATH/Build/Products/$configuration/${APP_PRODUCT_NAME}.app"
}

read_app_version() {
  local app_path="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist"
}

read_app_build() {
  local app_path="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist"
}

strip_embedded_tests() {
  local app_path="$1"
  local identity="${2:-}"
  if compgen -G "$app_path/Contents/PlugIns/"*.xctest >/dev/null; then
    echo "Removing embedded test bundles from app before packaging:" >&2
    rm -rf "$app_path/Contents/PlugIns/"*.xctest
    if [[ -z "$identity" ]]; then
      identity="$(signing_authority "$app_path" || true)"
    fi
    if [[ -n "$identity" ]]; then
      # Preserve secure timestamp for Developer ID; Development builds can skip TSA.
      if [[ "$identity" == Developer\ ID\ Application* ]]; then
        codesign --force --deep --sign "$identity" --options runtime --timestamp "$app_path"
      else
        codesign --force --deep --sign "$identity" --options runtime --timestamp=none "$app_path"
      fi
    else
      echo "warning: removed embedded tests but could not re-sign (no identity)" >&2
    fi
  fi
}

verify_codesign() {
  local app_path="$1"
  codesign --verify --strict --deep --verbose=2 "$app_path"
}

# Package a signed .app into a zip that survives plain `unzip` (GitHub downloads,
# command-line unzip, etc.) without injecting AppleDouble `._*` files.
#
# Why this exists:
#   `ditto -c -k --keepParent` preserves xattrs (e.g. com.apple.provenance) as
#   AppleDouble entries. Archive Utility / ditto rehydrate them as xattrs, but
#   plain `unzip` materializes them as literal `._*` files inside the bundle.
#   That breaks the code signature seal, and Safari then returns
#   SFErrorDomain:1 when looking up the embedded Web Extension.
package_zip() {
  local app_path="$1"
  local zip_path="$2"
  local app_name stage_dir verify_dir staged_app

  [[ -d "$app_path" ]] || die "package_zip: app not found: $app_path"
  require_cmd unzip
  app_name="$(basename "$app_path")"
  mkdir -p "$(dirname "$zip_path")"
  rm -f "$zip_path"

  stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/hazakura-amp-package.XXXXXX")"
  verify_dir="$(mktemp -d "${TMPDIR:-/tmp}/hazakura-amp-unzip-verify.XXXXXX")"

  # Do not use EXIT traps here — callers (e.g. notarize_and_staple) own EXIT.
  # Clean up explicitly on every path so we never clobber outer traps.
  # shellcheck disable=SC2317
  _package_zip_cleanup() {
    rm -rf "${stage_dir:-}" "${verify_dir:-}"
  }

  # Copy without resource forks / extended attributes so the zip has no AppleDouble.
  if ! ditto --norsrc --noextattr "$app_path" "$stage_dir/$app_name"; then
    _package_zip_cleanup
    die "package_zip: failed to stage app without xattrs"
  fi
  staged_app="$stage_dir/$app_name"
  xattr -cr "$staged_app" 2>/dev/null || true
  find "$staged_app" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true

  info "Verifying staged app still codesigns after stripping xattrs"
  if ! codesign --verify --strict --deep --verbose=2 "$staged_app"; then
    _package_zip_cleanup
    die "package_zip: codesign failed after stripping xattrs"
  fi

  # --norsrc/--noextattr keep provenance/xattrs out of the archive entirely.
  if ! ditto -c -k --norsrc --noextattr --keepParent "$staged_app" "$zip_path"; then
    _package_zip_cleanup
    die "package_zip: failed to create zip"
  fi

  # Regression gate: plain unzip is what many GitHub downloaders use.
  info "Verifying packaged zip survives plain unzip without breaking codesign"
  if ! unzip -q "$zip_path" -d "$verify_dir"; then
    _package_zip_cleanup
    die "package_zip: plain unzip of packaged zip failed"
  fi
  if find "$verify_dir" \( -name '._*' -o -name '.DS_Store' \) | grep -q .; then
    _package_zip_cleanup
    die "packaged zip still produces AppleDouble/._ files after plain unzip"
  fi
  if ! codesign --verify --strict --deep --verbose=2 "$verify_dir/$app_name"; then
    _package_zip_cleanup
    die "codesign failed after plain unzip of packaged zip (Safari extension will not load)"
  fi

  _package_zip_cleanup
}

write_checksum() {
  local zip_path="$1"
  local checksum_path="$2"
  local zip_name
  zip_name="$(basename "$zip_path")"
  (
    cd "$(dirname "$zip_path")"
    shasum -a 256 "$zip_name" > "$(basename "$checksum_path")"
  )
}

signing_authority() {
  local app_path="$1"
  # codesign emits Authority lines with leading whitespace/CR; strip both.
  codesign -dvvv "$app_path" 2>&1 | tr -d '\r' | awk -F'=[ \t]*' '/Authority=/ {print $2; exit}'
}

assert_no_get_task_allow() {
  local app_path="$1"
  local entitlements_path="$2"
  codesign -d --entitlements "$entitlements_path" "$app_path" 2>/dev/null || true
  if [[ ! -f "$entitlements_path" ]]; then
    return 0
  fi
  if /usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$entitlements_path" >/dev/null 2>&1; then
    if [[ "$(/usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$entitlements_path")" == "true" ]]; then
      die "Release candidate unexpectedly has get-task-allow=true"
    fi
  fi
}

preflight_dev() {
  require_cmd xcodebuild
  require_cmd codesign
  require_cmd ditto
  require_cmd shasum
  ensure_project
  if ! has_codesign_identity "Apple Development"; then
    die "No 'Apple Development' codesigning identity found in keychain"
  fi
}

preflight_release() {
  require_cmd xcodebuild
  require_cmd codesign
  require_cmd ditto
  require_cmd shasum
  ensure_project

  local missing=0
  if ! has_codesign_identity "Developer ID Application"; then
    echo "error: No 'Developer ID Application' certificate in keychain" >&2
    missing=1
  fi
  if ! has_profile "$APP_PROFILE_NAME"; then
    echo "error: Missing provisioning profile: $APP_PROFILE_NAME" >&2
    echo "       (expected for $APP_BUNDLE_ID, Developer ID / ProvisionsAllDevices)" >&2
    missing=1
  fi
  if ! has_profile "$EXTENSION_PROFILE_NAME"; then
    echo "error: Missing provisioning profile: $EXTENSION_PROFILE_NAME" >&2
    echo "       (expected for $EXTENSION_BUNDLE_ID, Developer ID / ProvisionsAllDevices)" >&2
    missing=1
  fi
  if [[ "$missing" -ne 0 ]]; then
    cat >&2 <<EOF

Install Developer ID Application certificate + both distribution profiles, then retry.
Profile names must match project.yml PROVISIONING_PROFILE_SPECIFIER
  app:       $APP_PROFILE_NAME
  extension: $EXTENSION_PROFILE_NAME

Team-only preview (registered Macs only):
  ./scripts/build_dist.sh dev
EOF
    exit 1
  fi
}

print_preflight_report() {
  echo "Hazakura Amp distribution preflight"
  echo "  project:  $PROJECT_DIR"
  echo "  team:     $DEVELOPMENT_TEAM"
  echo
  echo "Identities:"
  if has_codesign_identity "Apple Development"; then
    echo "  [ok] Apple Development"
  else
    echo "  [missing] Apple Development"
  fi
  if has_codesign_identity "Developer ID Application"; then
    echo "  [ok] Developer ID Application"
  else
    echo "  [missing] Developer ID Application"
  fi
  echo
  echo "Profiles (looking for release names):"
  if has_profile "$APP_PROFILE_NAME"; then
    echo "  [ok] $APP_PROFILE_NAME"
  else
    echo "  [missing] $APP_PROFILE_NAME"
  fi
  if has_profile "$EXTENSION_PROFILE_NAME"; then
    echo "  [ok] $EXTENSION_PROFILE_NAME"
  else
    echo "  [missing] $EXTENSION_PROFILE_NAME"
  fi
  echo
  echo "Installed profile names:"
  list_profile_names | sort -u | sed 's/^/  - /' || echo "  (none found)"
}
