# Clipboard Updates

- Introduced `ClipboardItem` model and `ClipboardManager` with SQLite-backed history, dedupe, pinning, search, and retention controls.
- Added adaptive grid-based `NotchClipboardView` with fixed-size cards, inline copy/pin/delete actions, per-item delete overlay, and copy confirmation checkmarks.
- Integrated pinning logic and sorted favorites to the top; UI mirrors settings toggles and honors history enable/disable states with overlays and empty states.
- Implemented clipboard settings panel exposing history enablement, retention, max items, capture options, and app exclusions.
