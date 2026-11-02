#!/usr/bin/env bash
set -euo pipefail

# Builds, signs, notarizes and staples a DMG of this personal fork.
# Usage: Configuration/dmg/package_fork.sh [notary-keychain-profile]
#
# One-time setup (stores an app-specific password in your keychain):
#   xcrun notarytool store-credentials boring-notch-notary --apple-id <apple-id> --team-id 3KU39KTTKP
# Pass "--skip-notarize" as the profile to produce a signed but unnotarized DMG.

TEAM_ID="3KU39KTTKP"
IDENTITY="Developer ID Application: Bai-Kuan Yeh (${TEAM_ID})"
PROFILE="${1:-boring-notch-notary}"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$REPO/build/release/work"
DMG="$REPO/build/release/BoringNotch-AI.dmg"
APP="$WORK/export/Boring Notch.app"

rm -rf "$WORK"
mkdir -p "$WORK"

echo "==> Archiving (universal, Release)"
xcodebuild archive -project "$REPO/boringNotch.xcodeproj" -scheme boringNotch -configuration Release \
    -archivePath "$WORK/boringNotch.xcarchive" -destination "generic/platform=macOS" \
    -derivedDataPath "$WORK/dd" DEVELOPMENT_TEAM="$TEAM_ID" ONLY_ACTIVE_ARCH=NO \
    -allowProvisioningUpdates -quiet

echo "==> Exporting with Developer ID"
cat > "$WORK/export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>${TEAM_ID}</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$WORK/boringNotch.xcarchive" -exportPath "$WORK/export" \
    -exportOptionsPlist "$WORK/export.plist" -allowProvisioningUpdates -quiet

# The prebuilt media test client is copied in as a resource, so Xcode signs it without
# hardened runtime, which notarization rejects. Re-sign it, then reseal the app.
echo "==> Re-signing the bundled media test client with hardened runtime"
codesign -d --entitlements :- "$APP" > "$WORK/app.entitlements" 2>/dev/null
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Resources/MediaRemoteAdapterTestClient"
codesign --force --options runtime --timestamp --entitlements "$WORK/app.entitlements" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Creating DMG"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Boring Notch.app"
ln -s /Applications "$STAGE/Applications"
cp "$REPO/Configuration/dmg/fork_read_me.txt" "$STAGE/請先讀我 Read Me.txt"
rm -f "$DMG"
hdiutil create -volname "Boring Notch AI" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if [ "$PROFILE" = "--skip-notarize" ]; then
    echo "==> Skipped notarization: $DMG"
    exit 0
fi

echo "==> Notarizing (usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> Gatekeeper check"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "Done: $DMG"
