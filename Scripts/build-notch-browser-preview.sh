#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
notch_project_root="$(cd "${script_directory}/.." && pwd)"
notch_derived_data="${NOTCH_BROWSER_DERIVED_DATA:-${notch_project_root}/.build/notch-browser-signed}"
notch_signing_identity="${NOTCH_BROWSER_SIGNING_IDENTITY:-Developer ID Application}"
notch_preview_app="${notch_project_root}/dist/agent-preview/notch-browser.app"

# Keep the signer and bundle identifier stable across previews. Ad-hoc signing
# makes macOS treat each rebuilt executable as different code for Keychain ACLs.
xcodebuild \
    -project "${notch_project_root}/notch-browser/notch-browser.xcodeproj" \
    -scheme notch-browser -configuration Debug -destination 'platform=macOS' \
    -skipPackageUpdates -derivedDataPath "${notch_derived_data}" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="${notch_signing_identity}" \
    DEVELOPMENT_TEAM=RZJT39VU7M

ditto "${notch_derived_data}/Build/Products/Debug/notch-browser.app" "${notch_preview_app}"
codesign --verify --deep --strict "${notch_preview_app}"
print "Built ${notch_preview_app}"
