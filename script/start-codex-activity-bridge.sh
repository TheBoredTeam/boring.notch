#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
session_name="boringnotch-codex-activity"
if tmux has-session -t "$session_name" 2>/dev/null; then
    printf 'Codex activity bridge session already exists: %s\n' "$session_name"
    exit 0
fi
log_dir="$HOME/Library/Logs/boringNotch"
mkdir -p "$log_dir"
chmod 700 "$log_dir"
printf -v command '%q %q >> %q 2>&1' "$(command -v python3)" "$repo_dir/script/codex_activity_bridge.py" "$log_dir/codex-activity.log"
# This ongoing integration intentionally lives as long as its tmux session.
tmux new-session -d -s "$session_name" "$command"
printf 'Started Codex activity bridge. Attach with: tmux attach -t %s\n' "$session_name"
