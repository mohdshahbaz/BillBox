#!/usr/bin/env python3
"""Builds the BillBox website (website/public) from the content below: python3 website/build.py

Every page gets its title, description, canonical address, social cards and structured data (search engines), and the
same navigation and footer. The feature videos come from website/video (node website/video/render.mjs)."""
import html, json, os, datetime

SITE = os.environ.get("SITE_URL", "https://billbox-app.pages.dev").rstrip("/")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "public")
EMAIL = "mohdshabaz12@gmail.com"
SELLER = "AK Enterprises"
REPO = "https://github.com/mohdshahbaz/BillBox"
TODAY = datetime.date.today().isoformat()
e = html.escape

PLATFORMS = {
    "mac": dict(name="Mac", glyph="💻", short="macOS 12 Monterey or newer · Apple silicon and Intel",
        title="BillBox for Mac — GST billing and stock software for distributors",
        desc="BillBox for Mac: fast GST billing with batches and expiry, purchases from supplier PDFs, stock, ledgers, Marg-style printing and Google Drive backups. A native Mac app for FMCG distributors.",
        lead="A native Mac app that bills as fast as you type. Built for distributors who live in their keyboard.",
        downloads=[("mac", "Download for Mac (.dmg)"), ("mac-zip", "Mac app as .zip")],
        specs=[("System", "macOS 12 or newer"), ("Chips", "Apple silicon and Intel"), ("Size", "about 60 MB"), ("Books", "on your Mac, backed up daily")],
        features=[
            ("Billing at keyboard speed", "Item search as you type, box and piece quantities, batches picked by expiry (FEFO), schemes and free pieces, rate and discount memory per party."),
            ("Purchases from the supplier's PDF", "Drop the supplier's bill PDF: items, batches, MRP, expiry and GST are read for you, new items created, stock updated."),
            ("GST done right", "CGST + SGST or IGST by the party's state, HSN summary, GSTR-1 style outward summary, Excel export, e-way bill JSON."),
            ("Parties and ledgers", "Credit limits and days, outstanding bills, receipts against bills, ledger of any year, WhatsApp reminders."),
            ("Stock that stays true", "Batch-wise stock, expiry warnings, low-stock list, stock adjustments, debit notes back to suppliers."),
            ("Printing", "Half sheet (A4 cut in two), A4, two copies on a sheet, BillBox or Marg style, compact totals for more rows."),
            ("WhatsApp", "Send the bill PDF to the party from inside BillBox."),
            ("Backups", "Daily verified backup to any folder or USB drive, plus Google Drive; restore with Replace or Merge."),
            ("Import from Marg ERP", "Bring items, parties, batches and balances over from a Marg backup."),
        ], soon=[]),
    "windows": dict(name="Windows", glyph="🖥️", short="Windows 10 and 11 · 64-bit",
        title="BillBox for Windows — GST billing software for FMCG distributors",
        desc="BillBox for Windows 10 and 11: GST billing with batches and expiry, purchases, stock, parties and ledgers, salesmen, GST reports and backups to Google Drive. Easy installer, works offline.",
        lead="The same books and the same bills as the Mac and phone apps, on the PC at your counter.",
        downloads=[("windows-setup", "Download for Windows (installer)"), ("windows-zip", "Portable .zip")],
        specs=[("System", "Windows 10 or 11, 64-bit"), ("Install", "one-click installer"), ("Works", "fully offline"), ("Books", "%APPDATA%\\BillBox")],
        features=[
            ("Billing", "Batches by expiry, box and piece quantities, schemes, free pieces, credit limits and the party's last rates."),
            ("Purchases", "Supplier bills typed or read from their PDF, with batches, MRP and expiry; stock updated at once."),
            ("Stock", "Batch-wise stock, expiry and low-stock lists."),
            ("Parties and ledgers", "Outstanding, receipts, ledgers and statements."),
            ("Salesmen and beats", "Routes, beat plans and each salesman's sales and collections."),
            ("Books and GST", "Sales and purchase books, GST outward summary, Excel export."),
            ("Printing", "Half sheet or A4, preview first, any Windows printer."),
            ("Backups", "Daily backup with restore, and Google Drive backups with restore on any BillBox."),
        ], soon=["Debit notes", "Marg ERP import", "E-way bill JSON", "WhatsApp sending", "Marg-style bill design"]),
    "linux": dict(name="Linux", glyph="🐧", short="Ubuntu 22.04+, Debian 12+, Mint 21+ · 64-bit",
        title="BillBox for Linux — GST billing and inventory software (.deb)",
        desc="BillBox for Linux (Ubuntu, Debian, Mint): GST billing with batches, purchases, stock, ledgers, salesmen, GST reports and Google Drive backups. .deb package or portable archive.",
        lead="Proper GST billing on Linux. Install the .deb, or unpack and run — your books stay on your machine.",
        downloads=[("linux-deb", "Download .deb (Ubuntu, Debian, Mint)"), ("linux-tar", "Portable .tar.gz")],
        specs=[("System", "Ubuntu 22.04+, Debian 12+"), ("Package", ".deb or .tar.gz"), ("Works", "fully offline"), ("Books", "~/.local/share/BillBox")],
        features=[
            ("Billing", "Batches by expiry, box and piece quantities, schemes, free pieces, credit limits."),
            ("Purchases", "Supplier bills typed or read from their PDF; stock updated at once."),
            ("Stock", "Batch-wise stock, expiry and low-stock lists."),
            ("Parties and ledgers", "Outstanding, receipts, ledgers and statements."),
            ("Salesmen and beats", "Routes, beat plans and performance."),
            ("Books and GST", "Sales and purchase books, GST outward summary, Excel export."),
            ("Printing", "Half sheet or A4 through CUPS, preview first."),
            ("Backups", "Daily backup with restore, and Google Drive backups with restore on any BillBox."),
        ], soon=["Debit notes", "Marg ERP import", "E-way bill JSON", "WhatsApp sending", "Marg-style bill design"]),
    "iphone": dict(name="iPhone", glyph="📱", short="iOS 16 or newer",
        title="BillBox for iPhone — GST billing app for distributors and salesmen",
        desc="BillBox for iPhone: make GST bills on the go, scan supplier bills, record payments from a photo, print or WhatsApp the bill, and keep the same books as the Mac. Works offline.",
        lead="Your whole billing counter in your pocket — the same engine as the Mac, so every figure matches.",
        downloads=[("iphone", "Download the .ipa (sideload)")],
        specs=[("System", "iOS 16 or newer"), ("Install", "Sideloadly or AltStore"), ("Works", "fully offline"), ("Backups", "Files, iCloud Drive, Google Drive")],
        features=[
            ("Billing on the go", "Search items, batches by expiry, schemes and free pieces, credit limits, GST worked out."),
            ("Scan supplier bills", "Open the supplier's PDF or scan paper: items, batches and expiry read with on-device text recognition."),
            ("Payments from a photo", "Photograph a collection sheet; BillBox reads the parties and amounts for you to confirm."),
            ("Print and share", "AirPrint half sheet or A4, BillBox or Marg style, or send the PDF on WhatsApp."),
            ("Stock and parties", "Batch-wise stock, expiry list, ledgers, outstanding and receipts."),
            ("Reports and GST", "Books, GST summaries and Excel export to Files."),
            ("Backups", "Daily backup to Files or iCloud Drive and to Google Drive, restore with Replace or Merge."),
            ("Same books everywhere", "A backup made on the Mac, Windows, Linux or Android restores here, and back."),
        ], soon=[]),
    "android": dict(name="Android", glyph="🤖", short="Android 12 or newer",
        title="BillBox for Android — GST billing app with batches, stock and ledgers",
        desc="BillBox for Android: GST billing with batches and expiry, purchases from supplier PDFs, stock, ledgers, printing, WhatsApp bills and Google Drive backups. Works offline.",
        lead="Fast GST billing on any Android phone or tablet, with the very same engine as the desktop apps.",
        downloads=[("android", "Download the APK")],
        specs=[("System", "Android 12 or newer"), ("Install", "APK from this site"), ("Works", "fully offline"), ("Backups", "phone, USB, Google Drive")],
        features=[
            ("Billing", "Batches by expiry, box and piece quantities, schemes, free pieces and credit limits."),
            ("Purchases from PDF", "Open the supplier's bill PDF: items, batches, MRP and expiry are read for you."),
            ("Print and share", "Print through Android printing, or send the bill PDF on WhatsApp."),
            ("Stock", "Batch-wise stock, expiry and low-stock lists, debit notes."),
            ("Parties and ledgers", "Outstanding, receipts, statements and reminders."),
            ("Reports and GST", "Books, GST summaries, Excel export, e-way bill JSON."),
            ("Backups", "Daily backup on the phone and to Google Drive, restore with Replace or Merge."),
            ("Import from Marg ERP", "Bring your Marg items, parties and balances over."),
        ], soon=[]),
}
ORDER = ["mac", "windows", "linux", "iphone", "android"]

FAQ = [
    ("Does BillBox work without the internet?", "Yes. Your books are kept on your own device and every bill, purchase and report works offline. The internet is used only for Google Drive backups, WhatsApp and checking the licence every few weeks."),
    ("Is there a free trial?", "Every app has a 15-day free trial with everything switched on. After it, your books stay safe and can still be seen, printed, exported and backed up; adding or changing anything needs a licence."),
    ("How many devices does one licence cover?", "Two devices — any mix of Mac, Windows, Linux, iPhone and Android. Remove the licence from one device (Settings › Licence) to move it to another."),
    ("Can I move my books from Marg ERP?", "Yes. BillBox imports items, parties, batches and opening balances from a Marg backup (Mac, iPhone and Android; Windows and Linux soon)."),
    ("Where is my data stored?", "Only on your devices, in a SQLite database per company. Backups go to a folder you choose and, if you switch it on, to your own Google Drive. We never see your books."),
    ("Which payment methods do you accept?", "UPI (any app: GPay, PhonePe, Paytm, BHIM) or bank transfer (IMPS / NEFT / RTGS). Send the reference on the buy page and your licence key is ready once the payment is confirmed, usually within a few hours. Payments from outside India are not taken for now."),
]

def head(title, desc, path, extra_ld=None, image=None):
    url = SITE + path
    img = SITE + (image or "/videos/mac.jpg")
    ld = [{"@context": "https://schema.org", "@type": "Organization", "name": "BillBox", "url": SITE, "logo": SITE + "/assets/icon-512.png", "email": EMAIL}]
    if extra_ld: ld += extra_ld
    return f"""<!doctype html>
<html lang="en-IN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(title)}</title>
<meta name="description" content="{e(desc)}">
<link rel="canonical" href="{url}">
<meta name="theme-color" content="#4f46e5">
<meta property="og:type" content="website"><meta property="og:site_name" content="BillBox"><meta property="og:title" content="{e(title)}">
<meta property="og:description" content="{e(desc)}"><meta property="og:url" content="{url}"><meta property="og:image" content="{img}">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="{e(title)}"><meta name="twitter:description" content="{e(desc)}"><meta name="twitter:image" content="{img}">
<link rel="icon" href="/favicon.ico" sizes="any"><link rel="icon" type="image/png" href="/assets/icon-32.png"><link rel="apple-touch-icon" href="/assets/icon-180.png">
<link rel="manifest" href="/site.webmanifest">
<link rel="stylesheet" href="/assets/style.css">
<script type="application/ld+json">{json.dumps(ld if len(ld) > 1 else ld[0], ensure_ascii=False)}</script>
</head>
<body>
<nav class="nav" aria-label="Main"><div class="wrap">
  <a class="brand" href="/"><img src="/assets/icon-32.png" alt="" width="22" height="22">BillBox</a>
  <button class="menu-btn" aria-label="Menu" aria-expanded="false">☰</button>
  <div class="links">{''.join(f'<a href="/{k}/">{PLATFORMS[k]["name"]}</a>' for k in ORDER)}<a href="/pricing/">Pricing</a><a href="/#faq">FAQ</a></div>
  <a class="cta" href="/pricing/">Buy</a>
</div></nav>
<main>
"""

FOOT = f"""</main>
<footer><div class="wrap">
  <div class="cols">
    <div><h4>BillBox</h4>{''.join(f'<a href="/{k}/">BillBox for {PLATFORMS[k]["name"]}</a>' for k in ORDER)}</div>
    <div><h4>Buy</h4><a href="/pricing/">Pricing</a><a href="/buy.html">Buy a licence</a><a href="/buy.html#find">Find my licence key</a></div>
    <div><h4>Help</h4><a href="/#faq">Questions</a><a href="{REPO}/releases">All downloads</a><a href="/contact/">Contact</a></div>
    <div><h4>Policies</h4><a href="/privacy/">Privacy</a><a href="/terms/">Terms</a><a href="/refunds/">Refunds and cancellation</a></div>
  </div>
  <div class="bottom"><span>Copyright © {datetime.date.today().year} {SELLER}. All rights reserved.</span><span>Made in India for Indian distributors.</span></div>
</div></footer>
<script src="/assets/site.js" defer></script>
</body></html>
"""

def write(path, text):
    full = os.path.join(OUT, path.lstrip("/"))
    if full.endswith("/"): full += "index.html"
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as f: f.write(text)

def video(p, cls=""):
    return f'<video class="{cls}" data-autoplay muted loop playsinline preload="metadata" poster="/videos/{p}.jpg" aria-label="BillBox for {PLATFORMS[p]["name"]}: dashboard, billing, printing and backup"><source src="/videos/{p}.mp4" type="video/mp4"></video>'

def software_ld(p=None):
    names = [PLATFORMS[p]["name"]] if p else [PLATFORMS[k]["name"] for k in ORDER]
    os_ = {"Mac": "macOS 12+", "Windows": "Windows 10, Windows 11", "Linux": "Ubuntu 22.04+, Debian 12+", "iPhone": "iOS 16+", "Android": "Android 12+"}
    return {"@context": "https://schema.org", "@type": "SoftwareApplication", "name": "BillBox" + (f" for {names[0]}" if p else ""),
            "applicationCategory": "BusinessApplication", "operatingSystem": ", ".join(os_[n] for n in names),
            "description": (PLATFORMS[p]["desc"] if p else "GST billing, stock and accounts software for FMCG distributors and wholesalers."),
            "offers": [{"@type": "Offer", "price": "1499", "priceCurrency": "INR", "name": "1 year"}, {"@type": "Offer", "price": "3999", "priceCurrency": "INR", "name": "Lifetime"}],
            "publisher": {"@type": "Organization", "name": SELLER}}

# ---------------------------------------------------------------- home
def home():
    t = "BillBox — GST billing, stock and accounts software for FMCG distributors"
    d = "BillBox is GST billing software for FMCG distributors and wholesalers: batches and expiry, purchases from supplier PDFs, stock, ledgers, salesmen, Marg-style printing and Google Drive backups. For Mac, Windows, Linux, iPhone and Android."
    faq_ld = {"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in FAQ]}
    s = head(t, d, "/", [software_ld(), faq_ld])
    s += f"""<section class="hero"><div class="wrap">
  <p class="eyebrow">BillBox 15.8</p>
  <h1>Billing that keeps up<br class="d"> <span class="grad">with your business.</span></h1>
  <p class="lead">GST billing, stock and accounts for FMCG distributors. One set of books on your Mac, PC, Linux, iPhone and Android.</p>
  <div class="btns"><a class="btn" href="#platforms">Download free for 15 days</a><a class="btn ghost" href="/pricing/">See pricing</a></div>
  <div class="video reveal">{video("mac")}</div>
</div></section>

<section class="alt" id="platforms"><div class="wrap center">
  <h2 class="reveal">One BillBox. Every device.</h2>
  <p class="lead reveal">The same engine runs inside every app, so a bill made on the phone and a report on the Mac always agree — to the paisa.</p>
  <div class="platforms">{''.join(f'<a class="plat reveal" href="/{k}/"><div class="glyph">{PLATFORMS[k]["glyph"]}</div><b>{PLATFORMS[k]["name"]}</b><span>{e(PLATFORMS[k]["short"].split(" · ")[0])}</span><i>Learn more ›</i></a>' for k in ORDER)}</div>
</div></section>

<section><div class="wrap">
  <div class="center"><p class="eyebrow reveal">Made for distributors</p><h2 class="reveal">Everything your counter needs.</h2></div>
  <div class="tiles">
    <div class="tile reveal"><div class="ic">₹</div><h3>Bills in seconds</h3><p>Batches picked by expiry, box and piece quantities, schemes and free pieces, credit limits, CGST + SGST or IGST worked out.</p></div>
    <div class="tile reveal"><div class="ic">⇣</div><h3>Purchases from a PDF</h3><p>Open the supplier's bill: items, batches, MRP, expiry and GST are read for you and the stock is updated.</p></div>
    <div class="tile reveal"><div class="ic">▦</div><h3>Stock that stays true</h3><p>Batch-wise stock, expiry warnings, low-stock lists, adjustments and debit notes to suppliers.</p></div>
    <div class="tile reveal"><div class="ic">☺</div><h3>Parties and ledgers</h3><p>Outstanding by bill, receipts, ledgers of any year, credit days and WhatsApp reminders.</p></div>
    <div class="tile reveal"><div class="ic">§</div><h3>GST, ready to file</h3><p>Outward summary by rate, B2B and B2C, HSN, input credit, Excel export and e-way bill JSON.</p></div>
    <div class="tile reveal"><div class="ic">⎙</div><h3>Prints like Marg</h3><p>Half sheet or A4, BillBox or Marg style, compact totals so more items fit on a page.</p></div>
    <div class="tile reveal"><div class="ic">⚑</div><h3>Salesmen and beats</h3><p>Routes, beat plans, targets, and each salesman's sales and collections.</p></div>
    <div class="tile reveal"><div class="ic">☁</div><h3>Backups you can trust</h3><p>Verified daily backups to a folder and to Google Drive, restored on any BillBox with Replace or Merge.</p></div>
    <div class="tile reveal"><div class="ic">⇄</div><h3>Coming from Marg?</h3><p>Import items, parties, batches and balances from a Marg ERP backup in minutes.</p></div>
  </div>
</div></section>

<section class="dark"><div class="wrap split">
  <div class="reveal"><p class="eyebrow">Your data stays yours</p><h2>Private by design.</h2><p class="lead" style="margin-left:0">Your books live on your own devices, not on our servers. Backups go to your folder and your own Google Drive. BillBox works fully offline.</p></div>
  <div class="reveal">{video("iphone")}</div>
</div></section>

<section class="alt"><div class="wrap center">
  <h2 class="reveal">Simple pricing.</h2><p class="lead reveal">Try everything free for 15 days. Then one licence covers two devices.</p>
  {pricing_cards()}
</div></section>

<section id="faq"><div class="wrap" style="max-width:820px">
  <h2 class="center reveal" style="margin-bottom:28px">Questions</h2>
  {''.join(f'<details class="reveal"><summary>{e(q)}</summary><p>{e(a)}</p></details>' for q, a in FAQ)}
</div></section>
"""
    write("/", s + FOOT)

def pricing_cards():
    return """<div class="prices">
    <div class="price reveal"><div class="tag">&nbsp;</div><h3>Yearly</h3><div class="amt">₹1,499<small> / year</small></div>
      <ul><li>Every feature, every app</li><li>2 devices</li><li>All updates during the year</li><li>UPI or bank transfer</li></ul>
      <a class="btn" href="/buy.html?plan=yearly_inr">Buy yearly</a></div>
    <div class="price best reveal"><div class="tag">Best value</div><h3>Lifetime</h3><div class="amt">₹3,999<small> once</small></div>
      <ul><li>Every feature, every app</li><li>2 devices</li><li>Never expires</li><li>UPI or bank transfer</li></ul>
      <a class="btn" href="/buy.html?plan=lifetime_inr">Buy lifetime</a></div>
  </div>"""

# ---------------------------------------------------------------- platform pages
def platform(k):
    p = PLATFORMS[k]
    s = head(p["title"], p["desc"], f"/{k}/", [software_ld(k)], image=f"/videos/{k}.jpg")
    dl = "".join(f'<a class="btn{" ghost" if i else ""}" data-dl="{key}" href="{REPO}/releases/latest">{e(label)}</a>' for i, (key, label) in enumerate(p["downloads"]))
    feats = "".join(f'<li><b>{e(a)}.</b> <span>{e(b)}</span></li>' for a, b in p["features"])
    soon = "".join(f'<li class="soon"><b>{e(x)}</b> <span>— coming in an update</span></li>' for x in p["soon"])
    install = {
        "mac": "Open the .dmg and drag BillBox to Applications. The first time, right-click BillBox › Open (on macOS 15: System Settings › Privacy & Security › Open Anyway).",
        "windows": "Run the installer. If SmartScreen warns about a new app, choose More info › Run anyway. BillBox opens with a 15-day trial.",
        "linux": "sudo apt install ./BillBox-linux-*-amd64.deb — or unpack the .tar.gz anywhere and run BillBox/install.sh once to add it to your menu.",
        "iphone": "Install the .ipa with Sideloadly or AltStore, which sign it with your Apple ID. An App Store version is on the way.",
        "android": "Download the APK on the phone and open it (allow installing from your browser or Files once). Updates keep your books.",
    }[k]
    s += f"""<section class="hero"><div class="wrap">
  <p class="eyebrow">BillBox for {p["name"]}</p>
  <h1>{e(p["name"])}. <span class="grad">Billing, done.</span></h1>
  <p class="lead">{e(p["lead"])}</p>
  <div class="btns">{dl}</div>
  <p style="color:var(--muted);font-size:14px;margin-top:14px">{e(p["short"])} · Free for 15 days · Version <span data-version>15.8</span></p>
  <div class="video reveal">{video(k)}</div>
</div></section>
<section class="alt"><div class="wrap split">
  <div class="reveal"><p class="eyebrow">What it does</p><h2>Everything for the counter, in one app.</h2>
    <p class="lead" style="margin-left:0">Every feature works offline, and your books open on every other BillBox.</p></div>
  <ul class="checks reveal">{feats}{soon}</ul>
</div></section>
<section><div class="wrap">
  <h2 class="reveal">Tech specs</h2>
  <div class="specs reveal">{''.join(f'<div><b>{e(a)}</b><span>{e(b)}</span></div>' for a, b in p["specs"])}</div>
  <h3 class="reveal" style="margin-top:48px">Install</h3><p class="reveal" style="color:var(--muted)">{e(install)}</p>
</div></section>
<section class="alt"><div class="wrap center"><h2 class="reveal">Also on</h2>
  <div class="platforms">{''.join(f'<a class="plat reveal" href="/{o}/"><div class="glyph">{PLATFORMS[o]["glyph"]}</div><b>{PLATFORMS[o]["name"]}</b><i>Learn more ›</i></a>' for o in ORDER if o != k)}</div>
</div></section>
"""
    write(f"/{k}/", s + FOOT)

# ---------------------------------------------------------------- pricing, buy
def pricing():
    s = head("BillBox pricing — ₹1,499 a year or ₹3,999 for life", "BillBox costs ₹1,499 a year or ₹3,999 for life. Every feature, every app, two devices, 15-day free trial.", "/pricing/", [software_ld()])
    s += f"""<section class="hero"><div class="wrap center"><p class="eyebrow">Pricing</p><h1>Pay once a year.<br class="d"> <span class="grad">Or never again.</span></h1>
  <p class="lead">Every feature on every app. Try it free for 15 days — no card needed.</p>{pricing_cards()}
  <p style="color:var(--muted);margin-top:28px;font-size:15px">Prices include GST where it applies. Pay by UPI or bank transfer. <a href="/refunds/">Refunds</a>.</p>
</div></section>"""
    write("/pricing/", s + FOOT)

def buy():
    s = head("Buy BillBox — pay by UPI or bank transfer", "Buy a BillBox licence: yearly ₹1,499 or lifetime ₹3,999, by UPI or bank transfer. Your licence key is ready once the payment is confirmed.", "/buy.html")
    s += """<section class="hero" style="padding-bottom:96px"><div class="wrap" style="max-width:640px">
  <div class="center"><p class="eyebrow">Buy a licence</p><h2>Pay by UPI or bank.</h2>
  <p class="lead">Pay, send the reference, then paste your key in BillBox › Settings › Licence.</p></div>
  <div id="testmode" class="notice warn" hidden><b>Test mode.</b> Keys bought here are test licence keys, which work only in the admin (test) BillBox.</div>
  <form class="card" id="buy" style="margin-top:28px" onsubmit="return false">
    <label>Plan</label>
    <div class="choices" id="plans">
      <label class="choice"><input type="radio" name="plan" value="yearly_inr" checked><b>Yearly</b><span>₹1,499</span></label>
      <label class="choice"><input type="radio" name="plan" value="lifetime_inr"><b>Lifetime</b><span>₹3,999</span></label>
    </div>
    <label for="email">E-mail (your licence is kept for it)</label><input id="email" type="email" autocomplete="email" required placeholder="you@business.in">
    <label for="name">Business name (optional)</label><input id="name" autocomplete="organization" placeholder="Your business">
    <div class="btns" style="justify-content:flex-start"><button class="btn" id="upiBtn" type="button">Pay by UPI</button><button class="btn ghost" id="bankBtn" type="button">Bank transfer</button></div>
    <div id="msg"></div>
  </form>
  <div class="card" id="done" hidden style="margin-top:28px"><h3>Thank you! Here is your licence key</h3>
    <p style="color:var(--muted)">Copy it into BillBox › Settings › Licence › Use this licence key. Keep it safe — it also works on your second device.</p>
    <div class="keybox" id="key"></div><div class="btns" style="justify-content:flex-start"><button class="btn" id="copy" type="button">Copy the key</button></div>
    <p style="color:var(--muted);font-size:14px" id="keyinfo"></p></div>
  <div class="card" id="upi" hidden style="margin-top:28px"><h3>Pay by UPI</h3>
    <p style="color:var(--muted)">Scan with any UPI app (GPay, PhonePe, Paytm, BHIM) or pay to <b id="vpa"></b>.</p>
    <div class="center"><div id="qr"></div><p id="upiApp"></p></div></div>
  <div class="card" id="bank" hidden style="margin-top:28px"><h3>Bank transfer (IMPS / NEFT / RTGS)</h3>
    <p style="color:var(--muted)">Send the amount below from your bank app or branch, then send the UTR / reference.</p><div class="kv" id="bdetails"></div></div>
  <div class="card" id="claim" hidden style="margin-top:28px"><h3>Paid? Send the reference</h3>
    <label for="cref" id="creflabel">UPI reference / UTR (12 digits, in your UPI app's payment details)</label><input id="cref" inputmode="text" autocomplete="off">
    <div class="btns" style="justify-content:flex-start"><button class="btn" id="claimBtn" type="button">I have paid</button></div><div id="cmsg"></div></div>
  <div class="card" id="find" style="margin-top:28px"><h3>Find my licence key</h3>
    <label for="femail">E-mail used when paying</label><input id="femail" type="email">
    <label for="fpay">UPI / bank reference you sent</label><input id="fpay">
    <div class="btns" style="justify-content:flex-start"><button class="btn" id="findBtn" type="button">Show my key</button></div><div id="fmsg"></div></div>
</div></section>
<script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js" defer></script>
<script src="/assets/buy.js" defer></script>
"""
    write("/buy.html", s.replace(f'<link rel="canonical" href="{SITE}/buy.html">', f'<link rel="canonical" href="{SITE}/buy.html"><meta name="robots" content="noindex">') + FOOT.replace("</body>", f"<script>window.BB_EMAIL={json.dumps(EMAIL)}</script></body>"))

# ---------------------------------------------------------------- legal and contact
def legal(path, title, desc, body):
    s = head(f"{title} — BillBox", desc, path)
    s += f'<section><div class="wrap legal" style="max-width:780px"><h1>{e(title)}</h1><p>Last updated {TODAY}.</p>{body}</div></section>'
    write(path, s + FOOT)

def legal_pages():
    legal("/privacy/", "Privacy policy", "How BillBox handles your data: your books stay on your devices.", f"""
<h2>Your books</h2><p>BillBox keeps your companies, bills, stock and ledgers only on your own devices. We do not receive, store or read them. Backups go to the folder you choose and, if you switch it on, to your own Google Drive using permission only for files BillBox itself creates.</p>
<h2>Licences and payments</h2><p>When you buy, we keep your e-mail, business name (if given), the plan, the payment ID (or the UPI / bank reference you send) and the anonymous ID of each device using the licence, so that the licence can be checked and recovered. We never see your bank login or UPI PIN.</p>
<h2>Website</h2><p>This website does not use advertising or tracking cookies.</p>
<h2>Your choices</h2><p>Write to <a href="mailto:{EMAIL}">{EMAIL}</a> to see or delete the licence data we hold about you.</p>""")
    legal("/terms/", "Terms of use", "The terms for using and buying BillBox.", f"""
<h2>The licence</h2><p>A BillBox licence lets you use BillBox on two devices at a time for the period bought (one year, or for life for the lifetime plan). It is for your own business and may not be resold or shared beyond two devices.</p>
<h2>Trial</h2><p>Each new installation can be used free for 15 days. After the trial, without a licence, BillBox stays usable to see, print, export and back up your books.</p>
<h2>Your data</h2><p>Your books are yours. Keep regular backups; BillBox makes a verified backup every day when it is switched on.</p>
<h2>Warranty</h2><p>BillBox is provided as is. We work to keep every figure correct and fix problems quickly, but you remain responsible for your GST returns and accounts.</p>
<h2>Seller</h2><p>{SELLER}, India. Contact: <a href="mailto:{EMAIL}">{EMAIL}</a>.</p>""")
    legal("/refunds/", "Refunds and cancellation", "BillBox refund and cancellation policy.", f"""
<h2>Try first</h2><p>Every BillBox app is free for 15 days with every feature, so you can be sure before paying.</p>
<h2>Refunds</h2><p>If BillBox does not work for you, write to <a href="mailto:{EMAIL}">{EMAIL}</a> within 7 days of paying with your payment ID. We refund the full amount to the original payment method within 5–7 working days and cancel the licence.</p>
<h2>Cancellation</h2><p>Yearly licences do not renew by themselves; nothing more is charged unless you buy again. There is nothing to cancel.</p>""")
    s = head("Contact BillBox", "Get help with BillBox, licences and payments.", "/contact/")
    s += f'<section class="hero"><div class="wrap center" style="max-width:720px"><h1>We\'re here to help.</h1><p class="lead">Questions about BillBox, licences or payments — write and we answer within a working day.</p><div class="btns"><a class="btn" href="mailto:{EMAIL}">{EMAIL}</a></div><p style="color:var(--muted);margin-top:22px">{SELLER}, India</p></div></section>'
    write("/contact/", s + FOOT)

def extras():
    pages = ["/", "/pricing/"] + [f"/{k}/" for k in ORDER] + ["/contact/", "/privacy/", "/terms/", "/refunds/"]
    write("/sitemap.xml", '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n' +
          "".join(f"  <url><loc>{SITE}{p}</loc><lastmod>{TODAY}</lastmod><priority>{'1.0' if p == '/' else '0.8'}</priority></url>\n" for p in pages) + "</urlset>\n")
    write("/robots.txt", f"User-agent: *\nAllow: /\nDisallow: /api/\nSitemap: {SITE}/sitemap.xml\n")
    write("/site.webmanifest", json.dumps({"name": "BillBox", "short_name": "BillBox", "icons": [{"src": "/assets/icon-192.png", "sizes": "192x192", "type": "image/png"}, {"src": "/assets/icon-512.png", "sizes": "512x512", "type": "image/png"}], "theme_color": "#4f46e5", "background_color": "#ffffff", "display": "standalone"}))
    write("/_headers", "/*\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: strict-origin-when-cross-origin\n  Permissions-Policy: camera=(), microphone=(), geolocation=()\n/assets/*\n  Cache-Control: public, max-age=86400\n/videos/*\n  Cache-Control: public, max-age=604800\n")
    s = head("Page not found — BillBox", "This page does not exist.", "/404.html")
    write("/404.html", s + '<section class="hero"><div class="wrap center"><h1>Page not found.</h1><p class="lead">The page you are looking for is not here.</p><div class="btns"><a class="btn" href="/">Go to BillBox</a></div></div></section>' + FOOT)

def admin():
    s = head("BillBox admin", "Licence administration.", "/admin.html")
    s = s.replace('<link rel="canonical"', '<meta name="robots" content="noindex, nofollow"><link rel="canonical"')
    s += """<section style="padding-top:56px"><div class="wrap" style="max-width:980px">
  <h2>Licences</h2><p style="color:var(--muted)">For the owner only. The admin token is kept in this browser.</p>
  <div class="card" style="margin-top:20px">
    <label for="tok">Admin token</label><input id="tok" type="password" autocomplete="off">
    <label>Licences of</label><div class="choices" style="grid-template-columns:1fr 1fr">
      <label class="choice"><input type="radio" name="env" value="test" checked><b>Test</b><span>admin apps</span></label>
      <label class="choice"><input type="radio" name="env" value="live"><b>Live</b><span>public apps</span></label></div>
  </div>
  <div class="card" style="margin-top:20px"><h3>Payments to confirm (UPI, bank)</h3><p style="color:var(--muted);font-size:14px">Check each reference in your bank / UPI app first; Confirm makes the licence and the buyer sees the key on the buy page.</p>
    <div class="btns" style="justify-content:flex-start;margin-top:10px"><button class="btn" id="loadClaims" type="button">Load</button></div>
    <div style="overflow-x:auto"><table id="claims" style="width:100%;font-size:14px;margin-top:14px;border-collapse:collapse"></table></div></div>
  <div class="card" style="margin-top:20px"><h3>Issue a licence (UPI, cash, free)</h3>
    <div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:0 16px">
      <div><label for="iplan">Plan</label><select id="iplan"><option value="yearly">Yearly</option><option value="lifetime">Lifetime</option></select></div>
      <div><label for="idays">Days (yearly)</label><input id="idays" type="number" value="365"></div>
      <div><label for="idev">Devices</label><input id="idev" type="number" value="2"></div>
      <div><label for="iemail">E-mail</label><input id="iemail" type="email"></div>
      <div><label for="iname">Name</label><input id="iname"></div>
      <div><label for="inote">Note (UPI ref…)</label><input id="inote"></div>
    </div>
    <div class="btns" style="justify-content:flex-start"><button class="btn" id="issue" type="button">Issue</button></div>
    <div id="imsg"></div></div>
  <div class="card" style="margin-top:20px"><h3>All licences</h3><div class="btns" style="justify-content:flex-start;margin-top:10px"><button class="btn" id="load" type="button">Load</button></div>
    <div style="overflow-x:auto"><table id="list" style="width:100%;font-size:14px;margin-top:14px;border-collapse:collapse"></table></div></div>
</div></section>
<script src="/assets/admin.js" defer></script>"""
    write("/admin.html", s + FOOT)

if __name__ == "__main__":
    home(); pricing(); buy(); legal_pages(); extras(); admin()
    for k in ORDER: platform(k)
    print("website built in", OUT)
