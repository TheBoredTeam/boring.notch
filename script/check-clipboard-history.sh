#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/boring-notch-clipboard-check.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
swiftc -target "$(uname -m)-apple-macosx14.0" -swift-version 5 -o "$build_dir/clipboard-history-tests" \
  "$repo_dir/boringNotch/models/ClipboardHistoryItem.swift" \
  "$repo_dir/boringNotch/managers/ClipboardHistoryManager.swift" \
  "$repo_dir/tests/ClipboardHistoryTests.swift"
"$build_dir/clipboard-history-tests"

swiftc -target "$(uname -m)-apple-macosx14.0" -swift-version 5 -o "$build_dir/clipboard-drag-tests" \
  "$repo_dir/boringNotch/models/ClipboardHistoryItem.swift" \
  "$repo_dir/boringNotch/components/Clipboard/ClipboardDragPayload.swift" \
  "$repo_dir/tests/ClipboardDragPayloadTests.swift"
"$build_dir/clipboard-drag-tests"
swiftc -target "$(uname -m)-apple-macosx14.0" -swift-version 5 -o "$build_dir/clipboard-selection-tests" \
  "$repo_dir/boringNotch/models/ClipboardHistoryItem.swift" \
  "$repo_dir/boringNotch/components/Clipboard/ClipboardDragPayload.swift" \
  "$repo_dir/boringNotch/components/Clipboard/ClipboardSelectionInteraction.swift" \
  "$repo_dir/tests/ClipboardSelectionTests.swift"
"$build_dir/clipboard-selection-tests"
