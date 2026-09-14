#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT

swiftc \
    "$repo_root/boringNotch/components/Calendar/CalendarTimelineGeometry.swift" \
    "$repo_root/boringNotch/components/Calendar/HomeCalendarGeometry.swift" \
    "$repo_root/tests/HomeCalendarGeometryTests.swift" \
    -o "$test_directory/home-calendar-tests"
"$test_directory/home-calendar-tests"
