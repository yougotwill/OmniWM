#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
SIGN_AND_NOTARIZE="${2:-true}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_CAPITALIZED="$(tr '[:lower:]' '[:upper:]' <<< "${CONFIG:0:1}")${CONFIG:1}"
BUILD_DIR="$ROOT_DIR/.build/apple/Products/$CONFIG_CAPITALIZED"
EXECUTABLE="$BUILD_DIR/OmniWM"
APP_DIR="$ROOT_DIR/dist/OmniWM.app"
REQUIRED_SYMBOLS=(
  "omni_niri_ctx_apply_txn"
  "omni_niri_ctx_export_delta"
  "omni_border_runtime_create"
  "omni_border_runtime_destroy"
  "omni_border_runtime_apply_config"
  "omni_border_runtime_apply_presentation"
  "omni_border_runtime_submit_snapshot"
  "omni_border_runtime_apply_motion"
  "omni_border_runtime_invalidate_displays"
  "omni_border_runtime_hide"
  "omni_controller_create"
  "omni_controller_destroy"
  "omni_controller_start"
  "omni_controller_stop"
  "omni_controller_submit_hotkey"
  "omni_controller_submit_os_event"
  "omni_controller_apply_settings"
  "omni_controller_tick"
  "omni_controller_query_ui_state"
)

verify_required_symbols() {
  local artifact="$1"
  local label="$2"
  local symbol_names

  symbol_names="$(nm "${artifact}" 2>/dev/null | awk '{ name = $NF; sub(/^_/, "", name); print name }')"
  if [[ -z "${symbol_names}" ]]; then
    echo "error: unable to inspect symbols in ${artifact}" >&2
    exit 1
  fi

  local missing=0
  local symbol
  for symbol in "${REQUIRED_SYMBOLS[@]}"; do
    if ! grep -Fxq "${symbol}" <<< "${symbol_names}"; then
      echo "error: missing required symbol '${symbol}' in ${label} (${artifact})" >&2
      missing=1
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    exit 1
  fi

  echo "Verified ${label} exports required layout and border symbols."
}

# Signing identity and notarization profile
SIGNING_IDENTITY="Developer ID Application: Oliver Nikolic (VF8LDJRGFM)"
NOTARIZE_PROFILE="OmniWM-Notarize"
ENTITLEMENTS="$ROOT_DIR/OmniWM.entitlements"

echo "Building Zig static library (universal arm64 + x86_64)..."
zig build omni-layout --prefix "$ROOT_DIR/.build"

ZIG_LIB="$ROOT_DIR/.build/zig/libomni_layout.a"
if [[ -f "$ZIG_LIB" ]]; then
  verify_required_symbols "$ZIG_LIB" "Zig archive"
fi

echo "Building OmniWM universal binary ($CONFIG)..."
swift build -c "$CONFIG" --arch arm64 --arch x86_64

echo "Verifying universal binary..."
lipo -info "$EXECUTABLE"

verify_required_symbols "$EXECUTABLE" "App binary"

echo "Packaging $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/OmniWM"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp -R "$BUILD_DIR/OmniWM_OmniWM.bundle" "$APP_DIR/Contents/Resources/"

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
fi

if [ "$SIGN_AND_NOTARIZE" = "true" ]; then
  echo "Signing $APP_DIR with hardened runtime..."
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" --timestamp "$APP_DIR/Contents/MacOS/OmniWM"
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGNING_IDENTITY" --timestamp "$APP_DIR"

  echo "Verifying signature..."
  codesign --verify --verbose "$APP_DIR"

  echo "Creating ZIP for notarization..."
  ZIP_PATH="$ROOT_DIR/dist/OmniWM.zip"
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

  echo "Submitting for notarization (this may take a few minutes)..."
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARIZE_PROFILE" --wait

  echo "Stapling notarization ticket..."
  xcrun stapler staple "$APP_DIR"

  echo "Verifying notarization..."
  spctl --assess --verbose=2 "$APP_DIR"

  rm -f "$ZIP_PATH"
  echo "Done! $APP_DIR is signed and notarized."
else
  echo "Done. Open $APP_DIR to grant Accessibility permissions."
  echo "Note: App is not signed. Run with 'release true' to sign and notarize."
fi
