#!/bin/zsh
# Build, sign with the stable Apple Development identity, and install boringNotch.
set -e
# Allow overriding the signing identity via environment variable, fallback to default
ID="${BORINGNOTCH_SIGNING_IDENTITY:-Apple Development: bssanath27mac@gmail.com (92L72ZD5TN)}"

# Derive source directory dynamically
SRC="$(cd "$(dirname "$0")" && pwd)"
APP="/Applications/boringNotch.app"

cd "$SRC"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD" | tail -3

# Find DerivedData build path dynamically, fallback if query fails
BUILT_DIR=$(xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS' -showBuildSettings 2>/dev/null | grep -E "\bCONFIGURATION_BUILD_DIR =" | awk -F'= ' '{print $2}')
if [[ -z "$BUILT_DIR" ]]; then
    BUILT_DIR="$HOME/Library/Developer/Xcode/DerivedData/boringNotch-bqyuokpjklhrwrdruqhqcihdiodu/Build/Products/Debug"
fi
BUILT="${BUILT_DIR}/boringNotch.app"

pkill -9 -x boringNotch 2>/dev/null || true; sleep 1
rm -rf "$APP"; ditto "$BUILT" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Re-sign inside-out with the stable identity (keeps Accessibility grant alive)
codesign --force --sign "$ID" "$APP/Contents/Frameworks/Lottie.framework"
codesign --force --sign "$ID" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --deep --sign "$ID" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$ID" --entitlements BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements "$APP/Contents/XPCServices/BoringNotchXPCHelper.xpc"
codesign --force --sign "$ID" --entitlements boringNotch/boringNotch.entitlements "$APP"

open "$APP"; sleep 1
codesign -dv "$APP" 2>&1 | grep TeamIdentifier
echo "✓ installed (stable-signed)"
