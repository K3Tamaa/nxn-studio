#!/bin/bash
# Build NXN Studio.app into dist/ (arm64, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/NXN Studio.app"
BIN=".build/release/NXNStudio"

echo "▸ Compilation release…"
swift build -c release

echo "▸ Icône…"
mkdir -p Resources build/AppIcon.iconset
if [ ! -f Resources/icon-1024.png ]; then
  swift build >/dev/null
  .build/debug/NXNStudio --make-icon Resources/icon-1024.png
fi
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
            "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" Resources/icon-1024.png --out "build/AppIcon.iconset/$2.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

echo "▸ Assemblage du bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NXNStudio"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

VERSION="${VERSION:-$(cat VERSION 2>/dev/null || echo 1.0.0)}"
BUILD="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD" "$APP/Contents/Info.plist"
# Feuille de mise à jour par défaut du projet (surchargée par UPDATE_FEED).
UPDATE_FEED="${UPDATE_FEED:-https://github.com/K3Tamaa/nxn-studio/releases/latest/download/latest.json}"
[ -n "${UPDATE_FEED:-}" ] && plutil -replace NXNUpdateFeed -string "$UPDATE_FEED" "$APP/Contents/Info.plist"
if [ -z "${UPDATE_PUBLIC_KEY:-}" ] && [ -f "$HOME/.nxnstudio/update-keypair.txt" ]; then
  UPDATE_PUBLIC_KEY=$(grep '^public=' "$HOME/.nxnstudio/update-keypair.txt" | cut -d= -f2-)
fi
[ -n "${UPDATE_PUBLIC_KEY:-}" ] && plutil -replace NXNUpdatePublicKey -string "$UPDATE_PUBLIC_KEY" "$APP/Contents/Info.plist"
echo "  version $VERSION ($BUILD)"

echo "▸ Symboles de crash…"
mkdir -p dist
rm -rf "dist/NXN Studio.dSYM"
dsymutil "$BIN" -o "dist/NXN Studio.dSYM" >/dev/null 2>&1 || echo "  (dSYM indisponible)"

echo "▸ Signature…"
if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$APP"
else
  codesign --force --sign - "$APP" >/dev/null
fi

echo "▸ DMG…"
STAGE="build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "dist/NXN Studio $VERSION.dmg"
hdiutil create -quiet -volname "NXN Studio" -srcfolder "$STAGE" \
  -ov -format UDZO "dist/NXN Studio $VERSION.dmg"

echo "✓ $APP"
echo "✓ dist/NXN Studio $VERSION.dmg"
echo "  Ouvrir : open \"$APP\""
