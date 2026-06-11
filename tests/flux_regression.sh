#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="/tmp/gojo-flux-regression"
swiftc \
  Gojo/components/Flux/FluxColorMath.swift \
  Gojo/components/Flux/SolarCalculator.swift \
  Gojo/components/Flux/FluxSchedule.swift \
  tests/flux_regression.swift \
  -o "$BIN"
"$BIN"
