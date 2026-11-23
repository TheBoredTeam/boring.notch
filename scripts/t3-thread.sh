#!/bin/sh
# Session lancée par T3 Code -> titre du fil T3 (généré, ou renommé par l'utilisateur) vers Boring Notch.
# Usage : <payload du hook> | t3-thread.sh <claude|codex>. Lancé détaché par agent-hook.sh / codex-hook.sh.
# N'agit qu'au Stop d'une session T3 Code (T3CODE_THREAD_ID) : un `t3 thread show` (~0,5 s) par tour, pas par outil.
# BN_DRY=1 : affiche au lieu d'envoyer. BN_T3_SHOW=<fichier> : réponse de `t3 thread show --json` enregistrée (auto-test).
exec /usr/bin/python3 -c '
import json, os, socket, subprocess, sys
SOCK = os.path.expanduser("~/Library/Containers/theboringteam.boringnotch/Data/.bn.sock")
tid = os.environ.get("T3CODE_THREAD_ID")
try:
    p = json.load(sys.stdin)
    if not tid or not isinstance(p, dict) or p.get("hook_event_name") != "Stop" or not p.get("session_id"):
        sys.exit(0)
    if os.environ.get("BN_T3_SHOW"):
        out = open(os.environ["BN_T3_SHOW"]).read()
    else:
        cli = os.environ.get("T3CODE_CLI_PATH") or os.path.expanduser("~/.t3/bin/t3")
        out = subprocess.run([cli, "thread", "show", tid, "--json", "--messages", "0"],
                             capture_output=True, text=True, timeout=15).stdout
    t = json.loads(out)["thread"]
    title = (t.get("title") or "").strip()
    if not title:
        sys.exit(0)
    msg = {"source": sys.argv[1], "kind": "title", "topic": title, "payload": {"session_id": p["session_id"]}}
    if os.environ.get("BN_DRY"):
        print(json.dumps(msg, ensure_ascii=False)); sys.exit(0)
    s = socket.socket(socket.AF_UNIX); s.settimeout(1); s.connect(SOCK)
    s.sendall(json.dumps(msg).encode()); s.close()
except Exception:
    pass
' "$1"
