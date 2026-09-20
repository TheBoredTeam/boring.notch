#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/boring-notch-month-tests.XXXXXX")"
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT

xcrun swiftc -parse-as-library \
  "$PROJECT_ROOT/boringNotch/components/Calendar/CalendarMonthGeometry.swift" \
  "$PROJECT_ROOT/tests/CalendarMonthGeometryTests.swift" \
  -o "$TEST_BUILD_DIR/calendar-month-tests"
"$TEST_BUILD_DIR/calendar-month-tests"
