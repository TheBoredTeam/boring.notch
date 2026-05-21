# Changelog

All notable changes to Gojo will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] — 2026-05-21

First public release of Gojo as a standalone product, distinct from the upstream `boring.notch` fork it grew out of.

### Added

- **Windows tab.** Stage strip of on-screen apps with real app icons + per-window position glyphs; live monitor preview with animated window rect; identity row + 3×2 grid of snap chips (left, right, top, bottom halves, fill, zoom). All cross-app — click any window, snap it. Six keyboard shortcuts (⌃⌥← / → / ↑ / ↓ / ↩ for halves+fill, ⌃⌥Z for zoom) shown under each chip and rebindable in Settings.
- **XPC helper** (`GojoXPCHelper`) isolates Accessibility-trusted work in its own process so the main app doesn't need direct AX permission. New helper RPCs: `setWindowFrame(pid:windowID:)`, `raiseWindow`, `enumerateWindows`, `performZoom`.
- **Stage strip** filters to regular activation-policy apps with usable window sizes; preserves stable ordering across enumerations (clicking a window raises it without reordering the strip).
- **Zoom action** triggers the window's native zoom button (same effect as double-clicking the title bar) — toggles between custom size and the app's standard frame.

### Changed

- Branding, copy, and product framing rewritten for Gojo as a standalone tool, with new fork-provenance documentation.
- Local build/run workflow consolidated under a `Makefile` (`make build`, `make run`, `make stop`, `make test-window`, etc.).

### Project & process

- README rewritten for v1.0.
- GitHub Actions build workflow (`build.yml`) — Debug + Release-unsigned builds on every push and PR, with SPM dependency caching.
- Issue templates (bug, feature) and PR template.
- This `CHANGELOG.md`.

## Earlier history

Gojo was forked from [`boring.notch`](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam. See [`NOTICE.md`](./NOTICE.md) for the provenance trail and [`THIRD_PARTY_LICENSES`](./THIRD_PARTY_LICENSES) for upstream and dependency attribution.

[Unreleased]: https://github.com/rohoswagger/gojo/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/rohoswagger/gojo/releases/tag/v1.0.0
