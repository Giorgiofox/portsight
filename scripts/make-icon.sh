#!/usr/bin/env bash
# Render the PortSight app icon (SwiftUI → 1024 PNG) and build Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="/tmp/portsight-icon-1024.png"
ICONSET="/tmp/PortSight.iconset"

echo "▸ Rendering 1024px icon…"
swift run CableProPreview --icon "$SRC" >/dev/null

echo "▸ Building iconset…"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
# name:size pairs required by iconutil
for pair in \
    "icon_16x16:16" "icon_16x16@2x:32" \
    "icon_32x32:32" "icon_32x32@2x:64" \
    "icon_128x128:128" "icon_128x128@2x:256" \
    "icon_256x256:256" "icon_256x256@2x:512" \
    "icon_512x512:512" "icon_512x512@2x:1024"; do
    name="${pair%:*}"; size="${pair#*:}"
    sips -z "$size" "$size" "$SRC" --out "$ICONSET/$name.png" >/dev/null
done

echo "▸ Converting to .icns…"
mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

echo "✓ Wrote Resources/AppIcon.icns"
