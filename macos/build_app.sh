#!/bin/bash
# Builds "BillBox.app": the SwiftUI app + the server + its own copy of Node, all inside one app.
# Needs: Xcode or the Xcode command line tools, and an internet connection (once, to fetch Node and the server libraries).
# After this, the app runs on its own: no Node, no npm, no Terminal. Your books live in
# ~/Library/Application Support/DistributorPro/data and are not touched when you rebuild or replace the app.
#
#   ARCH=universal ./build_app.sh   one app for Apple silicon and Intel Macs (default: this Mac's own kind; also arm64, x64)
#   VERSION=15.2.0 ./build_app.sh   the version shown in Finder (GitHub releases set it from the tag)
set -e
cd "$(dirname "$0")"
HERE="$(pwd)"
APP="$HERE/BillBox.app"

VERSION="${VERSION:-15.7.0}"
case "${ARCH:-$(uname -m)}" in
  universal) ARCHS="arm64 x64" ;;
  arm64)     ARCHS="arm64" ;;
  x64|x86_64) ARCHS="x64" ;;
  *) echo "ARCH must be universal, arm64 or x64"; exit 1 ;;
esac

echo "1/4  Building the app for $ARCHS (this takes a few minutes the first time)..."
# each kind of Mac is built on its own (SwiftPM's normal build), then joined with lipo: SwiftPM's multi-arch mode goes
# through Xcode's build system, which newer Xcodes reject for this package
BINS=()
for a in $ARCHS; do
  t=$([ "$a" = x64 ] && echo x86_64 || echo arm64)
  swift build -c release --arch "$t"
  BINS+=("$(swift build -c release --arch "$t" --show-bin-path)/DistributorPro")
done
BIN="$HERE/.build/DistributorPro-$(echo $ARCHS | tr ' ' -)"
if [ "${#BINS[@]}" -gt 1 ]; then lipo -create "${BINS[@]}" -output "$BIN"; else cp "${BINS[0]}" "$BIN"; fi

echo "2/4  Getting Node.js 22..."
CACHE="$HERE/.runtime-cache"; mkdir -p "$CACHE"
fetch_node() {   # $1 = arm64 | x64 ; unpacks into $CACHE/node-$1
  local tgz; tgz=$(ls "$CACHE"/node-v22*-darwin-$1.tar.gz 2>/dev/null | tail -1 || true)
  if [ -z "$tgz" ]; then
    local name; name=$(curl -fsSL https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt | grep "darwin-$1.tar.gz" | awk '{print $2}' | head -1)
    [ -n "$name" ] || { echo "Could not find a Node 22 download. Check your internet connection."; exit 1; }
    curl -fSL --retry 4 "https://nodejs.org/dist/latest-v22.x/$name" -o "$CACHE/$name"
    tgz="$CACHE/$name"
  fi
  rm -rf "$CACHE/node-$1"; mkdir -p "$CACHE/node-$1"
  tar -xzf "$tgz" -C "$CACHE/node-$1" --strip-components=1
}
for a in $ARCHS; do fetch_node "$a"; done
rm -rf "$CACHE/node"
FIRST="${ARCHS%% *}"
cp -R "$CACHE/node-$FIRST" "$CACHE/node"
if [ "$ARCHS" = "arm64 x64" ]; then   # one Node that runs on both kinds of Mac
  lipo -create "$CACHE/node-arm64/bin/node" "$CACHE/node-x64/bin/node" -output "$CACHE/node/bin/node"
fi

echo "3/4  Packing the server..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/runtime" "$APP/Contents/Resources/backend"
cp "$BIN" "$APP/Contents/MacOS/DistributorPro"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$CACHE/node/bin/node" "$APP/Contents/Resources/runtime/node"
cp -R ../backend/src ../backend/package.json "$APP/Contents/Resources/backend/"
( cd "$APP/Contents/Resources/backend" && PATH="$CACHE/node/bin:$PATH" "$CACHE/node/bin/node" "$CACHE/node/lib/node_modules/npm/bin/npm-cli.js" install --omit=dev --no-audit --no-fund --loglevel=error )

# keep the books from an earlier run of the project (backend/data) the first time
DATA="$HOME/Library/Application Support/DistributorPro/data"
if [ -z "${CI:-}" ] && [ ! -d "$DATA" ] && [ -f ../backend/data/registry.db ]; then
  mkdir -p "$DATA" && cp ../backend/data/*.db "$DATA/" && echo "     copied your existing books into the app's data folder"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>BillBox</string>
  <key>CFBundleDisplayName</key><string>BillBox</string>
  <key>CFBundleIdentifier</key><string>com.local.billbox</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>DistributorPro</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER:-1}</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.business</string>
</dict></plist>
PLIST

echo "4/4  Signing for this Mac..."
xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo
echo "Done: $APP"
echo "Drag it to Applications, or double-click it here. To open: right-click > Open the first time if macOS asks."
