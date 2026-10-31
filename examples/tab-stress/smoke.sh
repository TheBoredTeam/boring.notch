#!/bin/bash
# Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
# Attribution applies to the extension platform contributions.

set -euo pipefail
fixture_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$fixture_dir/../.." && pwd)"
bundle_dir="${1:-$fixture_dir/dist}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/boring-tab-stress-smoke.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/home"
activity_dir="$repo_dir/boringNotch/components/LiveActivities"
xcrun swiftc -D DEBUG -swift-version 5 -parse-as-library \
    "$fixture_dir/smoke.swift" \
    "$activity_dir"/Core/*.swift \
    "$activity_dir/Extensions/ExtensionPackage.swift" \
    "$activity_dir/Extensions/ExtensionActivityDescriptor.swift" \
    "$activity_dir/Extensions/ExtensionRuntime.swift" \
    "$activity_dir/Extensions/ExtensionTabDescriptor.swift" \
    "$activity_dir/Extensions/ExtensionTabRegistry.swift" \
    "$activity_dir/Extensions/ExtensionTab.swift" \
    -o "$scratch/smoke"
CFFIXED_USER_HOME="$scratch/home" BN_ALLOW_DEVELOPMENT_EXTENSIONS=1 \
    BN_TAB_STRESS_LOG="$scratch/controllers.jsonl" "$scratch/smoke" "$bundle_dir"
