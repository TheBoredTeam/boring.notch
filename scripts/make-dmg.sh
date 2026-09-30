#!/usr/bin/env bash
# Gera o instalador do boringCode: build Release + DMG com atalho para Aplicativos.
# Uso: scripts/make-dmg.sh            → dist/boringCode-<versão>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# dmgbuild (versões travadas por hash) num venv próprio, fora do sistema.
VENV="$ROOT/build/dmgenv"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
  if command -v uv >/dev/null 2>&1; then
    uv venv -q "$VENV"
    VIRTUAL_ENV="$VENV" uv pip install -q --require-hashes -r Configuration/dmg/requirements.txt
  else
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q --require-hashes -r Configuration/dmg/requirements.txt
  fi
fi
export PATH="$VENV/bin:$PATH"

echo "▸ Compilando (Release)…"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' build -quiet

APP="build/Build/Products/Release/boringCode.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p dist
DMG="dist/boringCode-$VERSION.dmg"
rm -f "$DMG"

echo "▸ Conferindo assinatura…"
codesign --verify --deep --strict "$APP"

echo "▸ Gerando $DMG…"
Configuration/dmg/create_dmg.sh "$APP" "$DMG" "boringCode"

echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
