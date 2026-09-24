#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
validation_tmp=$(mktemp -d)
trap 'rm -rf "$validation_tmp"' EXIT
swiftc -parse-as-library -o "$validation_tmp/DiarySmoke" \
  boringNotch/features/DailyPlanning/Core/*.swift \
  boringNotch/features/DailyPlanning/DailyReminderService.swift \
  boringNotch/features/DailyPlanning/DailyPlanningManager.swift \
  boringNotch/features/DailyPlanning/DailyPlanningView.swift \
  boringNotch/features/DailyPlanning/DailyConclusionView.swift \
  boringNotch/components/Notch/BoringNotchWindow.swift \
  validation/daily-conclusion/Smoke.swift
"$validation_tmp/DiarySmoke"
