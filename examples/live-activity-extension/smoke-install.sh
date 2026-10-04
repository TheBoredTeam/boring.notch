#!/bin/bash
# Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
# Attribution applies to the extension platform contributions.

set -euo pipefail
example_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$example_dir/../.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/boring-extension-install.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/home" "$scratch/installed"

if [ ! -f "$example_dir/dist/FocusTimer-development.zip" ]; then
    bash "$example_dir/build.sh"
fi

activity_dir="$repo_dir/boringNotch/components/LiveActivities"
xcrun swiftc -D DEBUG -swift-version 5 -parse-as-library \
    "$example_dir/smoke-install.swift" \
    "$activity_dir"/Core/*.swift \
    "$activity_dir/LiveActivityCenter.swift" \
    "$activity_dir"/Extensions/*.swift \
    -o "$scratch/smoke-install"

CFFIXED_USER_HOME="$scratch/home" \
BN_ALLOW_DEVELOPMENT_EXTENSIONS=1 \
BN_EXTENSION_TEST_DIRECTORY="$scratch/installed" \
    "$scratch/smoke-install" "$example_dir/dist/FocusTimer-development.zip"

# Separate process: Swift/Objective-C classes from two copies of the same
# plugin must not be loaded into one process merely to test code replacement.
CFFIXED_USER_HOME="$scratch/home" \
BN_ALLOW_DEVELOPMENT_EXTENSIONS=1 \
BN_EXTENSION_TEST_DIRECTORY="$scratch/installed" \
    "$scratch/smoke-install" "$example_dir/dist/FocusTimer-development.zip" --external-replacement
