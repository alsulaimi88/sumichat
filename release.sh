#!/bin/bash
# Makes a release that opens on any Mac without "unidentified developer" warnings:
# signs with your Developer ID certificates, has Apple notarize it, and staples the result.
#
#   ./release.sh            -> dist/SumiChat.dmg, .pkg and the update .zip, signed and notarized
#   ./release.sh --publish  also uploads them to GitHub as release v<version> and adds the
#                           release to the update feed (docs/appcast.xml), so installed copies
#                           offer the one-click update
#
# One-time setup (Apple Developer account, certificates, notary login): see RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SumiChat"
NOTARY_PROFILE="${NOTARY_PROFILE:-sumichat-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Resources/Info.plist)"
SPARKLE_ACCOUNT="sumichat"  # name of the update signing key in your keychain (made by generate_keys)

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

xmllint --noout docs/appcast.xml || fail "docs/appcast.xml isn't valid XML, so installed copies couldn't read it. Fix it first."

# Sparkle decides what's newer by CFBundleVersion, so it must go up every release.
LAST_BUILD="$(grep -o '<sparkle:version>[0-9]*' docs/appcast.xml | grep -o '[0-9]*$' | sort -n | tail -1 || true)"
if [ -n "$LAST_BUILD" ] && [ "$BUILD_NUMBER" -le "$LAST_BUILD" ]; then
  fail "CFBundleVersion is $BUILD_NUMBER but the update feed already has $LAST_BUILD. Raise it in Resources/Info.plist."
fi

if [ "${1:-}" = "--publish" ]; then
  gh release view "v$VERSION" >/dev/null 2>&1 \
    && fail "Release v$VERSION already exists on GitHub. Raise the version in Resources/Info.plist first."
  [ -z "$(git status --porcelain)" ] || fail "Commit your changes first, so the release matches the code on GitHub."
fi

echo "Releasing SumiChat $VERSION (build $BUILD_NUMBER)"
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

# The archive Sparkle downloads for one-click updates, signed with the update key.
UPDATE_ZIP="dist/$APP_NAME-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "build/$APP_NAME.app" "$UPDATE_ZIP"
SPARKLE_BIN="$(ls -d vendor/Sparkle-*/bin | tail -1)"
UPDATE_SIGNATURE="$("$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$UPDATE_ZIP")" \
  || fail "Couldn't sign the update with the \"$SPARKLE_ACCOUNT\" key. See RELEASING.md."

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
  REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
  gh release create "v$VERSION" "dist/$APP_NAME.dmg" "dist/$APP_NAME.pkg" "$UPDATE_ZIP" \
    --title "SumiChat $VERSION" --generate-notes

  # Add this release to the update feed, newest first, and publish the feed with the website.
  ITEM="build/appcast-item.xml"
  cat > "$ITEM" <<EOF
    <item>
      <title>SumiChat $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/$(basename "$UPDATE_ZIP")" $UPDATE_SIGNATURE type="application/octet-stream"/>
    </item>
EOF
  sed -i '' "/<!-- releases -->/r $ITEM" docs/appcast.xml
  xmllint --noout docs/appcast.xml || fail "The new update feed isn't valid XML; not publishing it."
  git add docs/appcast.xml
  git commit -q -m "Add SumiChat $VERSION to the update feed"
  git push -q
  echo "Update feed published: installed copies will offer $VERSION within a day."
fi

echo
echo "Done: SumiChat $VERSION is signed and notarized."
