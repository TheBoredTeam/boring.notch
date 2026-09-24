#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
validation_tmp=$(mktemp -d)
trap 'rm -rf "$validation_tmp"' EXIT
diary_products=${DIARY_BUILD_PRODUCTS:?Set DIARY_BUILD_PRODUCTS to the Debug build products directory}
swiftc -I "$diary_products" "$diary_products/Defaults.o" "$diary_products/SkyLightWindow.o" -parse-as-library -o "$validation_tmp/DiarySmoke" \
  boringNotch/features/DailyPlanning/Core/*.swift \
  boringNotch/features/DailyPlanning/DailyReminderService.swift \
  boringNotch/features/DailyPlanning/DailyPlanningManager.swift \
  boringNotch/features/DailyPlanning/DailyPlanningView.swift \
  boringNotch/features/DailyPlanning/DailyConclusionView.swift \
  boringNotch/components/Notch/BoringNotchWindow.swift \
  boringNotch/components/Notch/BoringNotchSkyLightWindow.swift \
  validation/daily-conclusion/Smoke.swift
"$validation_tmp/DiarySmoke"
