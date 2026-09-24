# MediaRemoteAdapter (vendored)

This directory contains a **vendored copy** of
[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter),
vendored under the terms of its BSD 3-Clause license
(see [../THIRD_PARTY_LICENSES](../THIRD_PARTY_LICENSES)).

## Why it's here

`MediaRemote.framework` is a private Apple framework. The sandboxed app
cannot link it directly, so `NowPlayingController` spawns
`mediaremote-adapter.pl` as a child process; the script dynamically loads
`MediaRemoteAdapter.framework`, which exposes now-playing data and commands
as a stream of JSON lines on stdout.

| File | Used as |
|---|---|
| `mediaremote-adapter.pl` | Copied into the app bundle's Resources; spawned by `NowPlayingController` (`stream` command) |
| `MediaRemoteAdapter.framework` | Embedded in `Contents/Frameworks`; loaded by the script at runtime |
| `MediaRemoteAdapterTestClient` | Bundled diagnostic executable (`test` command) that verifies the adapter is functional/entitled on the host macOS |

## Pinned version

- **Upstream tag: `v0.7.2`**
  (commit [`dc3ff17`](https://github.com/ungive/mediaremote-adapter/commit/dc3ff1740e2035a2490ec67d3b33322449af780a))
- Vendored-in commit: `61487af` ("Update MediaRemoteAdapter", 2025-08-14)
- `mediaremote-adapter.pl` is byte-identical to the upstream `bin/mediaremote-adapter.pl` at that tag.
- The framework binary reports `CFBundleShortVersionString = 0.1`
  (upstream does not sync this with release tags; the script match is the
  authoritative pin).
- The binaries are ad-hoc signed; see "Signing caveat" below.

## Updating to a new upstream release

1. Check the upstream
   [releases page](https://github.com/ungive/mediaremote-adapter/releases)
   and pick a tag.
2. Build the framework and test client from source at that tag
   (see the upstream `README.md` / `Makefile`), **or** download the
   release artifacts published on the tag and verify their checksums
   against the values published upstream.
3. Replace `MediaRemoteAdapter.framework`, `MediaRemoteAdapterTestClient`
   and `mediaremote-adapter.pl` (upstream path: `bin/mediaremote-adapter.pl`)
   in this directory.
4. Re-sign the binaries ad-hoc if you built from source
   (`codesign -s - --force --deep MediaRemoteAdapter.framework`), matching
   what the Xcode build phase expects.
5. Verify: run the app, confirm now-playing updates stream in, and run
   `MediaRemoteAdapterTestClient` (or `mediaremote-adapter.pl … test`)
   on the oldest supported macOS version.
6. **Update the pin in this README** (tag + commit hash) in the same commit.

## Signing caveat

The checked-in binaries were built on a maintainer's machine and are ad-hoc
signed (`codesign -dv` shows `Signature=adhoc`). They are **not**
independently verifiable bit-for-bit against the upstream source. Until the
build is wired to fetch pinned upstream release artifacts (with SHA-256
verification) instead of committing binaries, treat this directory as
trusted-but-unverifiable and prefer rebuilding from source when updating.
