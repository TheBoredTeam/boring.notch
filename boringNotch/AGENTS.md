# AGENTS.md

## Purpose

- This subtree owns the boringNotch area for `boringNotch`.
- Keep this file current when responsibilities, contracts, or child docs change.

## Ownership

- Applies to every file under `boringNotch` unless a deeper AGENTS.md overrides it.
- Parent instructions from the repository root remain binding.

## Local Contracts

- Key local files: boringNotchApp.swift, BoringViewCoordinator.swift, ContentView.swift, models/MinitapBrand.swift.
- `models/MinitapBrand.swift` owns the external minitap brand tokens, bundle identifiers, URL scheme, app URLs, and font registration contract.
- Preserve public interfaces, route names, data shapes, and documented workflows unless the task explicitly changes them.

## Work Guidance

- Read the nearest child AGENTS.md before editing nested areas listed below.
- Keep edits focused on the requested behavior and avoid speculative restructuring.
- Update this doc if the subtree gains a new durable boundary, workflow, or verification rule.

## Verification

- No subtree-specific automated verification is documented yet.

## Child DOX Index

- [components](components/AGENTS.md) - reusable UI components.
- [extensions](extensions/AGENTS.md) - the extensions area.
- [managers](managers/AGENTS.md) - the managers area.
- [MediaControllers](MediaControllers/AGENTS.md) - the MediaControllers area.
- [models](models/AGENTS.md) - the models area.
- [Services](Services/AGENTS.md) - service integrations and domain API clients.
- [utils](utils/AGENTS.md) - utility helpers.
