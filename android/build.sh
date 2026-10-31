#!/bin/bash
# BillBox for Android (Android 12 and up): build, install and run from a Terminal on a Mac, Linux or Windows (Git Bash / WSL).
#
#   ./build.sh               build the app and install it on the phone connected by USB (or Wi-Fi debugging), then open it
#   ./build.sh apk           build only: android/build/BillBox-debug.apk (copy it to any phone and install it)
#   ./build.sh release       signed release APK: android/build/BillBox-release.apk (keystore.properties, see below)
#   ./build.sh install       install the last APK built, then open BillBox
#   ./build.sh run           build, install, open BillBox and show its log here (a crash shows its reason)
#   ./build.sh logcat        show BillBox's log from the phone
#   ./build.sh devices       list the phones adb can see
#   ./build.sh wifi IP:PORT  connect to a phone over Wi-Fi debugging (Settings › Developer options › Wireless debugging)
#   ./build.sh pair IP:PORT  pair with a phone for Wi-Fi debugging first (Android 11+: "Pair device with pairing code")
#   ./build.sh setup         download the Android SDK pieces BillBox needs (when Android Studio is not installed)
#   ./build.sh engine        rebuild the bundled engine from backend/src (needs Node.js 22)
#   ./build.sh test          engine parity: the bundled engine against the Mac engine (needs Node.js 22 and Python 3)
#   ./build.sh typecheck     check the app's Kotlin without the Android SDK
#   ./build.sh clean         remove build output
#
# Optional settings (put them in front of the command, e.g.  SERIAL=R58M12ABC ./build.sh):
#   SERIAL        which phone to use when more than one is connected (from ./build.sh devices)
#   APP_ID        app identifier (default com.local.billbox) — to install a second copy beside the first
#   ANDROID_HOME  where the Android SDK is (found automatically for Android Studio's default places)
#   JAVA_HOME     a Java 17 or newer (Android Studio's own Java is used when found)
#
# On the phone, once: Settings › About phone › tap "Build number" 7 times; then Settings › System › Developer options ›
# USB debugging › On. Plug in the phone and tap "Allow" on the "Allow USB debugging?" question.
# Release signing: create android/keystore.properties with storeFile=…, storePassword=…, keyAlias=…, keyPassword=…
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
APP_ID="${APP_ID:-com.local.billbox}"
ACTION="${1:-all}"
OUT="$HERE/build"

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

# --- Java 17+ ---------------------------------------------------------------------------------------------------------
java_major() { "$1" -version 2>&1 | awk -F'"' '/version/ {split($2,a,"."); print (a[1]=="1" ? a[2] : a[1]); exit}'; }
find_java() {
    local c
    for c in "${JAVA_HOME:-}" \
             "/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
             "$HOME/Applications/Android Studio.app/Contents/jbr/Contents/Home" \
             "/opt/android-studio/jbr" "$HOME/android-studio/jbr" "/c/Program Files/Android/Android Studio/jbr" \
             "$( [ -x /usr/libexec/java_home ] && /usr/libexec/java_home -v 17+ 2>/dev/null || true)"; do
        if [ -n "$c" ] && [ -x "$c/bin/java" ] && [ "$(java_major "$c/bin/java")" -ge 17 ] 2>/dev/null; then export JAVA_HOME="$c"; return 0; fi
    done
    if command -v java >/dev/null 2>&1 && [ "$(java_major java)" -ge 17 ] 2>/dev/null; then return 0; fi
    return 1
}

# --- Android SDK ------------------------------------------------------------------------------------------------------
find_sdk() {
    local c
    for c in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" "${LOCALAPPDATA:-/nonexistent}/Android/Sdk" "$HERE/.sdk"; do
        if [ -n "$c" ] && [ -d "$c/platforms" -o -d "$c/cmdline-tools" -o -d "$c/platform-tools" ]; then export ANDROID_HOME="$c"; return 0; fi
    done
    return 1
}

setup_sdk() {
    find_java || fail "Java 17 or newer is needed first. Install Android Studio (it brings its own), or e.g. 'brew install openjdk@17'."
    local sdk="${ANDROID_HOME:-$HERE/.sdk}"
    mkdir -p "$sdk"
    if [ ! -x "$sdk/cmdline-tools/latest/bin/sdkmanager" ]; then
        local os=linux; case "$(uname -s)" in Darwin) os=mac;; MINGW*|MSYS*|CYGWIN*) os=win;; esac
        local url="https://dl.google.com/android/repository/commandlinetools-${os}-11076708_latest.zip"
        bold "Downloading the Android command-line tools"
        curl -fL --progress-bar -o "$sdk/cmdline.zip" "$url" || fail "Could not download $url"
        rm -rf "$sdk/cmdline-tools"; mkdir -p "$sdk/cmdline-tools"
        unzip -q "$sdk/cmdline.zip" -d "$sdk/cmdline-tools" && mv "$sdk/cmdline-tools/cmdline-tools" "$sdk/cmdline-tools/latest" && rm "$sdk/cmdline.zip"
    fi
    export ANDROID_HOME="$sdk"
    local sm="$sdk/cmdline-tools/latest/bin/sdkmanager"
    bold "Accepting the SDK licences and installing platform 34, build tools and adb"
    yes | "$sm" --sdk_root="$sdk" --licenses >/dev/null || true
    "$sm" --sdk_root="$sdk" "platforms;android-34" "build-tools;34.0.0" "platform-tools"
    ok "Android SDK ready in $sdk"
}

# EDITION=admin ./build.sh apk  makes the owner's test build (test licences, Razorpay test mode); the default is public.
set_edition() {
    local e="${EDITION:-public}" f="$HERE/app/src/main/java/com/local/billbox/engine/Edition.kt"
    case "$e" in public|admin) ;; *) fail "EDITION must be public or admin";; esac
    sed -i.bak -E "s/const val NAME = \"[a-z]+\"/const val NAME = \"$e\"/" "$f" && rm -f "$f.bak"
    [ "$e" = public ] || echo "Edition: $e"
}

prepare() {
    set_edition
    find_java || fail "Java 17 or newer was not found.
  Easiest: install Android Studio (https://developer.android.com/studio) — this script uses the Java inside it.
  Or install a JDK 17 (macOS: brew install openjdk@17) and set JAVA_HOME."
    find_sdk || fail "The Android SDK was not found.
  Install Android Studio and open it once (it downloads the SDK to ~/Library/Android/sdk on a Mac),
  or run:  ./build.sh setup   (downloads only what BillBox needs into android/.sdk),
  or set ANDROID_HOME to an existing SDK."
    printf 'sdk.dir=%s\n' "$ANDROID_HOME" > "$HERE/local.properties"
    ADB="$ANDROID_HOME/platform-tools/adb"; [ -x "$ADB" ] || ADB="$(command -v adb || true)"
    ok "Java: ${JAVA_HOME:-$(command -v java)}"
    ok "Android SDK: $ANDROID_HOME"
}

# --- Gradle itself ----------------------------------------------------------------------------------------------------
# ./gradlew downloads Gradle once, with a 10-second limit and from GitHub only. On a slow or filtered connection that fails,
# so the zip is fetched here first (patiently, resuming, with mirrors) into the very place ./gradlew looks for it.
# A zip downloaded in a browser also works: leave it in Downloads, or GRADLE_ZIP=/path/to/gradle-8.9-bin.zip ./build.sh
ensure_gradle() {
    local props="$HERE/gradle/wrapper/gradle-wrapper.properties"
    local url; url="$(sed -n 's/^distributionUrl=//p' "$props" | sed 's#\\:#:#g')"
    local name; name="$(basename "$url")"                      # gradle-8.9-bin.zip
    local base="${GRADLE_USER_HOME:-$HOME/.gradle}/wrapper/dists/${name%.zip}"
    local hash
    hash="$(python3 - "$url" 2>/dev/null <<'PY' || true
import hashlib, sys
n = int(hashlib.md5(sys.argv[1].encode()).hexdigest(), 16); d = "0123456789abcdefghijklmnopqrstuvwxyz"; s = ""
while n: n, r = divmod(n, 36); s = d[r] + s
print(s)
PY
)"
    [ -n "$hash" ] || hash="$(perl -MDigest::MD5=md5_hex -MMath::BigInt -e '$n=Math::BigInt->from_hex(md5_hex($ARGV[0]));$d="0123456789abcdefghijklmnopqrstuvwxyz";$s="";while($n>0){($n,$r)=$n->copy->bdiv(36);$s=substr($d,$r,1).$s}print $s' "$url" 2>/dev/null || true)"
    [ -n "$hash" ] || return 0                                  # cannot work out the folder: leave it to ./gradlew
    local dir="$base/$hash"
    ls "$dir"/*.ok >/dev/null 2>&1 && return 0                  # already unpacked by ./gradlew
    [ -f "$dir/$name" ] && unzip -tq "$dir/$name" >/dev/null 2>&1 && return 0
    mkdir -p "$dir"
    local got=""
    for f in "${GRADLE_ZIP:-}" "$HOME/Downloads/$name"; do
        if [ -n "$f" ] && [ -f "$f" ] && unzip -tq "$f" >/dev/null 2>&1; then cp "$f" "$dir/$name.part"; got="$f"; break; fi
    done
    if [ -z "$got" ]; then
        bold "Downloading Gradle (about 130 MB, once)"
        local m
        for m in "$url" "https://downloads.gradle.org/distributions/$name" "https://mirrors.cloud.tencent.com/gradle/$name"; do
            echo "from $m"
            if curl -fL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 60 -C - --progress-bar -o "$dir/$name.part" "$m" \
               && unzip -tq "$dir/$name.part" >/dev/null 2>&1; then got="$m"; break; fi
            rm -f "$dir/$name.part"
        done
    fi
    [ -n "$got" ] || fail "Gradle could not be downloaded (the connection to services.gradle.org / GitHub timed out).
  Download it in a browser instead: $url
  leave gradle-8.9-bin.zip in your Downloads folder, and run ./build.sh again.
  (On mobile data or a VPN, try another Wi-Fi; some networks block GitHub downloads.)"
    # checked against Gradle's published checksum when it can be fetched
    local want; want="$(curl -fsS --connect-timeout 20 "$url.sha256" 2>/dev/null | tr -d ' \r\n' || true)"
    if [ ${#want} -eq 64 ]; then
        local have; have="$(shasum -a 256 "$dir/$name.part" 2>/dev/null || sha256sum "$dir/$name.part")"; have="${have%% *}"
        [ "$have" = "$want" ] || { rm -f "$dir/$name.part"; fail "The downloaded Gradle zip does not match Gradle's checksum; it was deleted. Run ./build.sh again."; }
    fi
    mv "$dir/$name.part" "$dir/$name"
    ok "Gradle ready."
}

gradle() {
    ensure_gradle
    local extra=()
    [ "$APP_ID" != "com.local.billbox" ] && extra+=("-PbillboxAppId=$APP_ID")
    ./gradlew --console=plain ${extra[@]+"${extra[@]}"} "$@"
}

# --- engine bundle ---------------------------------------------------------------------------------------------------
build_engine() {
    command -v node >/dev/null 2>&1 || fail "Node.js 22 is needed to rebuild the engine (https://nodejs.org). The app builds without it, using the engine already bundled."
    bold "Bundling the engine (backend/src) for Android"
    if [ ! -d "$HERE/engine/node_modules/esbuild" ]; then (cd "$HERE/engine" && npm install --no-audit --no-fund); fi
    node "$HERE/engine/build.mjs"
    ok "android/app/src/main/assets/engine/engine.js updated"
}

# The bundle is rebuilt when Node is here and backend/src or the shims changed since it was made; otherwise the bundled copy is used.
maybe_engine() {
    local bundle="$HERE/app/src/main/assets/engine/engine.js"
    command -v node >/dev/null 2>&1 || return 0
    [ -d "$HERE/engine/node_modules/esbuild" ] || return 0
    if [ ! -f "$bundle" ] || [ -n "$(find "$HERE/../backend/src" "$HERE/engine/shims" "$HERE/engine/entry.js" -newer "$bundle" -name '*.js' 2>/dev/null | head -1)" ]; then build_engine; fi
}

# --- phone -----------------------------------------------------------------------------------------------------------
device() {
    [ -n "${ADB:-}" ] || fail "adb was not found (Android SDK platform-tools). Run ./build.sh setup."
    "$ADB" start-server >/dev/null 2>&1 || true
    local list; list="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')"
    if [ -n "${SERIAL:-}" ]; then echo "$list" | grep -qx "$SERIAL" || fail "Phone $SERIAL is not connected. Connected: ${list:-none}"; return 0; fi
    local unauth; unauth="$("$ADB" devices | awk 'NR>1 && $2=="unauthorized" {print $1}')"
    if [ -z "$list" ]; then
        [ -n "$unauth" ] && fail "The phone is connected but has not allowed this computer yet: unlock it and tap Allow on \"Allow USB debugging?\"."
        fail "No phone found. Plug it in by USB with USB debugging on (Settings › System › Developer options), or use ./build.sh wifi IP:PORT."
    fi
    SERIAL="$(echo "$list" | head -1)"
    [ "$(echo "$list" | wc -l | tr -d ' ')" -gt 1 ] && echo "More than one phone: using $SERIAL (set SERIAL=… to choose)."
    return 0
}
adbd() { "$ADB" -s "$SERIAL" "$@"; }

install_apk() {
    local apk="$OUT/BillBox-debug.apk"
    [ "${1:-}" = "release" ] && apk="$OUT/BillBox-release.apk"
    [ -f "$apk" ] || fail "No APK yet. Run ./build.sh apk first."
    device
    local model; model="$(adbd shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
    local sdkv; sdkv="$(adbd shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')"
    [ -n "$sdkv" ] && [ "$sdkv" -lt 31 ] && fail "$model runs Android API $sdkv; BillBox needs Android 12 (API 31) or newer."
    bold "Installing on $model ($SERIAL)"
    if ! adbd install -r -t "$apk"; then
        echo "Install failed. If an older BillBox signed with another key is on the phone, uninstall it first (your data on the phone goes with it — back up first):"
        echo "    $ADB -s $SERIAL uninstall $APP_ID"
        exit 1
    fi
    ok "Installed."
}

launch() {
    bold "Opening BillBox"
    adbd shell am start -n "$APP_ID/com.local.billbox.MainActivity" >/dev/null || adbd shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null
    ok "BillBox is open on the phone."
}

show_log() {
    device
    bold "BillBox log (Ctrl-C to stop)"
    local pid=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do pid="$(adbd shell pidof "$APP_ID" 2>/dev/null | tr -d '\r')"; [ -n "$pid" ] && break; sleep 1; done
    if [ -n "$pid" ]; then adbd logcat -v time --pid="$pid" '*:I' BillBoxEngine:V AndroidRuntime:E
    else adbd logcat -v time BillBoxEngine:V AndroidRuntime:E '*:S'; fi
}

build_apk() {
    maybe_engine
    bold "Building BillBox (debug)"
    gradle :app:assembleDebug
    mkdir -p "$OUT"; cp app/build/outputs/apk/debug/app-debug.apk "$OUT/BillBox-debug.apk"
    ok "APK: android/build/BillBox-debug.apk"
}

# The phone's real address, e.g. 192.168.1.20:37045 — not the words IP:PORT from the help text.
addr_ok() {
    [[ "${1:-}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]{2,5}$ ]] && return 0
    fail "Give the phone's address and port, e.g.  ./build.sh $ACTION 192.168.1.20:37045
  On the phone: Settings › System › Developer options › Wireless debugging › On, then read the numbers from the
  $2. Phone and computer must be on the same Wi-Fi."
}

case "$ACTION" in
    all|"")      prepare; build_apk; install_apk; launch ;;
    apk)         prepare; build_apk ;;
    release)     prepare; maybe_engine
                 [ -f keystore.properties ] || echo "No keystore.properties: the release APK is signed with the debug key (fine for your own phones)."
                 bold "Building BillBox (release)"; gradle :app:assembleRelease
                 mkdir -p "$OUT"; cp app/build/outputs/apk/release/app-release.apk "$OUT/BillBox-release.apk"; ok "APK: android/build/BillBox-release.apk" ;;
    install)     prepare; install_apk "${2:-}"; launch ;;
    run)         prepare; build_apk; install_apk; launch; show_log ;;
    logcat|log)  prepare; show_log ;;
    devices)     prepare; "$ADB" devices -l ;;
    wifi|connect) addr_ok "${2:-}" "Wireless debugging screen (\"IP address & Port\")"; prepare; "$ADB" connect "$2" ;;
    pair)        addr_ok "${2:-}" "\"Pair device with pairing code\" box (it also shows the 6-digit code to type)"; prepare; "$ADB" pair "$2" ;;
    setup)       setup_sdk ;;
    engine)      build_engine ;;
    test)        command -v node >/dev/null 2>&1 || fail "Node.js 22 is needed for the engine parity test."
                 bash "$HERE/engine/test/run.sh" ;;
    typecheck)   find_java || fail "Java 17+ needed."; GRADLE_LIB="${GRADLE_LIB:-$(ls -d "$HOME"/.gradle/wrapper/dists/gradle-8.9-bin/*/gradle-8.9/lib 2>/dev/null | head -1)}" bash "$HERE/tests/typecheck/check.sh" ;;
    clean)       rm -rf "$OUT" app/build build .gradle; ok "Cleaned." ;;
    -h|--help|help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//' ;;
    *)           fail "Unknown command '$ACTION'. See ./build.sh help" ;;
esac
