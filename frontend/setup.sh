#!/usr/bin/env bash
# One-time setup: generates the macOS runner around the Dart code in lib/, then sets the macOS permissions
# this app needs (network to the local API, printing, folder picker).
set -e
cd "$(dirname "$0")"

command -v flutter >/dev/null || { echo "Flutter not found. Install it first: https://docs.flutter.dev/get-started/install/macos/desktop"; exit 1; }

# 'flutter create' must not overwrite our code, so stash it and put it back afterwards.
tmp=$(mktemp -d)
cp -R lib "$tmp/lib"
cp pubspec.yaml "$tmp/pubspec.yaml"
flutter create --platforms=macos --project-name distributor_pro --org com.example .
rm -rf lib && cp -R "$tmp/lib" lib
cp "$tmp/pubspec.yaml" pubspec.yaml
rm -f test/widget_test.dart

# A sandboxed macOS app is blocked from these unless it asks:
#   network.client                 -> talk to the local API (otherwise "Cannot reach the server")
#   print                          -> print and list printers
#   files.user-selected.read-write -> the PDF and backup-folder pickers, and saving Excel exports
for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
  for key in com.apple.security.network.client com.apple.security.print com.apple.security.files.user-selected.read-only com.apple.security.files.user-selected.read-write; do
    /usr/libexec/PlistBuddy -c "Add :$key bool true" "$f" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :$key true" "$f"
  done
done

# The printing plugin needs macOS 10.15 or newer.
[ -f macos/Podfile ] && sed -i '' -E "s/platform :osx, '10\.(1[0-4])'/platform :osx, '10.15'/" macos/Podfile || true
[ -f macos/Runner.xcodeproj/project.pbxproj ] && sed -i '' -E 's/MACOSX_DEPLOYMENT_TARGET = 10\.1[0-4];/MACOSX_DEPLOYMENT_TARGET = 10.15;/g' macos/Runner.xcodeproj/project.pbxproj || true

flutter pub get
echo
echo "Setup complete. Start the backend, then run:  flutter run -d macos"
