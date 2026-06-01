#!/usr/bin/env bash
#
# sign-and-install.sh — build boring.notch Release, re-sign it with a STABLE
# Apple Development identity, install to /Applications, and reset its TCC grants.
#
# Why this exists
# ---------------
# The Xcode project ships with `CODE_SIGN_IDENTITY[sdk=macosx*] = "-"` (ad-hoc).
# Ad-hoc signing produces an *unstable* Designated Requirement: macOS keys
# Accessibility / Screen Recording grants to the app's code-signing identity, and
# an ad-hoc identity changes on every rebuild. The result is the notch
# re-prompting for Accessibility after every build. Signing with a real
# (Apple Development) identity gives the bundle a stable identifier-based
# Designated Requirement, so a grant survives rebuilds.
#
# Usage
# -----
#   scripts/sign-and-install.sh [-s SCHEME] [-i "Identity"] [-b BUNDLE_ID] [-n]
#
#   -s SCHEME      Xcode scheme to build           (default: boringNotch)
#   -i IDENTITY    codesign identity to sign with  (default: first
#                  "Apple Development" identity in the login keychain)
#   -b BUNDLE_ID   bundle id for the TCC reset      (default: theboringteam.boringnotch)
#   -n             do NOT reset TCC (keep existing Accessibility/SR grants)
#   -h             help
#
# Run `make sidecar` first if sidecar/index.ts changed — the binary is embedded
# at build time.

set -euo pipefail

# --- locate repo root (script lives in <root>/scripts) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

SCHEME="boringNotch"
IDENTITY=""
BUNDLE_ID="theboringteam.boringnotch"
RESET_TCC=1

while getopts "s:i:b:nh" opt; do
    case "$opt" in
        s) SCHEME="$OPTARG" ;;
        i) IDENTITY="$OPTARG" ;;
        b) BUNDLE_ID="$OPTARG" ;;
        n) RESET_TCC=0 ;;
        h) sed -n '2,40p' "$0"; exit 0 ;;
        *) echo "Run with -h for usage." >&2; exit 2 ;;
    esac
done

log()  { printf '\033[1;36m▸ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m✘ %s\033[0m\n' "$*" >&2; exit 1; }

PROJECT="boringNotch.xcodeproj"
[ -d "$PROJECT" ] || die "Can't find $PROJECT in $ROOT"

APP_ENTITLEMENTS="boringNotch/boringNotch.entitlements"
XPC_ENTITLEMENTS="BoringNotchXPCHelper/BoringNotchXPCHelper.entitlements"
[ -f "$APP_ENTITLEMENTS" ] || die "Missing $APP_ENTITLEMENTS"

# --- resolve a stable signing identity ---
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Apple Development" | head -1 | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]+[[:space:]]+"(.*)"$/\1/')"
fi
[ -n "$IDENTITY" ] || die "No 'Apple Development' codesigning identity found. Pass one with -i, or create one in Xcode → Settings → Accounts."
log "Signing identity: $IDENTITY"

# --- warn on ad-hoc (would re-prompt every build) ---
case "$IDENTITY" in
    "-"|"") die "Refusing to sign ad-hoc — that's the bug this script fixes." ;;
esac

BUILD_DIR="build_install"
log "Building $SCHEME (Release) → $BUILD_DIR"
# Build with the project's default (ad-hoc) signing — overriding the
# sdk-conditional CODE_SIGN_IDENTITY on the command line is unreliable (xcodebuild
# mis-parses the [sdk=macosx*] bracket). The *stable* identity is applied by the
# inside-out codesign re-sign below, which is what fixes the Designated Requirement.
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build | tail -20

APP="$(/usr/bin/find "$BUILD_DIR/Build/Products/Release" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null)"
[ -n "$APP" ] && [ -d "$APP" ] || die "Build succeeded but no .app found under $BUILD_DIR/Build/Products/Release"
log "Built: $APP"

# --- deep re-sign, inside-out, with hardened runtime ---
# Nested frameworks/dylibs first, then the XPC helper (its own entitlements),
# then the main app — so each signature is sealed before the thing that contains it.
sign() { # <entitlements-or-empty> <path>
    local ents="$1" path="$2"
    if [ -n "$ents" ] && [ -f "$ents" ]; then
        codesign --force --timestamp=none --options runtime \
            --sign "$IDENTITY" --entitlements "$ents" "$path"
    else
        codesign --force --timestamp=none --options runtime \
            --sign "$IDENTITY" "$path"
    fi
}

log "Re-signing nested code…"
if [ -d "$APP/Contents/Frameworks" ]; then
    # dylibs and frameworks
    while IFS= read -r -d '' item; do
        sign "" "$item"
    done < <(/usr/bin/find "$APP/Contents/Frameworks" \( -name '*.dylib' -o -name '*.framework' \) -print0)
fi

# XPC helper / login items / xpc services — sign with the helper entitlements.
while IFS= read -r -d '' helper; do
    log "Re-signing helper: ${helper#$APP/}"
    sign "$XPC_ENTITLEMENTS" "$helper"
done < <(/usr/bin/find "$APP/Contents" \( -path '*/XPCServices/*.xpc' -o -path '*/LoginItems/*.app' \) -maxdepth 4 -print0 2>/dev/null)

log "Re-signing app bundle…"
sign "$APP_ENTITLEMENTS" "$APP"

log "Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP" || die "Signature verification failed."
echo "  Designated Requirement (stable across rebuilds when identifier-based):"
codesign -d -r- "$APP" 2>&1 | sed 's/^/    /'

# --- install to /Applications ---
DEST="/Applications/$(basename "$APP")"
log "Installing → $DEST"
# Quit a running copy so the replace + TCC reset takes cleanly.
osascript -e 'tell application "boringNotch" to quit' >/dev/null 2>&1 || true
pkill -x boringNotch >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
cp -R "$APP" "$DEST"

# --- reset TCC so the freshly-signed identity is re-evaluated cleanly ---
if [ "$RESET_TCC" -eq 1 ]; then
    log "Resetting TCC for $BUNDLE_ID (you'll re-grant Accessibility/Screen Recording once)…"
    tccutil reset All "$BUNDLE_ID" || warn "tccutil reset returned non-zero (continuing)."
else
    warn "Skipping TCC reset (-n). Existing grants kept."
fi

log "Done. Launching…"
open "$DEST"

cat <<EOF

Next time you rebuild with this script, the signing identity stays the same, so
macOS keeps your Accessibility / Screen Recording grants instead of re-prompting.
EOF
