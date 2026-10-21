#!/usr/bin/env bash
# Public per-app settings. Fill from this app; do not put secret values here.
PROJECT_PATH="notch-browser/notch-browser.xcodeproj"
SCHEME="notch-browser"
BUILD_CONFIGURATION="Release"
ARCHITECTURES="arm64 x86_64"
APP_BUNDLE_NAME="notch-browser.app"
APP_DISPLAY_NAME="Notch Browser"
ARTIFACT_NAME="NotchBrowser"
APP_BUNDLE_ID="com.govi.app.notch-browser"
TEAM_ID="RZJT39VU7M"
SIGNING_IDENTITY="Developer ID Application: Yakshit Chhipa (RZJT39VU7M)"
SPARKLE_PUBLIC_ED_KEY="BUZ6XwUfwtv9mEepwk4IM2YANcJjr7CzixWrOVrcng0="
SPARKLE_KEYCHAIN_ACCOUNT="notch-browser"
SUPABASE_URL="https://qymrzmmsroxkteaxbgoo.supabase.co"
SUPABASE_BUCKET="updates"
SUPABASE_OBJECT_PREFIX="notch-browser"
NOTARY_PROFILE="${NOTARY_PROFILE:-notary-lazzy}"
# Publishing uses SUPABASE_STORAGE_KEY from the invoking environment only.
