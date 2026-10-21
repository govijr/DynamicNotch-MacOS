#!/usr/bin/env bash
# Sourced by release.sh; public reads never need a publishing key.

validate_storage_key() {
    [[ "$-" != *x* ]] || fail "Disable shell tracing before loading publishing credentials"
    [[ -n "${SUPABASE_STORAGE_KEY:-}" ]] || fail "Set SUPABASE_STORAGE_KEY from your local secret manager"
    STORAGE_KEY_TYPE="$(printf '%s' "$SUPABASE_STORAGE_KEY" | python3 "$SCRIPT_DIR/appcast.py" key-type)" \
        || fail "Invalid publishing credential type"
}

storage_headers() {
    printf 'apikey: %s\n' "$SUPABASE_STORAGE_KEY"
    if [[ "$STORAGE_KEY_TYPE" == legacy ]]; then
        printf 'Authorization: Bearer %s\n' "$SUPABASE_STORAGE_KEY"
    fi
}

validate_storage_bucket() {
    local response="$OUTPUT_DIR/bucket-info.json" status
    status="$(storage_headers | curl --silent --show-error --proto '=https' \
        "$SUPABASE_URL/storage/v1/bucket/$SUPABASE_BUCKET" --header @- \
        -o "$response" -w '%{http_code}')" || fail "Could not inspect the Supabase bucket"
    [[ "$status" == 200 ]] || fail "Bucket inspection returned HTTP $status; inspect bucket-info.json"
    python3 "$SCRIPT_DIR/appcast.py" bucket-check "$response" "$SUPABASE_BUCKET" \
        "$(stat -f%z "$ZIP_PATH")" "$(stat -f%z "$DMG_PATH")" "$(stat -f%z "$APPCAST_PATH")" \
        || fail "The bucket must be public and allow release artifact sizes and MIME types"
}

fetch_current_feed() {
    local destination="$1" status
    status="$(curl --silent --show-error --location --proto '=https' --proto-redir '=https' \
        -o "$destination" -w '%{http_code}' "$UPDATE_FEED_URL?release_probe=$BUILD-$(date +%s)")" \
        || fail "Could not read the public appcast"
    if [[ "$status" == 200 ]]; then
        python3 "$SCRIPT_DIR/appcast.py" max-build "$destination" >/dev/null \
            || fail "The public appcast is invalid"
        return 0
    fi
    if [[ "$status" == 400 || "$status" == 404 ]] \
        && python3 "$SCRIPT_DIR/appcast.py" missing-object "$destination"; then
        return 1
    fi
    fail "Public appcast returned HTTP $status; inspect $destination"
}

upload_object() {
    local file="$1" object="$2" mime="$3" cache="$4" upsert="$5" status
    # Read privileged headers from stdin so the key is not in curl's argv.
    status="$(storage_headers | curl --silent --show-error --proto '=https' -X POST \
        "$SUPABASE_URL/storage/v1/object/$SUPABASE_BUCKET/$object" \
        --header @- -H "Content-Type: $mime" -H "Cache-Control: max-age=$cache" \
        -H "x-upsert: $upsert" --data-binary "@$file" \
        -o "$OUTPUT_DIR/upload-response.json" -w '%{http_code}')" \
        || fail "Upload failed for $object"
    [[ "$status" == 200 || "$status" == 201 ]] \
        || fail "Upload $object returned HTTP $status; inspect upload-response.json. Immutable paths are never overwritten."
}

verify_public_file() {
    local local_file="$1" url="$2" probe="$3" expected actual
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        "$url?release_probe=$BUILD-$(date +%s)" -o "$probe" \
        || fail "Could not download published object: $url"
    expected="$(shasum -a 256 "$local_file" | awk '{print $1}')"
    actual="$(shasum -a 256 "$probe" | awk '{print $1}')"
    [[ "$expected" == "$actual" ]] || fail "Public object bytes do not match: $url"
}

publish_release() {
    validate_storage_key
    validate_storage_bucket
    local object="$SUPABASE_OBJECT_PREFIX/releases/v$VERSION-$BUILD"
    local zip_name dmg_name fresh="$OUTPUT_DIR/prepublish-appcast.xml"
    zip_name="$(basename -- "$ZIP_PATH")"
    dmg_name="$(basename -- "$DMG_PATH")"
    mkdir -p "$OUTPUT_DIR/verification"
    note "Uploading immutable versioned archives"
    upload_object "$ZIP_PATH" "$object/$zip_name" application/zip '31536000, immutable' false
    upload_object "$DMG_PATH" "$object/$dmg_name" application/x-apple-diskimage '31536000, immutable' false
    verify_public_file "$ZIP_PATH" "$SUPABASE_PUBLIC_PREFIX/releases/v$VERSION-$BUILD/$zip_name" "$OUTPUT_DIR/verification/$zip_name"
    verify_public_file "$DMG_PATH" "$SUPABASE_PUBLIC_PREFIX/releases/v$VERSION-$BUILD/$dmg_name" "$OUTPUT_DIR/verification/$dmg_name"

    # Re-read before changing mutable objects; preserve any intervening history.
    if fetch_current_feed "$fresh"; then
        python3 "$SCRIPT_DIR/appcast.py" assert-next "$fresh" "$BUILD"
        make_appcast "$fresh"
    elif [[ -n "$CURRENT_FEED" ]]; then
        fail "The existing appcast disappeared during release; inspect the bucket before retrying"
    fi

    note "Updating the latest DMG alias, then publishing the appcast"
    upload_object "$DMG_PATH" "$SUPABASE_OBJECT_PREFIX/releases/latest/$ARTIFACT_NAME.dmg" application/x-apple-diskimage '60, must-revalidate' true
    verify_public_file "$DMG_PATH" "$SUPABASE_PUBLIC_PREFIX/releases/latest/$ARTIFACT_NAME.dmg" "$OUTPUT_DIR/verification/latest.dmg"
    upload_object "$APPCAST_PATH" "$SUPABASE_OBJECT_PREFIX/appcast.xml" application/xml '60, must-revalidate' true
    verify_public_file "$APPCAST_PATH" "$UPDATE_FEED_URL" "$OUTPUT_DIR/verification/published-appcast.xml"
    python3 "$SCRIPT_DIR/appcast.py" verify "$OUTPUT_DIR/verification/published-appcast.xml" \
        "$BUILD" "$VERSIONED_DOWNLOAD_URL" "$(stat -f%z "$ZIP_PATH")"
}
