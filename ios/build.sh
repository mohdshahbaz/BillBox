#!/bin/bash
# BillBox for iPhone: build, test and install from Terminal on a Mac with Xcode 14.2 or newer.
#
#   ./build.sh               tests, then build and install on the iPhone plugged in by USB (or on Wi-Fi with "Connect via network")
#   ./build.sh test          unit tests only (on a simulator)
#   ./build.sh sim           build, install and open on a simulator
#   ./build.sh device        build and install on your iPhone, without running the tests
#   ./build.sh run           build, install and start BillBox on your iPhone, showing its log here (a crash shows its reason)
#   ./build.sh crashlog      copy BillBox's crash reports from the iPhone to ios/build/crashlogs and show the newest one
#   ./build.sh ipa           make BillBox.ipa in ios/build/ (for AltStore, Sideloadly or a paid account)
#   ./build.sh clean         remove ios/build
#
# Optional settings (put them in front of the command, e.g.  TEAM_ID=AB12CD34EF ./build.sh device):
#   TEAM_ID     your Apple developer team. Found automatically from the "Apple Development" certificate in your keychain.
#   BUNDLE_ID   app identifier (default com.local.billbox). With a free Apple ID, use your own, e.g. com.shabaz.billbox
#   DEVICE_ID   which iPhone to use, when more than one is connected
#   SIM_NAME    which simulator to use (default: the first iPhone simulator found)
#
# First time only: open Xcode › Settings › Accounts and sign in with your Apple ID, plug in the iPhone and tap "Trust".
# On the iPhone (iOS 16+): Settings › Privacy & Security › Developer Mode › On.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
PROJECT="BillBox.xcodeproj"
SCHEME="BillBox"
BUILD="$HERE/build"
DERIVED="$BUILD/DerivedData"
BUNDLE_ID="${BUNDLE_ID:-com.local.billbox}"
ACTION="${1:-all}"

bold() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

# xcpretty makes the log readable when it is installed (gem install xcpretty); otherwise the full log is kept in build/
pretty() {
    local log="$BUILD/$1.log"
    if command -v xcpretty >/dev/null 2>&1; then
        tee "$log" | xcpretty
    else
        tee "$log" | grep -E "error:|warning: .*BillBox|\*\* (BUILD|TEST|ARCHIVE|EXPORT)|Test Case .*(passed|failed)|Executed [0-9]+ test" || true
    fi
    return 0   # the caller reads xcodebuild's own result (pipefail)
}

check_tools() {
    command -v xcodebuild >/dev/null 2>&1 || fail "Xcode is not installed. Install Xcode 14.2 or newer, open it once, then run: sudo xcode-select -s /Applications/Xcode.app"
    xcodebuild -version >/dev/null 2>&1 || fail "Xcode's command-line tools are not selected. Run: sudo xcode-select -s /Applications/Xcode.app"
    XCODE_MAJOR="$(xcodebuild -version | awk 'NR==1 {split($2, v, "."); print v[1]}')"
    [ "$XCODE_MAJOR" -ge 14 ] || fail "Xcode $(xcodebuild -version | head -1) is too old; BillBox needs Xcode 14.2 or newer."
    echo "$(xcodebuild -version | head -1), macOS $(sw_vers -productVersion)"
    mkdir -p "$BUILD"
}

find_team() {
    if [ -n "${TEAM_ID:-}" ]; then echo "Team: $TEAM_ID"; return; fi
    # the team is the OU of the "Apple Development" signing certificate Xcode created when you signed in
    local pem
    pem="$(security find-certificate -a -c "Apple Development" -p 2>/dev/null || true)"
    if [ -n "$pem" ]; then
        TEAM_ID="$(printf '%s\n' "$pem" | awk '/BEGIN CERT/{c=""} {c=c $0 "\n"} /END CERT/{print c > "/dev/stdout"; exit}' \
            | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p')"
    fi
    [ -n "${TEAM_ID:-}" ] || fail "No signing team found. Open Xcode › Settings › Accounts, add your Apple ID, then run again
       (or give it directly:  TEAM_ID=XXXXXXXXXX ./build.sh device)."
    echo "Team: $TEAM_ID (from your keychain)"
}

pick_simulator() {
    local line
    if [ -n "${SIM_NAME:-}" ]; then
        line="$(xcrun simctl list devices available | grep -F "    $SIM_NAME (" | head -1 || true)"
        [ -n "$line" ] || fail "No simulator named \"$SIM_NAME\". See: xcrun simctl list devices available"
    else
        line="$(xcrun simctl list devices available | grep -E '^ +iPhone' | head -1 || true)"
        [ -n "$line" ] || fail "No iPhone simulator installed. Xcode › Settings › Platforms (or Components) › add iOS."
    fi
    SIM_ID="$(printf '%s' "$line" | grep -oE '[0-9A-F]{8}-([0-9A-F]{4}-){3}[0-9A-F]{12}' | head -1)"
    SIM_LABEL="$(printf '%s' "$line" | sed -E 's/^ +//; s/ \([0-9A-F-]{36}\).*//')"
    echo "Simulator: $SIM_LABEL"
}

pick_device() {
    if [ -n "${DEVICE_ID:-}" ]; then echo "iPhone: $DEVICE_ID"; return; fi
    # "Shabaz's iPhone (17.5) (00008020-001A2B3C4D5E6F7G)" between "== Devices ==" and "== Simulators =="
    local lines
    lines="$(xcrun xctrace list devices 2>/dev/null | awk '/^== Devices ==/{d=1; next} /^== /{d=0} d' \
        | grep -E '\([0-9]+(\.[0-9]+)+\) \([0-9A-Fa-f-]{20,}\)$' | grep -vE 'MacBook|iMac|Mac mini|Mac Pro|Mac Studio|Watch' || true)"
    [ -n "$lines" ] || fail "No iPhone found. Plug it in by USB, unlock it and tap \"Trust This Computer\"; on iOS 16+ also turn on
       Settings › Privacy & Security › Developer Mode."
    if [ "$(printf '%s\n' "$lines" | wc -l | tr -d ' ')" -gt 1 ]; then
        echo "More than one iPhone is connected:"; printf '  %s\n' "$lines"
        echo "Using the first one. Choose another with  DEVICE_ID=<id in brackets> ./build.sh device"
    fi
    local first; first="$(printf '%s\n' "$lines" | head -1)"
    DEVICE_ID="$(printf '%s' "$first" | sed -E 's/.*\(([0-9A-Fa-f-]{20,})\)$/\1/')"
    echo "iPhone: $(printf '%s' "$first" | sed -E 's/ \([0-9A-Fa-f-]{20,}\)$//')"
    # An Xcode older than the iPhone's iOS can usually still install (Xcode 15.4 installs on iOS 18), but cannot show the live log.
    local ios sdk
    ios="$(printf '%s' "$first" | sed -E 's/.*\(([0-9]+)(\.[0-9]+)+\) \([0-9A-Fa-f-]{20,}\)$/\1/')"
    sdk="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null | cut -d. -f1)"
    NEWER_IOS=""
    if [ -n "$ios" ] && [ -n "$sdk" ] && [ "$ios" -gt "$sdk" ]; then
        NEWER_IOS=1
        echo "Note: this iPhone runs iOS $ios and this Xcode knows up to iOS $sdk. Installing usually works; the live log does not."
        echo "      If installing fails, use  ./build.sh ipa  and Sideloadly, or update Xcode."
    fi
}

run_tests() {
    bold "Unit tests (the iPhone engine against answers recorded from the Mac)"
    pick_simulator
    set +e
    xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "id=$SIM_ID" \
        -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO 2>&1 | pretty test
    local rc=$?
    set -e
    [ $rc -eq 0 ] || fail "Some tests failed. Full log: $BUILD/test.log"
    ok "All tests passed."
}

build_sim() {
    bold "Build for the simulator"
    pick_simulator
    set +e
    xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Debug -destination "id=$SIM_ID" \
        -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO 2>&1 | pretty build-sim
    local rc=$?
    set -e
    [ $rc -eq 0 ] || fail "Build failed. Full log: $BUILD/build-sim.log"
    local app="$DERIVED/Build/Products/Debug-iphonesimulator/BillBox.app"
    bold "Install and open on $SIM_LABEL"
    xcrun simctl boot "$SIM_ID" 2>/dev/null || true
    open -a Simulator --args -CurrentDeviceUDID "$SIM_ID" || true
    xcrun simctl bootstatus "$SIM_ID" -b >/dev/null 2>&1 || true
    xcrun simctl install "$SIM_ID" "$app"
    xcrun simctl launch "$SIM_ID" com.local.billbox >/dev/null
    ok "BillBox is running on $SIM_LABEL."
}

# Builds and signs BillBox for the connected iPhone; sets APP to the built app.
build_signed() {
    bold "Build for your iPhone (signed)"
    find_team
    pick_device
    set +e
    xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination "id=$DEVICE_ID" \
        -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" 2>&1 | pretty build-device
    local rc=$?
    set -e
    if [ $rc -ne 0 ] && grep -qE "Timed out waiting for all destinations|preparation errors|Unable to find a destination|is not available for this build" "$BUILD/build-device.log"; then
        # Xcode could not "prepare" the iPhone (common after an iOS update, or with an Xcode older than the iPhone's iOS).
        # Building does not need the iPhone itself: build for any iPhone, then install with devicectl.
        echo "Xcode could not get the iPhone ready for debugging; building for any iPhone instead and installing it directly."
        set +e
        xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination "generic/platform=iOS" \
            -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
            DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" 2>&1 | pretty build-device
        rc=$?
        set -e
        NEWER_IOS=1   # no live log either way
    fi
    if [ $rc -ne 0 ]; then
        if grep -qE "is not available|cannot be registered|No profiles for" "$BUILD/build-device.log"; then
            fail "Signing failed: the app identifier \"$BUNDLE_ID\" is taken or not allowed for your account.
       Use your own, for example:  BUNDLE_ID=com.yourname.billbox ./build.sh device"
        fi
        fail "Build failed. Full log: $BUILD/build-device.log"
    fi
    APP="$DERIVED/Build/Products/Release-iphoneos/BillBox.app"
}

no_installer() {
    fail "Built, but Xcode 14 cannot install from Terminal by itself. Install the helper once:
       brew install ios-deploy      (Homebrew: https://brew.sh)
       then run this again.  Or open BillBox.xcodeproj and press Run."
}

trust_hint() {
    echo "If it does not open: iPhone Settings › General › VPN & Device Management › your Apple ID › Trust."
    echo "With a free Apple ID the app works for 7 days; build again to renew it (your data stays)."
}

build_device() {
    build_signed
    bold "Install on the iPhone"
    if xcrun devicectl --version >/dev/null 2>&1; then                 # Xcode 15 and newer
        if ! xcrun devicectl device install app --device "$DEVICE_ID" "$APP"; then
            fail "Built, but it could not be installed on the iPhone. Check:
       1. The iPhone is unlocked, connected by cable, and you tapped \"Trust\".
       2. Settings › Privacy & Security › Developer Mode is on (the iPhone restarts once).
       3. Open Xcode › Window › Devices and Simulators, select the iPhone and wait until it stops \"Preparing\"
          (after an iOS update this takes a few minutes; leave the cable in), then run this again.
       Still failing? Xcode 15.4 is older than iOS 18: install Xcode 16 (it runs on your macOS 14.8), or use
       ./build.sh ipa  and install BillBox.ipa with Sideloadly."
        fi
        xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
    elif command -v ios-deploy >/dev/null 2>&1; then                 # Xcode 14
        ios-deploy --id "$DEVICE_ID" --bundle "$APP" --justlaunch
    else
        no_installer
    fi
    ok "BillBox is installed on your iPhone."
    trust_hint
}

# Install, start and stay attached: what BillBox prints appears here, and if it crashes the reason and the stack are shown.
run_device() {
    build_signed
    bold "Install and start on the iPhone (press Ctrl-C to stop watching; BillBox keeps running)"
    trust_hint
    if xcrun devicectl --version >/dev/null 2>&1; then                 # Xcode 15 and newer
        xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
        if [ -n "${NEWER_IOS:-}" ]; then
            xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null
            ok "BillBox is running on your iPhone. (This Xcode cannot show its log on iOS $ios.)"
            echo "If BillBox ever closes by itself, it shows the reason the next time it opens (\"Last close\")."
        elif ! xcrun devicectl device process launch --console --terminate-existing --device "$DEVICE_ID" "$BUNDLE_ID"; then
            echo "The live log ended. BillBox may still be running; if it closed by itself, run  ./build.sh crashlog  to see why."
        fi
    elif command -v ios-deploy >/dev/null 2>&1; then                 # Xcode 14: starts under the debugger
        echo "BillBox starts under the debugger. If it crashes, type  bt  and press Return to see where, then  quit."
        ios-deploy --id "$DEVICE_ID" --bundle "$APP" --debug || echo "BillBox stopped. If it crashed, run  ./build.sh crashlog  to see why."
    else
        no_installer
    fi
}

# Crash reports iOS keeps for BillBox (Settings › Privacy & Security › Analytics & Improvements › Analytics Data).
crashlog() {
    pick_device
    local dir="$BUILD/crashlogs"
    rm -rf "$dir"; mkdir -p "$dir"
    bold "Copy crash reports from the iPhone"
    if xcrun devicectl --version >/dev/null 2>&1; then
        xcrun devicectl device copy from --device "$DEVICE_ID" --domain-type systemCrashLogs --source / --destination "$dir" >/dev/null 2>&1 || true
    fi
    if [ -z "$(find "$dir" -name 'BillBox*' 2>/dev/null | head -1)" ] && command -v idevicecrashreport >/dev/null 2>&1; then
        idevicecrashreport -u "$DEVICE_ID" -e -k "$dir" >/dev/null 2>&1 || true
    fi
    local newest
    newest="$(find "$dir" -name 'BillBox*' -type f -exec ls -t {} + 2>/dev/null | head -1 || true)"
    if [ -z "$newest" ]; then
        fail "No BillBox crash report found.
       With Xcode 14, install the helper once:  brew install libimobiledevice   and run this again.
       Or on the iPhone: Settings › Privacy & Security › Analytics & Improvements › Analytics Data › BillBox-… › Share.
       BillBox itself also shows the reason the next time it opens (\"Last close\")."
    fi
    ok "Newest report: $newest"
    echo "All BillBox reports: $dir"
    # the important part: what went wrong and the first lines of the crashed thread
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$newest" <<'PY' || head -60 "$newest"
import json, sys
text = open(sys.argv[1], errors='replace').read()
head, _, body = text.partition('\n')
try:
    d = json.loads(body)
except Exception:
    print('\n'.join(text.splitlines()[:60])); sys.exit()
ex = d.get('exception', {})
print('Exception:', ex.get('type'), ex.get('signal'), ex.get('subtype', ''))
if d.get('termination'): print('Termination:', d['termination'].get('indicator') or d['termination'])
if d.get('asi'): print('Message:', d['asi'])
images = d.get('usedImages', [])
for t in d.get('threads', []):
    if t.get('triggered'):
        print('Crashed thread:', t.get('name') or t.get('queue') or '')
        for f in t.get('frames', [])[:25]:
            img = images[f['imageIndex']]['name'] if f.get('imageIndex') is not None and f['imageIndex'] < len(images) else '?'
            print('   ', img, f.get('symbol', ''), '+', f.get('symbolLocation', ''))
PY
    else
        head -60 "$newest"
    fi
}

build_ipa() {
    bold "Archive and export BillBox.ipa"
    local archive="$BUILD/BillBox.xcarchive"
    rm -rf "$archive" "$BUILD/ipa"
    # without a signing team the app is left unsigned: Sideloadly / AltStore sign it with your Apple ID when installing
    if ! (find_team) >/dev/null 2>&1; then
        echo "No signing team: making an unsigned BillBox.ipa (Sideloadly or AltStore will sign it)."
        set +e
        xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination "generic/platform=iOS" \
            -archivePath "$archive" -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
            PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" 2>&1 | pretty archive
        local urc=$?
        set -e
        [ $urc -eq 0 ] || fail "Archive failed. Full log: $BUILD/archive.log"
        mkdir -p "$BUILD/ipa/Payload"
        cp -R "$archive/Products/Applications/BillBox.app" "$BUILD/ipa/Payload/"
        (cd "$BUILD/ipa" && zip -qry BillBox.ipa Payload && rm -rf Payload)
        ok "Made $BUILD/ipa/BillBox.ipa (unsigned)"
        return
    fi
    find_team
    set +e
    xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination "generic/platform=iOS" \
        -archivePath "$archive" -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" 2>&1 | pretty archive
    local rc=$?
    set -e
    [ $rc -eq 0 ] || fail "Archive failed. Full log: $BUILD/archive.log"
    cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>development</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
    <key>compileBitcode</key><false/>
    <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
PLIST
    set +e
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$BUILD/ipa" \
        -exportOptionsPlist "$BUILD/ExportOptions.plist" -allowProvisioningUpdates 2>&1 | pretty export
    rc=$?
    set -e
    if [ $rc -ne 0 ]; then
        # free Apple IDs cannot export; package the signed app from the archive instead (works with AltStore / Sideloadly)
        echo "Export was refused (normal with a free Apple ID); packaging the app from the archive instead."
        rm -rf "$BUILD/ipa" && mkdir -p "$BUILD/ipa/Payload"
        cp -R "$archive/Products/Applications/BillBox.app" "$BUILD/ipa/Payload/"
        (cd "$BUILD/ipa" && zip -qry BillBox.ipa Payload && rm -rf Payload)
    fi
    ok "Made $BUILD/ipa/BillBox.ipa"
}

check_tools
case "$ACTION" in
    all)    run_tests; build_device ;;
    test)   run_tests ;;
    sim)    build_sim ;;
    device) build_device ;;
    run)    run_device ;;
    crashlog) crashlog ;;
    ipa)    build_ipa ;;
    clean)  rm -rf "$BUILD"; ok "Removed $BUILD" ;;
    -h|--help|help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) fail "Unknown command \"$ACTION\". Use: ./build.sh [all|test|sim|device|run|crashlog|ipa|clean]" ;;
esac
