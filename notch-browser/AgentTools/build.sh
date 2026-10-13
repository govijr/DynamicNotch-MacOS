#!/bin/sh
set -eu
agent_tools_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
agent_build_root="$agent_tools_root/../../.build/notch-browser-agent-tools"
mkdir -p "$agent_build_root/skills/notch-browser" "$agent_build_root/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -O -module-cache-path "$agent_build_root/module-cache" \
  "$agent_tools_root/Sources/main.swift" \
  "$agent_tools_root/../notch-browser/BrowserAgentSocket.swift" \
  -o "$agent_build_root/notch-browser"
cp "$agent_tools_root/skills/notch-browser/SKILL.md" "$agent_build_root/skills/notch-browser/SKILL.md"
printf '%s\n' "$agent_build_root/notch-browser"
