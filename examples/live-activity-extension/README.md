# Standalone Focus Timer extension

This macOS 14+ example builds independently from Boring Notch. It imports only
AppKit, Combine and SwiftUI and exports the C ABI in
[extension-api.h](../../docs/extension-api.h). Each display gets its own leading
and trailing `NSHostingController`, plus its own native tab controller. Those
controllers retain a shared observable timer model safely through extension shutdown.

From this directory:

```sh
./build.sh
./smoke.sh
./smoke-install.sh
```

The build creates `dist/org.example.boringnotch.focus-timer.bnplugin` and `dist/FocusTimer-development.zip`
for your Mac's current architecture. The smoke test loads the actual signed
package through the host's runtime and checks registration metadata, separate
view ownership, v2 layout-context delivery, separate regular/compact renders,
shared state updates, actual host width changes, expiry renewal, withdrawal,
change callbacks and controller safety after destruction. It also exercises the
v1 factory used by older hosts and rejects invalid v2 contexts. It does not launch or
modify a running Boring Notch instance.

The bundle also registers a **Focus** tab beside Home and Shelf. Its complete
SwiftUI layouts, live progress bar, and start/pause/end controls live in this
example, with no extension code compiled into Boring Notch. Tab content updates
the same timer model as the collapsed activity; metadata publications are only
needed when a title, icon, or registered tab changes. The smoke tests verify
live rendering, metadata updates, removal, and fresh per-display controllers.

The tab explicitly declares `presentations: ["regular", "compact"]` and exports
`bn_extension_tab_view_v2`. The host supplies the presentation, display ID, and
finite content bounds through JSON. Regular mode places the timer beside its
controls; compact mode places the timer beside its heading and the controls
below the progress bar. Both use the same `FocusState` and `FocusControls`.
The example retains `tab_view_v1` for older hosts, which receive regular content.
Extensions omitting `presentations` remain regular-only; the host hides them in
compact mode and returns to Home if necessary.

Keep every layout inside the provided viewport. Preferred size cannot enlarge
the notch, and compact support must be authored explicitly rather than scaling
the regular view. Decode context during the factory call, ignore unknown keys,
and reject unsupported presentations or invalid dimensions. The host can remount
on mode or size changes, so durable state belongs in the model rather than in a
particular controller. Smoke screenshots are written under the system temporary
directory in `boring-native-tabs-validation/`.

The example starts a 25-minute activity when enabled. Its settings support start,
pause, resume and end. Pausing changes the leading view's ideal width; the host
handles the notch safe area and width animation. Existing IDs retain focus during
updates; a new timer session publishes a new ID.

The ZIP uses a local ad-hoc signature. To test installation, run a Debug host with
`BN_ALLOW_DEVELOPMENT_EXTENSIONS=1` and choose the ZIP in Extensions settings.
Release hosts require the independent publisher's notarized Developer ID
signature. This sample does not create a production signature or notarization
ticket. See [extensions.md](../../docs/extensions.md) for distribution and the
host lifecycle contract.
