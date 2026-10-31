#!/bin/bash
# Type-checks the Mac app's Swift sources on Linux, against the iOS SwiftUI/UIKit stubs plus the AppKit stub here.
# Catches type errors in Mac edits made without a Mac at hand. It does not replace building in Xcode / swift build on a Mac.
set -e
export PATH=/opt/swift/swift-wasm-6.0.2-RELEASE/usr/bin:$PATH
HERE="$(cd "$(dirname "$0")" && pwd)"
IOS_STUBS="$HERE/../../../ios/tests/typecheck/stubs"
OUT="$HERE/.mods"
mkdir -p "$OUT"
"$IOS_STUBS/build.sh" >/dev/null 2>&1 || true            # builds the shared stub modules
cp "$IOS_STUBS/../.mods/"*.swiftmodule "$OUT/" 2>/dev/null || true
swiftc -swift-version 5 -parse-as-library -emit-module -module-name AppKit -I "$OUT" "$HERE/AppKit.swift" -o "$OUT/AppKit.swiftmodule" -suppress-warnings
cp "$IOS_STUBS/AppleFoundationShim.swift.txt" "$OUT/AppleFoundationShim.swift"
cp "$HERE/MacShim.swift.txt" "$OUT/MacShim.swift"
cp "$HERE/MacSwiftUI.swift.txt" "$OUT/MacSwiftUI.swift"
cd "$HERE/../.."
# Any error fails, except in WhatsAppWeb.swift: the WebKit stub is the iOS one (WKWebView is a UIView there, an NSView on a
# Mac), so that one file's WebKit/window calls cannot be checked here. Swift reports little beyond the first file with
# errors, so one ignored file must stay error-free otherwise too: keep it small.
set +e
swiftc -swift-version 5 -typecheck -parse-as-library -Xfrontend -solver-expression-time-threshold=900 -I "$OUT" Sources/DistributorPro/*.swift "$OUT/AppleFoundationShim.swift" "$OUT/MacShim.swift" "$OUT/MacSwiftUI.swift" "$@" > "$OUT/log.txt" 2>&1
set -e
ERRS="$(grep -E "error:" "$OUT/log.txt" | grep -v "^ " | grep -v "^Sources/DistributorPro/WhatsAppWeb.swift:" || true)"
if [ -n "$ERRS" ]; then echo "$ERRS"; exit 1; fi
echo "MAC TYPECHECK OK"
