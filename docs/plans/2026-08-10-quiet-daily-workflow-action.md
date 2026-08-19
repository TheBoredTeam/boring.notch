# Quiet Daily Workflow Action Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the visually heavy daily planning/review finish capsule with the approved quiet text-and-arrow action, then rebuild and reopen a clean Debug app.

**Architecture:** Keep the existing `DailyWorkflowFinishButton` boundary and completion callback unchanged. Limit the production edit to its SwiftUI label and private `ButtonStyle`, using existing `StandardAnimations.interactive` and `Color.effectiveAccent` tokens so no workflow state or Reminder behavior changes.

**Tech Stack:** SwiftUI, macOS, Swift Package Manager tests, Xcode Debug build

---

### Task 1: Replace the workflow finish button treatment

**Files:**
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift:227`

**Step 1: Close the running Debug app**

Use Computer Use to inspect `/tmp/boring-notch-preserved-settings-build/Build/Products/Debug/boringNotch.app`, quit it if running, and inspect again to confirm its window is closed.

**Step 2: Simplify the button label**

Keep `Text(kind.actionTitle)` and `Image(systemName: "arrow.right")`, but remove the arrow's nested circular background. Move the arrow two points to the right on hover and use a rectangular content shape so the complete label remains clickable.

**Step 3: Replace the filled style**

Update `DailyWorkflowFinishButtonStyle` to:

```swift
configuration.label
    .foregroundStyle(isHovering ? Color.primary : Color.secondary)
    .padding(.horizontal, 6)
    .frame(height: 28)
    .overlay(alignment: .bottom) {
        Capsule()
            .fill(Color.effectiveAccent)
            .frame(height: 1)
            .scaleEffect(x: isHovering ? 1 : 0, anchor: .leading)
    }
    .opacity(configuration.isPressed ? 0.68 : 1)
    .scaleEffect(configuration.isPressed ? 0.97 : 1)
```

Preserve `StandardAnimations.interactive` for hover and pressed transitions. Do not add a resting fill, outline, shadow, or vertical lift.

**Step 4: Check the focused diff**

Run: `git diff --check`

Expected: exit code 0 with no output.

Run: `git diff -- boringNotch/features/DailyPlanning/DailyPlanningView.swift`

Expected: only the finish action presentation changes; session and Reminder behavior remain untouched.

### Task 2: Verify and relaunch the Debug build

**Files:**
- Verify: `Package.swift`
- Build: `boringNotch.xcodeproj`

**Step 1: Run planning tests**

Run: `swift test --disable-sandbox`

Expected: all 11 `DailyPlanningCoreTests` pass.

**Step 2: Erase only Debug preferences**

Run: `defaults delete dev.codex.boringnotch.dailyplanning`

Expected: the preference domain is deleted, or reported absent. Do not delete Apple Reminders or Shelf data.

**Step 3: Build the app**

Run the established `xcodebuild` Debug command with derived data at `/tmp/boring-notch-preserved-settings-build` and bundle identifier `dev.codex.boringnotch.dailyplanning`.

Expected: `xcodebuild` exits 0. Existing unrelated project warnings are acceptable; new errors are not.

**Step 4: Open and inspect the Debug app**

Use Computer Use to open `/tmp/boring-notch-preserved-settings-build/Build/Products/Debug/boringNotch.app` and inspect its state.

Expected: the Debug app is running at onboarding because its preferences were reset. Do not accept Reminders or other privacy permissions for the user.

**Step 5: Leave contribution history untouched**

Do not stage, commit, push, or modify the draft PR unless the user explicitly requests it. Preserve all existing uncommitted daily-planning work and disposable sketches.
