#!/bin/sh
# Hook d'agent -> Boring Notch. Usage : agent-hook.sh <claude|codex|cursor>
# Transmet aussi l'app du terminal (pour rouvrir la conversation au clic).
# Échoue en silence si l'app est fermée (l'agent n'est jamais bloqué). Déclenche aussi agent-usage.sh.
SOCK="$HOME/Library/Containers/theboringteam.boringnotch/Data/.bn.sock"
[ -S "$SOCK" ] || { cat >/dev/null; # Forfait à jour quel que soit le client (T3 Code, SDK, terminal) : sonde limitée à une fois / 3 min, détachée.
"$(dirname "$0")/agent-usage.sh" "$1" </dev/null >/dev/null 2>&1 &
exit 0; }
IN=$(cat)
# Lancé par T3 Code : lien profond vers le fil (t3code://threads/<environnement>/<fil>), ouvert au clic dans le notch.
LINK=""
ENV_FILE="${T3CODE_HOME:-$HOME/.t3}/userdata/environment-id"
[ -n "$T3CODE_THREAD_ID" ] && [ -r "$ENV_FILE" ] && LINK="t3code://threads/$(cat "$ENV_FILE")/$T3CODE_THREAD_ID"
{ printf '{"source":"%s","app":"%s","link":"%s","payload":' "$1" "$__CFBundleIdentifier" "$LINK"; printf %s "$IN" | tr -d '\n'; printf '}'; } | nc -U -w 1 "$SOCK" >/dev/null 2>&1
# Forfait à jour quel que soit le client (T3 Code, SDK, terminal) : sonde limitée à une fois / 3 min, détachée.
"$(dirname "$0")/agent-usage.sh" "$1" </dev/null >/dev/null 2>&1 &
exit 0
