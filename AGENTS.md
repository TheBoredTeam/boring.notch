# DOX framework

- DOX is a highly performant AGENTS.md hierarchy installed here.
- Agent must follow DOX instructions across any edits.

## Core Contract

- AGENTS.md files are binding work contracts for their subtrees.
- Work products, source materials, instructions, records, assets, and durable docs must stay understandable from the nearest applicable AGENTS.md plus every parent AGENTS.md above it.

## Read Before Editing

1. Read the root AGENTS.md.
2. Identify every file or folder you expect to touch.
3. Walk from the repository root to each target path.
4. Read every AGENTS.md found along each route.
5. If a parent AGENTS.md lists a child AGENTS.md whose scope contains the path, read that child and continue from there.
6. Use the nearest AGENTS.md as the local contract and parent docs for repo-wide rules.
7. If docs conflict, the closer doc controls local work details, but no child doc may weaken DOX.

Do not rely on memory.
Re-read the applicable DOX chain in the current session before editing.

## Update After Editing

Every meaningful change requires a DOX pass before the task is done.

Update the closest owning AGENTS.md when a change affects:

- purpose, scope, ownership, or responsibilities
- durable structure, contracts, workflows, or operating rules
- required inputs, outputs, permissions, constraints, side effects, or artifacts
- user preferences about behavior, communication, process, organization, or quality
- AGENTS.md creation, deletion, move, rename, or index contents

Update parent docs when parent-level structure, ownership, workflow, or child index changes.
Update child docs when parent changes alter local rules.
Remove stale or contradictory text immediately.
Small edits that do not change behavior or contracts may leave docs unchanged, but the DOX pass still must happen.

## Hierarchy

- Root AGENTS.md is the DOX rail: project-wide instructions, global preferences, durable workflow rules, and the top-level Child DOX Index.
- Child AGENTS.md files own domain-specific instructions and their own Child DOX Index.
- Each parent explains what its direct children cover and what stays owned by the parent.
- The closer a doc is to the work, the more specific and practical it must be.

## Child Doc Shape

- Create a child AGENTS.md when a folder becomes a durable boundary with its own purpose, rules, responsibilities, workflow, materials, or quality standards.
- Work Guidance must reflect the current standards of the project or user instructions; if there are no specific standards or instructions yet, leave it empty.
- Verification must reflect an existing check; if no verification framework exists yet, leave it empty and update it when one exists.

Default section order:

- Purpose
- Ownership
- Local Contracts
- Work Guidance
- Verification
- Child DOX Index

## Style

- Keep docs concise, current, and operational.
- Document stable contracts, not diary entries.
- Put broad rules in parent docs and concrete details in child docs.
- Prefer direct bullets with explicit names.
- Do not duplicate rules across many files unless each scope needs a local version.
- Delete stale notes instead of explaining history.
- Trim obvious statements, repeated rules, misplaced detail, and warnings for risks that no longer exist.

## Closeout

1. Re-check changed paths against the DOX chain.
2. Update nearest owning docs and any affected parents or children.
3. Refresh every affected Child DOX Index.
4. Remove stale or contradictory text.
5. Run existing verification when relevant.
6. Report any docs intentionally left unchanged and why.

## User Preferences

- Preserve existing project instructions when installing or refreshing DOX.
- Never copy private memory, secrets, local-only credentials, or unredacted logs into AGENTS.md.

## Project Context

- Project: minitap.
- Repository root: `boring.notch`.
- The app's external brand and technical identity are minitap.
- This DOX index is generated from stable source, docs, and config paths only.
- Private files, local environment files, dependency folders, build outputs, caches, and binary asset dumps are intentionally excluded from the DOX tree.

## Root Work Guidance

- Before editing, read this file and every child AGENTS.md on the path to the target file.
- Prefer the smallest correct edit and update the nearest owning AGENTS.md when contracts or structure change.
- Do not add secrets, unredacted logs, credentials, or machine-local paths to tracked docs.
- Do not treat generated outputs, caches, dependency installs, or binary asset folders as source contracts unless this file explicitly says otherwise.
- Keep user-facing copy, bundle identifiers, URL schemes, app assets, and packaging defaults aligned with `boringNotch/models/MinitapBrand.swift`.

## Verification

- No subtree-specific automated verification is documented yet.

## Child DOX Index

- [.github](.github/AGENTS.md) - the .github area.
- [boringNotch](boringNotch/AGENTS.md) - the boringNotch area.
- [BoringNotchXPCHelper](BoringNotchXPCHelper/AGENTS.md) - the BoringNotchXPCHelper area.
- [Configuration](Configuration/AGENTS.md) - the Configuration area.
- [mediaremote-adapter](mediaremote-adapter/AGENTS.md) - the mediaremote-adapter area.
- [SpotifyAdDampenerCore](SpotifyAdDampenerCore/AGENTS.md) - the SpotifyAdDampenerCore area.
