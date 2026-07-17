#!/usr/bin/env bash
# One-command distribution packaging for Hazakura Amp.
#
# Usage:
#   ./scripts/build_dist.sh              # Developer ID zip (other Macs; not notarized)
#   ./scripts/build_dist.sh release      # same as default
#   ./scripts/build_dist.sh dev          # Apple Development team preview
#   ./scripts/build_dist.sh notarized    # release + notarize + staple
#   ./scripts/build_dist.sh check        # preflight only (identities + profiles)
#
# Env overrides:
#   DEVELOPMENT_TEAM, DERIVED_DATA_PATH, DIST_DIR
#   APP_PROFILE_NAME, EXTENSION_PROFILE_NAME
#   HAZAKURA_NOTARY_APPLE_ID / HAZAKURA_NOTARY_TEAM_ID / HAZAKURA_NOTARY_PASSWORD
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/dist_common.sh
source "$SCRIPT_DIR/lib/dist_common.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/build_dist.sh [command]

Commands:
  release     Developer ID Application signed Release zip (default)
              Works on other Macs once notarized; without notarization
              Gatekeeper may still require right-click → Open.
  dev         Apple Development signed zip for registered team Macs
  notarized   release + notarize + staple (any Mac, double-click open)
  check       Print signing/profile preflight and exit

Examples:
  ./scripts/build_dist.sh
  ./scripts/build_dist.sh check
  ./scripts/build_dist.sh notarized
EOF
}

build_dev() {
  local configuration="${CONFIGURATION:-Debug}"
  local app_path
  app_path="$(app_path_for_configuration "$configuration")"

  preflight_dev
  info "Building $configuration with Automatic Apple Development signing"

  rm -rf "$DERIVED_DATA_PATH/Build/Products/$configuration"
  (
    cd "$PROJECT_DIR"
    xcodebuild \
      -project CoreAudioTapPoC.xcodeproj \
      -scheme CoreAudioTapPoC \
      -configuration "$configuration" \
      -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -allowProvisioningUpdates \
      CODE_SIGN_STYLE=Automatic \
      DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
      CODE_SIGN_IDENTITY='Apple Development' \
      build
  )

  [[ -d "$app_path" ]] || die "Built app not found at $app_path"
  strip_embedded_tests "$app_path" "Apple Development"

  local app_version app_build zip_name zip_path checksum_path notes_path
  app_version="$(read_app_version "$app_path")"
  app_build="$(read_app_build "$app_path")"
  zip_name="HazakuraAmp-v${app_version}-dev.zip"
  zip_path="$DIST_DIR/$zip_name"
  checksum_path="$DIST_DIR/HazakuraAmp-v${app_version}-dev.SHA256SUMS"
  notes_path="$DIST_DIR/HazakuraAmp-v${app_version}-dev-INSTALL.txt"

  info "Verifying signature"
  verify_codesign "$app_path"
  codesign -dv --verbose=2 "$app_path" 2>&1 | sed -n '1,80p'

  package_zip "$app_path" "$zip_path"
  write_checksum "$zip_path" "$checksum_path"

  cat > "$notes_path" <<EOF
Hazakura Amp v${app_version} (build ${app_build}) — developer preview

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
- For any-Mac distribution: ./scripts/build_dist.sh notarized

Checksum
- See $(basename "$checksum_path")
EOF

  echo
  echo "Dev distribution app:  $app_path"
  echo "Dev distribution zip:  $zip_path"
  echo "Checksums:             $checksum_path"
  echo "Install notes:         $notes_path"
  echo
  echo "Signing kind: Apple Development (team preview — not Developer ID / not notarized)"
}

build_release() {
  local app_path
  app_path="$(app_path_for_configuration Release)"
  local entitlements_path="$DIST_DIR/HazakuraAmp-release.entitlements.plist"

  preflight_release
  info "Building Release with Developer ID Application + distribution profiles"

  rm -rf "$DERIVED_DATA_PATH/Build/Products/Release"
  (
    cd "$PROJECT_DIR"
    xcodebuild \
      -project CoreAudioTapPoC.xcodeproj \
      -scheme CoreAudioTapPoC \
      -configuration Release \
      -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      clean build
  )

  [[ -d "$app_path" ]] || die "Built app not found at $app_path"
  strip_embedded_tests "$app_path"

  local app_version app_build zip_name zip_path checksum_path notes_path authority
  app_version="$(read_app_version "$app_path")"
  app_build="$(read_app_build "$app_path")"
  zip_name="HazakuraAmp-v${app_version}-developer-id.zip"
  zip_path="$DIST_DIR/$zip_name"
  checksum_path="$DIST_DIR/HazakuraAmp-v${app_version}-developer-id.SHA256SUMS"
  notes_path="$DIST_DIR/HazakuraAmp-v${app_version}-developer-id-INSTALL.txt"

  info "Verifying Developer ID signature"
  verify_codesign "$app_path"
  authority="$(signing_authority "$app_path")"
  if [[ "$authority" != Developer\ ID\ Application* ]]; then
    die "Expected Developer ID Application signature, got: $authority"
  fi
  assert_no_get_task_allow "$app_path" "$entitlements_path"
  codesign -dvvv --entitlements :- "$app_path" 2>&1 | sed -n '1,140p'

  package_zip "$app_path" "$zip_path"
  write_checksum "$zip_path" "$checksum_path"

  cat > "$notes_path" <<EOF
Hazakura Amp v${app_version} (build ${app_build}) — Developer ID (not notarized)

What this is
- Developer ID Application signed build
- Not notarized yet (Gatekeeper may require right-click → Open)
- Includes Safari YouTube remote extension inside the app bundle

Install
1. Unzip this archive
2. Move "Hazakura Amp.app" to /Applications
3. First launch: right-click → Open if Gatekeeper warns
4. Allow system audio access when prompted (not microphone)

Next step for frictionless any-Mac launch
  ./scripts/build_dist.sh notarized
  # or: ./scripts/notarize_and_staple.sh "$zip_path"

Checksum
- See $(basename "$checksum_path")
EOF

  echo
  echo "Release candidate app: $app_path"
  echo "Developer ID zip:      $zip_path"
  echo "Checksums:             $checksum_path"
  echo "Install notes:         $notes_path"
  echo "Signed by:             $authority"
  echo
  echo "Next (optional): notarize so any Mac can double-click open:"
  echo "  ./scripts/build_dist.sh notarized"
  echo "  # or: ./scripts/notarize_and_staple.sh \"$zip_path\""
}

build_notarized() {
  build_release
  info "Handing off to notarize_and_staple.sh"
  "$SCRIPT_DIR/notarize_and_staple.sh"
}

main() {
  local cmd="${1:-release}"
  case "$cmd" in
    -h|--help|help)
      usage
      ;;
    check|preflight)
      print_preflight_report
      ;;
    dev|preview|development)
      build_dev
      ;;
    release|developer-id|dist|"")
      build_release
      ;;
    notarized|notarize|ship)
      build_notarized
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage >&2
      exit 2
      ;;
  esac
}

main "$@"
