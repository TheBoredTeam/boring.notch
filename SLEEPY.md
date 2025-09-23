# Clipboard Updates

- Introduced `ClipboardItem` model and `ClipboardManager` with SQLite-backed history, dedupe, pinning, search, and retention controls.
- Added adaptive grid-based `NotchClipboardView` with fixed-size cards, inline copy/pin/delete actions, per-item delete overlay, and copy confirmation checkmarks.
- Integrated pinning logic and sorted favorites to the top; UI mirrors settings toggles and honors history enable/disable states with overlays and empty states.
- Implemented clipboard settings panel exposing history enablement, retention, max items, capture options, and app exclusions.

# Notes Updates

- Added `Note` model enhancements and a `NotesManager` that handles JSON-backed persistence, filtering, sorting, and live selection state with auto-save debouncing.
- Rebuilt `NotchNotesView` so the primary pane is a full-height `TextEditor` with focus management tied to the manager; selection and note creation now auto-focus for immediate typing.
- Simplified sidebar cards with inline pin/delete buttons, compact search bar, and layout tweaks to maximize editor space while keeping notes readable.
- Linked Notes settings to Defaults, providing toggles for enablement/monospace defaults and slider-based auto-save timing, all reusing the standard Settings form styling.
- Wired the notch tab bar and content router to hide the Notes tab (and view) automatically when the feature is disabled, keeping the UI consistent with user preferences.

## Storage Choices

- Clipboard history uses SQLite because copy events arrive rapidly and need indexed querying for search, dedupe, retention caps, and metadata (source app, favorites). The database keeps writes transactional and storage compact even with thousands of rows.
- Notes remain JSON-per-file since note counts stay modest, edits are heavier but less frequent, and human-readable blobs simplify backups, syncing, or external tooling. Per-note files also mesh well with Spotlight and git-style diffing.
