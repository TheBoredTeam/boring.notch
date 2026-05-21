#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="/tmp/gojo-window-management-regression"
swiftc \
  Gojo/WindowManagement/WindowAction.swift \
  Gojo/WindowManagement/WindowTargetResolver.swift \
  Gojo/WindowManagement/WindowFrameCalculator.swift \
  tests/window_management_regression.swift \
  -o "$BIN"
"$BIN"
