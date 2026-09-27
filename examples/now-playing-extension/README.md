# Now Playing Example

A complete free Boring Notch extension with no licensing dependency. Copy this directory, choose your own reverse-DNS identifier, change the manifest/plist values in `build.sh`, and implement your views and lifecycle behavior in `NowPlaying.swift`.

```sh
bash build.sh
bash smoke-host.sh
```

The example is ad-hoc signed for Debug development and builds for the current architecture. See [the public extension guide](../../docs/extensions.md) for installation, the C ABI, publisher trust, and release signing requirements. Paid developers may add their own checkout and entitlement logic inside their extension; the host makes no pricing decisions.
