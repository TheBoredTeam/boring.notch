#!/bin/bash
# Build Boring Notch (Release), sign it with a stable local identity and
# install it into /Applications.
#
# A stable signing identity keeps the designated requirement the same across
# rebuilds, so macOS (TCC) keeps the Accessibility permission. Ad-hoc signing
# ties the permission to the cdhash, which changes on every build.
#
# Usage:
#   scripts/install-local.sh                 # first codesigning identity
#   SIGN_IDENTITY="Boring Notch Local" scripts/install-local.sh
#   SKIP_BUILD=1 scripts/install-local.sh    # re-sign and install the last build
#   scripts/install-local.sh SETTING=value   # extra arguments go to xcodebuild
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Boring Notch.app"
BUNDLE_ID="theboringteam.boringnotch"
DERIVED_DATA="build"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
DEST_APP="/Applications/$APP_NAME"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    # Without -v so an untrusted self-signed certificate is found too; codesign
    # and TCC don't need it to be trusted.
    SIGN_IDENTITY=$(security find-identity -p codesigning | awk '/^ *1\)/ {print $2; exit}')
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "error: no code signing identity found (security find-identity -v -p codesigning)." >&2
    echo "Create an Apple Development certificate in Xcode or a self-signed" >&2
    echo "Code Signing certificate in Keychain Access, or set SIGN_IDENTITY." >&2
    exit 1
fi
echo "==> Signing identity: $SIGN_IDENTITY"

if [[ -z "${SKIP_BUILD:-}" ]]; then
    echo "==> Building Release (log: $DERIVED_DATA/install-local.log)"
    mkdir -p "$DERIVED_DATA"
    if ! xcodebuild \
        -project boringNotch.xcodeproj \
        -scheme boringNotch \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        -skipPackageUpdates \
        -disableAutomaticPackageResolution \
        -skipMacroValidation \
        -skipPackagePluginValidation \
        CODE_SIGNING_ALLOWED=NO \
        "$@" \
        build >"$DERIVED_DATA/install-local.log" 2>&1; then
        grep -E "error:" "$DERIVED_DATA/install-local.log" | head -20 >&2
        echo "error: xcodebuild failed, see $DERIVED_DATA/install-local.log" >&2
        exit 1
    fi
fi

[[ -d "$BUILT_APP" ]] || { echo "error: $BUILT_APP not found" >&2; exit 1; }

# Sign a copy so the build output stays untouched.
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/$APP_NAME"
ditto "$BUILT_APP" "$APP"

sign() {
    # No entitlements and no hardened runtime: the build runs unsandboxed,
    # like the previous ad-hoc installs.
    codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$@"
}

echo "==> Signing (inside-out)"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
if [[ -d "$SPARKLE" ]]; then
    for item in "$SPARKLE/XPCServices/"*.xpc "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app"; do
        [[ -e "$item" ]] && sign "$item"
    done
fi
find "$APP/Contents/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -print0 |
    while IFS= read -r -d '' item; do sign "$item"; done
for xpc in "$APP/Contents/XPCServices/"*.xpc; do
    [[ -e "$xpc" ]] && sign "$xpc"
done
sign "$APP"

codesign --verify --deep --strict "$APP"
echo "==> Designated requirement:"
codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => /    /p'

echo "==> Installing to $DEST_APP"
if pgrep -x "Boring Notch" >/dev/null; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -x "Boring Notch" >/dev/null || break; sleep 0.5; done
    pkill -x "Boring Notch" 2>/dev/null || true
fi
rm -rf "$DEST_APP"
ditto "$APP" "$DEST_APP"

echo "==> Launching"
open "$DEST_APP"
