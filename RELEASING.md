# Releasing Gojo

Gojo cuts releases from your local machine via [`scripts/release.sh`](./scripts/release.sh), wrapped as a Makefile target. The script handles build → sign → notarize → DMG → Sparkle-sign → appcast → GitHub Release in one command.

CI (`.github/workflows/build.yml`) verifies every PR/push compiles, but does **not** publish releases.

```
make release VERSION=1.0.0       # publish
make release-dry VERSION=1.0.0   # build, sign, notarize, appcast — but don't publish
```

---

## One-time setup

You'll do this once per machine you cut releases from.

### 1. Tools

```bash
brew install gh
gh auth login   # for creating the GitHub Release + uploading the DMG
```

You also need a working Xcode (`xcrun`, `codesign`, `hdiutil`, `notarytool`, `stapler` come with it) and Python 3 (preinstalled on macOS).

### 2. Apple Developer ID Application certificate

A **Developer ID Application** cert is required to sign apps for distribution outside the Mac App Store.

In Xcode → Settings → Accounts → your team → **Manage Certificates** → `+` → **Developer ID Application**. Once created, it lives in your login keychain and the release script picks it up by name.

Find the exact identity string:

```bash
security find-identity -v -p codesigning
```

You're looking for the line `"Developer ID Application: Your Name (TEAMID)"`. Copy that into `.env.local` as `MACOS_SIGNING_IDENTITY`.

### 3. App Store Connect API key (for notarization)

In [App Store Connect → Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/integrations/api), create a key with at least **Developer** access. Download the `.p8` immediately (you only get one chance). Note the **Key ID** (10 chars) and **Issuer ID** (UUID at the top of the page).

Stash the `.p8` somewhere outside the repo, e.g. `~/.config/gojo/AuthKey_XXXXXXXX.p8`. Set the path + IDs in `.env.local`.

### 4. Sparkle EdDSA signing keys

The public key is already in `Gojo/Info.plist` as `SUPublicEDKey`. You need the matching private key to sign updates.

```bash
curl -sL https://github.com/sparkle-project/Sparkle/releases/download/2.8.0/Sparkle-2.8.0.tar.xz | tar -xJ
cd bin
./generate_keys
```

If `generate_keys` shows the **same** public key that's in `Info.plist`, the private key already exists in your macOS keychain — export it for the release script:

```bash
./generate_keys -x ~/.config/gojo/sparkle_ed_private_key.txt
```

If the public key **does not match** what's in `Info.plist`, someone else generated the original keypair. Either recover their private key (it's a sensitive secret — wherever they stored their offline backup) or generate a fresh pair and update `Info.plist` (which means current installs won't trust your updates until they update once via the new key path — they'll need a manual reinstall).

Set the file path in `.env.local` as `SPARKLE_PRIVATE_ED_KEY`.

> **The Sparkle private key is the most sensitive secret in this project.** Anyone with it can sign updates Sparkle will trust on every existing install. Don't put it on cloud storage, don't share it. Keep an offline backup (encrypted USB drive / hardware key) so you don't lose your update channel if your machine dies.

### 5. GitHub Pages

The `SUFeedURL` in `Info.plist` points at `https://rohoswagger.github.io/gojo/appcast.xml`. For that URL to actually serve:

1. Repo → **Settings** → **Pages**
2. **Source:** Deploy from a branch
3. **Branch:** `main`, **Folder:** `/ (root)`
4. Save

The release script commits the updated `appcast.xml` to `main` at the end of each release; Pages serves it from there.

### 6. `.env.local`

```bash
cp .env.local.example .env.local
$EDITOR .env.local   # fill in real values
```

`.env.local` is gitignored. The release script auto-sources it.

### Verify everything works

```bash
make release-dry VERSION=0.0.0-test
```

This builds, signs, notarizes, and produces a real DMG + appcast entry in `.build/`, but stops before tagging, creating the GitHub Release, or committing back. Inspect the artifacts. If anything throws, fix it before doing a real release.

---

## Cutting a release

1. **Update `CHANGELOG.md`.** Promote the `[Unreleased]` section to `[<version>] — YYYY-MM-DD`. Add a fresh empty `[Unreleased]` block. The release script extracts this version's block verbatim as the GitHub Release body and as the Sparkle update notes — make sure the markdown is right.

2. **Bump `MARKETING_VERSION`** in `Gojo.xcodeproj/project.pbxproj` (4 occurrences across Debug/Release and main/helper targets):

   ```bash
   sed -i '' "s/MARKETING_VERSION = [0-9.]*;/MARKETING_VERSION = <version>;/g" \
     Gojo.xcodeproj/project.pbxproj
   ```

3. **Commit and push.**

   ```bash
   git add CHANGELOG.md Gojo.xcodeproj/project.pbxproj
   git commit -m "Release v<version>"
   git push origin main
   ```

   Wait for the `Build` workflow to pass green on `main`.

4. **Cut the release.** Takes 5–15 minutes (notarization is the slow part):

   ```bash
   make release VERSION=<version>
   ```

   The script:
   1. Pre-flight checks (clean tree, on main, tag doesn't exist, version matches, identity in keychain)
   2. `xcodebuild` Release with manual signing + hardened runtime
   3. Notarize the `.app` (waits up to 30 minutes)
   4. Staple the ticket
   5. Build the DMG, sign it
   6. Notarize and staple the DMG
   7. Run Sparkle's `sign_update` to produce the EdDSA signature line
   8. Prepend a new `<item>` to `appcast.xml`
   9. `gh release create v<version>` with the DMG as an asset
   10. Commit + push the updated `appcast.xml`

   Existing installs auto-update via Sparkle within ~24h (or immediately on a manual "Check for Updates").

## If something fails mid-release

The script is mostly idempotent up to step 9 (GitHub Release creation). Common issues:

| Failure | Fix |
|---------|-----|
| Notarization timed out | Re-run. `notarytool submit --wait` is patient (30m here) but Apple's queue occasionally lags. |
| Signing identity not found | Run `security find-identity -v -p codesigning`. If missing, regenerate the cert (Xcode → Settings → Accounts). |
| `sign_update` not found | The cached Sparkle CLI may be corrupt — `rm -rf .build/sparkle-tools` and re-run. |
| Bad Sparkle signature | The private key in `SPARKLE_PRIVATE_ED_KEY` doesn't match the public key in `Info.plist`. Recover or regenerate. |
| `gh release create` fails | Check `gh auth status`. Tag might already exist on origin — delete it with `git push origin :refs/tags/v<version>`. |
| Appcast commit conflict | Pull `origin/main` and re-run `make release` (the script is idempotent; build/notarize will be skipped to the extent steps re-detect existing artifacts — easier to just clean `.build/` and start over). |

## Rolling back a release

1. Delete the GitHub Release: `gh release delete v<version> --yes`
2. Delete the git tag locally and remote:
   ```bash
   git tag -d v<version>
   git push origin :refs/tags/v<version>
   ```
3. Revert the appcast commit:
   ```bash
   git revert <appcast-commit-sha>
   git push origin main
   ```

Users who already auto-updated will keep the version they got — there's no remote uninstall. Treat releases as one-way once shipped.
