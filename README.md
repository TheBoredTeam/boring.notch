<h1 align="center">
  <br>
  <img src="./Gojo/Assets.xcassets/gojo-wordmark.imageset/gojo-wordmark.svg" alt="Gojo" width="420">
  <br>
  Gojo
  <br>
</h1>

**Gojo** turns the MacBook notch into an easy-access hub for multiple useful macOS tools.

It is designed as a **see-all interface** into the parts of macOS that matter most while you work: media controls, calendar context, file shelf actions, webcam mirror, and accessibility-driven HUD controls for brightness, backlight, and volume.

<p align="center">
  <img src="https://github.com/user-attachments/assets/2d5f69c1-6e7b-4bc2-a6f1-bb9e27cf88a8" alt="Gojo demo" />
</p>

## What Gojo is for

- Quick access to useful notch-powered tools
- Easier control of media and system HUD features
- Fast visibility into calendar and active context
- Lightweight file staging and sharing from the notch
- A more expressive accessibility/control surface for macOS

## Installation

**System Requirements**
- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac

### Download manually

Download the latest DMG from the [latest release](https://github.com/rohoswagger/gojo/releases/latest).

After moving **Gojo.app** to `/Applications`, remove quarantine if macOS blocks first launch:

```bash
xattr -dr com.apple.quarantine /Applications/Gojo.app
```

## Building from source

```bash
git clone https://github.com/rohoswagger/gojo.git
cd gojo
open Gojo.xcodeproj
```

Then build/run in Xcode or via:

```bash
make build
make run
make stop
```

## License and provenance

Gojo is currently a **GPLv3-licensed, fork-derived project** based on
[`boring.notch`](https://github.com/TheBoredTeam/boring.notch), with
additional Gojo-specific product, UI, and module work on top.

- Main project license: [GPLv3](./LICENSE)
- Third-party notices: [THIRD_PARTY_LICENSES](./THIRD_PARTY_LICENSES)
- Fork/provenance notice: [NOTICE.md](./NOTICE.md)

If you distribute modified binaries of Gojo, you are responsible for
complying with the GPL and preserving the required notices and source
availability obligations for your distributed version.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

## Security

See [SECURITY.md](./SECURITY.md).

## Acknowledgments

Gojo builds on a number of open-source projects and platform integrations. See [THIRD_PARTY_LICENSES](./THIRD_PARTY_LICENSES) for details.
