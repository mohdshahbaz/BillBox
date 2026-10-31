#!/bin/bash
# Builds the Linux type-check stubs, then type-checks the whole iOS app (BillBox/ + BillBoxCore) against them.
set -e
export PATH=/opt/swift/swift-wasm-6.0.2-RELEASE/usr/bin:$PATH
HERE="$(cd "$(dirname "$0")" && pwd)"
IOS="$HERE/../../.."
OUT="$HERE/../.mods"
mkdir -p "$OUT"
cd "$HERE"
for m in Darwin Combine UniformTypeIdentifiers BackgroundTasks UIKit PDFKit Vision WebKit SwiftUI; do
  swiftc -swift-version 5 -parse-as-library -emit-module -module-name $m -I "$OUT" $m.swift -o "$OUT/$m.swiftmodule" -suppress-warnings
done
echo "stubs built"
cd "$IOS"
cp "$HERE/AppleFoundationShim.swift.txt" "$OUT/AppleFoundationShim.swift"
FILES="$(ls BillBox/*/*.swift BillBoxCore/Sources/BillBoxCore/*.swift) $OUT/AppleFoundationShim.swift"
swiftc -swift-version 5 -typecheck -parse-as-library -I "$OUT" -I BillBoxCore/Sources/CSQLite $FILES "$@"
echo "TYPECHECK OK"
