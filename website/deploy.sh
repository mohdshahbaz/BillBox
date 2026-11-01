#!/bin/bash
# Deploys website/public and the licence server (functions/) to Cloudflare Pages project "billbox" (billbox.pages.dev).
# Needs CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID; copies the licence and Razorpay secrets that are set.
set -uo pipefail
cd "$(dirname "$0")"
BRANCH="${1:-main}"
# a token or id pasted with a space or a line break still works
export CLOUDFLARE_API_TOKEN="$(printf '%s' "$CLOUDFLARE_API_TOKEN" | tr -d '[:space:]')"
export CLOUDFLARE_ACCOUNT_ID="$(printf '%s' "$CLOUDFLARE_ACCOUNT_ID" | tr -d '[:space:]')"
V="$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify)"
if ! printf '%s' "$V" | grep -q '"status":"active"'; then
  echo "::error::Cloudflare does not accept the API token in CLOUDFLARE_API_TOKEN ($(printf '%s' "$V" | grep -oE '"message":"[^"]*"' | head -1)). Copy the token again (My Profile › API Tokens › Roll, then copy the new value) into the GitHub secret."
  exit 1
fi
[[ "$CLOUDFLARE_ACCOUNT_ID" =~ ^[0-9a-f]{32}$ ]] || { echo "::error::CLOUDFLARE_ACCOUNT_ID should be 32 letters and digits (Workers & Pages › Account ID), not an e-mail or zone id."; exit 1; }
W() { npx --yes wrangler@4 "$@"; }
step() { echo; echo "== $*"; }

step "Cloudflare account and token"
W whoami 2>&1 | grep -vE 'wrangler|^─|^$' | sed -E 's/[0-9a-f]{32}/<id>/g' | head -20

step "Pages project"
for i in 1 2 3; do PL="$(W pages project list 2>&1)"; echo "$PL" | grep -q 'Rate limited' || break; echo "rate limited, waiting"; sleep 20; done
if ! echo "$PL" | grep -qE '(^|[^a-z-])billbox([^a-z-]|$)'; then
  W pages project create billbox --production-branch main || echo "(project create said no: it may exist already)"
fi

step "Licence store (KV namespace billbox-licenses)"
LIST="$(W kv namespace list 2>/dev/null)"
ID="$(printf '%s' "$LIST" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const i=s.indexOf("[");const l=JSON.parse(s.slice(i));const n=l.find(x=>x.title==="billbox-licenses"||x.title.endsWith("billbox-licenses"));console.log(n?n.id:"")}catch(e){console.log("")}})')"
if [ -z "$ID" ]; then
  OUT="$(W kv namespace create billbox-licenses 2>&1)"; echo "$OUT"
  ID="$(printf '%s' "$OUT" | grep -oE '[0-9a-f]{32}' | head -1)"
fi
if [ -n "$ID" ]; then
  echo "KV namespace: $ID"; sed -i "s/__KV_ID__/$ID/" wrangler.toml
else
  # the website still goes up; the licence server answers "not set up" until the token may use KV
  echo "::warning::Could not make or find the KV namespace billbox-licenses: give the Cloudflare API token the permission Account › Workers KV Storage › Edit. The website is deployed without the licence store."
  sed -i '/\[\[kv_namespaces\]\]/,$d' wrangler.toml
fi

step "Secrets"
for s in LICENSE_KEY_LIVE LICENSE_KEY_TEST ADMIN_TOKEN RZP_KEY_ID_LIVE RZP_KEY_SECRET_LIVE RZP_KEY_ID_TEST RZP_KEY_SECRET_TEST RZP_WEBHOOK_SECRET UPI_VPA; do
  v="${!s:-}"
  if [ -n "$v" ]; then
    if printf '%s' "$v" | W pages secret put "$s" --project-name billbox >/dev/null 2>secret.err; then echo "set $s"; else echo "::warning::secret $s: $(tail -3 secret.err | tr '\n' ' ')"; fi
  else echo "not set: $s"; fi
done
rm -f secret.err

step "Deploy ($BRANCH)"
for i in 1 2 3 4; do
  npx wrangler pages deploy dist --project-name=billbox-app --branch="${1:-main}"
  grep -q 'Rate limited' deploy.out || exit 1
  echo "rate limited, waiting $((i * 30)) s"; sleep $((i * 30))
done
exit 1
