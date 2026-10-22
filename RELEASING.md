# Releasing Notch Browser

Run these commands from `/Users/radha_govind/Desktop/cash/swift-notch`.
The shared `notch-browser` scheme builds `notch-browser.app`, including its
signed agent CLI. The separately distributed `notch-terminal` target is not
part of this release.

## App and credentials

- Bundle ID: `com.govi.app.notch-browser`; minimum macOS: 13.0.
- Architectures: `arm64 x86_64` (the app and embedded CLI).
- Certificate: `Developer ID Application: Yakshit Chhipa (RZJT39VU7M)`.
- Sparkle: 2.10.0, pinned in the Xcode project and `Package.resolved`.
- Sparkle Keychain account: `notch-browser`.
- Public key: `BUZ6XwUfwtv9mEepwk4IM2YANcJjr7CzixWrOVrcng0=`.
- Notarization Keychain profile: `notary-lazzy` (existing profile verified).
- Publishing credential: `SUPABASE_STORAGE_KEY`, read from the project-root
  `.env` file or your shell environment. It accepts a Supabase `sb_secret_`
  key or legacy `service_role` JWT; an anon/publishable key cannot publish.

Public settings live in `Scripts/release-config.sh`. The app's checked-in
`notch-browser/NotchBrowser-Info.plist` contains the same feed and public key.
Keep both synchronized when changing the hosting URL. Release verification
rejects mismatches. Keep private keys and credentials out of source and logs.

The private update key was created in Keychain during setup. Future releases
reuse it. On another Mac, restore the existing key securely; do not generate a
replacement for a shipped app. If the notarization profile needs configuring
on another Mac, use the interactive secure prompts:

```sh
xcrun notarytool store-credentials notary-lazzy
```

`--notary-profile NAME` or `NOTARY_PROFILE` can select another existing profile.

## Build numbers

The source starts at marketing version `1.0`, build `1`. Release arguments
override `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` for the archive.
Builds must be positive integers that increase across every published release,
including marketing-version changes. The script checks the highest public
appcast build and rejects an equal or older build.

There was no public Notch Browser feed at setup. Build `1` can be the initial
distribution; the next update needs build `2` or higher. Existing apps without
Sparkle need this baseline installed once before they can receive updates.

## Prepare a signed, notarized release

```sh
./Scripts/release.sh --version 1.0 --build 1
```

This archives with manual Developer ID signing, exports with the same team and
certificate, verifies the bundle identity, versions, architectures, feed and
key, notarizes/staples an app copy, and produces a ZIP, signed drag-to-Applications
DMG, and signed Sparkle appcast. The ZIP signature is verified with Sparkle's
own tool. Existing public feed history is retained. This command creates local
artifacts; publishing requires the separate `--publish` flag.

For an update with embedded release notes:

```sh
./Scripts/release.sh --version 1.0.1 --build 2 --notes /absolute/path/release-notes.md
```

Default output: `dist/release-<VERSION>-<BUILD>-<TIMESTAMP>/`, including the
`.xcarchive`, exported app, ZIP, DMG, and `appcast-work/appcast.xml`.
`--output /absolute/path/new-directory` chooses another fresh output directory.
The existing `.gitignore` excludes `dist/`, `.build/`, and `DerivedData/`.

For local packaging checks only:

```sh
./Scripts/release.sh --version 1.0 --build 1 --skip-notarization
```

Those artifacts are test files. The script rejects combining
`--skip-notarization` with `--publish`. A notarization failure must be resolved;
the release path does not automatically downgrade to this option.

## Package an already exported app

```sh
./Scripts/package-dmg.sh \
  --source-app /absolute/path/notch-browser.app \
  --output /absolute/path/new-artifacts-directory
```

The app must already have the configured Developer ID signature and bundle ID.
The packager copies it before notarization/stapling, preserves framework
symlinks, includes an `/Applications` shortcut in the DMG, and refuses to
overwrite existing artifacts. Use an Xcode-exported app so Sparkle's nested
helpers have the correct distribution signatures. The DMG uses a functional
Finder layout without custom background artwork.

## Publish to Supabase

Hosting uses the existing project `https://qymrzmmsroxkteaxbgoo.supabase.co`,
bucket `updates`, under the dedicated prefix `notch-browser`.

- [Update feed](https://qymrzmmsroxkteaxbgoo.supabase.co/storage/v1/object/public/updates/notch-browser/appcast.xml)
- [Latest DMG](https://qymrzmmsroxkteaxbgoo.supabase.co/storage/v1/object/public/updates/notch-browser/releases/latest/NotchBrowser.dmg)

Copy `.env.example` to `.env` in the project root, then edit `.env` and add your
publishing key:

```dotenv
SUPABASE_STORAGE_KEY=your_supabase_secret_key
```

The script reads this key automatically when `--publish` is used, including
when invoked from another directory. Quotes and comments are supported. An
existing nonempty `SUPABASE_STORAGE_KEY` in your shell environment takes
precedence. `.env` files are ignored by Git; `.env.example` contains no secret.

Then run:

```sh
./Scripts/release.sh --version 1.1 --build 2 --publish
```

Versioned objects are immutable:

```text
notch-browser/releases/v1.0-1/NotchBrowser-1.0-1.zip
notch-browser/releases/v1.0-1/NotchBrowser-1.0-1.dmg
notch-browser/releases/latest/NotchBrowser.dmg
notch-browser/appcast.xml
```

Before uploading, the publisher verifies that the bucket is public and its
configured size/MIME limits allow the artifacts. The project's global upload
limit also applies. It uploads the versioned archives without overwrites,
downloads and compares their SHA-256 hashes, rereads the feed to preserve
history, updates/verifies the latest DMG alias, then publishes/verifies the
appcast. Only a recognized missing object is accepted as a first release;
missing buckets, authentication errors, and invalid XML fail explicitly.

Run one release at a time for this prefix. After a partial publish failure,
inspect existing versioned objects and use an explicit recovery plan or a new
build. Do not replace immutable bytes. Publishing uses standard HTTP uploads;
for large files or unreliable connections, adapt to Supabase's supported
resumable upload tooling.

## Update verification

Release builds start the retained updater automatically. Both the status menu
and app menu contain `Check for Updates…`, with availability driven by Sparkle.
Ordinary Debug builds leave the updater inactive to avoid production checks.

After publishing, launch an older signed baseline from a writable normal
application location, check for updates, install the new build, and verify the
relaunch and new bundle version. Compilation, signed export, and local package
checks do not establish a successful installed-app update.

Setup verified dependency resolution, a universal Developer ID archive/export,
the app and nested Sparkle helper signatures with Hardened Runtime, the local
DMG's signed app and Applications shortcut, the ZIP's cryptographic signature,
the generated appcast, and 20 release safety checks. Local test artifacts are
in `dist/sparkle-setup-validation/`, created with `--skip-notarization`.

Setup did not notarize or publish anything. No publishing credential was present
in the invoking environment; bucket limits will be checked during a credentialed
publish. Notarization and a live update/relaunch remain release checks.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[Sparkle publishing](https://sparkle-project.org/documentation/publishing/),
[Supabase uploads](https://supabase.com/docs/guides/storage/uploads/standard-uploads).
