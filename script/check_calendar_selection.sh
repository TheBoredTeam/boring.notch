#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d)"
trap 'rm -rf "$test_directory"' EXIT

# Build the app first with -derivedDataPath DerivedData, or point this variable
# at another build's Debug/Release products directory.
products_directory="${CALENDAR_TEST_PRODUCTS_DIR:-$repo_root/DerivedData/Build/Products/Debug}"
if [[ ! -f "$products_directory/Defaults.o" && -z "${CALENDAR_TEST_PRODUCTS_DIR:-}" ]]; then
    products_directory="$repo_root/DerivedData/Build/Products/Release"
fi
if [[ ! -f "$products_directory/Defaults.o" || ! -d "$products_directory/Defaults.swiftmodule" ]]; then
    echo "Build boringNotch with -derivedDataPath DerivedData first, or set CALENDAR_TEST_PRODUCTS_DIR to its build products directory." >&2
    exit 1
fi

# Debug dependency builds can include LLVM coverage instrumentation.
xcrun swiftc -profile-generate -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    -I "$products_directory" \
    "$repo_root/boringNotch/models/CalendarModel.swift" \
    "$repo_root/boringNotch/models/EventModel.swift" \
    "$repo_root/boringNotch/models/MeetingLink.swift" \
    "$repo_root/boringNotch/helpers/Log.swift" \
    "$repo_root/boringNotch/Providers/MeetingLinkDetector.swift" \
    "$repo_root/boringNotch/Providers/CalendarServiceProviding.swift" \
    "$repo_root/boringNotch/managers/CalendarManager.swift" \
    "$repo_root/tests/CalendarSelectionTests.swift" \
    "$products_directory/Defaults.o" \
    -o "$test_directory/calendar-selection-tests"
LLVM_PROFILE_FILE="$test_directory/calendar-selection.profraw" "$test_directory/calendar-selection-tests"
