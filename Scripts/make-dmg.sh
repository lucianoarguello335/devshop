#!/bin/bash
# Packages DevShop.app into a distributable disk image.
#
# A DMG rather than a ZIP, for one concrete reason: a notarization ticket can be stapled to a
# disk image but not to a ZIP archive, so opening the download works with no network.
# https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
#
# That ticket covers the image, not the copy the user drags to Applications. release.sh
# therefore notarizes and staples DevShop.app first, and this script packages the already
# stapled bundle — see the two passes there.
#
# Environment:
#   DEVSHOP_SIGN_IDENTITY=...  signs the image itself; "-" or unset leaves it unsigned
set -euo pipefail

cd "$(dirname "$0")/.."
APP="DevShop.app"
IDENTITY="${DEVSHOP_SIGN_IDENTITY:--}"

[ -d "$APP" ] || { echo "missing $APP — run: make app" >&2; exit 1; }

VERSION="$(tr -d '[:space:]' < VERSION)"
DMG="dist/DevShop-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p dist
rm -f "$DMG"

cp -R "$APP" "$STAGE/"
# The drop target every Mac user expects. A symlink costs nothing in the image and needs no
# Finder scripting, which would need automation permission on the build machine.
ln -s /Applications "$STAGE/Applications"

# UDZO is the ordinary compressed format. Apple warns that heavily compressed images slow
# notarization down, so this stays at the default compression rather than reaching for ULFO.
hdiutil create \
  -volname "DevShop" \
  -srcfolder "$STAGE" \
  -format UDZO \
  -ov -quiet \
  "$DMG"

# A corrupt image is one of the documented causes of a notarization rejection, so check here
# rather than finding out after a round trip to Apple.
hdiutil verify -quiet "$DMG"

if [ "$IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

echo "built $DMG ($(du -h "$DMG" | cut -f1))"
