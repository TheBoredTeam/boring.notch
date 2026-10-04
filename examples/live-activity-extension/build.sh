#!/bin/bash
# Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
# Attribution applies to the extension platform contributions.

set -euo pipefail
cd "$(dirname "$0")"

output="${1:-dist}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
staging="$(mktemp -d "$output/.focus-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
bundle_name="org.example.boringnotch.focus-timer.bnplugin"
bundle="$staging/$bundle_name"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
architecture="$(uname -m)"
sdk="$(xcrun --sdk macosx --show-sdk-path)"

xcrun swiftc -swift-version 5 -strict-concurrency=complete -O -emit-library \
  -module-name FocusTimer -sdk "$sdk" -target "$architecture-apple-macos14.0" \
  FocusTimer.swift -o "$bundle/Contents/MacOS/FocusTimer"

python3 - "$bundle" <<'PY'
import json, plistlib, sys
from pathlib import Path
bundle = Path(sys.argv[1])
identifier = 'org.example.boringnotch.focus-timer'
(bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': identifier, 'CFBundleName': 'Focus Timer',
    'CFBundleExecutable': 'FocusTimer', 'CFBundlePackageType': 'BNDL',
    'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '1',
    'LSMinimumSystemVersion': '14.0'
}))
(bundle / 'Contents/Resources/manifest.json').write_text(json.dumps({
    'id': identifier, 'name': 'Focus Timer', 'version': '1.0.0',
    'apiVersion': 1, 'activation': 'always', 'capabilities': ['liveActivities', 'tabs']
}, indent=2) + '\n')
PY

codesign --force --sign - "$bundle"
codesign --verify --strict --all-architectures "$bundle"
ditto -c -k --keepParent "$bundle" "$staging/FocusTimer-development.zip"
rm -rf "$output/$bundle_name"
mv "$bundle" "$output/$bundle_name"
mv -f "$staging/FocusTimer-development.zip" "$output/FocusTimer-development.zip"
printf 'Built local %s example: %s\n' "$architecture" "$output/$bundle_name"
printf 'ZIP: %s\n' "$output/FocusTimer-development.zip"
