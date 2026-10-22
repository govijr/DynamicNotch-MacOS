# Notch Browser commercial readiness

Reviewed October 12, 2026 against the current local working tree.

Verdict: the main code issues from the initial review are addressed, and an unsigned Release app builds. The product is not ready for paid distribution until the real Polar purchase-to-unlock path and a signed, notarized installation are verified. No purchase, publication, or signing action was performed.

## Changes completed

- Added a compact first-launch licensing window with a secure key field, validation progress and errors, a $5 purchase link, and a manual “Enter License Key” menu item. Browser entry points check the shared entitlement.
- Connected the app to Polar’s public license validation endpoint using the supplied organization and Notch Browser benefit IDs. The app checks the returned organization, benefit, and `granted` status; it stores the key in macOS Keychain and allows a 72-hour offline grace after a successful validation. No merchant token is bundled. Polar documents this endpoint for public desktop clients and recommends checking the benefit ID when an organization has multiple license types. [Validation API](https://polar.sh/docs/api-reference/2026-10/customer_portal/validate-license-key), [license key guide](https://polar.sh/docs/features/benefits/license-keys)
- Fixed explicit navigation being dropped while another page loads, and persisted the ordered open tabs and selected tab across restarts.
- Updated Chrome cookie import to read Chromium’s database version and handle its v24 SHA-256 domain prefix. Import status reports how many cookies were added.
- Added popup tabs, download handling, JavaScript dialogs, and common browser keyboard shortcuts.
- Added app name, copyright, macOS 13 minimum, icon assets, and a neutral new-tab greeting.
- Added a CI job that builds the browser app in Release configuration.

## Verification

- Release build succeeded with code signing disabled at `/private/tmp/notch-browser-release-build/Build/Products/Release/notch-browser.app`.
- Verified the built Info.plist contains the supplied Polar organization, benefit, and checkout URL; display name `Notch Browser`; and `LSMinimumSystemVersion` `13.0`.
- `git diff --check` and the explicit Info.plist lint passed.
- `swift test` could not run in this sandbox: SwiftPM manifest compilation was denied access to its host module cache and sandbox setup. This is an environment restriction, not a test assertion failure.
- The final configured onboarding window was not manually exercised against Polar. No real valid, invalid, wrong-product, expired, revoked, offline, or purchase-to-unlock cases have been tested.

## Remaining release gates

1. Run the Polar checkout and key flow end to end. Verify the configured benefit issues a non-expiring key, then test activation, restart, network loss, wrong-product keys, and revocation. The current implementation does not create device activations; if you enable Polar activation limits, add activation creation, persistent activation IDs, and deactivation before release.
2. Sign with the intended Developer ID, notarize and staple the app, then install and launch that download on a clean Mac. The local build used `CODE_SIGNING_ALLOWED=NO`; it does not prove customer distribution works. [Apple Developer ID guidance](https://developer.apple.com/developer-id/)
3. Verify the supported macOS range and advertised website flows on real devices, including sign-in, popups, downloads, tab restore, and sleep/wake. The app currently declares macOS 13 as its minimum; that compatibility has not been runtime-tested on the oldest supported release.
4. Commit the intended browser sources, app assets, configuration, and CI changes. This working tree contains staged, unstaged, and untracked files from ongoing work; nothing was staged or committed during this pass.

The app still has no explicit file-input picker or WebKit content-process recovery. I left the browser-agent integration alone as requested, so these shared WebKit hooks remain open for a follow-up after that work settles. There is also no browser-specific automated interaction suite yet.

The app is positioned as a quick browser available from the notch. Current evidence does not support promises of a full Safari/Chrome replacement or universal session import.
