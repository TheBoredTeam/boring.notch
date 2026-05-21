#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 - <<'PY'
from pathlib import Path

source = Path("Gojo/components/Windows/WindowPowerView.swift").read_text()
assert "InteractiveWindowLayoutMap" in source, "Windows tab must expose an interactive layout map."
assert "@EnvironmentObject var vm: GojoViewModel" in source, "Windows tab must use per-notch view model."
assert "vm.windowPowerState" in source, "Windows tab must bind per-notch window power state."
assert "layoutTile" in source, "Windows tab must use a flush-left layout tile."
assert "windowsLayoutTileSide" in source, "Layout tile should scale with notch height like album art."
assert "GeometryReader" in source, "Windows tab should size from available notch height."
assert "windowsContentPadding" in source, "Windows tab should use music-player content inset."
assert "appNameColumn" in source, "Windows tab must show app name on the right."
assert "MarqueeText" in source, "App name should scroll like the music player."
assert "centerPreviewInTile" in source, "Layout preview should be centered in the square tile."
assert "NSWorkspace.didActivateApplicationNotification" in source, "Windows tab must refresh when frontmost app changes."
assert "screenUUID: vm.screenUUID" in source, "Refresh must be scoped to this notch display."
assert "MusicPlayerImageSizes.cornerRadiusInset.opened" in source, "Layout tile should match music player corner radius."
assert "statusHeader" not in source, "Remove verbose status header stack."
assert ".frame(width: 170" not in source, "Remove fixed-width status column from old layout."
assert "state.displayName" not in source, "Do not show display name in the compact panel."

matters = Path("Gojo/sizing/matters.swift").read_text()
assert "windowsLayoutTileSide" in matters, "Tile sizing helper belongs in NotchContentLayout."
assert "windowsContentPadding" in matters, "Windows tab padding should match music album inset."

content = Path("Gojo/ContentView.swift").read_text()
assert "WindowPowerView()" in content, "ContentView must host the Windows tab."
assert ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)" in content, "Open tab content must fill notch height for layout tile sizing."

map_start = source.index("private struct WindowMapZoneButton")
map_end = source.index("#Preview", map_start)
map_button = source[map_start:map_end]

assert "Button" in map_button, "Window map zones must render as clickable buttons."
assert "onAction(action)" in map_button, "Clicking a map zone must execute its action."
assert "hoverOutcomeVisible" in map_button, "Zone buttons must suppress duplicate fills while the hover outcome overlay is shown."

executor = Path("Gojo/WindowManagement/WindowActionExecutor.swift").read_text()
assert "screenUUID: String?" in executor, "Executor must accept screen UUID."
assert "state: WindowPowerState" in executor, "Executor must accept per-notch state."
assert "focusedWindow(for: notchScreen" in executor, "Executor must resolve focus for the notch screen."

vm = Path("Gojo/models/GojoViewModel.swift").read_text()
assert "let windowPowerState = WindowPowerState()" in vm, "Each view model owns window power state."

print("window_power_view_regression: ok")
PY
