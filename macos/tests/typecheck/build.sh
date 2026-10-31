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
cd "$HERE/../.."
# The stubs give SwiftUI many more overloads to try than the real SDK, so one long header expression in DataGrid.swift runs
# out of the type checker's time budget here (it builds fine with Xcode). That one message is ignored; any other error fails.
set +e
swiftc -swift-version 5 -typecheck -parse-as-library -I "$OUT" Sources/DistributorPro/*.swift "$OUT/AppleFoundationShim.swift" "$OUT/MacShim.swift" "$@" > "$OUT/log.txt" 2>&1
set -e
ERRS="$(grep -E "error:" "$OUT/log.txt" | grep -v "^ " | grep -v "DataGrid.swift:[0-9]*:[0-9]*: error: the compiler is unable to type-check this expression in reasonable time" || true)"
if [ -n "$ERRS" ]; then echo "$ERRS"; exit 1; fi
echo "MAC TYPECHECK OK"
