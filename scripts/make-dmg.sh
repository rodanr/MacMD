#!/usr/bin/env bash
# Packages MacMD.app into a compressed, drag-to-install DMG.
# Usage: scripts/make-dmg.sh <path/to/MacMD.app> <output directory>
set -euo pipefail

APP="${1:?path to MacMD.app}"
OUT_DIR="${2:?output directory}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT_DIR/MacMD-$VERSION.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP" "$STAGING/MacMD.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$OUT_DIR"
rm -f "$DMG"
hdiutil create -quiet -volname "MacMD $VERSION" -srcfolder "$STAGING" -fs APFS -format ULFO "$DMG"
shasum -a 256 "$DMG" | sed "s|$OUT_DIR/||" > "$DMG.sha256"

echo "$DMG"
