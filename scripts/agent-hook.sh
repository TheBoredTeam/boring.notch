#!/bin/sh
# Hook d'agent -> Boring Notch. Usage : agent-hook.sh <claude|codex|cursor>
# Transmet aussi l'app du terminal (pour rouvrir la conversation au clic).
# Échoue en silence si l'app est fermée (l'agent n'est jamais bloqué). Déclenche aussi agent-usage.sh.
SOCK="$HOME/Library/Containers/theboringteam.boringnotch/Data/.bn.sock"
[ -S "$SOCK" ] || { cat >/dev/null; # Forfait à jour quel que soit le client (T3 Code, SDK, terminal) : sonde limitée à une fois / 3 min, détachée.
"$(dirname "$0")/agent-usage.sh" "$1" </dev/null >/dev/null 2>&1 &
exit 0; }
IN=$(cat)
# Sujet : nom du fil Delta, relu seulement au prompt et à la fin (≈ 40 ms) ; toute erreur = pas de champ topic.
TOPIC=
if [ -n "$DELTA_CURRENT_THREAD_ID" ] && printf %s "$IN" | grep -Eq '"hook_event_name" *: *"(UserPromptSubmit|Stop)"'; then
  TOPIC=$(/usr/bin/python3 -c '
import json, os, subprocess
try:
    cli = os.environ.get("DELTA_CLI") or "/Applications/Delta.app/Contents/MacOS/delta"
    out = subprocess.run([cli, "--json", "thread", "list"], capture_output=True, timeout=1.5).stdout
    n = next((t.get("name") for t in json.loads(out) if t.get("id") == os.environ["DELTA_CURRENT_THREAD_ID"]), None)
    if isinstance(n, str) and n: print(json.dumps(n))
except Exception: pass' 2>/dev/null)
fi
# Lancé par T3 Code : lien profond vers le fil (t3code://threads/<environnement>/<fil>), ouvert au clic dans le notch.
LINK=""
ENV_FILE="${T3CODE_HOME:-$HOME/.t3}/userdata/environment-id"
[ -n "$T3CODE_THREAD_ID" ] && [ -r "$ENV_FILE" ] && LINK="t3code://threads/$(cat "$ENV_FILE")/$T3CODE_THREAD_ID"
{ printf '{"source":"%s","app":"%s","link":"%s",' "$1" "$__CFBundleIdentifier" "$LINK"; [ -n "$TOPIC" ] && printf '"topic":%s,' "$TOPIC"; printf '"payload":'; printf %s "$IN" | tr -d '\n'; printf '}'; } | nc -U -w 1 "$SOCK" >/dev/null 2>&1
# Session T3 Code : titre du fil à jour à chaque fin de tour (détaché, n'agit qu'au Stop).
[ -n "$T3CODE_THREAD_ID" ] && { printf %s "$IN" | "$(dirname "$0")/t3-thread.sh" "$1" >/dev/null 2>&1 & }
# Forfait à jour quel que soit le client (T3 Code, SDK, terminal) : sonde limitée à une fois / 3 min, détachée.
"$(dirname "$0")/agent-usage.sh" "$1" </dev/null >/dev/null 2>&1 &
exit 0
