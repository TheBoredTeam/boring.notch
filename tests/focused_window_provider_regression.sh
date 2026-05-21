#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path

source = Path("Gojo/WindowManagement/FocusedWindowProvider.swift").read_text()

assert "preferredTopWindowID(for: app.processIdentifier)" in source, "FocusedWindowProvider must derive a preferred top CGWindow ID for fallback targeting."
assert "bestWindowElement(for: appElement, preferredWindowID: preferredWindowID)" in source, "FocusedWindowProvider must pass the preferred window ID into AX window selection."
assert "private func preferredTopWindowID(for pid: pid_t) -> CGWindowID?" in source, "FocusedWindowProvider must expose a preferred top-window helper."
assert "windowID(of: $0) == preferredWindowID" in source, "AX window selection must match the top CGWindow ID when focused/main window is unavailable."
assert source.index("if let preferredWindowID,") < source.index("let directCandidates = ["), "AX selection should prefer the top CGWindow before focused/main AX candidates so external-display top windows win."
PY
