# Building and distributing extensions

Independent developers can compile a native Boring Notch extension, distribute a ZIP, and let users install it from **Settings → Extensions** by dropping the ZIP or choosing a file. Extensions can be free or paid; purchase and licensing behavior belongs to the developer. The public host and example need no private source, account, or commercial configuration.

An extension can supply collapsed live activities, tabs in the expanded notch, or both. Its SwiftUI/AppKit layouts, controls, observable models, timers, and business logic stay inside its bundle. The host discovers contributions at runtime through the C ABI. Building Boring Notch never compiles, embeds, or statically links third-party extension source; the standalone example is built separately by its own script.

The in-app **Store** reads the reviewed [boring-notch-extensions](https://github.com/TheBoredTeam/boring-notch-extensions) registry. Each native extension has one source TOML; CI generates a complete JSON catalog, so approved listings and release updates appear on refresh without an app release. Paid and free releases use the same installation contract; price never gates bundle installation. See [the Store publication guide](extension-store.md) for approved release metadata and the boundary between host services and developer commerce.

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

Disable immediately withdraws the extension's activities and tabs and destroys its instance. Re-enable creates a fresh instance. Replacing a binary that has been loaded requires an app restart: Swift runtime metadata cannot safely be unloaded with `dlclose`. Uninstall moves the package to Trash and removes approval. A failed validation leaves the previous installed package in place.

Native extensions execute **inside the Boring Notch process** and share its sandbox, permissions, and crash fate. This is a trusted native plugin model, not a per-extension security sandbox. Publisher checks gate entry; they do not isolate a loaded extension. The host's library-validation exception allows independently signed publishers while keeping its other hardened-runtime and sandbox settings. Untrusted extension execution would require a separate-process transport and a different UI boundary.

## ABI and lifecycle

[extension-api.h](extension-api.h) is the binary contract. All calls and callbacks run on the main thread. No Swift generics or host application types cross it.

The five base exports are `create`, `destroy`, `update`, `event`, and `settings`, each suffixed `_v1`. `create` returns an owned instance; `destroy` cancels tasks, timers, observers, and windows. The optional settings controller is borrowed and retained by the host while displayed. Set `preferredContentSize.height` for the settings panel (bounded to 200–1,400 points).

Do not send commands during `create`; the host registers the instance after it returns. Commands become available with the first update. Store local state before callbacks. The host defers activity reconciliation until the current ABI call returns. Never retain a borrowed JSON pointer beyond the documented call boundary. Never send callbacks after destruction.

Lifecycle events are `lock`, `unlock`, `sleep`, `wake`, `session-inactive`, and `session-active`. Release hidden resources on sleep and inactive sessions. `update` receives copied UTF-8 media JSON containing title, artist, album, duration, elapsed, timestamp, rate, playing, idle, bounded JPEG artwork, favorite, and canFavorite. Ignore unknown fields. Use elapsed/rate/timestamp to extrapolate rather than requiring a host display timer.

Snapshots also include `activitySurfaces: ["desktop", "lockScreen"]` and `presentationAllowed`, the current manifest/session/media-request gate. If `activitySurfaces` is missing, assume desktop support only. Check that it contains `lockScreen` before publishing locked content, because older v1 hosts ignore unknown activity fields. Initial load sends a snapshot, then establishes awake/session state before the lock event. On unlock, the event arrives while your native region is still available, before the secure surface is removed and a denied snapshot is delivered. A provider can capture its own region geometry for an independent exit animation; no guessed notch coordinates are supplied.

| Command | Value | Behavior |
| --- | --- | --- |
| `activities.changed` | ignored | Reconcile the extension's current activity snapshot |
| `tabs.changed` | ignored | Reconcile the extension's current tab metadata and membership |
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

Optional `surface` is `desktop` (default) or `lockScreen`. A lock-screen activity renders only in the host's separate, noninteractive secure window. Desktop activities and the opened workspace never appear there, regardless of the “Show notch on lock screen” preference; that preference supplies an empty shape when no locked activity exists. Locked content disappears during sleep, inactive sessions, or withdrawal, and returns when eligible. Publishers decide which content is suitable for a locked Mac. Ordinary activities remain registered through lock transitions and retain their desktop selection.

The verified manifest ID supplies the namespace. A bundle cannot claim another provider's namespace through this publication API. Keep the local ID stable while updating progress. Remove it from the next snapshot to end it; return `{"activities":[]}` to withdraw everything. Notify with `activities.changed` whenever descriptors or membership change. Invalid snapshots withdraw that provider's activities and report an error without clearing other providers.

For each selected activity, `activity_view` receives region `0` (leading) or `1` (trailing) and an optional display UUID. Return a **new, +1 retained NSViewController for every call**; the host takes ownership. Return null for an empty region. Never reuse one controller across multiple displays. SwiftUI authors can return an `NSHostingController`; AppKit views work too. Set a finite `preferredContentSize` or intrinsic/fitting size and let the host bound it. Do not add camera spacers or outer notch padding.

Existing controllers observe your own model as payload changes. They must retain the state needed to render independently of the extension instance because SwiftUI may finish a removal transition after `destroy` returns. Avoid continuous polling for static content, honor Reduced Motion in your own animation, and stop resource work during lifecycle teardown.

The host handles camera clearance, width animation, display eligibility, selection, interruption, and resumption. See [live-activities.md](live-activities.md) for that contract. This API covers collapsed two-region activities on explicitly supported surfaces. Independent extension overlays remain owned and cleaned up by their publisher; the host does not provide a general lock-screen window API. Opting out of media snapshots with `presentation.active` does not withdraw live activities; membership follows the activity snapshot and extension lifecycle.

## Native tabs

Declare `"capabilities":["tabs"]` for tabs alone, or `["liveActivities","tabs"]` for both. Publish tab metadata and supply a view factory:

```c
const char *bn_extension_tabs_v1(void *instance);
void *bn_extension_tab_view_v2(void *instance, const char *tab_id,
                              const char *context_json);
// Optional regular-layout compatibility for hosts predating v2:
void *bn_extension_tab_view_v1(void *instance, const char *tab_id,
                              const char *display_id);
```

The snapshot uses the same main-thread, borrowed-pointer, and 65,536-byte rules as activity publication:

```json
{"tabs":[{"id":"focus","title":"Focus","symbol":"timer","presentations":["regular","compact"]}]}
```

Each provider may register up to eight tabs with unique local IDs using the activity ID grammar. Titles are nonblank, contain no control characters, and occupy at most 64 UTF-8 bytes. `symbol` is an SF Symbol name of at most 128 bytes; the host supplies a puzzle-piece fallback when the symbol is unavailable. The signed bundle ID namespaces each tab, so two developers can both use a local `focus` ID. Keep IDs stable while updating titles or icons.

An optional `iconPNG` field supplies a publisher icon as a base64 string of at most 16,384 UTF-8 bytes. It must encode one complete static PNG, from 1 × 1 through 128 × 128 pixels; APNG, other formats, trailing data, URLs, and data-URL prefixes are unsupported. Provide an alpha-mask glyph: the host renders it as a template, tinting it for selection and appearance in both the strip and overflow menu. Keep `symbol` as a fallback for older hosts. Missing or invalid custom artwork falls back to that symbol without removing the tab. The host caches decoded artwork across unchanged publications and title changes; updating an icon keeps mounted content identity. The complete tab snapshot still has a 65,536-byte limit, including base64 artwork.

`presentations` is an explicit, nonempty list containing `"regular"`, `"compact"`, or both, without duplicates. Omit it for the backward-compatible `["regular"]` behavior. A compact tab must declare `"compact"` **and** export `tab_view_v2`; the host never squeezes a regular-only extension into compact mode. Declaring compact without providing v2 leaves the tab hidden in compact mode while any valid regular presentation remains usable. A v2-only bundle works with current hosts; retain v1 when supporting older hosts, which ignore the new metadata and request regular content through v1.

Call `tabs.changed` after metadata or membership changes. The host reconciles after the ABI call returns and preserves mounted content identity when only metadata changes. Return `{"tabs":[]}` to withdraw tabs. Removing, disabling, uninstalling, or replacing the selected tab's provider returns selection to Home. Registering a tab never steals selection. Tabs appear beside Home and Shelf, with scrolling and an overflow menu for large collections. In compact mode, the same switcher floats below the opened notch and offers only tabs supporting compact presentation. Selecting compact mode while a regular-only tab is active returns to Home. The detached strip and its gap belong to the notch's hover region, so moving between content and tabs keeps it open. Extension tabs never appear on the lock screen.

The v2 factory receives borrowed JSON describing **this mount**, including the actual available content size in macOS points:

```json
{"presentation":"compact","displayID":null,"contentSize":{"width":336,"height":132}}
```

`presentation` is `"regular"` or `"compact"`. `displayID` is a display UUID string or null. Decode the context during the call, validate finite dimensions, and ignore unknown keys. The dimensions above illustrate the current compact viewport; they are not an ABI promise. Render inside the supplied bounds for the requested mode. If v2 exists, the host prefers it for both modes; a null v2 result displays unavailable content and never calls v1 as a fallback. A bundle exporting only v1 supports regular mode only.

For every `tab_view` call, return a **fresh, +1 retained NSViewController** or null for unavailable content. The host takes ownership and mounts only selected tab content, separately per display. It provides finite content bounds clear of the physical notch and clips to them; preferred size cannot resize the whole notch. Inside that area the extension owns its entire layout: buttons, text input, charts, progress, lists, and other native controls. Use an `NSHostingController` for SwiftUI or an AppKit controller. No host-defined widget schema is required.

Each declared presentation needs an intentional layout. A regular view can place detail and controls side by side; a compact view can prioritize a summary and arrange its controls below. Share model state and reusable controls between them. Do not add camera spacers or host chrome, depend on oversized preferred/intrinsic sizes, or scale a desktop layout down to fit. Use scrolling within the supplied viewport when content needs it. The tab API does not offer window creation, host resizing, or control over other tabs. These are hosting rules, not a sandbox: signed native code still runs inside the host process.

Update your observable model or AppKit views directly on the main thread to change live content. Do not republish tab descriptors for every progress tick or recreate controllers for content changes. Use native appear/disappear lifecycle to suspend hidden UI work. Switching tabs, changing presentation or content bounds, or closing the notch remounts/unmounts the controller; keep durable navigation and feature state in your plugin model so a new controller can restore it. Controllers must retain the state they need through removal transitions; destroy must silence commands, cancel work, and leave surviving views inert.

While a native tab is shown, its controls receive scrolling and drag/drop instead of the host's whole-notch pan/drop handlers. The panel becomes eligible for keyboard input when a control such as a text field requests focus; mounting a tab does not take focus from another app. Visible child windows, including native SwiftUI/AppKit popovers, and active text editing in the mounted tab keep the notch open when the pointer leaves. Native navigation controls also retain the notch while they are the key panel's first responder and declare both `acceptsFirstResponder` and `needsPanelToBecomeKey`; moving from search to results preserves the keyboard interaction. Unmounting releases input eligibility and any owned field editor, and dismisses the tab's owned presentations.

The notch is a nonactivating panel. For an explicit user action that opens a keyboard composer, activate `NSApplication.shared` before presenting a transient popover, wait for activation if necessary, then make the editor's attached window key and request focus in the control. Wait until that specific window is visible and cancel a pending focus request if the view detaches. Activating after presentation can cause AppKit to dismiss the existing popover; a SwiftUI focus binding alone does not activate the application or make its window key. Keep mounting, live model updates, and passive content presentation free of activation calls.

The separately compiled [Focus Timer example](../examples/live-activity-extension) supplies a live activity and separate regular/compact native tab layouts backed by one extension-owned model. Its smoke tests load the signed bundle, verify context delivery and shared live updates in both layouts, and install/disable/update/uninstall it through the real host manager. The example also opts out of media snapshots without withdrawing either contribution.
