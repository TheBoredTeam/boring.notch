#!/bin/bash
# Copyright (c) 2026 Harsh Vardhan Goswami (@theboringhumane).
# Attribution applies to the extension platform contributions.

set -euo pipefail
cd "$(dirname "$0")"

root="$(cd ../.. && pwd)"
bundle="${1:-dist/org.example.boringnotch.focus-timer.bnplugin}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/focus-extension-smoke.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
source="$root/boringNotch/components/LiveActivities"

xcrun swiftc -swift-version 5 -strict-concurrency=complete -D DEBUG -parse-as-library \
  "$source/Core/"*.swift \
  "$source/LiveActivityCenter.swift" \
  "$source/NotchActivityLayoutMetrics.swift" \
  "$source/NotchActivityHost.swift" \
  "$source/Extensions/ExtensionPackage.swift" \
  "$source/Extensions/ExtensionActivityDescriptor.swift" \
  "$source/Extensions/ExtensionActivity.swift" \
  "$source/Extensions/ExtensionRuntime.swift" smoke.swift \
  "$source/Extensions/ExtensionTabDescriptor.swift" \
  "$source/Extensions/ExtensionTabRegistry.swift" \
  "$source/Extensions/ExtensionTab.swift" \
  -o "$scratch/focus-extension-smoke"
BN_ALLOW_DEVELOPMENT_EXTENSIONS=1 "$scratch/focus-extension-smoke" "$bundle"
