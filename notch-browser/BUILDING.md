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
