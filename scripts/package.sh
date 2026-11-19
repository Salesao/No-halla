#!/bin/bash
# Build No-halla (universal, Release, ad-hoc) and package installable artifacts:
#   dist/No-halla-<version>.dmg  — styled drag-to-Applications disk image
#   dist/No-halla-<version>.zip  — zipped app bundle
#   dist/SHA256SUMS.txt
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

APP="build/Build/Products/Release/No-halla.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DIST="dist"
NAME="No-halla-$VERSION"
VOLNAME="No-halla $VERSION"
mkdir -p "$DIST"
WORK_DIR="$(mktemp -d "$DIST/.package.XXXXXX")"
STAGE="$WORK_DIR/stage"
RW_IMAGE="$WORK_DIR/read-write.dmg"
BACKGROUND="$WORK_DIR/background.png"
MOUNT_POINT=""
cleanup() {
  if [ -n "$MOUNT_POINT" ] && mount | grep -Fq " on $MOUNT_POINT "; then
    if ! hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1; then
      echo "package: could not detach $MOUNT_POINT; keeping $WORK_DIR" >&2
      return
    fi
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/No-halla.app"
ln -s /Applications "$STAGE/Applications"

# Keep the picture inside the app bundle so no background folder is visible.
# Adding it changes the bundle, so sign the staged copy again.
swift scripts/dmg-background.swift "$BACKGROUND"
cp "$BACKGROUND" "$STAGE/No-halla.app/Contents/Resources/dmg-background.png"
codesign --force --sign - --options runtime --preserve-metadata=entitlements "$STAGE/No-halla.app"
codesign --verify --deep --strict "$STAGE/No-halla.app"

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW_IMAGE" >/dev/null
MOUNT_POINT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_IMAGE" | awk -F'\t' 'END { print $NF }')"
if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
  echo "package: cannot mount the read-write image" >&2
  exit 1
fi
MOUNTED_NAME="$(basename "$MOUNT_POINT")"

# Finder must be available and allow automation so the layout can be saved.
if ! osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$MOUNTED_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 548}
        set vo to the icon view options of container window
        set arrangement of vo to not arranged
        set icon size of vo to 128
        set text size of vo to 12
        set background color of vo to {62965, 62965, 61937}
        set bg to (POSIX file "$MOUNT_POINT/No-halla.app/Contents/Resources/dmg-background.png") as alias
        set background picture of vo to bg
        set position of item "No-halla.app" of container window to {160, 140}
        set position of item "Applications" of container window to {440, 140}
        try
            set position of item ".fseventsd" of container window to {700, 500}
        end try
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT
then
  echo "package: Finder layout failed; allow Finder automation and retry" >&2
  exit 1
fi

if [ ! -f "$MOUNT_POINT/.DS_Store" ]; then
  echo "package: Finder layout was not saved" >&2
  exit 1
fi

sync
hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNT_POINT=""

hdiutil convert "$RW_IMAGE" -format UDZO -imagekey zlib-level=9 -o "$WORK_DIR/$NAME.dmg" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$STAGE/No-halla.app" "$WORK_DIR/$NAME.zip"
mv -f "$WORK_DIR/$NAME.dmg" "$DIST/$NAME.dmg"
mv -f "$WORK_DIR/$NAME.zip" "$DIST/$NAME.zip"

shasum -a 256 "$DIST/$NAME.dmg" "$DIST/$NAME.zip" > "$DIST/SHA256SUMS.txt"
cat "$DIST/SHA256SUMS.txt"
ls -lh "$DIST/$NAME.dmg" "$DIST/$NAME.zip"
