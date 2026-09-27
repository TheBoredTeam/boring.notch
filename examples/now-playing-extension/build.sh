#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bundle="$PWD/dist/com.example.boringnotch.now-playing.bnplugin"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun swiftc -O -emit-library -target "$(uname -m)-apple-macos14.0" NowPlaying.swift -o "$bundle/Contents/MacOS/NowPlaying"
python3 - "$bundle" <<'PY'
import json, plistlib, sys
from pathlib import Path
bundle = Path(sys.argv[1])
identifier = 'com.example.boringnotch.now-playing'
(bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': identifier, 'CFBundleName': 'Now Playing Example',
    'CFBundleExecutable': 'NowPlaying', 'CFBundlePackageType': 'BNDL',
    'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '1', 'LSMinimumSystemVersion': '14.0'}))
(bundle / 'Contents/Resources/manifest.json').write_text(json.dumps({
    'id': identifier, 'name': 'Now Playing Example', 'version': '1.0.0', 'apiVersion': 1, 'activation': 'always'}))
PY
codesign --force --sign - "$bundle"
echo "Built local development extension: $bundle"
