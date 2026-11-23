#!/bin/sh
# Hook PermissionRequest bloquant -> Boring Notch. Usage : agent-permission.sh <claude>
# Envoie la demande puis attend la décision cliquée dans le notch (Autoriser/Refuser, réponse à une
# question AskUserQuestion, plan ExitPlanMode approuvé) et la renvoie à l'agent. La question reste
# affichée dans le terminal en parallèle. Sans réponse (app fermée, délai dépassé, réponse donnée
# dans le terminal) : sortie vide = le flux de validation normal continue.
# Délai : 590 s, sous le "timeout": 600 du hook dans ~/.claude/settings.json.
exec /usr/bin/python3 -c '
import json, os, socket, sys
SOCK = os.path.expanduser("~/Library/Containers/theboringteam.boringnotch/Data/.bn.sock")
def t3_link():
    # Lancé par T3 Code : lien profond vers le fil, ouvert au clic dans le notch.
    tid = os.environ.get("T3CODE_THREAD_ID")
    f = os.path.join(os.environ.get("T3CODE_HOME") or os.path.expanduser("~/.t3"), "userdata", "environment-id")
    try: return "t3code://threads/%s/%s" % (open(f).read().strip(), tid) if tid else ""
    except OSError: return ""
try:
    p = json.load(sys.stdin)
    s = socket.socket(socket.AF_UNIX); s.settimeout(1); s.connect(SOCK)
    s.sendall(json.dumps({"source": sys.argv[1], "app": os.environ.get("__CFBundleIdentifier", ""), "link": t3_link(), "wait": True, "payload": p}).encode())
    s.shutdown(socket.SHUT_WR); s.settimeout(590)
    out = b""
    while True:
        c = s.recv(4096)
        if not c: break
        out += c
    if out:
        # Le notch renvoie la décision seule ({"behavior":…, "answers"?:…}) ; AskUserQuestion et
        # ExitPlanMode exigent en plus updatedInput = entrée d origine (+ answers).
        d = json.loads(out)
        answers = d.pop("answers", None)
        if d.get("behavior") == "allow" and p.get("tool_name") in ("AskUserQuestion", "ExitPlanMode"):
            d["updatedInput"] = dict(p.get("tool_input") or {}, **({"answers": answers} if answers else {}))
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": d}}))
except Exception:
    pass
' "$1"
