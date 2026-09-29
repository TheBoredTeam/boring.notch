# Building and distributing extensions

Independent developers can compile a native Boring Notch extension, distribute a ZIP, and let users install it from **Settings → Extensions** by dropping the ZIP or choosing a file. Extensions can be free or paid; purchase and licensing behavior belongs to the developer. The public host and example need no private source, account, or commercial configuration.

The in-app **Store** uses the same reviewed catalog as the website. Paid and free releases use the same installation contract; price never gates bundle installation. See [the Store publication guide](extension-store.md) for approved release metadata and the boundary between host services and developer commerce.

## Build the example

```sh
bash examples/live-activity-extension/build.sh
bash examples/live-activity-extension/smoke.sh
bash examples/live-activity-extension/smoke-install.sh
```

The example imports AppKit/SwiftUI, not the Boring Notch Swift module. It builds a `.bnplugin` plus a ZIP and exercises the actual package/runtime API in an isolated smoke host. Its local ad-hoc signature is only for explicit Debug development mode:

```sh
open -n '/path/to/Boring Notch.app' \
  --env BN_ALLOW_DEVELOPMENT_EXTENSIONS=1 \
  --env "BN_EXTENSION_TEST_DIRECTORY=$PWD/examples/live-activity-extension/dist"
```

These environment overrides are compiled out of Release. Development packages still need an intact code signature. The sample builds for the current architecture; produce arm64 and x86_64 slices if you distribute to both.

## Package

```text
com.example.focus.bnplugin/
  Contents/
    Info.plist
    MacOS/Focus
    Resources/manifest.json
```

`CFBundleIdentifier` must equal the manifest ID. `CFBundleExecutable` names the binary under `Contents/MacOS`. Package one bundle at the ZIP root. Finder's `__MACOSX` metadata is tolerated; extra product bundles, path traversal, links, special files, encrypted entries, and duplicate/ambiguous paths are rejected. Installation limits are 100 MB compressed and expanded, 4,096 entries, and 64 KB for each manifest/Info.plist.

```json
{
  "id": "com.example.focus",
  "name": "Focus Timer",
  "version": "1.0.0",
  "apiVersion": 1,
  "activation": "always",
  "capabilities": ["liveActivities"]
}
```

`activation` is `always` (default) or `lockScreen`. It controls routine media snapshot delivery; initial snapshots and lifecycle events are still sent. `capabilities` is optional for existing v1 extensions. `liveActivities` requires the two activity exports below. Unknown capabilities are ignored for forward compatibility; incompatible `apiVersion` values fail validation.

## Publisher verification and updates

Production bundles require a valid **Developer ID Application** signature and notarization from their own publisher. They do not need the Boring Notch Team ID or a maintainer-issued key. Sign the finished bundle, submit the distribution to Apple's notarization service, and test the ZIP on a clean Mac before distribution. This repository's unsigned app builds and ad-hoc smoke test do not validate production notarization.

The host extracts into private staging with bounded streaming reads, checks bundle structure and all architecture signatures, and asks the user to review the verified publisher. Approval is stored per extension ID and Team ID. It validates the staged copy before replacement and rechecks signature and approval before loading code. A publisher change requires another review. Copying a bundle directly into Application Support does not approve it.

Disable immediately withdraws the extension's activities and destroys its instance. Re-enable creates a fresh instance. Replacing a binary that has been loaded requires an app restart: Swift runtime metadata cannot safely be unloaded with `dlclose`. Uninstall moves the package to Trash and removes approval. A failed validation leaves the previous installed package in place.

Native extensions execute **inside the Boring Notch process** and share its sandbox, permissions, and crash fate. This is a trusted native plugin model, not a per-extension security sandbox. Publisher checks gate entry; they do not isolate a loaded extension. The host's library-validation exception allows independently signed publishers while keeping its other hardened-runtime and sandbox settings. Untrusted extension execution would require a separate-process transport and a different UI boundary.

## ABI and lifecycle

[extension-api.h](extension-api.h) is the binary contract. All calls and callbacks run on the main thread. No Swift generics or host application types cross it.

The five base exports are `create`, `destroy`, `update`, `event`, and `settings`, each suffixed `_v1`. `create` returns an owned instance; `destroy` cancels tasks, timers, observers, and windows. The optional settings controller is borrowed and retained by the host while displayed. Set `preferredContentSize.height` for the settings panel (bounded to 200–1,400 points).

Do not send commands during `create`; the host registers the instance after it returns. Commands become available with the first update. Store local state before callbacks. The host defers activity reconciliation until the current ABI call returns. Never retain a borrowed JSON pointer beyond the documented call boundary. Never send callbacks after destruction.

Lifecycle events are `lock`, `unlock`, `sleep`, `wake`, `session-inactive`, and `session-active`. Release hidden resources on sleep and inactive sessions. `update` receives copied UTF-8 media JSON containing title, artist, album, duration, elapsed, timestamp, rate, playing, idle, bounded JPEG artwork, favorite, and canFavorite. Ignore unknown fields. Use elapsed/rate/timestamp to extrapolate rather than requiring a host display timer.

| Command | Value | Behavior |
| --- | --- | --- |
| `activities.changed` | ignored | Reconcile the extension's current activity snapshot |
| `media.toggle` | ignored | Toggle playback |
| `media.next` / `media.previous` | ignored | Change track |
| `media.favorite` | ignored | Toggle favorite when supported |
| `media.seek` | seconds | Seek within track bounds |
| `presentation.active` | 0 or 1 | Suspend/resume routine media snapshots |
| `presentation.artwork` | 0 or 1 | Opt out/in to artwork serialization |

## Live activity publication

With `liveActivities` declared, export:

```c
const char *bn_extension_activities_v1(void *instance);
void *bn_extension_activity_view_v1(
    void *instance, const char *activity_id, int32_t region,
    const char *display_id);
```

The first returns a borrowed, null-terminated UTF-8 snapshot, valid until the next extension ABI call. The host copies at most 65,536 bytes:

```json
{"activities":[{
  "id":"timer-42",
  "label":"Focus timer",
  "relevance":"active",
  "expiresAt":1800000000,
  "displays":["optional-display-uuid"]
}]}
```

Omit `expiresAt` for a persistent activity and `displays` for all eligible displays. `relevance` is `passive`, `active` (default), or `timeSensitive`; the host maps these below system notifications and reserves system interrupts for the app. Each snapshot contains at most 16 unique local IDs; IDs are 1–100 ASCII letters/digits/dots/underscores/hyphens, starting with a letter or digit. Labels are required and bounded to 256 UTF-8 bytes.

The verified manifest ID supplies the namespace. A bundle cannot claim another provider's namespace through this publication API. Keep the local ID stable while updating progress. Remove it from the next snapshot to end it; return `{"activities":[]}` to withdraw everything. Notify with `activities.changed` whenever descriptors or membership change. Invalid snapshots withdraw that provider's activities and report an error without clearing other providers.

For each selected activity, `activity_view` receives region `0` (leading) or `1` (trailing) and an optional display UUID. Return a **new, +1 retained NSViewController for every call**; the host takes ownership. Return null for an empty region. Never reuse one controller across multiple displays. SwiftUI authors can return an `NSHostingController`; AppKit views work too. Set a finite `preferredContentSize` or intrinsic/fitting size and let the host bound it. Do not add camera spacers or outer notch padding.

Existing controllers observe your own model as payload changes. They must retain the state needed to render independently of the extension instance because SwiftUI may finish a removal transition after `destroy` returns. Avoid continuous polling for static content, honor Reduced Motion in your own animation, and stop resource work during lifecycle teardown.

The host handles camera clearance, width animation, display eligibility, selection, interruption, and resumption. See [live-activities.md](live-activities.md) for that contract. This API covers the collapsed two-region notch, not the expanded workspace or arbitrary lock-screen windows.
