#!/usr/bin/env bash
# Compila o boringCode (Debug), assina com o certificado fixo "boringCode Dev" e instala a
# única cópia em /Applications, abrindo o app em seguida.
# Uso: scripts/install-dev.sh            (roda scripts/setup-dev-signing.sh se precisar)
#      scripts/install-dev.sh --no-open  (só instala)
#
# Por quê: build ad-hoc muda de identidade a cada compilação e o macOS pede as permissões de
# novo; e cópias soltas em build/ apareciam no Finder/Spotlight como "outros boringCode".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

IDENTITY="boringCode Dev"
BUNDLE_ID="com.reesoousa.boringcode"
# ".noindex" no nome faz o Spotlight ignorar a pasta: os builds não aparecem como apps.
DERIVED="build.noindex"
BUILT="$DERIVED/Build/Products/Debug/boringCode.app"
DEST="/Applications/boringCode.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

scripts/setup-dev-signing.sh

echo "▸ Compilando (Debug)…"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug \
  -derivedDataPath "$DERIVED" -destination 'platform=macOS,arch=arm64' build -quiet

echo "▸ Assinando com \"$IDENTITY\"…"
sign() {
  codesign --force --sign "$IDENTITY" --timestamp=none \
    --preserve-metadata=identifier,entitlements,flags,runtime "$1" 2>/dev/null \
    || { echo "✗ Falhou ao assinar $1" >&2; exit 1; }
}
# De dentro para fora: primeiro binários soltos, depois bundles (mais fundos antes), por fim o app.
while IFS= read -r f; do
  if file -b "$f" | grep -q 'Mach-O'; then sign "$f"; fi
done < <(find "$BUILT/Contents" -type f -perm -111 | awk -F/ '{print NF, $0}' | sort -rn | cut -d' ' -f2-)
while IFS= read -r b; do
  sign "$b"
done < <(find "$BUILT/Contents" -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name '*.appex' \) \
  | awk -F/ '{print NF, $0}' | sort -rn | cut -d' ' -f2-)
sign "$BUILT"
codesign --verify --deep --strict "$BUILT"

echo "▸ Instalando em $DEST…"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 1
pkill -9 -x boringCode 2>/dev/null || true
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

# Só a cópia de /Applications fica registrada como app: tira do registro qualquer outro
# boringCode.app (builds, DMG montado, pastas antigas) para o Finder não oferecer "outros".
"$LSREGISTER" -dump 2>/dev/null \
  | sed -nE 's#^path: +(.*/boringCode\.app(/.*)?\.app|.*/boringCode\.app)( \(0x[0-9a-f]+\))?$#\1#p' \
  | sort -u | while IFS= read -r stale; do
      case "$stale" in "$DEST"|"$DEST"/*) ;; *) "$LSREGISTER" -u "$stale" >/dev/null 2>&1 || true ;; esac
    done
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

echo "✓ Instalado: $DEST"
[ "${1:-}" = "--no-open" ] || open "$DEST"
