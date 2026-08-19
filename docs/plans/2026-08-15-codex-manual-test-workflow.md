# Codex Manual Test Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Define deterministic daily-work prompts and a repeatable manual workflow for validating Codex success, failure, and permission-required notifications in the Debug app.

**Architecture:** Keep the tests on the real Codex hook path. A normal completed instruction validates the passive green Success notice, a deliberately stopped long-running instruction validates Failure, and a safe write outside the current workspace validates the live Permission Required flow. Document reset, expected UI, decision, timing, and troubleshooting rules in the repository-root `AGENT.md`.

**Tech Stack:** Codex conversations and hooks, Boring Notch macOS Debug app, SwiftUI notification UI, Markdown documentation.

---

### Task 1: Define the three test prompts

**Files:**
- Modify: `AGENT.md`

Write one copy-pasteable prompt for each lifecycle path:

- Success: run a harmless workspace-only command and complete normally.
- Failure: run `sleep 120` without retrying, then let the tester press Codex Stop after the process starts.
- Permission: create and read a file on the Desktop, which is outside the current workspace and should require approval.

Each prompt must state what Codex should not do so the lifecycle signal remains deterministic.

### Task 2: Document the Debug-app setup and reset

**Files:**
- Modify: `AGENT.md`

Record the retained Debug bundle path, the requirement to run only that build, hook installation/restart prerequisites, and the rule to run cases in separate conversations. Include the existing focused-test command as a preflight check.

### Task 3: Document expected UI and decision checks

**Files:**
- Modify: `AGENT.md`

For each case, specify the expected color/status, title and project line, animation/timing behavior, hover behavior, expanded-view behavior, and Allow/Deny result. State that synthetic URL events are not a substitute for manual lifecycle testing.

### Task 4: Validate the documentation

Run:

```bash
git diff --check
sed -n '1,260p' AGENT.md
```

Expected: no whitespace errors, and the document contains all three prompts, setup steps, expected results, cleanup, and troubleshooting guidance.
