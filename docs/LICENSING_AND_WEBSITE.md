# Licences, payments and the website

## Editions

| Edition | Who | Licence keys | Payments | How it is built |
|---|---|---|---|---|
| **public** | everyone (website downloads) | live keys (`/api/live`) | Razorpay **live** | every normal release (`./github.sh release 15.8.0`) |
| **admin** | you, for testing | test keys (`/api/test`) | Razorpay **test mode** | a release whose version ends in `-admin` (`./github.sh release 15.8.0-admin`): a pre-release, never shown as "latest" on the website |

Developer runs and the automatic checks have no edition: nothing is limited.

Each app: 15-day trial → then read-only (see, print, export, back up) until a licence key is entered in
**Settings › Licence**. One licence = 2 devices; the activation is renewed online every few weeks (works offline in between).
The admin edition also has **Start the trial again** for testing.

## Prices (website/functions/api/[[path]].js → `PLANS`)

Yearly ₹1,499 · Lifetime ₹3,999 · Yearly $29 (outside India). Change them there and on the website (website/build.py).

## Payments

- **Razorpay** (cards, UPI, net banking, wallets; international cards in USD once enabled on your Razorpay account).
  Razorpay charges its fee per payment.
- **Direct UPI, no fees**: the buy page shows a UPI QR for `UPI_VPA`; the buyer e-mails you the UPI reference and you
  issue the key on **billbox-app.pages.dev/admin.html** (Issue a licence).

## GitHub secrets (Settings › Secrets and variables › Actions)

| Secret | What |
|---|---|
| `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` | deploy to Cloudflare Pages (token from the "Edit Cloudflare Workers" template) |
| `LICENSE_KEY_LIVE`, `LICENSE_KEY_TEST` | the licence signing keys (from the file you were given; never share them) |
| `ADMIN_TOKEN` | password of admin.html and `/api/*/admin/*` |
| `RZP_KEY_ID_TEST`, `RZP_KEY_SECRET_TEST` | Razorpay Dashboard › Test mode › Account & Settings › API keys |
| `RZP_KEY_ID_LIVE`, `RZP_KEY_SECRET_LIVE` | the same in Live mode (after Razorpay activates your account) |
| `RZP_WEBHOOK_SECRET` | optional: Razorpay › Webhooks › `https://billbox-app.pages.dev/api/live/webhook` (and `/api/test/webhook` in test mode), events `payment.captured`, `order.paid` |
| `UPI_VPA` | optional: your UPI ID for direct UPI payments, e.g. `akenterprises@okhdfc` |

After adding or changing secrets: **Actions › Website › Run workflow** (main).

Testing a purchase end to end: install an admin build, Settings › Licence › Buy a licence (opens `buy.html?test=1`),
pay with Razorpay's test card `4111 1111 1111 1111` (any future date, any CVV) or test UPI `success@razorpay`,
paste the key in the app.

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
