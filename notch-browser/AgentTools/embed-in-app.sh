#!/bin/sh
# Run by the Notch Browser Xcode target, before code signing.
set -eu
agent_tools_root="$SRCROOT/AgentTools"
agent_helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
agent_skill_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/AgentSkills/notch-browser"
agent_intermediates="$TEMP_DIR/NotchBrowserAgentCLI"
mkdir -p "$agent_helper_dir" "$agent_skill_dir" "$agent_intermediates/module-cache"
for agent_arch in $ARCHS; do
  xcrun swiftc -swift-version 5 -parse-as-library -O -sdk "$SDKROOT" \
    -target "$agent_arch-apple-macos13.0" -module-cache-path "$agent_intermediates/module-cache" \
    "$agent_tools_root/Sources/main.swift" "$SRCROOT/notch-browser/BrowserAgentSocket.swift" \
    -o "$agent_intermediates/notch-browser-$agent_arch"
done
# shellcheck disable=SC2086
set --
for agent_arch in $ARCHS; do
  set -- "$@" "$agent_intermediates/notch-browser-$agent_arch"
done
xcrun lipo -create "$@" -output "$agent_intermediates/notch-browser"
if [ "${CODE_SIGNING_ALLOWED:-NO}" = "YES" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  /usr/bin/codesign --force --options runtime --timestamp \
    --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$agent_intermediates/notch-browser"
fi
cp "$agent_intermediates/notch-browser" "$agent_helper_dir/notch-browser"
chmod 755 "$agent_helper_dir/notch-browser"
cp "$agent_tools_root/skills/notch-browser/SKILL.md" "$agent_skill_dir/SKILL.md"
