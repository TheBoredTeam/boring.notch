#!/bin/sh
# Selftest de scripts/t3-thread.sh (BN_DRY, réponse de `t3 thread show` enregistrée, sans socket ni T3 Code).
cd "$(dirname "$0")" || exit 1
python3 - <<'PY' || exit 1
import json, os, subprocess
def run(payload, tid="06496119"):
    env = {**os.environ, "BN_DRY": "1", "BN_T3_SHOW": "show.json", "T3CODE_THREAD_ID": tid}
    if not tid: env.pop("T3CODE_THREAD_ID")
    r = subprocess.run(["sh", "../t3-thread.sh", "claude"], input=payload, capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.returncode
    return [json.loads(l) for l in r.stdout.splitlines() if l.strip()]
stop = json.dumps({"session_id": "s1", "hook_event_name": "Stop"})
out = run(stop)
assert out == [{"source": "claude", "kind": "title", "topic": "Basculer l’agent IA de la notch sur T3 Code", "payload": {"session_id": "s1"}}], out
assert run(json.dumps({"session_id": "s1", "hook_event_name": "PreToolUse"})) == []   # pas d appel à chaque outil
assert run(stop, tid="") == []                                                          # hors T3 Code : rien
assert run("pas du json") == [] and run("[1]") == []
PY
echo OK
