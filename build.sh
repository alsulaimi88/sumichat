#!/bin/bash
# Builds build/SumiChat.app for Apple silicon and Intel Macs.
#   ./build.sh            signed for this Mac only
#   ./build.sh install    also copies it to /Applications
# release.sh sets SIGN_IDENTITY to your "Developer ID Application" certificate so it opens on any Mac.
# FEED_URL overrides where Sparkle looks for updates (used to test updates locally).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SumiChat"
ICON_STYLE="${ICON_STYLE:-garden}"  # any style listed at the top of tools/make_icon.swift
SIGN_IDENTITY="${SIGN_IDENTITY:--}"     # "-" means ad-hoc (this Mac only)
BUILD="build"
APP="$BUILD/$APP_NAME.app"

# Sparkle (one-click updates), downloaded once from its official GitHub release and checked.
SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
SPARKLE="vendor/Sparkle-$SPARKLE_VERSION"
if [ ! -d "$SPARKLE/Sparkle.framework" ]; then
  mkdir -p "$SPARKLE"
  curl -sSL -o "$SPARKLE.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "$SPARKLE_SHA256  $SPARKLE.tar.xz" | shasum -a 256 -c - >/dev/null || { echo "Sparkle download failed its checksum"; exit 1; }
  tar -xJf "$SPARKLE.tar.xz" -C "$SPARKLE"
fi

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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
    -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -parse-as-library Sources/*.swift -o "$BUILD/$APP_NAME-$arch"
done
lipo -create "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"

cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -z "${FEED_URL:-}" ] || /usr/libexec/PlistBuddy -c "Set :SUFeedURL $FEED_URL" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# Sign the inside first, then the app. Developer ID builds get the hardened runtime and a
# timestamp, which Apple's notarization requires; local ad-hoc builds skip both.
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
[ "$SIGN_IDENTITY" = "-" ] || SIGN_ARGS+=(--options runtime --timestamp)
sign() { codesign "${SIGN_ARGS[@]}" "$@"; }
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$FW/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
sign "$FW/Autoupdate"
sign "$FW/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements Resources/SumiChat.entitlements "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  echo "Installed /Applications/$APP_NAME.app"
fi
