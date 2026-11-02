#!/bin/sh
set -eu
repository=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/boring-notch-ai-test-build.XXXXXX")
trap 'rm -rf "$test_directory"' EXIT HUP INT TERM
swiftc -module-cache-path "$test_directory/module-cache" \
    "$repository/boringNotch/models/AIActivity.swift" \
    "$repository/BoringNotchXPCHelper/AIActivitySocket.swift" \
    "$repository/BoringNotchXPCHelper/AIActivityHookInstaller.swift" \
    "$repository/Tests/AIActivityTests/main.swift" \
    -o "$test_directory/AIActivityTests"
"$test_directory/AIActivityTests"
