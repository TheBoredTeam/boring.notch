#!/bin/bash
#
# Builds a Chrome Web Store upload package.
#
#   ./package.sh            -> dist/boringnotch-ytmusic-<version>.zip
#
# There is no build step: the extension is plain ES2022 with no dependencies and no
# bundler, so packaging is just "zip the files Chrome needs". Keeping it that way is
# deliberate — it means the reviewed source and the shipped source are byte-identical.

set -euo pipefail

cd "$(dirname "$0")"

VERSION=$(python3 -c "import json;print(json.load(open('manifest.json'))['version'])")
OUT="dist/boringnotch-ytmusic-${VERSION}.zip"

rm -rf dist
mkdir -p dist

# Ship only what the extension loads at runtime. Anything used purely for development
# (tests, this script, docs) stays out of the package.
zip -q -r "$OUT" \
  manifest.json \
  src/ \
  icons/ \
  -x '*.DS_Store'

echo "$OUT"
echo
echo "Contents:"
unzip -Z1 "$OUT" | sed "s/^/  /"

cat <<'EOF'

Next steps:
  1. https://chrome.google.com/webstore/devconsole -> your item -> Package -> Upload new package
  2. Bump "version" in manifest.json before each upload; the Web Store rejects a re-used version.
  3. Chrome assigns a permanent extension ID on first publish. The app does not need to know
     it — authorisation is by Origin scheme (chrome-extension://), not by a specific ID.
EOF
