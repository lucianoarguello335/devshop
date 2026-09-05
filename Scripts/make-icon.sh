#!/bin/bash
# Builds the two app icons from Scripts/render-appicon.swift.
#
# macOS resolves one .icns per bundle, so the light icon is the one Finder and the Dock
# show before launch; the running app swaps in the dark one when the appearance is dark
# (see UI/Chrome/DockIcon.swift).
set -euo pipefail

cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Top-level code only runs from main.swift, so the renderer is compiled rather than run
# through `swift <file>`, which would treat later arguments as more source files.
cp Scripts/render-appicon.swift "$WORK/main.swift"
swiftc -O -o "$WORK/render-appicon" "$WORK/main.swift"

mkdir -p Resources
for appearance in light dark; do
  "$WORK/render-appicon" "$appearance" "$WORK/$appearance.iconset"
done

iconutil -c icns "$WORK/light.iconset" -o Resources/DevShop.icns
iconutil -c icns "$WORK/dark.iconset" -o Resources/DevShop-Dark.icns

# A pair of 1024px stills for the README.
mkdir -p docs
cp "$WORK/light.iconset/icon_512x512@2x.png" docs/icon-light.png
cp "$WORK/dark.iconset/icon_512x512@2x.png" docs/icon-dark.png

for icns in Resources/DevShop.icns Resources/DevShop-Dark.icns; do
  echo "wrote $icns ($(wc -c < "$icns" | tr -d ' ') bytes)"
done
