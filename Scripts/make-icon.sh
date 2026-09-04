#!/bin/bash
# Builds Resources/DevShop.icns from a single-path SVG glyph.
#
# The glyph is rendered through the app's own SVGPath parser, so the icon and the in-app
# brand marks come from exactly the same drawing code.
set -euo pipefail

cd "$(dirname "$0")/.."
SVG="${1:-docs/icon-options/svg/code.svg}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SET="$WORK/DevShop.iconset"

# `swift file.swift ...` treats everything after the first file as arguments, and top-level
# code only runs from main.swift, so the renderer is compiled rather than interpreted.
cp Sources/DevShop/UI/Theme/SVGPath.swift "$WORK/SVGPath.swift"
cp Scripts/render-icon.swift "$WORK/main.swift"
swiftc -O -o "$WORK/render-icon" "$WORK/SVGPath.swift" "$WORK/main.swift"
"$WORK/render-icon" "$SVG" "$SET"

mkdir -p Resources
iconutil -c icns "$SET" -o Resources/DevShop.icns
echo "wrote Resources/DevShop.icns ($(wc -c < Resources/DevShop.icns | tr -d ' ') bytes)"
