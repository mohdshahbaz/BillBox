#!/bin/bash
# Makes the key that signs BillBox for Android, once. Every release must be signed with the same key, or phones refuse
# the update ("App not installed") and BillBox has to be uninstalled first — which deletes its books on that phone.
#
#   android/tools/make_keystore.sh
#
# It writes android/billbox-release.jks and android/keystore.properties (both stay on this Mac and are never committed),
# and prints the four values to paste into GitHub › your repo › Settings › Secrets and variables › Actions:
#   ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD
# Keep a copy of billbox-release.jks and its password somewhere safe (a USB drive, a password manager).
set -euo pipefail
cd "$(dirname "$0")/.."
JKS=billbox-release.jks
[ -f "$JKS" ] && { echo "$JKS already exists — it is your signing key; keep using it. Delete it only if you are sure."; exit 1; }
# macOS has a /usr/bin/keytool stub that fails without Java: use the first keytool that actually runs
KEYTOOL=""
for k in "${JAVA_HOME:+$JAVA_HOME/bin/keytool}" "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
         "/Applications/Android Studio.app/Contents/jre/Contents/Home/bin/keytool" "$(command -v keytool || true)"; do
    [ -n "$k" ] && [ -x "$k" ] && "$k" -help >/dev/null 2>&1 && { KEYTOOL="$k"; break; }
done
[ -n "$KEYTOOL" ] || { echo "keytool not found: install Android Studio or a JDK 17."; exit 1; }
PASS="$(openssl rand -hex 16)"
echo "Making the signing key (a few seconds)..."
"$KEYTOOL" -genkeypair -keystore "$JKS" -storetype PKCS12 -alias billbox -keyalg RSA -keysize 4096 -validity 36500 \
  -storepass "$PASS" -keypass "$PASS" -dname "CN=BillBox, O=AK Enterprises, C=IN" >/dev/null 2>&1 \
  || { rm -f "$JKS"; echo "keytool could not make the key."; exit 1; }
printf 'storeFile=%s\nstorePassword=%s\nkeyAlias=billbox\nkeyPassword=%s\n' "$JKS" "$PASS" "$PASS" > keystore.properties
B64="$(base64 < "$JKS" | tr -d '\n')"
echo
echo "Made android/$JKS and android/keystore.properties (./build.sh release now signs with it)."
echo
echo "Add these as GitHub secrets (repo › Settings › Secrets and variables › Actions › New repository secret):"
echo "  ANDROID_KEYSTORE_BASE64   = (the long text below)"
echo "  ANDROID_KEYSTORE_PASSWORD = $PASS"
echo "  ANDROID_KEY_ALIAS         = billbox"
echo "  ANDROID_KEY_PASSWORD      = $PASS"
echo
echo "$B64"
echo
if command -v pbcopy >/dev/null 2>&1; then printf '%s' "$B64" | pbcopy; echo "(ANDROID_KEYSTORE_BASE64 is also on the clipboard.)"; fi
# with the GitHub CLI signed in, put the secrets on GitHub straight away
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    R="${REPO_SLUG:-mohdshahbaz/BillBox}"
    if printf '%s' "$B64" | gh secret set ANDROID_KEYSTORE_BASE64 -R "$R" \
       && gh secret set ANDROID_KEYSTORE_PASSWORD -R "$R" --body "$PASS" \
       && gh secret set ANDROID_KEY_ALIAS -R "$R" --body billbox \
       && gh secret set ANDROID_KEY_PASSWORD -R "$R" --body "$PASS"; then
        echo "The 4 secrets are now set on GitHub ($R): nothing to paste."
    else
        echo "Could not set the secrets with gh: paste them on GitHub by hand (values above)."
    fi
fi
echo "Keep a copy of android/$JKS and the password safe: without them, future versions cannot update BillBox on phones."
