# Building extensions

Boring Notch is a neutral host for independently developed `.bnplugin` extensions. Extensions may be free or paid. The host has no purchase catalog, activation codes, receipt verification, license server, or payment-provider configuration. A developer who charges for an extension implements that behavior inside their own package or service.

The public app builds without private source or commercial configuration. `extensions/lockscreen-lyrics` remains an optional maintainer-only submodule; normal clones and public CI do not initialize it.

## Start with the free example

[Now Playing Example](../examples/now-playing-extension/NowPlaying.swift) is a small SwiftUI extension with media updates, a playback button, and its own settings controller. It needs no account, license, or keys.

```sh
bash examples/now-playing-extension/build.sh
bash examples/now-playing-extension/smoke-host.sh
```

The smoke test compiles the public package loader and runtime, loads the example, sends a media snapshot with no licensing fields, checks its host callback, and verifies teardown. It never locks the Mac.

For interactive development, launch a Debug Boring Notch build with:

```sh
open -n '/path/to/Boring Notch.app' \
  --env BN_ALLOW_DEVELOPMENT_EXTENSIONS=1 \
  --env "BN_EXTENSION_TEST_DIRECTORY=$PWD/examples/now-playing-extension/dist"
```

Then open Settings → Extensions. Debug opt-in permits local ad-hoc signatures. These overrides are absent from Release builds. The example builds for the current Mac architecture; distribute both arm64 and x86_64 slices if you support both.

## Package format

```text
com.example.boringnotch.now-playing.bnplugin/
  Contents/
    Info.plist
    MacOS/NowPlaying
    Resources/manifest.json
```

`CFBundleIdentifier` must match the manifest ID. `CFBundleExecutable` names the binary under `Contents/MacOS`. The binary exports the five functions in [extension-api.h](extension-api.h). Installed packages are named `<manifest.id>.bnplugin`.

```json
{"id":"com.example.boringnotch.now-playing","name":"Now Playing Example","version":"1.0.0","apiVersion":1,"activation":"always"}
```

`activation` is `always` (also the default when omitted) or `lockScreen`. A lock-screen extension receives routine media updates only while locked, awake, and in the active session. Both types receive initial/forced snapshots and lifecycle events. The manifest contains no price or license requirement.

## Installation and publisher trust

Users choose **Install extension…** in Settings → Extensions. Boring Notch validates the manifest, bundle paths, all architecture signatures, and notarization before installation. Production packages need a valid **Developer ID Application** signature from their own publisher; the publisher does not need Boring Notch's Team ID or permission from its maintainers.

Before enabling an extension, the user reviews its verified publisher. Approval is stored for that extension ID and Team ID. A different publisher requires another review. Copying a package into Application Support does not approve it automatically. Each load checks the signature again before `dlopen`; updating a loaded binary requires an app restart. Uninstall moves the package to Trash, removes approval, and stops the instance.

Extensions execute in the app process and share the host's sandbox, permissions, and access. They are not isolated from the host. The app's `disable-library-validation` entitlement permits third-party Team IDs; explicit package signature/notarization checks and publisher approval gate the loader. The rest of the host's hardened runtime and sandbox remain enabled. Notarization does not certify an extension's behavior.

To distribute your extension, build the desired architectures, sign the bundle with your Developer ID Application certificate, distribute it in a signed/notarized/stapled DMG, and test installation on a clean Mac. Do not ship the example's ad-hoc development signature.

## ABI v1 and lifecycle

Calls and command callbacks run on the main thread. No Swift application types cross the C ABI. `create` owns the returned instance pointer; `destroy` closes windows, cancels work, and breaks view/controller retain cycles. The settings-controller pointer is borrowed and retained by the host while displayed. Set its `preferredContentSize.height` for the desired settings space (the host bounds this to 200–1400 points). Swift library metadata stays loaded until the app exits.

Do not send host commands from `create`; the instance is registered after it returns. Commands are available from the first `update`. Callbacks may synchronously cause another snapshot, so update your local policy state before invoking them.

`update` receives copied UTF-8 JSON:

```json
{"title":"Song","artist":"Artist","album":"Album","duration":180,"elapsed":12.5,"timestamp":1790000000,"rate":1,"playing":true,"idle":false,"artwork":"base64 JPEG","favorite":false,"canFavorite":false}
```

Extrapolate playback using `timestamp` and `rate`, freezing when paused. Artwork is a bounded JPEG and can be empty. Ignore unknown fields. There is no `licensed` field or host-issued entitlement.

Lifecycle events are `lock`, `unlock`, `sleep`, `wake`, `session-inactive`, and `session-active`. Release hidden resources on unlock/sleep/session changes as appropriate. Initial lifecycle events arrive after the initial snapshot.

Commands available to every loaded, approved extension:

| Command | Value | Behavior |
| --- | --- | --- |
| `media.toggle` | ignored | Toggle playback |
| `media.next` / `media.previous` | ignored | Change track |
| `media.favorite` | ignored | Toggle favorite when supported |
| `media.seek` | seconds | Seek within the track bounds |
| `presentation.active` | 0 or 1 | Suspend/resume routine media snapshots; lifecycle events continue |
| `presentation.artwork` | 0 or 1 | Opt out/in to artwork serialization |
| `presentation.lockedNotch` | 0 or 1 | Request the host's static lock badge and subsequent unlock transition |

While the screen is locked, snapshots may include `notchTarget` with global AppKit center coordinates `x`, `y` and a point `size`, for coordinating a brief presentation transition. Ignore it if unused. The lock badge responds to the current session's lock/unlock events, not initial login before the app is running.

Use bounded caches and event-driven updates. Avoid a display-link or continuous animation timer for static content. Any extension that displays over the lock screen must be physically tested with password/Touch ID, sleep/wake, user switching, display changes, and accessibility preferences on supported macOS versions. Desktop previews and successful builds do not establish lock-screen compatibility.
