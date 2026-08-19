# Permission Window Lifetime and Collapse Fix

**Goal:** Keep the mirrored permission prompt actionable for as long as Codex's native permission prompt exists, preserve that prompt throughout notch collapse, and keep the expanded surface inside the existing rounded notch shape.

**Architecture:** Remove the temporary loopback callback server and its expiry metadata. The asynchronous Codex hook only mirrors a permission event and marks it for the existing Accessibility decision path; the app submits Allow or Deny by pressing the matching control in the currently visible native Codex prompt. Keep permission content mounted until the normal notch close animation completes, then clear expansion state. Let the existing outer notch shape own clipping instead of forcing an overflowing inner width.

**Decision latency:** Start the notch's normal collapse as soon as the user presses Allow or Deny, while retaining the permission notification until the helper reports a verified Accessibility or physical-click result. A failed result therefore leaves the compact request actionable and opens Codex instead of treating the initial Accessibility action acknowledgement as success.

## Tasks

1. Replace `CodexPermissionCallback` with the non-expiring `CodexPermissionControl` marker throughout parsing, notification state, UI eligibility, and native-prompt observation.
2. Delete the obsolete localhost permission relay and simplify the generated `PermissionRequest` hook to open the notch and exit immediately.
3. Close the notch before clearing expanded permission state so the home destination cannot render during collapse.
4. Remove fixed permission widths and rectangular clipping that overrun the rounded outer notch mask.
5. Strip Codex's attachment/document preamble from mirrored prompts and derive the title from the user's `## My request:` body.
6. Update core tests, run the focused Swift suite, build Debug, reinstall the current hook, and launch only the newest Debug app.
7. Use Computer Use for real Allow and Deny requests and verify that each decision reaches Codex.

## Invariants

- Normal home/shelf hover opening and closing keeps its existing code path and animation.
- Codex always retains its native permission prompt; notch actions only mirror a deliberate Allow or Deny click into that visible prompt.
- If no matching native prompt is visible, fail closed and bring Codex forward; never report a request as expired.
- Permission prompts remain persistent until a decision or native dismissal is observed.
