#!/usr/bin/env bash
# Builds a release Warren.app and packages it into a DMG with a laid-out
# Finder window, a background and a volume icon.
#
#   scripts/make-dmg.sh
#
# Signing: set CODESIGN_IDENTITY to a "Developer ID Application: …" identity for
# a release anyone can open. Without it the app is signed ad hoc, which is fine
# for local use but will be refused by Gatekeeper on another Mac — see the
# README's Releasing section.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
BUILD="$ROOT/build"
STAGE="$BUILD/dmg"
DERIVED="$BUILD/DerivedData"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
VOLUME_NAME="Warren"

rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "==> Building Release"
xcodebuild build -scheme Warren -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO >/dev/null

APP="$DERIVED/Build/Products/Release/Warren.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$BUILD/Warren-$VERSION.dmg"
echo "    Warren $VERSION — $(lipo -info "$APP/Contents/MacOS/Warren" | sed 's/.*are: //')"

echo "==> Signing with: $CODESIGN_IDENTITY"
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/Warren/Warren.entitlements" \
  --sign "$CODESIGN_IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "==> Staging"
cp -R "$APP" "$STAGE/Warren.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"

# The background is generated rather than checked in as a binary: one TIFF
# holding @1x and @2x, so the Finder picks the right one on Retina.
swiftc -swift-version 5 -O "$ROOT/scripts/dmg-background.swift" -o "$BUILD/dmg-background" >/dev/null
"$BUILD/dmg-background" "$BUILD/background.tiff"
cp "$BUILD/background.tiff" "$STAGE/.background/background.tiff"

echo "==> Creating writable image"
RW="$BUILD/rw.dmg"
rm -f "$RW" "$DMG"
SIZE_KB=$(( $(du -sk "$STAGE" | cut -f1) + 40000 ))
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME_NAME" -fs HFS+ \
  -format UDRW -size "${SIZE_KB}k" "$RW" >/dev/null

MOUNT="/Volumes/$VOLUME_NAME"
hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
hdiutil attach "$RW" -mountpoint "$MOUNT" -nobrowse >/dev/null
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true' EXIT

echo "==> Laying out the window"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 520}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 104
        set text size of options to 12
        set background picture of options to file ".background:background.tiff"
        set position of item "Warren.app" of container window to {150, 205}
        set position of item "Applications" of container window to {450, 205}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# The volume icon has to be placed on the mounted image: hdiutil silently drops
# a .VolumeIcon.icns found in the -srcfolder.
cp "$APP/Contents/Resources/AppIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT"
sync

hdiutil detach "$MOUNT" >/dev/null
trap - EXIT

echo "==> Compressing"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"
hdiutil verify "$DMG" >/dev/null

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
