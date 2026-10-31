#!/bin/bash
# Runs inside the Android emulator job (.github/workflows/android-selftest.yml): installs the debug app, hands it the parity
# working session, starts it in self-test mode, waits for it to finish and copies out what it wrote.
#   selftest_device.sh <app-debug.apk> <scenario-android.json> <out-dir>
set -u
APK="$1"; SCEN="$2"; OUT="$3"
PKG=com.local.billbox
mkdir -p "$OUT"
adb wait-for-device
adb install -r -g "$APK" || { echo "::error::install failed"; exit 1; }
adb logcat -c
adb shell "run-as $PKG mkdir -p files/selftest"
adb shell "run-as $PKG sh -c 'cat > files/selftest/scenario.json'" < "$SCEN"
adb shell "run-as $PKG ls -l files/selftest"
adb shell am start -W -n "$PKG/.MainActivity" --ez selftest true
for i in $(seq 1 240); do
  if adb shell "run-as $PKG ls files/selftest/done" >/dev/null 2>&1; then echo "self-test finished after $((i * 5)) s"; break; fi
  if ! adb shell pidof "$PKG" >/dev/null 2>&1; then echo "::error::BillBox is no longer running (crashed?)"; break; fi
  sleep 5
done
adb exec-out "run-as $PKG tar -c -C files selftest" | tar -x -C "$OUT" || echo "::warning::could not copy files/selftest"

# ---- the real screens, tapped like a person would (uiautomator finds the buttons by their text)
HERE="$(cd "$(dirname "$0")" && pwd)"
UI="$OUT/ui"; mkdir -p "$UI"; N=20
dump() {
  local msg; msg=$(adb shell uiautomator dump --compressed /sdcard/ui.xml 2>&1)
  echo "dump: $msg" >> "$UI/dumps.txt"
  adb exec-out cat /sdcard/ui.xml
}
# the emulator's own launcher sometimes shows "isn't responding" over the app: answer Wait and carry on
calm() {
  local x; x=$(dump)
  echo "$x" > "$UI/last.xml"
  if echo "$x" | grep -q "responding"; then
    local xy; xy=$(echo "$x" | python3 "$HERE/ui_find.py" "Wait") && adb shell input tap $xy && sleep 1.5
    adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1
  fi
}
shot() { sleep "${2:-2}"; adb exec-out screencap -p > "$UI/${N}_$1.png"; N=$((N + 1)); }
tap() {   # tap <text> [--edit] [--skip=n]
  local xy=""
  for try in 1 2 3; do calm; xy=$(dump | python3 "$HERE/ui_find.py" "$@") && break; xy=""; sleep 2; done
  [ -n "$xy" ] || { echo "::warning::UI step: nothing called '$1' on screen"; echo "missing: $1" >> "$UI/steps.txt"; cp "$UI/last.xml" "$UI/missing_${N}.xml" 2>/dev/null; return 1; }
  adb shell input tap $xy; echo "tapped: $1 at $xy" >> "$UI/steps.txt"; sleep 1.5
}
typetext() { adb shell input text "$(echo "$1" | sed 's/ /%s/g')"; sleep 2; }
back() { adb shell input keyevent KEYCODE_BACK; sleep 1.5; }

adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1; calm
tap "Billing" ; shot billing 1
tap "Type an item name" --edit && typetext "bikano" && shot search
tap "Bikano" --skip=1 && shot line_added
tap "Save & print" && shot after_save 4
back; back
tap "Parties" && shot parties
tap "City Mart" && shot party_open 3
back; back
tap "Stock" && tap "New item" && shot new_item
back; back
tap "More" && tap "Settings" && tap "Companies" && shot companies
back; tap "Printing" && shot printing
adb shell input swipe 500 1600 500 500 400; shot printing_more 1
back; tap "WhatsApp" && shot whatsapp
adb logcat -d -v time | grep -E "AndroidRuntime|FATAL|BillBoxEngine" > "$UI/logcat-ui.txt" || true
adb logcat -d -v time > "$OUT/logcat-full.txt" || true
grep -E "SELFTEST|BillBoxEngine|AndroidRuntime|FATAL|chromium.*(Uncaught|Error)|System.err" "$OUT/logcat-full.txt" > "$OUT/logcat.txt" || true
adb exec-out screencap -p > "$OUT/final-screen.png" || true
ls -la "$OUT" "$OUT/selftest" "$OUT/selftest/shots" 2>/dev/null || true
