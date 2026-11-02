#!/bin/sh
set -eu
repository=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
if [ "$#" -ne 1 ]; then
    echo 'Usage: sh Tests/AIActivityTests/run-xpc-smoke.sh "/path/to/Boring Notch.app"' >&2
    exit 1
fi
smoke_directory=$(mktemp -d "${TMPDIR:-/tmp}/boring-notch-ai-xpc.XXXXXX")
socket_directory=$(mktemp -d /tmp/bnai-xpc.XXXXXX)
trap 'rm -rf "$smoke_directory" "$socket_directory"' EXIT HUP INT TERM
smoke_service="local.boringnotch.ai-smoke-$(basename "$socket_directory")"
smoke_app="$smoke_directory/AIActivitySmokeTest.app"
mkdir -p "$smoke_app/Contents/MacOS" "$smoke_app/Contents/XPCServices"
cp -R "$1/Contents/XPCServices/BoringNotchXPCHelper.xpc" "$smoke_app/Contents/XPCServices/"
cat > "$smoke_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.boringnotch.AIActivitySmokeTest</string>
<key>CFBundleExecutable</key><string>AIActivitySmokeTest</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :AIActivitySmokeService string $smoke_service" "$smoke_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :AIActivitySmokeSocketDirectory string $socket_directory" "$smoke_app/Contents/Info.plist"
helper_bundle="$smoke_app/Contents/XPCServices/BoringNotchXPCHelper.xpc"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $smoke_service" "$helper_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :XPCService:EnvironmentVariables dict' "$helper_bundle/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :XPCService:EnvironmentVariables:BORING_NOTCH_AI_SOCKET_DIRECTORY string $socket_directory" "$helper_bundle/Contents/Info.plist"
codesign --force --sign - --entitlements "$repository/BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements" "$helper_bundle" > /dev/null 2>&1
swiftc -module-cache-path "$smoke_directory/module-cache" \
    "$repository/boringNotch/models/AIActivity.swift" \
    "$repository/boringNotch/XPCHelperClient/BoringNotchXPCHelperProtocol.swift" \
    "$repository/Tests/AIActivityTests/XPCSmokeTest.swift" \
    -o "$smoke_app/Contents/MacOS/AIActivitySmokeTest"
codesign --force --sign - "$smoke_app" > /dev/null 2>&1
"$smoke_app/Contents/MacOS/AIActivitySmokeTest"
