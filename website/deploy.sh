#!/bin/bash
# Deploys website/public and the licence server (functions/) to Cloudflare Pages project "billbox" (billbox.pages.dev).
# Needs CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID; copies the licence and Razorpay secrets that are set.
set -uo pipefail
cd "$(dirname "$0")"
BRANCH="${1:-main}"
W() { npx --yes wrangler@4 "$@"; }
step() { echo; echo "== $*"; }

step "Pages project"
if ! W pages project list 2>&1 | grep -qE '(^|[^a-z-])billbox([^a-z-]|$)'; then
  W pages project create billbox --production-branch main || echo "(project create said no: it may exist already)"
fi

step "Licence store (KV namespace billbox-licenses)"
LIST="$(W kv namespace list 2>/dev/null)"
ID="$(printf '%s' "$LIST" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const i=s.indexOf("[");const l=JSON.parse(s.slice(i));const n=l.find(x=>x.title==="billbox-licenses"||x.title.endsWith("billbox-licenses"));console.log(n?n.id:"")}catch(e){console.log("")}})')"
if [ -z "$ID" ]; then
  OUT="$(W kv namespace create billbox-licenses 2>&1)"; echo "$OUT"
  ID="$(printf '%s' "$OUT" | grep -oE '[0-9a-f]{32}' | head -1)"
fi
[ -n "$ID" ] || { echo "::error::Could not make or find the KV namespace billbox-licenses (does the API token have Workers KV Storage: Edit?)"; exit 1; }
echo "KV namespace: $ID"
sed -i "s/__KV_ID__/$ID/" wrangler.toml

step "Secrets"
for s in LICENSE_KEY_LIVE LICENSE_KEY_TEST ADMIN_TOKEN RZP_KEY_ID_LIVE RZP_KEY_SECRET_LIVE RZP_KEY_ID_TEST RZP_KEY_SECRET_TEST RZP_WEBHOOK_SECRET UPI_VPA; do
  v="${!s:-}"
  if [ -n "$v" ]; then
    if printf '%s' "$v" | W pages secret put "$s" --project-name billbox >/dev/null 2>secret.err; then echo "set $s"; else echo "::warning::secret $s: $(tail -3 secret.err | tr '\n' ' ')"; fi
  else echo "not set: $s"; fi
done
rm -f secret.err

step "Deploy ($BRANCH)"
W pages deploy public --project-name billbox --branch "$BRANCH" --commit-dirty=true
