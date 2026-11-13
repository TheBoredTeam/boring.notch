#!/bin/bash
# Ad-hoc sign a built Boring Notch.app while preserving entitlements.
# Usage: sign_app.sh "/path/to/Boring Notch.app"
set -euo pipefail

APP="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
TMP_ENT="$(mktemp /tmp/boringNotch.entitlements.XXXXXX)"
trap 'rm -f "$TMP_ENT"' EXIT

sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
  "$ROOT/boringNotch/boringNotch.entitlements" > "$TMP_ENT"

if [ ! -d "$APP" ]; then
  echo "App bundle not found: $APP" >&2
  exit 1
fi

# Frameworks first (MediaRemoteAdapter expects an ad-hoc signature).
if [ -d "$APP/Contents/Frameworks" ]; then
  for fw in "$APP"/Contents/Frameworks/*.framework; do
    [ -e "$fw" ] || continue
    codesign --force --sign - "$fw" >/dev/null
  done
fi

# XPC helper keeps its own (non-sandboxed) entitlements.
XPC="$APP/Contents/XPCServices/BoringNotchXPCHelper.xpc"
if [ -d "$XPC" ]; then
  codesign --force --sign - \
    --entitlements "$ROOT/BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements" \
    "$XPC" >/dev/null
fi

# Main app keeps the sandbox / TCC related entitlements.
codesign --force --sign - \
  --entitlements "$TMP_ENT" \
  "$APP" >/dev/null

echo "Signed: $APP"
