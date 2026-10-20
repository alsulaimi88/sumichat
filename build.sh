#!/bin/bash
# Builds build/SumiChat.app for Apple silicon and Intel Macs.
#   ./build.sh            signed for this Mac only
#   ./build.sh install    also copies it to /Applications
# release.sh sets SIGN_IDENTITY to your "Developer ID Application" certificate so it opens on any Mac.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SumiChat"
ICON_STYLE="${ICON_STYLE:-garden}"  # any style listed at the top of tools/make_icon.swift
SIGN_IDENTITY="${SIGN_IDENTITY:--}"     # "-" means ad-hoc (this Mac only)
BUILD="build"
APP="$BUILD/$APP_NAME.app"

# App icon (generated once; delete Resources/AppIcon.icns to redraw it)
if [ ! -f Resources/AppIcon.icns ]; then
  ICONSET="$BUILD/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift tools/make_icon.swift "$ICON_STYLE" "$BUILD/icon_1024.png"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
    -parse-as-library Sources/*.swift -o "$BUILD/$APP_NAME-$arch"
done
lipo -create "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Hardened runtime + entitlements are what Apple's notarization requires.
SIGN_ARGS=(--force --options runtime --entitlements Resources/SumiChat.entitlements --sign "$SIGN_IDENTITY")
[ "$SIGN_IDENTITY" = "-" ] || SIGN_ARGS+=(--timestamp)
codesign "${SIGN_ARGS[@]}" "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  echo "Installed /Applications/$APP_NAME.app"
fi
