#!/bin/bash
# Puts BillBox on GitHub and makes releases, from this folder on your Mac.
#
#   ./github.sh                 first time: connects this folder to github.com/mohdshahbaz/BillBox and uploads it;
#                               later: uploads your changes (GitHub then checks them: Actions › CI)
#   ./github.sh fresh           starts the GitHub history over with one clean upload (use it once if real data was ever
#                               uploaded before: the old history is replaced; your old local history is kept in .git-old-*)
#   ./github.sh release 15.2.0  uploads, then tags v15.2.0: GitHub builds the Android, Mac and iPhone apps and publishes
#                               them under Releases (about 30 minutes; follow it under Actions › Release)
#
# Real business data never leaves this Mac: backend/test/fixtures/private (your Marg backup, supplier bills),
# ios/.../Golden/private, android/keystore.properties and the release key are kept out by .gitignore, and this script
# stops if any of them would be uploaded.
set -euo pipefail
cd "$(dirname "$0")"
REPO="${REPO:-https://github.com/mohdshahbaz/BillBox.git}"
fail() { printf '\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }
command -v git >/dev/null || fail "git is needed (it comes with Xcode's command line tools: xcode-select --install)."

if [ ! -d .git ]; then
    git init -q -b main
    git remote add origin "$REPO"
    echo "Connected this folder to $REPO"
    # a freshly unzipped project: carry on from what's already on GitHub (its history is clean), keeping these files
    if [ "${1:-}" != "fresh" ] && git fetch -q origin main 2>/dev/null; then
        git reset -q origin/main && echo "Picked up GitHub's history; your files here are the new version."
    fi
fi
git remote get-url origin >/dev/null 2>&1 || git remote add origin "$REPO"

PRIVATE='(^|/)(fixtures/private|Golden/private)/|keystore\.properties$|\.jks$|\.keystore$|(^|/)backend/data/|marg_csv_backup|pdf_text_runs\.json|real_bills\.js|(^|/)backend/test/fixtures/[^/]*_(proforma_)?[0-9]{4}\.(txt|pages\.json)$|(^|/)Golden/(parser|pagetext)(\.mac)?\.jsonl?$'

# files from older versions that hold real data and now live in fixtures/private: take them off the upload list
for f in $(git ls-files 2>/dev/null | grep -E "$PRIVATE" || true); do git rm -q --cached "$f"; done

if [ "${1:-}" = "fresh" ]; then
    OLD=".git-old-$(date +%Y%m%d-%H%M%S)"; mv .git "$OLD"; echo "Old local history kept in $OLD"
    git init -q -b main; git remote add origin "$REPO"
fi

git add -A
if git diff --cached --name-only --diff-filter=ACMR | grep -E "$PRIVATE"; then
    git reset -q
    fail "the files above hold private data and must not go to GitHub. Move them out (or into backend/test/fixtures/private), then run ./github.sh again."
fi
if git rev-parse -q --verify HEAD >/dev/null && git log --name-only --format= | grep -qE "$PRIVATE"; then
    git reset -q
    fail "your saved history still contains real data from an earlier upload. Run ./github.sh fresh instead (once)."
fi
if ! git diff --cached --quiet; then
    git commit -q -m "${MESSAGE:-BillBox update $(date '+%d-%m-%Y %H:%M')}"
    echo "Saved your changes."
fi
BR="$(git rev-parse --abbrev-ref HEAD)"
# GitHub's history is never merged in (an earlier upload there may hold real data): "fresh" replaces it
if [ "${1:-}" = "fresh" ]; then git push -f -u origin "$BR"; else git push -u origin "$BR" || fail "GitHub has changes this folder doesn't. If you uploaded from another computer, upload from there; to replace GitHub's copy with this folder: ./github.sh fresh"; fi
echo "Uploaded. GitHub checks it now: https://github.com/mohdshahbaz/BillBox/actions"

if [ "${1:-}" = "release" ]; then
    V="${2:-}"; V="${V#v}"
    [[ "$V" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.]+)?$ ]] || fail "Usage: ./github.sh release 15.2.0"
    if git ls-remote --exit-code --tags origin "refs/tags/v$V" >/dev/null 2>&1 || git rev-parse -q --verify "refs/tags/v$V" >/dev/null; then
        echo "v$V was released before (or tried): replacing that tag."
        git tag -d "v$V" >/dev/null 2>&1 || true
        git push -q origin ":refs/tags/v$V" 2>/dev/null || true
    fi
    git tag -a "v$V" -m "BillBox $V"
    git push origin "v$V"
    echo "Release v$V started: https://github.com/mohdshahbaz/BillBox/actions — the apps appear under Releases when it finishes."
fi
