# The in-app Extension Store

Boring Notch provides discovery, bundle delivery, installation, and runtime services. Independent developers own pricing, checkout, customer accounts, licenses, refunds, and paid-feature enforcement. The host has no payment SDK, receipt database, or entitlement service. Paid and free bundles follow the same installation path.

## A reviewed catalog independent of app releases

The native Store in Settings → Extensions reads a complete property-list catalog from the dedicated public [boring.extensions repository](https://github.com/TheBoredTeam/boring.extensions):

```text
https://raw.githubusercontent.com/TheBoredTeam/boring.extensions/main/catalog.plist
```

Each extension has its own reviewed `extensions/<manifest-id>.plist` source file. CI validates those files and generates the full `catalog.plist` after changes reach `main`. Adding an approved listing or updating its artifact metadata requires a catalog change, **not a new Boring Notch release**. Direct ZIP installation remains available independently of Store inclusion. An extension's own manifest cannot declare itself approved or add itself to the official catalog.

The app loads one aggregate when the Store is opened and its one-hour freshness period has elapsed. Manual Refresh always revalidates, using ETag/Last-Modified when the server supplies them; a 304 response reuses previously verified bytes. The shared Store persists a revalidated last-good snapshot bound to its catalog URL. Network or malformed-data failures preserve those listings and show a refresh error. Catalog delivery does not load any extension binaries.

Search and native lazy lists support up to 500 entries. Source records are limited to 64 KiB each and the aggregate to 2 MB. IDs, slugs, responses, URLs, and field sizes are validated before presentation; catalog content is plain data, not executable HTML. XML and binary aggregate plists are accepted. Legacy `schemaVersion: 1` JSON remains decode-compatible, but the official source is the dedicated plist repository. The website's former JSON feed is a separate consumer and is no longer the native Store's endpoint.

The built-in catalog URL can be overridden by the app's `BoringNotchExtensionCatalogURL` Info.plist key; an invalid explicit override fails closed. Installed extensions cannot change the source. The schema supports `coming-soon`, `preview`, and `available` listings. Coming-soon entries have no install action. Previews may link to public source. Available listings require complete, validated `artifact` metadata; missing release information never becomes a guessed download link.

## Adding a downloadable release

Add or update one XML property list in the registry repository. Its top-level dictionary contains `schemaVersion = 1` and the ordinary listing fields. The following JSON notation illustrates the dictionary shape; the source file itself is a `.plist`:

```json
{
  "schemaVersion": 1,
  "id": "org.example.focus",
  "version": "1.0.0",
  "status": "available",
  "artifact": {
    "downloadURL": "https://downloads.example.org/focus-1.0.0.zip",
    "sha256": "64_lowercase_hex_digits_of_the_exact_distributed_zip",
    "publisherTeamID": "ABCDE12345",
    "version": "1.0.0",
    "apiVersion": 1
  }
}
```

This is an excerpt with placeholder release values, not a complete or publishable listing. Include permanent slug, name, tagline, description, developer, categories, price, version, requirements, and truthful release status. Optional `websiteUrl` supplies the public HTTPS product page used by “View on website”; without it the app uses `developer.url` rather than inventing a website page from the slug. Optional support/source URLs and preview information remain publisher-owned. Icon and artwork values may be absolute public HTTPS URLs; existing `assets/extensions/...` website paths also work. The artifact version must match the listing and packaged manifest. `downloadURL` must deliver a public ZIP; it is not a checkout page or an authenticated customer download token. The legacy artifact key `url` is accepted for compatibility; if both keys exist they must match.

Run the registry's `python3 scripts/catalog.py` and unit tests, then submit the source plist for maintainer review. The generator sorts full listing records by ID and emits `{schemaVersion: 1, extensions: [...]}` without individual file lookups from the app. Sources use XML for review, reject duplicate keys, and must be named after their exact manifest ID. Do not hand-edit the generated aggregate. See the registry's [contribution guide](https://github.com/TheBoredTeam/boring.extensions#register-or-update-an-extension) for the complete schema and CI flow.

The reviewed release includes three independent checks:

1. The public HTTPS artifact is streamed to private temporary storage, with a 100 MB transfer limit, timeouts, cancellation cleanup, and a SHA-256 match to the catalog. HTTPS redirects are validated and cookies are not persisted.
2. The ordinary ZIP installer validates paths, limits, bundle structure, all architecture signatures, and notarization in staging.
3. Before replacement, the staged bundle must match the reviewed manifest ID, exact version, and signing Team ID. Publisher approval and runtime identity checks still apply.

Compute the hash from the final distributed ZIP after signing/notarization and archive creation. A publisher replacing a URL's bytes must submit the new hash and release metadata through catalog review. Prefer immutable versioned release URLs. No catalog record should contain signing secrets, API keys, customer identifiers, or license codes.

## Payments stay with the developer

A price is descriptive metadata. It does not change whether Boring Notch can install a valid approved artifact. For example, a paid extension can distribute its signed bundle publicly, then present the developer's own checkout or activation UI in its extension settings. The host neither verifies nor stores the resulting purchase.

The developer can also distribute packages outside the Store; users install those through the file picker or ZIP drop target. The host's publisher checks and runtime contract are the same. Store approval is release curation, not a statement that the user has purchased anything.

## Release readiness

The initial catalog preserves the existing preview/coming-soon listings and has no approved consumer ZIP artifact. The native Store displays that data truthfully. Enabling downloads for a product requires its actual signed/notarized bundle plus reviewed artifact metadata; the local ad-hoc Focus Timer example is not a production release.

Run the registry's catalog generator and Python tests when editing a listing. In this host repository, run `swift test --jobs 4`, the standalone example's `smoke.sh`, and `smoke-install.sh`. The latter exercises the real asynchronous installer and runtime in isolated temporary storage with a stub media provider; it does not launch the application or modify installed user extensions.
