# Licences, payments and the website

## Editions

| Edition | Who | Licence keys | Payments | How it is built |
|---|---|---|---|---|
| **public** | everyone (website downloads) | live keys (`/api/live`) | real UPI / bank payments | every normal release (`./github.sh release 15.8.0`) |
| **admin** | you, for testing | test keys (`/api/test`) | test claims (confirm them yourself) | a release whose version ends in `-admin` (`./github.sh release 15.8.0-admin`): a pre-release, never shown as "latest" on the website |

Developer runs and the automatic checks have no edition: nothing is limited.

Each app: 15-day trial → then read-only (see, print, export, back up) until a licence key is entered in
**Settings › Licence**. One licence = 2 devices; the activation is renewed online every few weeks (works offline in between).
The admin edition also has **Start the trial again** for testing.

## Prices (website/functions/api/[[path]].js → `PLANS`)

Yearly ₹1,499 · Lifetime ₹3,999 (no international plan for now). Change them there and on the website (website/build.py).

## Payments

No payment gateway, no fees: **direct UPI** (QR / UPI app link for `UPI_VPA`) and **bank transfer** (`BANK_DETAILS`).
The buyer pays, enters the UTR on the buy page, and it waits on **billbox-app.pages.dev/admin.html › Payments to confirm**.
Check the reference in your bank / UPI app, press **Confirm**: the licence is made and the buyer gets the key with
**Find my licence key** (e-mail + reference). **Not received** rejects it.

## GitHub secrets (Settings › Secrets and variables › Actions)

| Secret | What |
|---|---|
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | deploy to Cloudflare Pages (token from the "Edit Cloudflare Workers" template) |
| `LICENSE_KEY_LIVE`, `LICENSE_KEY_TEST` | the licence signing keys (from the file you were given; never share them) |
| `ADMIN_TOKEN` | password of admin.html and `/api/*/admin/*` |
| `UPI_VPA` | your UPI ID for direct UPI payments, e.g. `akenterprises@okhdfc` |
| `BANK_DETAILS` | optional, for bank transfer: `Name|Account number|IFSC|Bank` |

After adding or changing secrets: **Actions › Website › Run workflow** (main).

Testing a purchase end to end: install an admin build, Settings › Licence › Buy a licence (opens `buy.html?test=1`),
choose UPI, enter any 12-digit reference, confirm it on admin.html with **Test** selected, then Find my licence key
and paste the key in the app.

## Website

`website/build.py` writes the pages into `website/public`; `website/video/render.mjs` renders the feature videos
(`website/video/scene.html`, one per platform). The Website workflow checks the licence server and deploys both to
Cloudflare Pages on every push to `main` (other branches get a preview address).

### billbox.eu.org (free domain, later)

1. Make an account at **nic.eu.org** (Sign up), then **New domain**: `billbox.eu.org`.
2. Name servers: in Cloudflare, **Add a domain** › `billbox.eu.org` › Free plan; Cloudflare shows two name servers
   (e.g. `ada.ns.cloudflare.com`, `bob.ns.cloudflare.com`). Enter those two in the eu.org form and submit.
3. eu.org approves by hand (days to weeks). When the domain shows **Active** in Cloudflare: Workers & Pages › billbox ›
   Custom domains › Set up a custom domain › `billbox.eu.org`.
4. Then set `SITE_URL=https://billbox.eu.org` for `website/build.py` (canonical addresses and sitemap) and change
   `SITE` in `backend/src/services/license.js` and `ios/BillBoxCore/Sources/BillBoxCore/License.swift` (or keep
   billbox-app.pages.dev there: it keeps working).
