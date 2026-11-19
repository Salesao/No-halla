#!/bin/bash
# Build No-halla (universal, Release, ad-hoc) and package installable artifacts:
#   dist/No-halla-<version>.dmg  — drag-to-Applications disk image
#   dist/No-halla-<version>.zip  — zipped app bundle
#   dist/SHA256SUMS.txt
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

APP="build/Build/Products/Release/No-halla.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DIST="dist"
NAME="No-halla-$VERSION"
STAGE="$DIST/stage"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/No-halla.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/INSTALL.txt" <<'TXT'
No-halla
========

1. Drag No-halla.app to the Applications folder.
2. First launch: right-click No-halla → Open (the build is ad-hoc signed,
   not notarized, so Gatekeeper asks once).
   If macOS still blocks it, run in Terminal:
     xattr -dr com.apple.quarantine "/Applications/No-halla.app"

The optional domain guard (Settings → Protection → Blocked sites) needs a
one-time admin install; use the Install… button there.

TXT

rm -f "$DIST/$NAME.dmg" "$DIST/$NAME.zip"
hdiutil create -volname "No-halla $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$NAME.dmg" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/$NAME.zip"
rm -rf "$STAGE"

shasum -a 256 "$DIST/$NAME.dmg" "$DIST/$NAME.zip" > "$DIST/SHA256SUMS.txt"
cat "$DIST/SHA256SUMS.txt"
ls -lh "$DIST/$NAME.dmg" "$DIST/$NAME.zip"