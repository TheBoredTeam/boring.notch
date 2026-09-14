#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# Prerequisite: xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath DerivedData build
build_products="${BORING_NOTCH_BUILD_PRODUCTS_DIR:-$repo_root/DerivedData/Build/Products/Debug}"
if [[ ! -f "$build_products/Defaults.o" ]]; then
    printf '%s\n' "Missing Defaults.o. Run the Debug build above, or set BORING_NOTCH_BUILD_PRODUCTS_DIR to its products directory." >&2
    exit 1
fi

test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT

# Debug package objects may include coverage instrumentation.
xcrun swiftc -parse-as-library -profile-generate \
    -I "$build_products" \
    "$repo_root/boringNotch/extensions/PanGesture.swift" \
    "$repo_root/boringNotch/components/Calendar/CalendarTimelineGeometry.swift" \
    "$repo_root/boringNotch/components/Calendar/HomeCalendarGeometry.swift" \
    "$repo_root/boringNotch/components/Calendar/HomeCalendarScrollView.swift" \
    "$repo_root/tests/PanGestureScrollRoutingTests.swift" \
    "$build_products/Defaults.o" \
    -o "$test_directory/calendar-wheel-tests"
LLVM_PROFILE_FILE="$test_directory/calendar-wheel.profraw" "$test_directory/calendar-wheel-tests"
