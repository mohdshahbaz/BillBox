#!/bin/bash
# Replays the same working session on the Mac engine (Node, backend/src) and the iOS engine (BillBoxCore), then compares.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$HERE/../../BillBoxCore"
WORK="${WORK:-$(mktemp -d)}"
mkdir -p "$WORK"
( cd "$CORE" && swift build -c debug >/dev/null )
BIN="$(cd "$CORE" && swift build --show-bin-path)/bbcheck"
python3 "$HERE/gen_scenario.py" "$WORK" >/dev/null
sed "s#{engine}#mac#g" "$WORK/scenario.json" > "$WORK/scen-mac.json"
sed "s#{engine}#ios#g" "$WORK/scenario.json" > "$WORK/scen-ios.json"
rm -rf "$WORK/mac" "$WORK/ios"; mkdir -p "$WORK/mac/home" "$WORK/ios/home"
node --disable-warning=ExperimentalWarning "$HERE/run-node.js" "$WORK/mac/data" "$WORK/scen-mac.json" "$WORK/mac/home/DistributorProBackups" > "$WORK/mac.jsonl"
"$BIN" "$WORK/ios/data" "$WORK/scen-ios.json" "$WORK/ios/home/DistributorProBackups" > "$WORK/ios.jsonl"
python3 "$HERE/compare.py" "$WORK/scenario.json" "$WORK/mac.jsonl" "$WORK/ios.jsonl"
python3 "$HERE/compare_xlsx.py" "$WORK/gst-mac.xlsx" "$WORK/gst-ios.xlsx"
echo "work files: $WORK"
