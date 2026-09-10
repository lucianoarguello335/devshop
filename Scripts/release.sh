#!/bin/bash
# Builds a signed, notarized, stapled DevShop.dmg ready to attach to a GitHub release.
#
# Usage:
#   ./Scripts/release.sh                 full release: universal, Developer ID, notarized
#   ./Scripts/release.sh --dry-run       everything except signing and notarization
#   ./Scripts/release.sh --skip-notarize sign, but stop before the round trip to Apple
#
# Environment:
#   DEVSHOP_SIGN_IDENTITY   overrides certificate auto-detection
#   DEVSHOP_NOTARY_PROFILE  keychain profile from `notarytool store-credentials` (default:
#                           devshop-notary)
set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
NOTARIZE=1
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1; NOTARIZE=0 ;;
    --skip-notarize) NOTARIZE=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

VERSION="$(tr -d '[:space:]' < VERSION)"
PROFILE="${DEVSHOP_NOTARY_PROFILE:-devshop-notary}"
DMG="dist/DevShop-$VERSION.dmg"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# Submits one artefact and blocks until Apple answers. Apple's docs say to read the log even on
# success, because it can carry warnings that become errors in a later submission.
notarize() {
  local target="$1" log id
  log="$(mktemp)"
  # The pipeline is allowed to fail; the status line below is what decides.
  xcrun notarytool submit "$target" --keychain-profile "$PROFILE" --wait 2>&1 | tee "$log" || true
  id="$(sed -n 's/^ *id: \([0-9a-f-]*\)$/\1/p' "$log" | head -1)"
  if [ -n "$id" ]; then
    step "Notary log — $(basename "$target")"
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" 2>/dev/null || true
  fi
  if ! grep -q "status: Accepted" "$log"; then
    echo "error: notarization of $target did not succeed" >&2
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
}

# ---------------------------------------------------------------- preflight

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "warning: working tree is dirty — the release will not match any commit" >&2
fi

if [ "$DRY_RUN" = "1" ]; then
  IDENTITY="-"
else
  # Auto-detect so the certificate name never has to be typed. Developer ID is the only kind
  # the notary service accepts; an Apple Development certificate is silently rejected.
  IDENTITY="${DEVSHOP_SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" \
    | head -1 \
    | sed -n 's/.*"\(.*\)".*/\1/p')}"
  if [ -z "$IDENTITY" ]; then
    cat >&2 <<'MSG'
error: no "Developer ID Application" certificate in the keychain.

Create one in Xcode: Settings > Accounts > (your team) > Manage Certificates > + >
Developer ID Application. Then re-run. To build an unsigned image for testing, use:

  ./Scripts/release.sh --dry-run
MSG
    exit 1
  fi
fi

echo "version   $VERSION"
echo "identity  $IDENTITY"
echo "notarize  $([ "$NOTARIZE" = 1 ] && echo yes || echo no)"

# ---------------------------------------------------------------- build

step "Building universal app"
DEVSHOP_UNIVERSAL=1 DEVSHOP_SIGN_IDENTITY="$IDENTITY" ./Scripts/make-app.sh release

# Both slices must be present, or Intel users get an app that cannot launch at all. The
# website promises "Apple silicon or Intel", so this is a hard failure rather than a warning.
ARCHS="$(lipo -archs DevShop.app/Contents/MacOS/DevShop)"
case "$ARCHS" in
  *arm64*x86_64*|*x86_64*arm64*) echo "architectures: $ARCHS" ;;
  *) echo "error: expected a universal binary, got: $ARCHS" >&2; exit 1 ;;
esac

if [ "$DRY_RUN" = "0" ]; then
  step "Verifying signature"
  codesign --verify --deep --strict --verbose=2 DevShop.app
  # Confirms the two things the notary service checks that a plain --verify does not surface.
  codesign -d --verbose=4 DevShop.app 2>&1 | grep -E "^(Authority|TeamIdentifier|Timestamp|CodeDirectory)" || true
  codesign -d --entitlements - DevShop.app 2>&1 | grep -q "get-task-allow" \
    && { echo "error: get-task-allow entitlement present; notarization will fail" >&2; exit 1; }
fi

if [ "$NOTARIZE" = "1" ]; then
  # Pass one: notarize the app on its own and staple the ticket into the bundle. Without this
  # the app that the user drags out of the image carries no ticket, so its first launch needs a
  # round trip to Apple — and fails to open cleanly if that Mac happens to be offline.
  step "Notarizing the app (pass 1 of 2)"
  ZIP="$(mktemp -d)/DevShop.zip"
  # ditto is what Apple's docs specify; a plain `zip` loses symlinks and extended attributes.
  /usr/bin/ditto -c -k --keepParent DevShop.app "$ZIP"
  notarize "$ZIP"
  rm -rf "$(dirname "$ZIP")"

  step "Stapling the app"
  xcrun stapler staple DevShop.app
  xcrun stapler validate DevShop.app
  # Stapling writes into the bundle, so prove it did not disturb the seal before packaging it.
  codesign --verify --deep --strict DevShop.app
fi

step "Building disk image"
DEVSHOP_SIGN_IDENTITY="$IDENTITY" ./Scripts/make-dmg.sh

if [ "$NOTARIZE" = "1" ]; then
  # Pass two: the image itself, so that opening the download is clean as well.
  step "Notarizing the disk image (pass 2 of 2)"
  notarize "$DMG"

  step "Stapling the disk image"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"

  step "Gatekeeper assessment"
  # What the user's Mac actually decides when the image is opened.
  spctl -a -vvv -t open --context context:primary-signature "$DMG"
fi

# ---------------------------------------------------------------- summary

step "Done"
echo "artifact  $DMG"
echo "size      $(du -h "$DMG" | cut -f1)"
echo "sha256    $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo
echo "Next:"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "  gh release create v$VERSION $DMG --title \"DevShop $VERSION\" --notes-file <notes>"
