#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*"; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }
read_plist() { plutil -extract "$2" raw -o - "$1"; }

require_setting() {
    local name="$1"
    [[ -n "${!name:-}" ]] || fail "Configure $name in release-config.sh"
}

load_release_config() {
    local config="${RELEASE_CONFIG_FILE:-$SCRIPT_DIR/release-config.sh}"
    [[ -f "$config" ]] || fail "Missing $config; fill the release-config.sh example"
    source "$config"
}

validate_app_config() {
    local name
    for name in APP_BUNDLE_NAME APP_DISPLAY_NAME ARTIFACT_NAME APP_BUNDLE_ID TEAM_ID SIGNING_IDENTITY; do
        require_setting "$name"
    done
    [[ "$APP_BUNDLE_NAME" == *.app && "$APP_BUNDLE_NAME" != */* ]] || fail "APP_BUNDLE_NAME must be an .app filename"
    [[ "$ARTIFACT_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "ARTIFACT_NAME must be URL-safe"
    [[ "$SIGNING_IDENTITY" == "Developer ID Application: "*"($TEAM_ID)" ]] \
        || fail "SIGNING_IDENTITY must be the exact Developer ID Application certificate name for TEAM_ID"
}

validate_release_config() {
    validate_app_config
    local name
    for name in PROJECT_PATH SCHEME BUILD_CONFIGURATION ARCHITECTURES SPARKLE_PUBLIC_ED_KEY SPARKLE_KEYCHAIN_ACCOUNT SUPABASE_URL SUPABASE_BUCKET SUPABASE_OBJECT_PREFIX; do
        require_setting "$name"
    done
    [[ "$SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "Invalid public Sparkle key"
    [[ "$SUPABASE_URL" == https://* && "$SUPABASE_URL" != */ && "$SUPABASE_URL" != *[[:space:]\?#]* ]] \
        || fail "SUPABASE_URL must be an HTTPS base URL without trailing slash, query, or whitespace"
    [[ "$SUPABASE_BUCKET" =~ ^[A-Za-z0-9_-]+$ ]] || fail "SUPABASE_BUCKET must be URL-safe"
    [[ "$SUPABASE_OBJECT_PREFIX" =~ ^[a-z0-9][a-z0-9/_-]*$ && "$SUPABASE_OBJECT_PREFIX" != */ && "$SUPABASE_OBJECT_PREFIX" != *//* ]] \
        || fail "SUPABASE_OBJECT_PREFIX must be a URL-safe per-app path"
    SUPABASE_PUBLIC_PREFIX="$SUPABASE_URL/storage/v1/object/public/$SUPABASE_BUCKET/$SUPABASE_OBJECT_PREFIX"
    UPDATE_FEED_URL="$SUPABASE_PUBLIC_PREFIX/appcast.xml"
}

validate_version() {
    [[ "$1" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "Version must be numeric, e.g. 1.0 or 1.0.1"
    [[ "$2" =~ ^[1-9][0-9]*$ ]] || fail "Build must be a positive incrementing integer"
}

verify_app_signature() {
    local app="$1" details
    codesign --verify --deep --strict --verbose=2 "$app"
    details="$(codesign -dv --verbose=4 "$app" 2>&1)" || fail "Could not inspect signature"
    [[ "$details" == *"Authority=$SIGNING_IDENTITY"* && "$details" == *"TeamIdentifier=$TEAM_ID"* ]] \
        || fail "App must have this team's Developer ID Application signature"
}

verify_release_app() {
    local app="$1" info="$1/Contents/Info.plist"
    verify_app_signature "$app"
    [[ "$(basename -- "$app")" == "$APP_BUNDLE_NAME" ]] || fail "Unexpected exported app filename"
    [[ "$(read_plist "$info" CFBundleIdentifier)" == "$APP_BUNDLE_ID" ]] || fail "Bundle identifier mismatch"
    [[ "$(read_plist "$info" CFBundleShortVersionString)" == "$VERSION" ]] || fail "Marketing version mismatch"
    [[ "$(read_plist "$info" CFBundleVersion)" == "$BUILD" ]] || fail "Build number mismatch"
    [[ "$(read_plist "$info" SUFeedURL)" == "$UPDATE_FEED_URL" ]] || fail "Sparkle feed URL mismatch"
    [[ "$(read_plist "$info" SUPublicEDKey)" == "$SPARKLE_PUBLIC_ED_KEY" ]] || fail "Sparkle public key mismatch"
    local executable arch slices
    executable="$(read_plist "$info" CFBundleExecutable)"
    slices="$(xcrun lipo -archs "$app/Contents/MacOS/$executable")"
    for arch in $ARCHITECTURES; do
        [[ " $slices " == *" $arch "* ]] || fail "Exported app is missing $arch"
    done
}

require_notary_tools() {
    [[ -n "${NOTARY_PROFILE:-}" ]] || fail "Set NOTARY_PROFILE or pass --notary-profile"
    xcrun --find notarytool >/dev/null || fail "notarytool is unavailable"
    xcrun --find stapler >/dev/null || fail "stapler is unavailable"
    require_command spctl
}
