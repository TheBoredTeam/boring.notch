# My Contributions to boring.notch

> [boring.notch](https://github.com/TheBoredTeam/boring.notch) is an open-source macOS app that transforms the MacBook notch into an interactive control center. These are my feature contributions.

**PR:** [#1187 — Clipboard History, Bluetooth Battery, System Stats](https://github.com/TheBoredTeam/boring.notch/pull/1187)

---

## Features Built

### 1. Clipboard History (Win+V Style)

A full clipboard manager built into the notch as a new tab.

**Problem:** macOS has no built-in clipboard history. Existing approaches (PRs #1130, #1165) simulate Cmd+V via CGEvent, which fails in Microsoft Teams and other sandboxed apps.

**Solution:** Copy-only architecture — clicking an item writes to NSPasteboard without simulating keystrokes. Works with every app, including Teams and Slack.

**Technical highlights:**
- NSPasteboard polling (0.5s) with deduplication
- Supports text, images, and file URLs
- Search/filter, pin items, context menus
- In-memory only (privacy-first, no disk persistence)
- Source app icon detection via bundle ID

### 2. Bluetooth Device Battery

Battery monitoring for any connected Bluetooth device, shown in the notch header.

**Problem:** No notch app shows battery for non-AirPods Bluetooth devices. Users with OnePlus Buds, Sony headphones, etc. had to open System Settings.

**Solution:** 3-tier battery detection fallback:
1. IORegistry scan (4 service classes)
2. IOBluetooth HID driver query
3. `system_profiler SPBluetoothDataType` JSON parse

**Technical highlights:**
- Name-based device classification (earbuds, headphones, speaker, keyboard, mouse, etc.)
- Works with non-MFi devices (OnePlus, Sony, JBL, etc.)
- Clickable popover with full device list and gradient battery bars
- 30-second refresh interval

### 3. System Stats

Live CPU, RAM, and thermal monitoring as a dedicated notch tab with circular gauge cards.

**Problem:** On fanless MacBook Air, the only thermal signal is throttling. No way to monitor system load without opening Activity Monitor.

**Solution:** Circular gauge UI with real-time data from Mach kernel APIs.

**Technical highlights:**
- `host_processor_info` for per-CPU tick deltas (sandbox-friendly, unlike `host_statistics`)
- `vm_statistics64` for RAM (active + wired + compressed = used)
- `ProcessInfo.thermalStateDidChangeNotification` for thermal
- Animated progress rings with color-coded thresholds

---

## Architecture

All features follow boring.notch's existing patterns:

```
Manager (singleton, IOKit/Mach APIs)
  → ViewModel (@ObservableObject, @Published state)
    → View (SwiftUI, tabs/header/popovers)
```

- Settings via `Defaults` library with auto-start/stop via `Defaults.publisher`
- Tab system via `NotchViews` enum
- 7 new files, 10 modified files, 1,600+ lines of Swift

## Stack

Swift, SwiftUI, IOBluetooth, IOKit, Mach kernel APIs, CoreBluetooth, Combine, Defaults
