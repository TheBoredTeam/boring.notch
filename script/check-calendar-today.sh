#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc -swift-version 5 \
    "$repo_dir/boringNotch/components/Calendar/CalendarTodayShortcut.swift" \
    "$repo_dir/tests/CalendarTodayShortcutTests.swift" \
    -o "$test_dir/calendar-today-tests"
"$test_dir/calendar-today-tests"
