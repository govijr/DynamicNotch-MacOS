#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/release-common.sh"

SOURCE_APP=""
OUTPUT_DIR=""
VERSION=""
BUILD=""
NOTARY_PROFILE_ARG=""
SKIP_NOTARIZATION=false

usage() {
    printf '%s\n' \
        'Usage: ./Scripts/package-dmg.sh --source-app /absolute/path/notch-browser.app [options]' \
        '  --output PATH           Artifact directory (default: dist)' \
        '  --version VERSION       Require this marketing version' \
        '  --build NUMBER          Require this bundle build' \
        '  --notary-profile NAME   Keychain notarytool profile' \
        '  --skip-notarization     Local test artifacts only' \
        '  --help'
}
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --source-app|--output|--version|--build|--notary-profile)
            [[ "$#" -ge 2 ]] || fail "$1 needs a value"
            case "$1" in
                --source-app) SOURCE_APP="$2";;
                --output) OUTPUT_DIR="$2";;
                --version) VERSION="$2";;
                --build) BUILD="$2";;
                --notary-profile) NOTARY_PROFILE_ARG="$2";;
            esac
            shift 2;;
        --skip-notarization) SKIP_NOTARIZATION=true; shift;;
        -h|--help) usage; exit 0;;
        *) fail "Unknown option: $1";;
    esac
done

[[ -n "$SOURCE_APP" && -d "$SOURCE_APP" && "$SOURCE_APP" == *.app ]] || fail "Pass an existing signed .app"
SOURCE_APP="$(cd -- "$(dirname -- "$SOURCE_APP")" && pwd)/$(basename -- "$SOURCE_APP")"
load_release_config
validate_app_config
[[ -z "$NOTARY_PROFILE_ARG" ]] || NOTARY_PROFILE="$NOTARY_PROFILE_ARG"
for command in codesign ditto plutil hdiutil xcrun shasum awk; do require_command "$command"; done
[[ "$SKIP_NOTARIZATION" == true ]] || require_notary_tools
[[ "$(basename -- "$SOURCE_APP")" == "$APP_BUNDLE_NAME" ]] || fail "Source app filename mismatch"
INFO="$SOURCE_APP/Contents/Info.plist"
[[ "$(read_plist "$INFO" CFBundleIdentifier)" == "$APP_BUNDLE_ID" ]] || fail "Source bundle identifier mismatch"
APP_VERSION="$(read_plist "$INFO" CFBundleShortVersionString)"
APP_BUILD="$(read_plist "$INFO" CFBundleVersion)"
[[ -z "$VERSION" || "$VERSION" == "$APP_VERSION" ]] || fail "Source marketing version mismatch"
[[ -z "$BUILD" || "$BUILD" == "$APP_BUILD" ]] || fail "Source build mismatch"
VERSION="$APP_VERSION"
BUILD="$APP_BUILD"
validate_version "$VERSION" "$BUILD"
verify_app_signature "$SOURCE_APP"

[[ -n "$OUTPUT_DIR" ]] || OUTPUT_DIR="$PROJECT_ROOT/dist"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd)"
ZIP_PATH="$OUTPUT_DIR/$ARTIFACT_NAME-$VERSION-$BUILD.zip"
DMG_PATH="$OUTPUT_DIR/$ARTIFACT_NAME-$VERSION-$BUILD.dmg"
[[ ! -e "$ZIP_PATH" && ! -L "$ZIP_PATH" && ! -e "$DMG_PATH" && ! -L "$DMG_PATH" ]] || fail "Artifacts already exist"
PACKAGE_WORK_DIR="$(mktemp -d -t macos-package)"
readonly PACKAGE_WORK_DIR
cleanup() { if [[ -d "$PACKAGE_WORK_DIR" ]]; then rm -rf -- "$PACKAGE_WORK_DIR"; fi; }
trap cleanup EXIT
APP_COPY="$PACKAGE_WORK_DIR/$APP_BUNDLE_NAME"
ditto "$SOURCE_APP" "$APP_COPY"

if [[ "$SKIP_NOTARIZATION" == false ]]; then
    note "Notarizing and stapling the app copy"
    ditto -c -k --sequesterRsrc --keepParent "$APP_COPY" "$PACKAGE_WORK_DIR/notarize.zip"
    xcrun notarytool submit "$PACKAGE_WORK_DIR/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_COPY"
    xcrun stapler validate "$APP_COPY"
    spctl --assess --type execute --verbose=4 "$APP_COPY"
fi
note "Creating Sparkle ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_COPY" "$ZIP_PATH"
mkdir -p "$PACKAGE_WORK_DIR/staging"
ditto "$APP_COPY" "$PACKAGE_WORK_DIR/staging/$APP_BUNDLE_NAME"
ln -s /Applications "$PACKAGE_WORK_DIR/staging/Applications"

note "Creating signed drag-to-Applications DMG"
hdiutil create -volname "$APP_DISPLAY_NAME" -srcfolder "$PACKAGE_WORK_DIR/staging" -format UDZO "$DMG_PATH"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
hdiutil verify "$DMG_PATH"

if [[ "$SKIP_NOTARIZATION" == false ]]; then
    note "Notarizing and stapling DMG"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
else
    note "Local test artifacts: notarization was explicitly skipped"
fi
printf '\nZIP: %s\nDMG: %s\n' "$ZIP_PATH" "$DMG_PATH"
shasum -a 256 "$ZIP_PATH" "$DMG_PATH"
