# Daily Workflow Scrollbar Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the prominent macOS scrollbar chrome from daily planning and evening review while preserving normal scrolling.

**Architecture:** Keep the existing SwiftUI `ScrollView` and adopt the repository's established notch convention of hiding system indicators. This avoids custom AppKit scroller introspection and leaves wheel, trackpad, and keyboard scrolling behavior intact.

**Tech Stack:** SwiftUI, AppKit/macOS, Swift Package Manager, Xcode

---

### Task 1: Match the Existing Notch Scroll Style

**Files:**
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift:144-159`
- Reference: `boringNotch/components/Calendar/BoringCalendar.swift:628-649`
- Reference: `boringNotch/components/Shelf/Views/ShelfView.swift:97-106`

**Step 1: Confirm the current mismatch**

Inspect the daily workflow list and verify that its plain `ScrollView` uses the default macOS indicator while calendar and shelf scroll views apply `.scrollIndicators(.never)`.

Expected: daily planning has no explicit indicator style; the reference views hide indicators.

**Step 2: Apply the minimal theme-consistent implementation**

Add the existing repository convention to the daily reminder list:

```swift
ScrollView {
    // Existing reminder content.
}
.scrollIndicators(.never)
```

Expected: the system scrollbar and its gutter are no longer visible, while list content remains scrollable.

**Step 3: Check formatting and scope**

Run:

```bash
git diff --check
git diff -- boringNotch/features/DailyPlanning/DailyPlanningView.swift
```

Expected: no whitespace errors and only the intended modifier is added.

### Task 2: Verify Behavior and Publish

**Files:**
- Test: `Package.swift`
- Build: `boringNotch.xcodeproj`

**Step 1: Run unit tests**

Run:

```bash
swift test --disable-sandbox
```

Expected: all existing tests pass.

**Step 2: Rebuild the Debug application**

Close the running Debug app, reset `dev.codex.boringnotch.dailyplanning`, and build the Debug scheme with the existing isolated build directory.

Expected: `xcodebuild` exits successfully and produces `boringNotch.app`.

**Step 3: Manually verify the UI**

Open a daily workflow with more reminders than fit in the viewport. Verify morning planning and both evening columns scroll to their final item without showing the wide system scrollbar. Verify completion animations and section transfers still work.

Expected: scrolling remains functional and the list visually blends into the black notch surface.

**Step 4: Commit and push only the scrollbar change**

```bash
git add boringNotch/features/DailyPlanning/DailyPlanningView.swift
git commit -m "Polish daily workflow scrolling"
git push origin feature/daily-planning-review
```

Expected: PR #1438 advances to the new commit without including local `docs/` or `sketches/` artifacts.

**Step 5: Recheck contribution readiness**

Confirm issue #1439 and PR #1438 follow `CONTRIBUTING.md`: issue-first workflow, feature label, feature branch based on `dev`, PR base `dev`, clear rationale, issue reference, UI screenshots, successful tests/build, and passing GitHub checks.
