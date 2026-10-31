#!/bin/bash
# Android engine parity: the bundled engine (with Android's bridge rules) against the Mac engine, on the full working session,
# the parser / random bills / Marg import scenarios, and the Excel file.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
P="$HERE/../../../ios/tests/parity"
WORK="${WORK:-$(mktemp -d)}"; mkdir -p "$WORK"
BUNDLE="$HERE/../../app/src/main/assets/engine/engine.js"
[ -f "$BUNDLE" ] || node "$HERE/../build.mjs"
python3 "$P/gen_scenario.py" "$WORK" >/dev/null
for side in mac android; do sed "s#{engine}#$side#g" "$WORK/scenario.json" > "$WORK/scen-$side.json"; done
rm -rf "$WORK/mac" "$WORK/android"; mkdir -p "$WORK/mac/home" "$WORK/android/home"
node --disable-warning=ExperimentalWarning "$P/run-node.js" "$WORK/mac/data" "$WORK/scen-mac.json" "$WORK/mac/home/DistributorProBackups" > "$WORK/mac.jsonl"
node --disable-warning=ExperimentalWarning "$HERE/run-bundle.js" "$BUNDLE" "$WORK/android/data" "$WORK/scen-android.json" "$WORK/android/home/DistributorProBackups" > "$WORK/android.jsonl"
echo "== working session (Mac engine vs Android bundle)"; python3 "$P/compare.py" "$WORK/scenario.json" "$WORK/mac.jsonl" "$WORK/android.jsonl"
[ -f "$WORK/gst-android.xlsx" ] && python3 "$P/compare_xlsx.py" "$WORK/gst-mac.xlsx" "$WORK/gst-android.xlsx"
for name in parser fuzz marg; do
  rc=0; python3 "$P/gen_$name.py" "$WORK" >/dev/null || rc=$?
  if [ $rc -eq 3 ]; then echo "== $name: skipped (private test files not present)"; continue; elif [ $rc -ne 0 ]; then exit $rc; fi
  rm -rf "$WORK/$name-mac" "$WORK/$name-android"
  node --disable-warning=ExperimentalWarning "$P/run-node.js" "$WORK/$name-mac/data" "$WORK/$name.json" "$WORK/$name-mac/home/DistributorProBackups" > "$WORK/$name-mac.jsonl"
  node --disable-warning=ExperimentalWarning "$HERE/run-bundle.js" "$BUNDLE" "$WORK/$name-android/data" "$WORK/$name.json" "$WORK/$name-android/home/DistributorProBackups" > "$WORK/$name-android.jsonl"
  echo "== $name"; python3 "$P/compare.py" "$WORK/$name.json" "$WORK/$name-mac.jsonl" "$WORK/$name-android.jsonl"
done
