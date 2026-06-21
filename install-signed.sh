#!/bin/zsh
# Build, sign with the stable Apple Development identity, and install boringNotch.
set -e
ID="Apple Development: bssanath27mac@gmail.com (92L72ZD5TN)"
SRC="/Users/sanathbs/03_Dev_Lab/boring.notch"
APP="/Applications/boringNotch.app"
BUILT="/Users/sanathbs/Library/Developer/Xcode/DerivedData/boringNotch-bqyuokpjklhrwrdruqhqcihdiodu/Build/Products/Debug/boringNotch.app"

cd "$SRC"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD" | tail -3

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
