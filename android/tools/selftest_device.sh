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
adb logcat -d -v time > "$OUT/logcat-full.txt" || true
grep -E "SELFTEST|BillBoxEngine|AndroidRuntime|FATAL|chromium.*(Uncaught|Error)|System.err" "$OUT/logcat-full.txt" > "$OUT/logcat.txt" || true
adb exec-out screencap -p > "$OUT/final-screen.png" || true
ls -la "$OUT" "$OUT/selftest" "$OUT/selftest/shots" 2>/dev/null || true
