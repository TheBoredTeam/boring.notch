#!/bin/sh
# Hook Codex -> Boring Notch : événement de session ; déclenche aussi agent-usage.sh (forfait).
# Échoue en silence si l'app est fermée.
exec /usr/bin/python3 -c '
import json, os, re, socket, subprocess, sys
SOCK = os.path.expanduser("~/Library/Containers/theboringteam.boringnotch/Data/.bn.sock")
def t3_link():
    # Lancé par T3 Code : lien profond vers le fil, ouvert au clic dans le notch.
    tid = os.environ.get("T3CODE_THREAD_ID")
    f = os.path.join(os.environ.get("T3CODE_HOME") or os.path.expanduser("~/.t3"), "userdata", "environment-id")
    try: return "t3code://threads/%s/%s" % (open(f).read().strip(), tid) if tid else ""
    except OSError: return ""
try:
    p = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(p, dict):
    sys.exit(0)

def send(obj):
    if os.environ.get("BN_DRY"):
        print(json.dumps(obj)); return
    try:
        s = socket.socket(socket.AF_UNIX); s.settimeout(1)
        s.connect(SOCK); s.sendall(json.dumps(obj).encode()); s.close()
    except Exception:
        pass

def normalize(p):
    # Codex envoie déjà le format Claude (Bash, tool_input.command, tool_use_id).
    # Seul apply_patch (format non observé, d’après la doc Codex) devient Edit.
    # PermissionRequest : non vérifié, relayé tel quel.
    ti = p.get("tool_input")
    if p.get("tool_name") == "apply_patch" and isinstance(ti, dict):
        c = ti.get("command")
        txt = "\n".join(map(str, c)) if isinstance(c, list) else str(c or "")
        m = re.search(r"^\*\*\* (?:Update|Add) File: (.+)$", txt, re.M)
        p = dict(p, tool_name="Edit", tool_input={"file_path": m.group(1).strip() if m else ""})
    elif isinstance(ti, dict) and isinstance(ti.get("command"), list):
        p = dict(p, tool_input=dict(ti, command=" ".join(map(str, ti["command"]))))
    return p

p = normalize(p)
app = os.environ.get("__CFBundleIdentifier", "")
send({"source": "codex", "app": app, "link": t3_link(), "payload": p})

# Forfait : même sonde que Claude (account/rateLimits/read), limitée à une fois / 3 min, détachée.
if not os.environ.get("BN_DRY"):
    subprocess.Popen([os.path.join(sys.argv[1], "agent-usage.sh"), "codex"],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
' "$(cd "$(dirname "$0")" && pwd)"
