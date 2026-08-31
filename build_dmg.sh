#!/usr/bin/env bash
set -euo pipefail

# Build a Release .app and package it into dist/boringNotch.dmg.
# Unsigned/ad-hoc — for local use, not distribution.

cd "$(dirname "${BASH_SOURCE[0]}")"

DERIVED="build"
APP="$DERIVED/Build/Products/Release/boringNotch.app"
OUT_DIR="dist"
DMG="$OUT_DIR/boringNotch.dmg"

echo "==> Building Release app"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build

[ -d "$APP" ] || { echo "Build did not produce $APP" >&2; exit 1; }

# dmgbuild is required by create_dmg.sh; install it if missing.
if ! command -v dmgbuild >/dev/null 2>&1; then
  echo "==> Installing dmgbuild"
  python3 -m pip install --require-hashes -r Configuration/dmg/requirements.txt
fi

mkdir -p "$OUT_DIR"
rm -f "$DMG"

echo "==> Creating DMG"
Configuration/dmg/create_dmg.sh "$APP" "$DMG" "Boring Notch"

echo "==> Done: $DMG"
