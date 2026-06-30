# AGENTS.md

## Purpose

- This subtree owns reusable UI components for `boringNotch/components`.
- Keep this file current when responsibilities, contracts, or child docs change.

## Ownership

- Applies to every file under `boringNotch/components` unless a deeper AGENTS.md overrides it.
- Parent instructions from the repository root remain binding.

## Local Contracts

- Key local files: AnimatedFace.swift, BottomRoundedRectangle.swift, EmptyState.swift, HoverButton.swift, LottieView.swift, ProgressIndicator.swift, TestView.swift, WhatsNewView.swift.
- Preserve public interfaces, route names, data shapes, and documented workflows unless the task explicitly changes them.

## Work Guidance

- Read the nearest child AGENTS.md before editing nested areas listed below.
- Keep edits focused on the requested behavior and avoid speculative restructuring.
- Update this doc if the subtree gains a new durable boundary, workflow, or verification rule.

## Verification

- No subtree-specific automated verification is documented yet.

## Child DOX Index

- [Clipboard](Clipboard/AGENTS.md) - clipboard history capture, storage, and menu-bar UI.
- [Shelf](Shelf/AGENTS.md) - the Shelf area.
