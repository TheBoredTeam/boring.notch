# Paid extensions

Boring Notch loads separately installed, publisher-signed `.bnplugin` bundles. The free app builds without downloading private extension source. `extensions/lockscreen-lyrics` is an optional private Git submodule, not an Xcode dependency or bundled app resource.

Maintainers with access can run `git submodule update --init extensions/lockscreen-lyrics`. Public contributors should use a normal clone, without recursive submodule checkout. Public CI deliberately does not initialize private submodules.

## Install and ownership

Open Settings → Extensions, choose **Install extension…**, and select the downloaded `.bnplugin` bundle. Installation validates its manifest, API version, paths, and Apple code signature before copying it into Application Support. Release builds require the same Apple Team ID as the host app and retain hardened runtime library validation. Restart is required after updating an already loaded binary. Uninstall moves the bundle to Trash and immediately stops its instance.

The [$1 Buy Me a Coffee shop item](https://buymeacoffee.com/jfxh67wvfxq/e/580376) permanently unlocks Lock Screen Lyrics only. This is a one-time payment, with no subscription or renewal. Future extensions require their own product-specific purchase. Downloading or installing a plugin is not proof of payment.

The customer receives a random, 14-character alphanumeric activation code. This code is a bearer credential for retrieving a signed receipt, not a truncated cryptographic signature. The app exchanges it and a random Keychain-persisted Mac identifier over HTTPS. The returned receipt is verified with Ed25519, checked for the expected product/Mac/issuer, and stored in Keychain. Valid permanent receipts work offline without periodic online checks. No hardware serial number is sent.

The app starts purchases at the configured license service's `/buy` page. Buyers verify their email once before checkout, then return from Buy Me a Coffee to `/license`. The page displays the code after a verified payment for that email/product. Direct shop buyers receive an emailed private link; codes are also emailed as a backup. The shop's fixed redirect is not proof of ownership. The private service README covers redirect, webhook, SMTP, and public-origin setup.

## Build configuration

The reusable app build injects these through `.github/scripts/stamp_extension_licensing.py`, before Apple code signing:

- GitHub Actions secret `EXTENSION_LICENSE_PUBLIC_KEYS`: JSON mapping a signing key ID to its base64-encoded 32-byte Ed25519 **public** key.
- Repository variable `EXTENSION_LICENSE_SERVER_URL`: HTTPS base URL of the private license service.
The checkout URL is generated from the license service origin as `/buy?product=theboringteam.boringnotch.lockscreen-lyrics`. The private service catalog controls the Buy Me a Coffee destination. No separate checkout variable is needed.

The public keys and server URL must be set together. With none set, the free app builds normally and purchasing/activation show as unavailable. No placeholder checkout is opened. The public key is intentionally public; putting it in a GitHub secret does not make it a client secret. The private signing key belongs only on the issuer server, never in the app, plugin, app CI, or this repository. Keep previous public key IDs when rotating signing keys so existing permanent receipts remain valid.

The receipt signing key is separate from the Developer ID certificate used to sign the Mac binaries. Apple code signing authenticates the distributed app/plugin to macOS; it is not remote attestation to the license service. A modified client can bypass local checks. Keeping signing keys private prevents forging receipts for authentic clients.

## Extension ABI v1

Every entry point and command callback is invoked on the main thread. Symbol names and C signatures are declared in [extension-api.h](extension-api.h). No Swift app types cross the ABI. The instance pointer owns the plugin; the settings-controller pointer is borrowed, retained by the host while displayed. `destroy` must close windows, cancel work, and break all view/controller retain cycles. Swift library code stays loaded until the app exits.

`update` receives UTF-8 JSON, copied by the plugin before returning:

```json
{"title":"Song","artist":"Artist","album":"Album","duration":180,"elapsed":12.5,"timestamp":1790000000,"rate":1,"playing":true,"idle":false,"artwork":"base64 JPEG","favorite":false,"canFavorite":true,"licensed":true}
```

The host computes `licensed` per extension ID from a verified receipt. Media updates are coalesced; extensions extrapolate position from `timestamp` and `rate`, freezing it when paused. Artwork is resized and encoded only when changed. Lifecycle events are `lock`, `unlock`, `sleep`, `wake`, `session-inactive`, and `session-active`. Commands are `media.toggle`, `media.next`, `media.previous`, `media.favorite`, and `media.seek` (seconds). Unknown commands are ignored; media commands require a verified entitlement in the host.

For local development only, a Debug host launched with `BN_ALLOW_DEVELOPMENT_EXTENSIONS=1` accepts an ad-hoc-signed package. This opt-in is compiled out of Release. It does not grant an entitlement or disable the app's hardened-runtime settings.

## Local manual testing

Maintainers with the private submodule can run:

```sh
bash extensions/lockscreen-lyrics/scripts/run-local.sh "$PWD"
```

This builds an isolated Debug app/plugin pair, generates an ephemeral Go-signed receipt, pins its public key in that app copy, and launches with the extension enabled. No purchase is needed and the license Keychain is untouched. `BN_REPLACE_LOCAL_TEST=1` replaces only test copies launched from that submodule checkout after the new build succeeds. Play music and press Control–Command–Q to test the physical lock screen.

The host's lock-screen notch shows a closed padlock beside the camera cutout. After macOS confirms an unlock, it opens the padlock and fades the badge out over 600 ms before restoring the normal notch. Reduce Motion uses a brief static open-padlock state. Re-locking or changing displays cancels the transition; no animation task runs while idle. This responds to the existing session's unlock notification, not the initial login before Boring Notch is running.

The fixture path (`BN_EXTENSION_LICENSE_FIXTURE`) and isolated plugin directory (`BN_EXTENSION_TEST_DIRECTORY`) are honored only in Debug with `BN_ALLOW_DEVELOPMENT_EXTENSIONS=1`. Receipt signatures are still checked. Release builds contain neither override.

## Runtime validation still required before sale

Test a Developer ID signed and notarized app/plugin pair on supported macOS versions, on a physical lock screen, with Touch ID/password unlock, display sleep/wake, fast user switching, changing display layouts, playback pause/seek/track changes, unavailable lyrics, and reduced motion. The private SkyLight API is OS-dependent; successful compilation or a desktop preview alone is not lock-screen compatibility proof.

The reference is [the supplied Droppy clip](https://x.com/Droppyformac/status/2103885027310199137/video/1). The implementation is independently authored; reference footage, album art, and song lyrics are not bundled.
