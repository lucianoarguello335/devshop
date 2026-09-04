#!/bin/bash
# Wraps the SwiftPM binary into DevShop.app.
#
# The package builds a plain executable; macOS needs a bundle for a proper Dock icon,
# menu bar and window behaviour. Everything here is deterministic, so the app can be
# rebuilt from a clean checkout with no Xcode project involved.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
BIN=".build/$CONFIG/DevShop"
APP="DevShop.app"

[ -f "$BIN" ] || { echo "missing $BIN — run: swift build -c $CONFIG" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DevShop"

# SwiftPM emits resources as a sibling bundle; Bundle.module looks for it next to the
# executable, so it has to travel with the binary.
for bundle in ".build/$CONFIG"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Built by Scripts/make-icon.sh; committed so a plain `make app` needs no extra step.
if [ -f Resources/DevShop.icns ]; then
  cp Resources/DevShop.icns "$APP/Contents/Resources/DevShop.icns"
else
  echo "note: Resources/DevShop.icns missing — run ./Scripts/make-icon.sh" >&2
fi

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
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Read-only viewer. Brand marks from Simple Icons (CC0).</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for the app to launch locally without a developer identity.
codesign --force --sign - "$APP" >/dev/null 2>&1 || \
  echo "note: ad-hoc signing failed; the app still runs" >&2

echo "built $APP"
