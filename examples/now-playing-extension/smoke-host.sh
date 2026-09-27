#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
root="$(cd ../.. && pwd)"
bash build.sh
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
xcrun swiftc -D DEBUG -parse-as-library \
  "$root/boringNotch/ExtensionHost/ExtensionPackage.swift" \
  "$root/boringNotch/ExtensionHost/ExtensionRuntime.swift" smoke-host.swift -o "$scratch/host"
BN_ALLOW_DEVELOPMENT_EXTENSIONS=1 "$scratch/host" "$PWD/dist/com.example.boringnotch.now-playing.bnplugin"
