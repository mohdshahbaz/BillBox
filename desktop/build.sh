#!/bin/bash
# Builds BillBox for Linux or Windows: the Flutter desktop app (frontend/) with the books engine beside it
# (Node.js 22 + backend/src, the same engine as the Mac app). Run on the matching system (GitHub Actions does both):
#
#   desktop/build.sh linux   15.8.0     ->  dist/BillBox-linux-15.8.0-x64.tar.gz, dist/BillBox-linux-15.8.0-amd64.deb
#   desktop/build.sh windows 15.8.0     ->  dist/BillBox-windows-15.8.0-x64.zip,  dist/BillBox-windows-15.8.0-setup.exe
#
# Needs: Flutter (stable), Node.js 22 with npm; on Linux the GTK build tools; on Windows Visual Studio's C++ tools and
# Inno Setup (for the installer). The licence edition is chosen with EDITION=public (default) or EDITION=admin.
set -euo pipefail
OS="${1:?linux or windows}"; VERSION="${2:-0.0.0}"; EDITION="${EDITION:-public}"
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"; FE="$ROOT/frontend"; DIST="$ROOT/dist"
mkdir -p "$DIST"
say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

say "Flutter runner for $OS"
cd "$FE"
if [ ! -d "$OS" ]; then
  tmp="$(mktemp -d)"; cp -R lib "$tmp/lib"; cp pubspec.yaml "$tmp/pubspec.yaml"
  flutter create --platforms="$OS" --project-name distributor_pro --org com.akenterprises . >/dev/null
  rm -rf lib && cp -R "$tmp/lib" lib && cp "$tmp/pubspec.yaml" pubspec.yaml && rm -rf test
fi
# the app's name, window title and icon
if [ "$OS" = linux ]; then
  sed -i 's/set(BINARY_NAME "distributor_pro")/set(BINARY_NAME "billbox")/; s/set(APPLICATION_ID "[^"]*")/set(APPLICATION_ID "com.akenterprises.billbox")/' linux/CMakeLists.txt
  sed -i 's/"distributor_pro"/"BillBox"/g' linux/runner/my_application.cc 2>/dev/null || sed -i 's/"distributor_pro"/"BillBox"/g' linux/my_application.cc
else
  sed -i 's/set(BINARY_NAME "distributor_pro")/set(BINARY_NAME "BillBox")/' windows/CMakeLists.txt
  sed -i 's/L"distributor_pro"/L"BillBox"/' windows/runner/main.cpp
  sed -i 's/"FileDescription", "distributor_pro"/"FileDescription", "BillBox"/; s/"ProductName", "distributor_pro"/"ProductName", "BillBox"/; s/"CompanyName", "[^"]*"/"CompanyName", "AK Enterprises"/; s/"OriginalFilename", "distributor_pro.exe"/"OriginalFilename", "BillBox.exe"/; s/"InternalName", "distributor_pro"/"InternalName", "BillBox"/' windows/runner/Runner.rc
  [ -f "$HERE/billbox.ico" ] && cp "$HERE/billbox.ico" windows/runner/resources/app_icon.ico
fi

say "Dart packages and checks"
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings lib

say "Build ($OS, $EDITION edition)"
NUM="${VERSION%%-*}"
# --split-debug-info keeps Dart's debug symbols out of the app (a smaller download, same code); --tree-shake-icons keeps
# only the icons BillBox uses
flutter build "$OS" --release --build-name="$NUM" --build-number="$(echo "$NUM" | awk -F. '{print $1*10000+$2*100+$3}')" \
  --split-debug-info="$FE/build/debug-info" --tree-shake-icons \
  --dart-define=BILLBOX_EDITION="$EDITION" --dart-define=BILLBOX_VERSION="$VERSION"
if [ "$OS" = linux ]; then APP="$FE/build/linux/x64/release/bundle"; else APP="$FE/build/windows/x64/runner/Release"; fi

say "Engine (Node.js $(node --version) + backend/src)"
ENG="$APP/engine"; rm -rf "$ENG"; mkdir -p "$ENG/backend"
cp -R "$ROOT/backend/src" "$ENG/backend/src"
cp "$ROOT/backend/package.json" "$ENG/backend/"
[ -f "$ROOT/backend/package-lock.json" ] && cp "$ROOT/backend/package-lock.json" "$ENG/backend/"
(cd "$ENG/backend" && npm install --omit=dev --no-audit --no-fund >/dev/null)
# the libraries' docs, tests and type files are not needed to run
find "$ENG/backend/node_modules" \( -iname "*.md" -o -iname "*.markdown" -o -iname "*.ts" -o -iname "*.map" -o -iname "CHANGELOG*" \) -type f -delete 2>/dev/null || true
find "$ENG/backend/node_modules" -type d \( -name test -o -name tests -o -name docs -o -name example -o -name examples -o -name .github \) -prune -exec rm -rf {} + 2>/dev/null || true
NODE_BIN="$(command -v node)"
if [ "$OS" = windows ]; then cp "$(cygpath -u "$(node -p 'process.execPath')" 2>/dev/null || node -p 'process.execPath')" "$ENG/node.exe"; else cp "$NODE_BIN" "$ENG/node"; chmod +x "$ENG/node"; strip --strip-unneeded "$ENG/node" 2>/dev/null || true; fi
cp "$ROOT/LICENSE" "$APP/" 2>/dev/null || true

say "Package"
if [ "$OS" = linux ]; then
  install -Dm644 "$ROOT/macos/Icon/AppIcon.png" "$APP/data/billbox.png"
  STAGE="$(mktemp -d)/BillBox"; mkdir -p "$STAGE"; cp -R "$APP"/. "$STAGE/"
  cat > "$STAGE/install.sh" <<'SH'
#!/bin/sh
# Adds BillBox to the applications menu for this user (no root needed).
D="$(cd "$(dirname "$0")" && pwd)"
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/billbox.desktop <<DESK
[Desktop Entry]
Name=BillBox
Comment=FMCG distributor billing, stock, GST and accounts
Exec="$D/billbox"
Icon=$D/data/billbox.png
Terminal=false
Type=Application
Categories=Office;Finance;
DESK
echo "BillBox added to the applications menu."
SH
  chmod +x "$STAGE/install.sh"
  tar -C "$(dirname "$STAGE")" -czf "$DIST/BillBox-linux-$VERSION-x64.tar.gz" BillBox
  # .deb: /opt/billbox + menu entry + /usr/bin/billbox
  DEB="$(mktemp -d)"; mkdir -p "$DEB/DEBIAN" "$DEB/opt/billbox" "$DEB/usr/share/applications" "$DEB/usr/bin" "$DEB/usr/share/icons/hicolor/512x512/apps"
  cp -R "$APP"/. "$DEB/opt/billbox/"
  ln -s /opt/billbox/billbox "$DEB/usr/bin/billbox"
  cp "$ROOT/macos/Icon/AppIcon.png" "$DEB/usr/share/icons/hicolor/512x512/apps/billbox.png"
  printf '[Desktop Entry]\nName=BillBox\nComment=FMCG distributor billing, stock, GST and accounts\nExec=/opt/billbox/billbox\nIcon=billbox\nTerminal=false\nType=Application\nCategories=Office;Finance;\n' > "$DEB/usr/share/applications/billbox.desktop"
  cat > "$DEB/DEBIAN/control" <<CTL
Package: billbox
Version: $NUM
Section: office
Priority: optional
Architecture: amd64
Depends: libgtk-3-0, libstdc++6
Maintainer: AK Enterprises <mohdshabaz12@gmail.com>
Description: BillBox - FMCG distributor billing software
 Billing with batches and expiry, purchases, stock, parties and ledgers, salesmen, GST reports,
 Marg-style printing and backups (also to Google Drive). The same books as BillBox on Mac, iPhone and Android.
CTL
  dpkg-deb --root-owner-group --build "$DEB" "$DIST/BillBox-linux-$VERSION-amd64.deb" >/dev/null
else
  (cd "$APP" && 7z a -tzip "$(cygpath -w "$DIST/BillBox-windows-$VERSION-x64.zip" 2>/dev/null || echo "$DIST/BillBox-windows-$VERSION-x64.zip")" . >/dev/null)
  ISCC="$(command -v iscc || true)"; [ -z "$ISCC" ] && [ -f "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" ] && ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
  if [ -n "$ISCC" ]; then
    "$ISCC" //Q "//DAppVersion=$VERSION" "//DAppDir=$(cygpath -w "$APP")" "//DOutDir=$(cygpath -w "$DIST")" "$(cygpath -w "$HERE/billbox.iss")"
  else
    echo "Inno Setup not found: only the .zip was made."
  fi
fi
ls -la "$DIST"
