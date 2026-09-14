#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
label="theboringteam.boringnotch.codex-activity-login"
agent_file="$HOME/Library/LaunchAgents/$label.plist"
log_dir="$HOME/Library/Logs/boringNotch"
runtime_dir="$HOME/Library/Application Support/boringNotch/CodexActivity"
python_path="$(command -v python3)"
tmux_path="$(command -v tmux)"
mkdir -p "$HOME/Library/LaunchAgents" "$log_dir" "$runtime_dir/script"
chmod 700 "$log_dir" "$runtime_dir" "$runtime_dir/script"
# Login startup uses an installed runtime, independent of the source checkout.
install -m 700 "$repo_dir/script/codex_activity_bridge.py" "$runtime_dir/script/codex_activity_bridge.py"
install -m 700 "$repo_dir/script/codex_activity_json.py" "$runtime_dir/script/codex_activity_json.py"
install -m 700 "$repo_dir/script/codex_activity_discovery.py" "$runtime_dir/script/codex_activity_discovery.py"
install -m 700 "$repo_dir/script/start-codex-activity-bridge.sh" "$runtime_dir/script/start-codex-activity-bridge.sh"
export BORINGNOTCH_ACTIVITY_RUNTIME="$runtime_dir"
export BORINGNOTCH_ACTIVITY_AGENT_FILE="$agent_file"
export BORINGNOTCH_ACTIVITY_LOG_DIR="$log_dir"
export BORINGNOTCH_ACTIVITY_PYTHON="$python_path"
export BORINGNOTCH_ACTIVITY_TMUX="$tmux_path"
"$python_path" <<'PY'
import os
from pathlib import Path
import plistlib

runtime = Path(os.environ["BORINGNOTCH_ACTIVITY_RUNTIME"])
agent_file = Path(os.environ["BORINGNOTCH_ACTIVITY_AGENT_FILE"])
log_dir = Path(os.environ["BORINGNOTCH_ACTIVITY_LOG_DIR"])
path_parts = [str(Path(os.environ["BORINGNOTCH_ACTIVITY_TMUX"]).parent),
              str(Path(os.environ["BORINGNOTCH_ACTIVITY_PYTHON"]).parent),
              "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
configuration = {
    "Label": "theboringteam.boringnotch.codex-activity-login",
    "ProgramArguments": ["/bin/bash", str(runtime / "script/start-codex-activity-bridge.sh")],
    "RunAtLoad": True,
    "WorkingDirectory": str(runtime),
    "EnvironmentVariables": {"PATH": ":".join(dict.fromkeys(path_parts)),
                             "PYTHONDONTWRITEBYTECODE": "1"},
    "StandardOutPath": str(log_dir / "codex-activity-login.log"),
    "StandardErrorPath": str(log_dir / "codex-activity-login.log"),
}
# plistlib escapes paths safely; the server itself remains owned by tmux.
agent_file.write_bytes(plistlib.dumps(configuration))
agent_file.chmod(0o600)
PY
launch_domain="gui/$(id -u)"
if launchctl print "$launch_domain/$label" >/dev/null 2>&1; then
    launchctl bootout "$launch_domain/$label"
fi
launchctl bootstrap "$launch_domain" "$agent_file"
printf 'Installed login startup for tmux session boringnotch-codex-activity.\n'
