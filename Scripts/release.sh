#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/release-common.sh"

VERSION=""
BUILD=""
OUTPUT_DIR=""
NOTARY_PROFILE_ARG=""
RELEASE_NOTES=""
PUBLISH=false
SKIP_NOTARIZATION=false

usage() {
    printf '%s\n' \
        'Usage: ./Scripts/release.sh --version 1.1 --build 2 [options]' \
        '  --output PATH           New artifact directory (default: dist/release-...)' \
        '  --notary-profile NAME   Keychain notarytool profile' \
        '  --notes PATH            Embedded .md, .html, or .txt release notes' \
        '  --publish               Publish verified archives, latest DMG, then feed' \
        '  --skip-notarization     Local test only; incompatible with --publish' \
        '  --help' \
        'Configure release-config.sh first. Publishing alone needs SUPABASE_STORAGE_KEY in the environment.'
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --version|--build|--output|--notary-profile|--notes)
            [[ "$#" -ge 2 ]] || fail "$1 needs a value"
            case "$1" in
                --version) VERSION="$2";;
                --build) BUILD="$2";;
                --output) OUTPUT_DIR="$2";;
                --notary-profile) NOTARY_PROFILE_ARG="$2";;
                --notes) RELEASE_NOTES="$2";;
            esac
            shift 2;;
        --publish) PUBLISH=true; shift;;
        --skip-notarization) SKIP_NOTARIZATION=true; shift;;
        -h|--help) usage; exit 0;;
        *) fail "Unknown option: $1";;
    esac
done

validate_version "$VERSION" "$BUILD"
[[ "$SKIP_NOTARIZATION" != true || "$PUBLISH" != true ]] || fail "Cannot publish unnotarized test artifacts"
load_release_config
validate_release_config
[[ -z "$NOTARY_PROFILE_ARG" ]] || NOTARY_PROFILE="$NOTARY_PROFILE_ARG"
for command in xcodebuild xcrun codesign plutil ditto curl python3 shasum awk stat find; do require_command "$command"; done
[[ "$SKIP_NOTARIZATION" == true ]] || require_notary_tools
source "$SCRIPT_DIR/release-supabase.sh"
[[ "$PUBLISH" != true ]] || validate_storage_key

case "$PROJECT_PATH" in
    /*) PROJECT_FILE="$PROJECT_PATH";;
    *) PROJECT_FILE="$PROJECT_ROOT/$PROJECT_PATH";;
esac
[[ -d "$PROJECT_FILE" ]] || fail "Project/workspace does not exist: $PROJECT_FILE"
case "$PROJECT_FILE" in
    *.xcodeproj) PROJECT_ARGS=(-project "$PROJECT_FILE");;
    *.xcworkspace) PROJECT_ARGS=(-workspace "$PROJECT_FILE");;
    *) fail "PROJECT_PATH must be an .xcodeproj or .xcworkspace";;
esac
if [[ -n "$RELEASE_NOTES" ]]; then
    [[ -f "$RELEASE_NOTES" ]] || fail "Release notes file is missing"
    case "$RELEASE_NOTES" in *.md|*.html|*.txt) ;; *) fail "Unsupported release notes format";; esac
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="$PROJECT_ROOT/dist/release-$VERSION-$BUILD-$(date +%Y%m%d-%H%M%S)"
fi
[[ ! -e "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || fail "Output path already exists: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd)"
CURRENT_FEED="$OUTPUT_DIR/current-appcast.xml"
if fetch_current_feed "$CURRENT_FEED"; then
    python3 "$SCRIPT_DIR/appcast.py" assert-next "$CURRENT_FEED" "$BUILD"
else
    CURRENT_FEED=""
fi

DERIVED_DATA="$OUTPUT_DIR/DerivedData"
ARCHIVE_PATH="$OUTPUT_DIR/$ARTIFACT_NAME.xcarchive"
EXPORT_PATH="$OUTPUT_DIR/export"
note "Archiving $APP_DISPLAY_NAME $VERSION ($BUILD) with Developer ID"
xcodebuild "${PROJECT_ARGS[@]}" -scheme "$SCHEME" -configuration "$BUILD_CONFIGURATION" \
    -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED_DATA" \
    -clonedSourcePackagesDirPath "$DERIVED_DATA/SourcePackages" \
    -packageCachePath "$DERIVED_DATA/PackageCache" -skipPackageUpdates \
    -archivePath "$ARCHIVE_PATH" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_ALLOWED=YES ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp \
    ONLY_ACTIVE_ARCH=NO ARCHS="$ARCHITECTURES" archive

APPLICATION_PATH="$(read_plist "$ARCHIVE_PATH/Info.plist" ApplicationProperties.ApplicationPath)" \
    || fail "Generic archive: inspect Products and set SKIP_INSTALL=YES on embedded-only helper targets"
[[ "$APPLICATION_PATH" == "Applications/$APP_BUNDLE_NAME" ]] || fail "Unexpected archive application path: $APPLICATION_PATH"
EXPORT_OPTIONS="$OUTPUT_DIR/ExportOptions.plist"
ditto "$SCRIPT_DIR/ExportOptions.plist" "$EXPORT_OPTIONS"
plutil -replace teamID -string "$TEAM_ID" "$EXPORT_OPTIONS"
plutil -replace signingCertificate -string "$SIGNING_IDENTITY" "$EXPORT_OPTIONS"
note "Exporting Developer ID app"
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" -exportPath "$EXPORT_PATH"
APP_PATH="$EXPORT_PATH/$APP_BUNDLE_NAME"
[[ -d "$APP_PATH" ]] || fail "Export did not produce $APP_BUNDLE_NAME"
verify_release_app "$APP_PATH"

PACKAGE_ARGS=(--source-app "$APP_PATH" --version "$VERSION" --build "$BUILD" --output "$OUTPUT_DIR")
[[ "$SKIP_NOTARIZATION" != true ]] || PACKAGE_ARGS+=(--skip-notarization)
[[ -z "${NOTARY_PROFILE:-}" ]] || PACKAGE_ARGS+=(--notary-profile "$NOTARY_PROFILE")
bash "$SCRIPT_DIR/package-dmg.sh" "${PACKAGE_ARGS[@]}"
ZIP_PATH="$OUTPUT_DIR/$ARTIFACT_NAME-$VERSION-$BUILD.zip"
DMG_PATH="$OUTPUT_DIR/$ARTIFACT_NAME-$VERSION-$BUILD.dmg"
[[ -f "$ZIP_PATH" && -f "$DMG_PATH" ]] || fail "Package artifacts are missing"

SPARKLE_TOOL="$(find "$DERIVED_DATA/SourcePackages/artifacts" -type f -path '*/Sparkle/bin/generate_appcast' -print -quit)"
[[ -n "$SPARKLE_TOOL" && -x "$SPARKLE_TOOL" ]] || fail "Resolved Sparkle generate_appcast tool is missing"
SPARKLE_BIN_DIR="$(dirname -- "$SPARKLE_TOOL")"
[[ "$("$SPARKLE_BIN_DIR/generate_keys" --account "$SPARKLE_KEYCHAIN_ACCOUNT" -p)" == "$SPARKLE_PUBLIC_ED_KEY" ]] \
    || fail "Keychain account does not match the public key embedded in the app"
APPCAST_DIR="$OUTPUT_DIR/appcast-work"
APPCAST_PATH="$APPCAST_DIR/appcast.xml"
VERSIONED_DOWNLOAD_URL="$SUPABASE_PUBLIC_PREFIX/releases/v$VERSION-$BUILD/$(basename -- "$ZIP_PATH")"
mkdir -p "$APPCAST_DIR"
ditto "$ZIP_PATH" "$APPCAST_DIR/$(basename -- "$ZIP_PATH")"
if [[ -n "$RELEASE_NOTES" ]]; then
    ditto "$RELEASE_NOTES" "$APPCAST_DIR/$ARTIFACT_NAME-$VERSION-$BUILD.${RELEASE_NOTES##*.}"
fi

make_appcast() {
    local previous="$1" signature
    if [[ -n "$previous" ]]; then ditto "$previous" "$APPCAST_PATH"; fi
    "$SPARKLE_TOOL" --account "$SPARKLE_KEYCHAIN_ACCOUNT" \
        --download-url-prefix "$SUPABASE_PUBLIC_PREFIX/releases/v$VERSION-$BUILD/" \
        --maximum-versions 0 --maximum-deltas 0 --versions "$BUILD" --embed-release-notes \
        -o "$APPCAST_PATH" "$APPCAST_DIR"
    signature="$(python3 "$SCRIPT_DIR/appcast.py" verify "$APPCAST_PATH" "$BUILD" \
        "$VERSIONED_DOWNLOAD_URL" "$(stat -f%z "$ZIP_PATH")" --print-signature)"
    "$SPARKLE_BIN_DIR/sign_update" --account "$SPARKLE_KEYCHAIN_ACCOUNT" --verify "$ZIP_PATH" "$signature"
}

make_appcast "$CURRENT_FEED"
if [[ "$PUBLISH" == true ]]; then publish_release; fi
printf '\nArtifacts ready:\n  ZIP: %s\n  DMG: %s\n  Appcast: %s\n' "$ZIP_PATH" "$DMG_PATH" "$APPCAST_PATH"
if [[ "$PUBLISH" == true ]]; then printf '  Feed: %s\n' "$UPDATE_FEED_URL"; fi
