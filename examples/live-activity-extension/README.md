# Standalone Focus Timer extension

This macOS 14+ example builds independently from Boring Notch. It imports only
AppKit, Combine and SwiftUI and exports the C ABI in
[extension-api.h](../../docs/extension-api.h). Each display gets its own leading
and trailing `NSHostingController`; those controllers retain a shared observable
timer model safely through extension shutdown.

From this directory:

```sh
./build.sh
./smoke.sh
```

The build creates `dist/org.example.boringnotch.focus-timer.bnplugin` and `dist/FocusTimer-development.zip`
for your Mac's current architecture. The smoke test loads the actual signed
package through the host's runtime and checks registration metadata, separate
view ownership, state updates, actual host width changes, expiry renewal, withdrawal,
change callbacks and controller safety after destruction. It does not launch or
modify a running Boring Notch instance.

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
