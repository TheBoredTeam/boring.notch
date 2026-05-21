# Gojo screenshots

This directory holds the static screenshots referenced from the project README.

## Conventions

- **Format:** PNG, transparent background where possible, no drop shadow (the README adds its own framing).
- **Width:** 1280–1600px (renders well at retina; downscales cleanly).
- **Background:** dark grey-ish or solid black wallpaper so the notch reads cleanly.
- **State:** open notch, hovered, no menu bar clutter. Real apps (Cursor, Safari, Spotify, Terminal) preferred over Lorem-Ipsum placeholders.
- **Naming:** `<feature>.png` — referenced verbatim from `README.md`.

## Expected files

| File | Shows |
|------|-------|
| `windows-tab.png` | Windows tab open: stage strip with 4+ apps, preview monitor showing a snapped position, identity row + 6 chip grid with shortcuts visible. |
| `music.png` | Music tab with now-playing track, artwork in the album-art slot, scrubber visible. |
| `clipboard.png` | Clipboard tab with 3+ entries, one hovered to show paste affordance. |
| `shelf.png` | Shelf tab with a few files staged via drag-and-drop. |
| `hud-brightness.png` | Inline HUD for brightness or volume sneak peek. |
| `webcam.png` | Webcam mirror in the notch (small portrait of whoever's testing). |

## Taking screenshots

Run the app via `make run`, set up each state, and capture with `⌘⇧4` (rectangle selection) — include the notch and ~10–20px of the wallpaper around it. Then drop the PNGs into this directory at the names above.

If you change the README's screenshot URLs, also update this list.
