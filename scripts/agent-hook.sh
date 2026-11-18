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
  TOPIC=$("${DELTA_CLI:-/Applications/Delta.app/Contents/MacOS/delta}" --json thread list 2>/dev/null | /usr/bin/python3 -c '
import json, os, sys
n = next((t.get("name") for t in json.load(sys.stdin) if t.get("id") == os.environ["DELTA_CURRENT_THREAD_ID"]), None)
if n: print(json.dumps(n))' 2>/dev/null)
fi
{ printf '{"source":"%s","app":"%s",' "$1" "$__CFBundleIdentifier"; [ -n "$TOPIC" ] && printf '"topic":%s,' "$TOPIC"; printf '"payload":'; printf %s "$IN" | tr -d '\n'; printf '}'; } | nc -U -w 1 "$SOCK" >/dev/null 2>&1
# Forfait à jour quel que soit le client (T3 Code, SDK, terminal) : sonde limitée à une fois / 3 min, détachée.
"$(dirname "$0")/agent-usage.sh" "$1" </dev/null >/dev/null 2>&1 &
exit 0
