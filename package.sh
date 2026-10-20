#!/bin/bash
# Builds the app, then packages it as:
#   dist/SumiChat.pkg   step-by-step installer that puts it in /Applications
#   dist/SumiChat.dmg   disk image to drag into Applications
# On its own this makes files for testing. release.sh calls it with your Apple
# certificates (APP_IDENTITY, INSTALLER_IDENTITY) and SKIP_BUILD=1.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SumiChat"
BUNDLE_ID="com.sumi.chat"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
STAGE="build/package"
DIST="dist"

[ "${SKIP_BUILD:-}" = 1 ] || ./build.sh

rm -rf "$STAGE" "$DIST" && mkdir -p "$STAGE/root" "$STAGE/dmg" "$DIST"
chmod +x installer/scripts/*

# --- .pkg installer ---
cp -R "build/$APP_NAME.app" "$STAGE/root/"

# Always install into /Applications (otherwise Installer may "update" some other copy it finds).
pkgbuild --analyze --root "$STAGE/root" "$STAGE/components.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$STAGE/components.plist"

pkgbuild \
  --root "$STAGE/root" \
  --component-plist "$STAGE/components.plist" \
  --install-location /Applications \
  --scripts installer/scripts \
  --identifier "$BUNDLE_ID" \
  --version "$VERSION" \
  "$STAGE/$APP_NAME-component.pkg"

cat > "$STAGE/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>$APP_NAME $VERSION</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true"/>
    <os-version min="13.0"/>
    <choices-outline>
        <line choice="default"/>
    </choices-outline>
    <choice id="default" title="$APP_NAME">
        <pkg-ref id="$BUNDLE_ID"/>
    </choice>
    <pkg-ref id="$BUNDLE_ID" version="$VERSION" onConclusion="none">$APP_NAME-component.pkg</pkg-ref>
</installer-gui-script>
EOF

PKG_SIGN=()
[ -z "${INSTALLER_IDENTITY:-}" ] || PKG_SIGN=(--sign "$INSTALLER_IDENTITY" --timestamp)
productbuild ${PKG_SIGN[@]+"${PKG_SIGN[@]}"} \
  --distribution "$STAGE/distribution.xml" \
  --resources installer \
  --package-path "$STAGE" \
  "$DIST/$APP_NAME.pkg"

# --- .dmg ---
cp -R "build/$APP_NAME.app" "$STAGE/dmg/"
ln -s /Applications "$STAGE/dmg/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE/dmg" -ov -format UDZO "$DIST/$APP_NAME.dmg" >/dev/null
[ -z "${APP_IDENTITY:-}" ] || codesign --sign "$APP_IDENTITY" --timestamp "$DIST/$APP_NAME.dmg"

echo
echo "SumiChat $VERSION"
echo "  Installer:  $DIST/$APP_NAME.pkg"
echo "  Disk image: $DIST/$APP_NAME.dmg"
