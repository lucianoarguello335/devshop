#!/bin/bash
# Wraps the SwiftPM binary into DevShop.app.
#
# The package builds a plain executable; macOS needs a bundle for a proper Dock icon,
# menu bar and window behaviour. Everything here is deterministic, so the app can be
# rebuilt from a clean checkout with no Xcode project involved.
#
# Environment:
#   DEVSHOP_UNIVERSAL=1        build arm64 + x86_64 and lipo them together (releases)
#   DEVSHOP_SIGN_IDENTITY=...  a Developer ID Application identity (releases); "-" is ad-hoc
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="DevShop.app"

# A release ships both architectures. A local `make app` builds the host arch only, which keeps
# the edit-build-run loop at one compile instead of two.
UNIVERSAL="${DEVSHOP_UNIVERSAL:-0}"
# Ad-hoc is enough to launch on this Mac. The notary service accepts no other kind of signature
# than Developer ID, so a release must override this.
IDENTITY="${DEVSHOP_SIGN_IDENTITY:--}"

# Must match Package.swift's platforms line, or the two slices get different deployment targets.
DEPLOY="15.0"

# One source of truth for the version the user sees, the DMG filename and the git tag.
[ -f VERSION ] || { echo "missing VERSION file" >&2; exit 1; }
VERSION="$(tr -d '[:space:]' < VERSION)"
# CFBundleVersion only has to increase between releases. The commit count does that on its own,
# so there is no second number to remember to bump. A tarball with no git history still builds.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# SwiftPM writes each triple to its own directory. The .build/release symlink follows whichever
# triple was built last, so a universal build must never read through it.
HOST_ARCH="$(uname -m)"
ARM_DIR=".build/arm64-apple-macosx/$CONFIG"
X86_DIR=".build/x86_64-apple-macosx/$CONFIG"
HOST_DIR=".build/$HOST_ARCH-apple-macosx/$CONFIG"

if [ "$UNIVERSAL" = "1" ]; then
  echo "building arm64…"
  swift build -c "$CONFIG" --triple "arm64-apple-macosx$DEPLOY"
  echo "building x86_64…"
  swift build -c "$CONFIG" --triple "x86_64-apple-macosx$DEPLOY"
  RESOURCE_DIR="$ARM_DIR"
else
  swift build -c "$CONFIG"
  RESOURCE_DIR="$HOST_DIR"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [ "$UNIVERSAL" = "1" ]; then
  for bin in "$ARM_DIR/DevShop" "$X86_DIR/DevShop"; do
    [ -f "$bin" ] || { echo "missing $bin" >&2; exit 1; }
  done
  lipo -create "$ARM_DIR/DevShop" "$X86_DIR/DevShop" -output "$APP/Contents/MacOS/DevShop"
else
  [ -f "$HOST_DIR/DevShop" ] || { echo "missing $HOST_DIR/DevShop" >&2; exit 1; }
  cp "$HOST_DIR/DevShop" "$APP/Contents/MacOS/DevShop"
fi

# Local symbols are two thirds of the linked binary and nothing at runtime reads them.
# Done before signing, because stripping afterwards would invalidate the signature. Crash
# reports still symbolicate from .build, which keeps the full binary and its debug info.
strip -x "$APP/Contents/MacOS/DevShop"

# SwiftPM emits resources as a sibling bundle. It travels in Contents/Resources: the standard
# place, and the only one codesign will seal — a bundle at the app root is refused outright with
# "unsealed contents present in the bundle root". Sources/DevShop/ResourceBundle.swift is what
# finds it there at runtime; Bundle.module cannot, and that is why it is not used.
# Both slices produce identical resource bundles, so either one will do.
shopt -s nullglob
BUNDLES=("$RESOURCE_DIR"/*.bundle)
shopt -u nullglob
[ ${#BUNDLES[@]} -gt 0 ] || { echo "error: no resource bundle in $RESOURCE_DIR" >&2; exit 1; }
for bundle in "${BUNDLES[@]}"; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

# Built by Scripts/make-icon.sh; committed so a plain `make app` needs no extra step.
# Both travel with the app: the bundle names the light one, and DockIcon swaps to the dark
# one at runtime when the window is dark.
for icon in DevShop DevShop-Dark; do
  if [ -f "Resources/$icon.icns" ]; then
    cp "Resources/$icon.icns" "$APP/Contents/Resources/$icon.icns"
  else
    echo "note: Resources/$icon.icns missing — run ./Scripts/make-icon.sh" >&2
  fi
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>DevShop</string>
  <key>CFBundleDisplayName</key><string>DevShop</string>
  <key>CFBundleExecutable</key><string>DevShop</string>
  <key>CFBundleIconFile</key><string>DevShop</string>
  <key>CFBundleIdentifier</key><string>com.lucianoarguello.devshop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSMinimumSystemVersion</key><string>$DEPLOY</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Read-only viewer. Brand marks from Simple Icons (CC0).</string>
</dict>
</plist>
PLIST

if [ "$IDENTITY" = "-" ]; then
  # Ad-hoc signature: enough for the app to launch locally without a developer identity.
  codesign --force --sign - "$APP" >/dev/null 2>&1 || \
    echo "note: ad-hoc signing failed; the app still runs" >&2
else
  # The notary service requires both of these alongside the Developer ID certificate: the
  # hardened runtime, and a timestamp countersigned by Apple's timestamp server.
  # https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

echo "built $APP ($VERSION build $BUILD, $(lipo -archs "$APP/Contents/MacOS/DevShop"))"
