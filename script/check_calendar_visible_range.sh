#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT

swiftc \
    "$repo_root/boringNotch/components/Calendar/CalendarTimelineGeometry.swift" \
    "$repo_root/tests/CalendarVisibleRangeTests.swift" \
    -o "$test_directory/calendar-visible-range-tests"
"$test_directory/calendar-visible-range-tests"
