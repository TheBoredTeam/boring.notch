# Publish Daily Workflow Demo Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Publish the finished daily planning/review interaction changes, demonstrate the real Debug UI with screenshots, and move PR #1438 out of draft only after validation passes.

**Architecture:** Keep the Git commit limited to the four existing Swift follow-up files and leave local planning/mockup artifacts untracked. Exercise the built app through its real onboarding, settings, scheduling, EventKit, notification, and reminder-transition paths; use the GitHub connector for PR metadata and browser control only for the attachment upload that the connector cannot perform.

**Tech Stack:** SwiftUI, EventKit, Swift Package Manager, Xcode, git, GitHub CLI, GitHub connector, macOS Computer Use

---

### Task 1: Confirm and stage the publish scope

**Files:**
- Modify: `boringNotch/ContentView.swift`
- Modify: `boringNotch/components/Settings/Views/CalendarSettingsView.swift`
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningManager.swift`
- Modify: `boringNotch/features/DailyPlanning/DailyPlanningView.swift`
- Exclude: `docs/`
- Exclude: `sketches/`

**Step 1: Review the working tree**

Run: `git status -sb`

Expected: only the four Swift files are tracked modifications; `docs/` and `sketches/` remain untracked.

**Step 2: Review the complete diff**

Run: `git diff --check`

Expected: exit code 0 with no whitespace errors.

Inspect each Swift diff and confirm that it contains only the bell prompt, hover activation, settings copy, reminder-transition coordination, todo animations, and quiet finish action.

**Step 3: Run tests**

Run: `swift test --disable-sandbox`

Expected: all 11 `DailyPlanningCoreTests` pass.

**Step 4: Build the Debug app**

Run the established Debug `xcodebuild` command with derived data at `/tmp/boring-notch-preserved-settings-build` and bundle identifier `dev.codex.boringnotch.dailyplanning`.

Expected: build exits 0. Existing unrelated warnings are acceptable.

**Step 5: Stage exact files**

Run:

```bash
git add boringNotch/ContentView.swift \
  boringNotch/components/Settings/Views/CalendarSettingsView.swift \
  boringNotch/features/DailyPlanning/DailyPlanningManager.swift \
  boringNotch/features/DailyPlanning/DailyPlanningView.swift
```

Expected: `git diff --cached --name-only` lists exactly these four files.

### Task 2: Commit and push the follow-up

**Files:**
- Commit: the four staged Swift files

**Step 1: Commit**

Run: `git commit -m "Improve daily planning and review interactions"`

Expected: one new commit on `feature/daily-planning-review`.

**Step 2: Push to the fork**

Run: `git push -u origin feature/daily-planning-review`

Expected: the fork branch advances and PR #1438 picks up the new commit.

**Step 3: Confirm PR branch metadata**

Fetch PR #1438 through the GitHub connector.

Expected: head is `feature/daily-planning-review`, base is `dev`, and the PR remains draft until the demo and checks complete.

### Task 3: Run the real workflow and capture screenshots

**Files:**
- App: `/tmp/boring-notch-preserved-settings-build/Build/Products/Debug/boringNotch.app`
- Create temporarily: screenshot image files under `/tmp/boring-notch-daily-workflow-demo/`

**Step 1: Open the Debug app**

Use Computer Use to inspect and complete the app's normal onboarding. Do not accept an OS privacy prompt without user authorization at action time.

**Step 2: Prepare safe demo reminders**

Use the existing `test1` and `test2` reminders if they can be shown for today's session without exposing unrelated Reminder content. If their due dates must change, ask before modifying them and restore them afterward when practical.

**Step 3: Trigger morning planning**

Enable morning planning and set its time to the current or immediately previous minute.

Expected: a compact bell prompt appears without opening the full notch. Hovering opens `Today’s Plan` and shows today's test reminders.

Capture screenshots of the bell prompt and morning plan.

**Step 4: Trigger evening review**

Finish morning planning, enable evening review, and set its time to the current or immediately previous minute.

Expected: the evening bell prompt appears, hover opens `Evening Review`, and reminders are split between `Still open` and `Completed`.

Toggle a test reminder in both directions. Confirm the checkbox/strike animation finishes before the row fades out and fades into the opposite section.

Capture an evening review screenshot with both sections visible.

**Step 5: Verify dismissal**

Click `Wrap Up My Day`.

Expected: workflow content disappears before the close animation and no calendar, music, header, or menu UI flashes.

### Task 4: Add screenshots and finish the PR description

**Files:**
- Upload: screenshots from `/tmp/boring-notch-daily-workflow-demo/`
- Update: PR #1438 description

**Step 1: Upload screenshots**

Use Browser control on PR #1438 because the GitHub connector has no attachment-upload API. Upload only the captured Boring Notch images; do not upload unrelated desktop or Reminder data.

Expected: GitHub returns `user-attachments` Markdown for each image.

**Step 2: Update the PR body**

Keep the concise `Description`, `What changed`, `Related issue`, and `Testing` sections. Add the uploaded screenshots and replace `Draft status` with completed manual-test results.

Expected: the PR still contains `Closes #1439` and accurately distinguishes automated from manual checks.

### Task 5: Check CI and mark ready

**Files:**
- GitHub PR: `TheBoredTeam/boring.notch#1438`

**Step 1: Inspect checks**

Run: `/opt/homebrew/bin/gh pr checks 1438 --repo TheBoredTeam/boring.notch`

Expected: all required checks pass. If a check fails, stop the ready transition and use the GitHub CI-fix workflow to diagnose it.

**Step 2: Mark ready for review**

Use the GitHub connector's ready-for-review action only when the commit is pushed, screenshots are attached, manual testing is complete, and required checks pass.

Expected: PR #1438 is open, no longer draft, still targets `dev`, and retains `Closes #1439`.

**Step 3: Final read-back**

Fetch PR #1438 and confirm its title, base, head SHA, draft state, screenshot links, testing text, and issue link.
