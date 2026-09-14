#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/boring-notch-codex-check.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
PYTHONDONTWRITEBYTECODE=1 python3 "$repo_dir/tests/CodexActivityBridgeTests.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$repo_dir/tests/CodexActivityJSONTests.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$repo_dir/tests/CodexActivityDiscoveryTests.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$repo_dir/tests/CodexActivitySubscriptionTests.py"
swiftc -swift-version 5 -o "$build_dir/codex-activity-tests" \
  "$repo_dir/boringNotch/models/CodexActivityPhase.swift" \
  "$repo_dir/boringNotch/models/CodexAvatarStyle.swift" \
  "$repo_dir/boringNotch/components/Notch/CodexAvatarView.swift" \
  "$repo_dir/boringNotch/components/AnimatedFace.swift" \
  "$repo_dir/boringNotch/helpers/Log.swift" \
  "$repo_dir/boringNotch/managers/CodexActivityManager.swift" \
  "$repo_dir/tests/CodexActivityTests.swift"
"$build_dir/codex-activity-tests"
