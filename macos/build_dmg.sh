#!/bin/bash
# Makes BillBox-<version>.dmg: open it and drag BillBox to Applications (the usual Mac installer).
#   ./build_dmg.sh                       builds BillBox.app first if needed (for this Mac's kind; ARCH=universal for both)
#   VERSION=15.4.0 ARCH=universal ./build_dmg.sh
set -e
cd "$(dirname "$0")"
VERSION="${VERSION:-$(sed -n 's/^VERSION="\${VERSION:-\(.*\)}"$/\1/p' build_app.sh)}"
[ -d BillBox.app ] && [ -z "${REBUILD:-}" ] || ./build_app.sh
OUT="${OUT:-$PWD/BillBox-$VERSION.dmg}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto BillBox.app "$STAGE/BillBox.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read me.txt" <<TXT
BillBox $VERSION

1. Drag BillBox onto the Applications folder.
2. The first time: right-click BillBox in Applications and choose Open (it is not from the App Store).

Your books are kept in ~/Library/Application Support/DistributorPro/data and are not touched when BillBox is replaced.
TXT
rm -f "$OUT"
hdiutil create -volname "BillBox $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null
echo "Made $OUT"
