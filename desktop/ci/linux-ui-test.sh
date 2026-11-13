#!/bin/bash
# Linux UI check for CI, run inside a virtual screen:  xvfb-run -a -s "-screen 0 1440x900x24" bash desktop/ci/linux-ui-test.sh
# Seeds the demo books, starts the built app, opens each of the 9 screens with Ctrl+1…9 and takes a screenshot, first in
# light and then in dark mode. Fails when the app quits, the engine does not answer, or the log shows an uncaught error,
# so a screen that crashes is caught even though the engine itself is fine. Screenshots go to $OUT (default /tmp/ui).
set -u
APP=${APP:-/tmp/run/BillBox/billbox}
OUT=${OUT:-/tmp/ui}
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
BASE="$HOME/.local/share/BillBox"
mkdir -p "$OUT" "$BASE/data"
NAMES=(dashboard billing purchases bills stock parties salesmen books settings)
fail=0

# demo books (items, parties, bills) so every table has rows to show
DATA_DIR="$BASE/data" node --disable-warning=ExperimentalWarning "$HERE/backend/src/seed.js" >/dev/null || { echo "::error::seeding the demo books failed"; exit 1; }

pass() {   # $1 = light | dark
  local mode=$1 log=/tmp/app-$1.log
  printf '{"theme":"clean","appearance":"%s"}' "$mode" > "$BASE/appearance.json"
  "$APP" > "$log" 2>&1 &
  local pid=$!
  for i in $(seq 1 60); do curl -sf http://127.0.0.1:37420/api/companies >/dev/null && break; sleep 1; done
  curl -sf http://127.0.0.1:37420/api/companies >/dev/null || { echo "::error::engine did not answer ($mode)"; cat "$log"; fail=1; kill $pid 2>/dev/null; return; }
  local win=""
  for i in $(seq 1 30); do win=$(xdotool search --pid $pid --onlyvisible 2>/dev/null | head -1); [ -n "$win" ] && break; sleep 1; done
  [ -n "$win" ] || { echo "::error::no app window ($mode)"; cat "$log"; fail=1; kill $pid 2>/dev/null; return; }
  xdotool windowsize "$win" 1440 900 windowmove "$win" 0 0 2>/dev/null || true
  sleep 4
  for n in $(seq 1 9); do
    kill -0 $pid 2>/dev/null || { echo "::error::the app quit while opening screen $n ($mode)"; tail -40 "$log"; fail=1; return; }
    # a click on the sidebar entry (the virtual screen has no window manager to give the window keyboard focus,
    # so Ctrl+1…9 would not arrive); entries start at y≈89 and are 42 px apart at 1440×900
    xdotool mousemove 105 $((89 + (n - 1) * 42)) click 1 2>/dev/null || true
    xdotool mousemove 1300 880 2>/dev/null || true   # pointer out of the way (no hover tint in the shot)
    sleep 3
    import -window root "$OUT/$(printf '%02d' $n)_${NAMES[$((n-1))]}_$mode.png"
  done
  # nine different screens must give (nearly) nine different pictures, or the clicks did not arrive
  local distinct; distinct=$(md5sum "$OUT"/0?_*_"$mode".png | cut -d' ' -f1 | sort -u | wc -l)
  [ "$distinct" -ge 7 ] || { echo "::error title=Linux UI ($mode)::only $distinct different screens in 9 screenshots: navigation did not work"; fail=1; }
  # Flutter prints uncaught errors even in release builds; a layout or build error shows up here
  if grep -nE "Stack Overflow|Unhandled Exception|EXCEPTION CAUGHT|RenderFlex overflowed|Another exception was thrown" "$log" | head -10 | tee /tmp/ui-errors-$mode.txt | grep -q .; then
    sed "s/^/::error title=Linux UI ($mode)::/" /tmp/ui-errors-$mode.txt; fail=1
  fi
  cp "$log" "$OUT/app-$mode.log"
  kill $pid 2>/dev/null; sleep 4
  pkill -f "BillBox/engine/node" 2>/dev/null || true; sleep 1
}

pass light
pass dark
ls "$OUT"
exit $fail
