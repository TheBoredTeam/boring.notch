#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT

swiftc \
    "$repo_root/boringNotch/components/Calendar/CalendarDayStackGeometry.swift" \
    "$repo_root/tests/CalendarDayStackGeometryTests.swift" \
    -o "$test_directory/calendar-day-stack-tests"
"$test_directory/calendar-day-stack-tests"

swiftc -parse-as-library \
    "$repo_root/boringNotch/components/Calendar/CalendarTimelineGeometry.swift" \
    "$repo_root/boringNotch/components/Calendar/CalendarDayStackGeometry.swift" \
    "$repo_root/boringNotch/components/Calendar/CalendarDayScrollView.swift" \
    "$repo_root/tests/CalendarDayNativeScrollTests.swift" \
    -o "$test_directory/calendar-day-native-scroll-tests"
"$test_directory/calendar-day-native-scroll-tests"
