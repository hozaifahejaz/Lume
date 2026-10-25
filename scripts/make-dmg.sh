#!/bin/bash
# Builds Lume for one architecture and packs it into a drag-to-Applications disk image.
# Usage: scripts/make-dmg.sh arm64|x86_64 [output.dmg]
set -euo pipefail

cd "$(dirname "$0")/.."
ARCH="${1:?usage: make-dmg.sh arm64|x86_64 [output.dmg]}"
case "$ARCH" in
    arm64) NAME="Lume-AppleSilicon.dmg" ;;
    x86_64) NAME="Lume-Intel.dmg" ;;
    *) echo "Unknown architecture: $ARCH" >&2; exit 1 ;;
esac
OUT="${2:-build/$NAME}"

ARCH="$ARCH" bash scripts/build-app.sh

# The image holds the app and a shortcut to Applications to drag it onto.
STAGE="build/$ARCH/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "build/$ARCH/Lume.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create -volname "Lume" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null
rm -rf "$STAGE"
echo "Made $OUT"
