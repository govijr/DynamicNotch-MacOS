#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
project_directory="$(cd "${script_directory}/.." && pwd)"
app_path="${project_directory}/dist/DynamicNotchDemo.app"

swift build \
    --product DynamicNotchDemo \
    --configuration debug

binary_directory="$(swift build --show-bin-path --configuration debug)"
mkdir -p "${app_path}/Contents/MacOS"
cp "${binary_directory}/DynamicNotchDemo" "${app_path}/Contents/MacOS/DynamicNotchDemo"
cp "${project_directory}/DemoApp/Info.plist" "${app_path}/Contents/Info.plist"

/usr/bin/codesign --force --deep --sign - "${app_path}" >/dev/null

print "Built ${app_path}"
