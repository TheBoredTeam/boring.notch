# The in-app Extension Store

Boring Notch provides discovery, bundle delivery, installation, and runtime services. Independent developers own pricing, checkout, customer accounts, licenses, refunds, and paid-feature enforcement. The host has no payment SDK, receipt database, or entitlement service. Paid and free bundles follow the same installation path.

## One reviewed catalog

The native Store in Settings → Extensions reads the same public catalog as the website:

```text
https://theboring.name/extensions/catalog.json
```

Listings enter this maintainer-controlled catalog through review. Direct ZIP installation remains available independently of Store inclusion. An extension's own manifest cannot declare itself approved or add itself to the official catalog.

The app loads the catalog when the Store is opened, retains it for the session, and offers manual refresh. It does not poll or load extensions merely because their listings were downloaded. Search and native lazy lists support a catalog of up to 500 entries. Responses, URLs, and field sizes are validated before presentation; catalog content is plain data, not executable HTML.

The existing schemaVersion 1 supports `coming-soon`, `preview`, and `available` listings. Coming-soon entries have no install action. Previews may link to public source. An available listing is installable in the native host only when it includes a complete, validated `artifact` record. Missing release metadata never becomes a guessed download link.

## Adding a downloadable release

In the website repository's `extensions/catalog.json`, add this optional record to a reviewed listing:

```json
{
  "schemaVersion": 1,
  "extensions": [{
    "id": "org.example.focus",
    "version": "1.0.0",
    "status": "available",
    "artifact": {
      "url": "https://downloads.example.org/focus-1.0.0.zip",
      "sha256": "64_lowercase_hex_digits_of_the_exact_distributed_zip",
      "publisherTeamID": "ABCDE12345",
      "version": "1.0.0",
      "apiVersion": 1
    }
  }]
}
```

This is an excerpt, not a complete listing. Retain the ordinary website metadata: permanent slug, name, developer, description, categories, status note, price, requirements, support, and preview information. The artifact version must match the listing and packaged manifest. The artifact URL must deliver a public ZIP; it is not a checkout page or an authenticated customer download token. Existing website renderers can ignore the additive artifact field.

The reviewed release includes three independent checks:

1. The public HTTPS artifact is streamed to private temporary storage, with a 100 MB transfer limit, timeouts, cancellation cleanup, and a SHA-256 match to the catalog. HTTPS redirects are validated and cookies are not persisted.
2. The ordinary ZIP installer validates paths, limits, bundle structure, all architecture signatures, and notarization in staging.
3. Before replacement, the staged bundle must match the reviewed manifest ID, exact version, and signing Team ID. Publisher approval and runtime identity checks still apply.

Compute the hash from the final distributed ZIP after signing/notarization and archive creation. A publisher replacing a URL's bytes must submit the new hash and release metadata through catalog review. Prefer immutable versioned release URLs. No catalog record should contain signing secrets, API keys, customer identifiers, or license codes.

## Payments stay with the developer

A price is descriptive metadata. It does not change whether Boring Notch can install a valid approved artifact. For example, a paid extension can distribute its signed bundle publicly, then present the developer's own checkout or activation UI in its extension settings. The host neither verifies nor stores the resulting purchase.

The developer can also distribute packages outside the Store; users install those through the file picker or ZIP drop target. The host's publisher checks and runtime contract are the same. Store approval is release curation, not a statement that the user has purchased anything.

## Release readiness

The current public catalog contains preview/coming-soon listings and has no approved consumer ZIP artifact. The native Store displays that data truthfully. Enabling downloads for a product requires its actual signed/notarized bundle plus reviewed artifact metadata; the local ad-hoc Focus Timer example is not a production release.

Run the website's existing catalog validation and tests when editing its listing. In this repository, run `swift test --jobs 4`, the standalone example's `smoke.sh`, and `smoke-install.sh`. The latter exercises the real asynchronous installer and runtime in isolated temporary storage with a stub media provider; it does not launch the application or modify installed user extensions.
