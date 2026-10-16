# Local Notch Browser previews

From the repository root, use:

```sh
zsh Scripts/build-notch-browser-preview.sh
```

The script builds with the installed Developer ID Application certificate and
copies the signed app to `dist/agent-preview/notch-browser.app`. Keep the signing
identity and bundle identifier consistent between builds. Do not re-sign this
preview ad hoc or build it with `CODE_SIGNING_ALLOWED=NO` for normal daily use:
those builds have no stable signing identity for macOS to remember Keychain trust.

`NOTCH_BROWSER_SIGNING_IDENTITY` and `NOTCH_BROWSER_DERIVED_DATA` can override the
certificate selector and build directory. Switching between development and
distribution signing identities can require a new Keychain authorization.

The browser uses WebKit's persistent website data store. Its additional Keychain
cookie backup is optional: startup, background saves and termination run with
Keychain interaction disabled, preserving the existing backup if access fails.
Explicit Chrome imports and manual saves may request access. The permission
policy is scoped to one synchronous operation and serialized with the app's
other Keychain calls so it cannot suppress an unrelated explicit import.

The policy regression checks use no user Keychain items:

```sh
xcrun swiftc -swift-version 5 -parse-as-library \
  notch-browser/notch-browser/BrowserKeychainAccess.swift \
  notch-browser/Tests/KeychainInteractionTests.swift \
  -o /tmp/notch-browser-keychain-policy-tests
/tmp/notch-browser-keychain-policy-tests
```

## Browser regression checks

Run `python3 Scripts/test-notch-browser.py` for navigation/Stop, bounded page
snapshots, session/title migration, live URL updates, native Find/address focus,
cookie backup batching, license startup/races, downloads, bookmarks, backgrounds,
and Keychain interaction policy. Use `--suite behavior`, `session`, `keyboard`,
`license`, `transfer`, or `foundation` to check one batch.

The session suite also checks the real search-provider results URLs and query
encoding. Transfer checks include Copy Image menu routing and pasteable image
data on a disposable clipboard, while preserving native Copy Link behavior.

These checks build separate native test bundles with disposable preferences and
website stores. License tests use synthetic credentials and intercepted responses;
cookie tests use in-memory backup storage and a local HTTP server on a free port.
They do not read the user's accounts or prove third-party login/purchase behavior.
Run them in a logged-in macOS desktop session with WebKit/WindowServer access.

Run `python3 notch-browser/AgentTools/Tests/integration.py` for the real local CLI,
semantic references, background tabs, popups, screenshots, waits, history,
Stop/Resume, and license enforcement. Both runners execute in the browser CI job.

The agent suite also checks `extract [css-selector]` for scoped readable text,
metadata, links, images and available captions. A synthetic native-generated
video verifies `media-frame <ref> <absolute-output.png>` without downloading
media or reading user accounts. Tests cover playback preservation, source/ref
changes, cross-origin capture denial and missing captions/decoded frames.
See `AgentTools/README.md` for extraction limits and examples.

Page screenshots are capped at three entries and 16 MiB. Live web views retain
their browsing state and use WebKit's default background scheduling. Cookie
backups keep session cookies only; persistent cookies remain owned by WebKit.
Change notifications schedule coalesced saves, with a 15-second check during
browser/agent use for macOS versions that miss notifications. Checks stop when
both activities end, followed by a final save. Unchanged backups skip storage
writes, and explicit saves keep their interactive Keychain policy.
