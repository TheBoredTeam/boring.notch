#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DERIVED_DATA_PATH=".build/DerivedData"
APP_PATH="$ROOT/$DERIVED_DATA_PATH/Build/Products/Debug/Gojo.app"
CLIPBOARD_DIR="$HOME/Library/Application Support/Gojo/Clipboard"
HISTORY_PATH="$CLIPBOARD_DIR/history.json"
HISTORY_BACKUP="$(mktemp -u /tmp/gojo-history-backup.XXXXXX.json)"
DOMAIN="rohoswagger.gojo"
TEST_PNG="/tmp/gojo-image-smoke.png"

# `defaults write $DOMAIN` can route into the sandboxed container of a signed
# install, which an unsigned debug build never reads. Write through the
# UserDefaults API so cfprefsd updates the plist the debug build actually uses.
read_pref() {
  swift -e "import Foundation; let d = UserDefaults(suiteName: \"$DOMAIN\")!; print(d.object(forKey: \"clipboardHistoryEnabled\").map { \"\(\$0)\" } ?? \"__unset__\")"
}
write_pref() {
  swift -e "import Foundation; let d = UserDefaults(suiteName: \"$DOMAIN\")!; $1"
}

ORIGINAL_VALUE="$(read_pref)"
HAD_HISTORY=0
[[ -f "$HISTORY_PATH" ]] && { cp "$HISTORY_PATH" "$HISTORY_BACKUP"; HAD_HISTORY=1; }

cleanup() {
  pkill -9 -x Gojo >/dev/null 2>&1 || true
  if [[ "$ORIGINAL_VALUE" == "__unset__" ]]; then
    write_pref 'd.removeObject(forKey: "clipboardHistoryEnabled")' || true
  else
    write_pref "d.set($ORIGINAL_VALUE, forKey: \"clipboardHistoryEnabled\")" || true
  fi
  if [[ "$HAD_HISTORY" == "1" ]]; then
    cp "$HISTORY_BACKUP" "$HISTORY_PATH" >/dev/null 2>&1 || true
    rm -f "$HISTORY_BACKUP"
  else
    rm -f "$HISTORY_PATH"
  fi
}
trap cleanup EXIT

write_pref 'd.set(true, forKey: "clipboardHistoryEnabled")'
rm -f "$HISTORY_PATH"

xcodebuild \
  -project Gojo.xcodeproj \
  -scheme Gojo \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build \
  >/tmp/gojo-clipboard-image-roundtrip-build.log

test -d "$APP_PATH"

pkill -9 -x Gojo >/dev/null 2>&1 || true
sleep 1
open -na "$APP_PATH"
sleep 4

# Generate a small deterministic PNG.
python3 - <<PY
import struct, zlib

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

width, height = 24, 16
rows = b"".join(
    b"\x00" + bytes([y * 10 % 256, y * 16 % 256, 200, 255]) * width
    for y in range(height)
)
ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
open("$TEST_PNG", "wb").write(png)
PY

# Captures from Gojo itself are intentionally ignored, and a freshly launched
# Gojo is frontmost — hand focus to Finder before copying.
osascript -e 'tell application "Finder" to activate'
sleep 1
osascript -e "set the clipboard to (read (POSIX file \"$TEST_PNG\") as «class PNGf»)"
sleep 2
osascript -e 'set the clipboard to "gojo-image-smoke-spacer"'
sleep 1
osascript -e "set the clipboard to (read (POSIX file \"$TEST_PNG\") as «class PNGf»)"

python3 - <<'PY'
import json
import os
import time

clipboard_dir = os.path.expanduser("~/Library/Application Support/Gojo/Clipboard")
history_path = os.path.join(clipboard_dir, "history.json")

deadline = time.time() + 8
while time.time() < deadline:
    if os.path.exists(history_path):
        with open(history_path, "r", encoding="utf-8") as f:
            items = json.load(f)
        images = [item for item in items if item.get("kind") == "image"]
        if images and images[0]["copyCount"] >= 2:
            image = images[0]["image"]
            assert len(images) == 1, "duplicate image copies should dedupe into one entry"
            assert image["pixelWidth"] == 24, image
            assert image["pixelHeight"] == 16, image
            blob = os.path.join(clipboard_dir, "Images", image["fileName"])
            assert os.path.exists(blob), f"missing image blob {blob}"
            assert os.path.getsize(blob) == image["byteCount"], "byteCount mismatch"
            assert any(item.get("kind") == "text" and item["content"] == "gojo-image-smoke-spacer" for item in items), \
                "text capture should still work alongside images"
            break
    time.sleep(0.25)
else:
    raise SystemExit("clipboard image roundtrip smoke failed")
PY

# Pasteboards carrying BOTH real text and image flavors (Excel cells,
# Keynote objects) must be captured as text, not as an image.
swift -e "
import AppKit
let pb = NSPasteboard.general
pb.clearContents()
pb.setString(\"gojo-dual-flavor-text\", forType: .string)
pb.setData(try! Data(contentsOf: URL(fileURLWithPath: \"$TEST_PNG\")), forType: .png)
"

python3 - <<'PY'
import json
import os
import time

history_path = os.path.expanduser("~/Library/Application Support/Gojo/Clipboard/history.json")

deadline = time.time() + 8
while time.time() < deadline:
    with open(history_path, "r", encoding="utf-8") as f:
        items = json.load(f)
    match = [item for item in items if item["content"] == "gojo-dual-flavor-text"]
    if match:
        assert match[0].get("kind") == "text", "text+image pasteboard must be stored as text"
        print("clipboard-image-roundtrip-pass")
        raise SystemExit(0)
    time.sleep(0.25)

raise SystemExit("dual-flavor pasteboard was not captured as text")
PY
