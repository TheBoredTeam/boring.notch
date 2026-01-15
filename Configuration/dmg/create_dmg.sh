#!/usr/bin/env bash
set -euo pipefail

# Minimal wrapper to create a DMG using dmgbuild.
# Usage: ./create_dmg.sh <app_path> <dmg_output> <volume_name>

APP_PATH="${1:?App path required}"
DMG_OUTPUT="${2:?DMG output path required}"
VOLUME_NAME="${3:?Volume name required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$SCRIPT_DIR/dmgbuild_settings.py"

BACKGROUND_DIR="$SCRIPT_DIR/.background"

die() {
  echo "Error: $*" >&2
  exit 1
}

abs_path() {
  python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$1"
}

ensure_dmgbuild_and_badge_support() {
  if command -v dmgbuild >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v pip3 >/dev/null 2>&1; then
    die "dmgbuild is not installed and pip3 is not available. Please install dmgbuild."
  fi

  echo "dmgbuild not found — installing via pip3 (user scope)..."
  python3 -m pip install --user "dmgbuild[badge_icons]" || python3 -m pip install "dmgbuild[badge_icons]"
  USER_BIN="$(python3 -c 'import site,sys; print(site.getuserbase() + "/bin")')"
  export PATH="$USER_BIN:$PATH"
}

find_app_icns() {
  local app="$1"
  local info_plist="$app/Contents/Info.plist"

  if [ ! -f "$info_plist" ]; then
    return 1
  fi

  local icon_file=""
  icon_file="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$info_plist" 2>/dev/null || true)"
  if [ -z "$icon_file" ]; then
    icon_file="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$info_plist" 2>/dev/null || true)"
  fi

  if [ -n "$icon_file" ]; then
    if [[ "$icon_file" != *.icns ]]; then
      icon_file="$icon_file.icns"
    fi
    if [ -f "$app/Contents/Resources/$icon_file" ]; then
      echo "$app/Contents/Resources/$icon_file"
      return 0
    fi
  fi

  # Fallback: any .icns inside the app bundle
  local candidate
  candidate="$(find "$app/Contents/Resources" -maxdepth 1 -name '*.icns' -print -quit 2>/dev/null || true)"
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    echo "$candidate"
    return 0
  fi

  return 1
}

if [ ! -f "$SETTINGS" ]; then
  die "dmgbuild settings not found: $SETTINGS"
fi

ensure_dmgbuild_and_badge_support

export DMG_APP_PATH="$(abs_path "$APP_PATH")"
export DMG_VOLUME_NAME="$VOLUME_NAME"

BACKGROUND_TIFF="$BACKGROUND_DIR/background.tiff"

export DMG_BACKGROUND="$(abs_path "$BACKGROUND_TIFF")"

# Badge icon: use the app's icon for badging the volume icon
if DMG_ICON_ICNS="$(find_app_icns "$DMG_APP_PATH" 2>/dev/null)"; then
  export DMG_BADGE_ICON="$(abs_path "$DMG_ICON_ICNS")"
  echo "Using badge icon for DMG volume."
else
  echo "No app icon found, skipping badge."
fi

echo "Creating DMG via dmgbuild: app=$DMG_APP_PATH output=$DMG_OUTPUT volume=$DMG_VOLUME_NAME"

# Validate inputs early to give clearer errors for common typos
if [ ! -e "$DMG_APP_PATH" ]; then
  echo "Error: App path not found: $DMG_APP_PATH" >&2
  echo "Make sure you passed the correct .app path (e.g. Release/boringNotch.app)" >&2
  exit 2
fi

if [ ! -d "$DMG_APP_PATH" ]; then
  echo "Error: App path exists but is not a directory: $DMG_APP_PATH" >&2
  exit 3
fi

dmgbuild -s "$SETTINGS" "$DMG_VOLUME_NAME" "$DMG_OUTPUT"

exit $?
