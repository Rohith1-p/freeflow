#!/bin/bash
# Build the drag-to-install DMG for Freeflow.
# Usage: scripts/build-dmg.sh <version>   (expects a signed+stapled /Applications/Freeflow.app)
set -e
VERSION="${1:?version required, e.g. 2.0.3}"
OUT="/tmp/Freeflow-v${VERSION}.dmg"
SRC=/tmp/dmg_src
BG=/tmp/dmg-background.png

swift "$(dirname "$0")/dmg-background.swift"          # renders $BG
rm -rf "$SRC" "$OUT" && mkdir -p "$SRC"
cp -R /Applications/Freeflow.app "$SRC/"

create-dmg \
  --volname "Freeflow" \
  --background "$BG" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 104 \
  --icon "Freeflow.app" 165 185 \
  --app-drop-link 495 185 \
  --hide-extension "Freeflow.app" \
  --no-internet-enable \
  "$OUT" "$SRC"

xcrun notarytool submit "$OUT" --keychain-profile freeflow-notary --wait
xcrun stapler staple "$OUT"
echo "✓ $OUT"
