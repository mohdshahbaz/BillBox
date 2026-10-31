#!/bin/bash
# Parser and random-bill parity (see run.sh for the main scenario).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
CORE="$HERE/../../BillBoxCore"
WORK="${WORK:-$(mktemp -d)}"; mkdir -p "$WORK"
( cd "$CORE" && swift build -c debug >/dev/null )
BIN="$(cd "$CORE" && swift build --show-bin-path)/bbcheck"
for name in parser fuzz marg; do
  rc=0; python3 "$HERE/gen_$name.py" "$WORK" ${SEED:-} >/dev/null || rc=$?
  if [ $rc -eq 3 ]; then echo "== $name: skipped (private test files not present)"; continue; elif [ $rc -ne 0 ]; then exit $rc; fi
  rm -rf "$WORK/$name-mac" "$WORK/$name-ios"; mkdir -p "$WORK/$name-mac" "$WORK/$name-ios"
  node --disable-warning=ExperimentalWarning "$HERE/run-node.js" "$WORK/$name-mac/data" "$WORK/$name.json" "$WORK/$name-mac/home/DistributorProBackups" > "$WORK/$name-mac.jsonl"
  "$BIN" "$WORK/$name-ios/data" "$WORK/$name.json" "$WORK/$name-ios/home/DistributorProBackups" > "$WORK/$name-ios.jsonl"
  echo "== $name"; python3 "$HERE/compare.py" "$WORK/$name.json" "$WORK/$name-mac.jsonl" "$WORK/$name-ios.jsonl"
done
# page text from real PDF text runs (pdf.js items of the three AK Enterprises bills), watermarks included
F="$HERE/../../../backend/test/fixtures/private/pdf_text_runs.json"
if [ ! -f "$F" ]; then echo "== page text: skipped (private test files not present)"; exit 0; fi
node --disable-warning=ExperimentalWarning "$HERE/run-node.js" "$WORK/pt-mac" "$F" "$WORK/pt-mac/home/b" > "$WORK/pt-mac.jsonl"
"$BIN" "$WORK/pt-ios" "$F" "$WORK/pt-ios/b" > "$WORK/pt-ios.jsonl"
echo "== page text"; python3 "$HERE/compare.py" "$F" "$WORK/pt-mac.jsonl" "$WORK/pt-ios.jsonl"
