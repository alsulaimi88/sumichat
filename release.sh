#!/bin/bash
# Makes a release that opens on any Mac without "unidentified developer" warnings:
# signs with your Developer ID certificates, has Apple notarize it, and staples the result.
#
#   ./release.sh            -> dist/SumiChat.dmg and dist/SumiChat.pkg, signed and notarized
#   ./release.sh --publish  also uploads them to GitHub as release v<version>
#
# One-time setup (Apple Developer account, certificates, notary login): see RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SumiChat"
NOTARY_PROFILE="${NOTARY_PROFILE:-sumichat-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"

fail() { echo "✗ $*" >&2; exit 1; }

identity() {
  security find-identity -v | grep -o "\"$1: [^\"]*\"" | head -1 | tr -d '"' || true
}

# --- Check the one-time setup ---
APP_IDENTITY="${APP_IDENTITY:-$(identity "Developer ID Application")}"
INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-$(identity "Developer ID Installer")}"
[ -n "$APP_IDENTITY" ]       || fail "No \"Developer ID Application\" certificate in your keychain. See RELEASING.md, step 2."
[ -n "$INSTALLER_IDENTITY" ] || fail "No \"Developer ID Installer\" certificate in your keychain. See RELEASING.md, step 2."
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "No saved notary login called \"$NOTARY_PROFILE\". See RELEASING.md, step 3."

if [ "${1:-}" = "--publish" ]; then
  gh release view "v$VERSION" >/dev/null 2>&1 \
    && fail "Release v$VERSION already exists on GitHub. Raise the version in Resources/Info.plist first."
fi

echo "Releasing SumiChat $VERSION"
echo "  App signed by:       $APP_IDENTITY"
echo "  Installer signed by: $INSTALLER_IDENTITY"
echo

notarize() {
  echo "→ Sending $(basename "$1") to Apple for notarization (usually 1–5 minutes)…"
  local result="build/notary-result.json"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$result" || true
  local status id
  status="$(plutil -extract status raw "$result" 2>/dev/null || true)"
  if [ "$status" != "Accepted" ]; then
    cat "$result"
    id="$(plutil -extract id raw "$result" 2>/dev/null || true)"
    [ -z "$id" ] || xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE"
    fail "Apple did not accept $(basename "$1") (status: ${status:-unknown}). The log above says why."
  fi
  echo "  Accepted."
}

# 1. Build and sign the app, then notarize it and staple the ticket to it.
SIGN_IDENTITY="$APP_IDENTITY" ./build.sh
ditto -c -k --keepParent "build/$APP_NAME.app" "build/$APP_NAME.zip"
notarize "build/$APP_NAME.zip"
xcrun stapler staple -q "build/$APP_NAME.app"

# 2. Package the notarized app, then notarize and staple the installer and the disk image.
SKIP_BUILD=1 APP_IDENTITY="$APP_IDENTITY" INSTALLER_IDENTITY="$INSTALLER_IDENTITY" ./package.sh
for file in "dist/$APP_NAME.pkg" "dist/$APP_NAME.dmg"; do
  notarize "$file"
  xcrun stapler staple -q "$file"
done

# 3. Ask Gatekeeper what a downloaded copy will see.
echo
echo "Gatekeeper check:"
spctl --assess --type execute "build/$APP_NAME.app" || fail "Gatekeeper rejected the app."
echo "  App:        accepted"
spctl --assess --type install "dist/$APP_NAME.pkg" || fail "Gatekeeper rejected the installer."
echo "  Installer:  accepted"
spctl --assess --type open --context context:primary-signature "dist/$APP_NAME.dmg" || fail "Gatekeeper rejected the disk image."
echo "  Disk image: accepted"

# 4. Optionally publish to GitHub.
if [ "${1:-}" = "--publish" ]; then
  echo
  gh release create "v$VERSION" "dist/$APP_NAME.dmg" "dist/$APP_NAME.pkg" \
    --title "SumiChat $VERSION" --generate-notes
fi

echo
echo "Done: SumiChat $VERSION is signed and notarized."
