# Distributor Pro v4: FMCG distribution software for macOS

Node.js + Express + SQLite backend, Flutter macOS desktop frontend.

## Run it

Requirements: macOS, Node 20 or 22 LTS, Flutter (stable) + Xcode.

```bash
# 1. Backend
cd backend
npm install
npm run seed         # optional demo data for the open company
npm test             # optional: 32 automated checks on a throwaway database
npm start            # http://127.0.0.1:3000

# 2. Frontend (first time only, then just: flutter run -d macos)
cd ../frontend
./setup.sh
flutter run -d macos
```

## Builds and releases on GitHub
Every push is checked by GitHub Actions (all engines compared, Android app built); pushing a tag such as `v15.2.0` builds
the Android APK, the Mac app and the iPhone .ipa and publishes them as a release. See `docs/CI_CD.md`.

## v15.9 — Busy and Bizom bill designs, more themes, accent colours

- **Two more bill designs** (Settings › Printing › Bill design), on iPhone, Mac and Android:
  - **Busy style**: TAX INVOICE line, the firm centred, *Billed to* beside Invoice No. / Dated / Place of Supply / Reverse
    Charge, a full-grid item table (S.N., Description of Goods, HSN/SAC, Qty, MRP, Price, Disc %, GST %, Amount), the tax
    summary by HSN/SAC with Add : SGST / CGST and Rounded Off, and Receiver's Signature | Authorised signatory.
  - **Bizom style**: distributor and TAX INVOICE on a coloured band, the outlet with salesman, beat and payment, a striped
    table without column lines (SKU, MRP, Qty cases/pieces, Free, Rate, Gross, Scheme discount, Tax %, Net), "You saved ₹…"
    (schemes and free goods) and NET PAYABLE.
  - Both share the Marg style choices (colour — now also Teal and Orange — typeface, columns, compact totals…).
- **iPhone: Settings › Appearance stays open** while you change the theme, so you see each one at once.
- **Eight more themes** (Teal, Sky, Emerald, Plum, Sand, Peacock, Cherry, Olive), an **accent colour** of your own over any
  theme, **Background** Theme / Plain / Tinted, and **striped table rows** (iPhone, Mac; accent and background on Android too).

## v15.8.2 — Google Drive shows "Connected" at once

- iPhone and Mac: after connecting, Settings › Backup › Google Drive shows **Connected** (and the Client ID) straight away;
  before, the screen kept its old state until BillBox was opened again. The same fix lets the licence screen and other
  status panels refresh at once.

## v15.8.1 — Connect Google Drive always shows

- **Google Drive**: **Connect Google Drive** shows at once after importing the JSON file or saving the keys, on every app
  (iPhone, Mac, Android, Windows, Linux), and also sits under the key fields so it can never go missing. A JSON file that
  cannot be read (for example still in iCloud) now says so instead of doing nothing; on iPhone the file is copied in first.

## v15.8 — Restore from Google Drive, Connect right after importing, faster iPhone dashboard, typefaces, compact totals

- **Restore from Google Drive** (iPhone, Mac, Android): Settings › Backup › Google Drive › *Restore from Google Drive…* lists the
  backups in Drive › BillBox Backups; choosing one brings it to this device and asks Replace or Merge like any backup. A new
  install (or another device with the same Google keys) finds the BillBox Backups folder already in Drive instead of making a
  second one.
- **Google Drive buttons**: one style everywhere (full width, same height); after importing the JSON file **Connect Google
  Drive** appears at once (on iPhone it only appeared after opening BillBox again).
- **iPhone dashboard is faster**: figures are worked out once per load, kept per company and year (shown at once, refreshed
  behind), and the screen no longer redraws for every message in the app; card shadows are drawn from the card shape only, so
  every list scrolls more smoothly (Mac too).
- **More typefaces** (Settings › Appearance › Typeface): System, Rounded, Serif (New York), Mono, Condensed, Expanded,
  Compressed, Avenir Next, Helvetica Neue, Futura, Gill Sans, Optima, Georgia, Palatino, Baskerville, American Typewriter,
  Menlo. The chosen letters and weight now apply to the whole app (before, the choice was saved but not used).
- **Compact totals** (Settings › Printing, on by default): the totals take only the height their lines need; the Marg style
  shows only the bill's GST classes (unless "all" is chosen) and puts the bank details in the footer. More item rows fit on
  each page, so fewer bills run to a second page.
- **Icons follow the theme on iPhone**: every coloured icon (Settings, dashboard cards, ticks, the bill total, the Files
  picker and alerts) now takes the theme colour; before, iPhone kept the fixed indigo.

## v15.7 — Google keys from the downloaded file, tick boxes, compact bank details, more themes, Android icon

- **Google Drive**: import the `client_secret_….json` downloaded from Google Cloud instead of pasting the keys; Google's
  errors ("The OAuth client was not found", wrong client type, Drive API off, not a test user) are explained in plain words.
  The Drive section is beside the backup settings on the Mac and has cleaner buttons on iPhone, Mac and Android.
- **Tick boxes** in tables stay lined up, and a row is ticked only with its box (a click on the row no longer ticks it).
- **Price and party changes show at once** on the Mac (its connection to the books no longer keeps old answers).
- **Bank details** print in three short lines where the bill has room anyway (the footer, or under the GST classes in the
  Marg style): no item rows are lost. **ORIGINAL / DUPLICATE** on each copy can be switched off. Marg style: E-Mail,
  GSTIN and State code lined up.
- **Appearance**: seven more themes (Midnight, Mint, Lavender, Saffron, Crimson, Coffee, Graphite) and a choice of
  letters (System, Rounded, Serif, Mono) and weight. Changing the theme or saving a setting keeps you on the same page.
- Android: the dashboard tiles are all the same size; the app icon is the same as on iPhone and Mac.
- Mac: clicks in tables respond at once (no double-click wait).

## v15.6 — Marg style bill design

- **Settings › Printing › Bill design**: "BillBox (clean, modern)" or **"Marg style"**, laid out like a Marg ERP bill: firm and
  M/s party side by side, GSTIN | GST INVOICE | Invoice No., Date, Sales Man, Due Date, then Sn. Box Pcs Free Pack Product
  MRP Exp. HSN Rate Dis SGST CGST Amount, the GST CLASS table with SUB TOTAL … GRAND TOTAL beside it, the amount in words,
  bank details, and Terms & Conditions | Receiver | Authorised signatory.
- Marg style choices: colour (Marg blue, black only, green, maroon), serif or modern letters, rate and MRP per box or per
  piece, all GST classes or only the bill's, each optional column, M/s, due date (party's credit days), receiver box,
  page number, company e-mail. IGST replaces SGST and CGST on bills to another state.
- **Preview on my latest bill** shows the chosen design at once.

## v15.5 — Google Drive backups, bank details on bills, ledger by year, many bills at once

- **Google Drive backups** (Mac, iPhone, Android): Settings › Backup › Google Drive. Sign in once with a short code at
  google.com/device; every backup then also goes to Drive › BillBox Backups. Setup: [docs/GOOGLE_DRIVE.md](docs/GOOGLE_DRIVE.md).
- **Bank details on the bill**, above the amount in words, one per line (bank, account name, number, IFSC, branch,
  branch code, address): Settings › Print › Bank details. "Bill to:" now has its colon.
- **Ledger of an earlier year**: Parties › ledger › Year (also for years kept in their own file).
- **All Bills: tick several bills** and Print them together, Mark printed, or send on WhatsApp.
- **PDF purchase bills** match items with a slightly different spelling or size format (200 GM = 200g) and add the stock
  to the existing item; an existing supplier gets missing GSTIN, phone and address filled in from the bill.
- **Dashboard tiles** are all the same size.
- **WhatsApp on iPhone**: choose "The WhatsApp app" (share sheet, nothing to link) or "WhatsApp Web in BillBox"; linking
  WhatsApp Web now opens the desktop page, so both the QR and phone-number code work.

## v15.4 — Marg prices per piece, quantity first, bolder Bill to, Mac .dmg

- **Marg prices**: an item without past sales got Marg's Rate A divided by the case size in its name ("Boondi Salted 38g
  (250 PKT)": ₹0.32 a packet instead of ₹7.90). Rate A is now divided by the pack it is really for (Marg's own pack, the case,
  or one piece, checked against the last purchase rate); sale rates come from rows in the item's usual billing pack (a later
  change of pack in Marg made one item ₹47.62 a packet); MRP and purchase rates follow the same pack. Items already in your
  books: Settings › Import from Marg › choose the backup › **Check item prices against this backup** › Correct (only prices
  twice or half of Marg's are changed).
- **Billing**: picking an item puts the cursor in that line's Box (Pcs for loose items); the first digit typed replaces the 1.
  iPhone: "Next item" above the number pad goes back to the search; Mac: Return does. The empty bill's hint no longer sits on
  the table headings.
- **Print**: "Bill to" and the party in bold and larger; the buyer's address, GSTIN and phone a size up.
- **WhatsApp on iPhone**: the WhatsApp page now asks for the desktop site and looks like a Mac to WhatsApp's checks (a phone
  was sent to "download the app", with no QR code and no phone-number login). If the code still doesn't come, the message
  says what the page shows.
- **iPhone backups**: while they are in BillBox's own folder (deleted with the app) Settings shows a warning and
  Settings › Backup offers "Choose a safe folder…" (iCloud Drive, or a folder made in Files outside BillBox).
- **Mac**: releases include BillBox-mac-<version>.dmg (open, drag to Applications); ./macos/build_dmg.sh makes one locally.

## v15.3 — print, companies, iPhone fixes, WhatsApp linking, Android fixed and tested on emulators

- **Print**: a full-weight line between "Amount in words" and the totals, down beside GRAND TOTAL (Android's grey shading
  used to cover it). New option Settings › Printing › "Company and Bill to in CAPITALS". Android's small print text
  (address, terms, GST table) is no longer squeezed.
- **Delete a company**: Settings › Companies › Delete (type the name to confirm). The books are hidden, not erased: the
  file stays, and earlier backups still hold it. The last company can't be deleted.
- **Clear message for duplicates**: adding a category or batch that already exists says so (it said "Server error" on every
  engine, because Node's SQLite reports these differently from what the check expected).
- **iPhone**: tables (Stock, Parties, All Bills, every list) no longer slide under the bottom bar; printing through AirPrint
  (including a USB printer shared from a Mac) draws each page fitted to the paper instead of sending a PDF that printed blank.
- **WhatsApp (Mac, iPhone)**: "Link with phone number" gives an 8-letter code to type in WhatsApp › Linked devices › Link
  with phone number instead — the way to link when WhatsApp is on the same iPhone. WhatsApp Web now sees a current Safari.
- **Android**: the bill's lines were hidden under the table heading (the heading filled the screen in the bill table);
  phone tables lead with party and amount; the bill shows each line's amount under the item; buttons no longer cover totals;
  a stuck request can no longer freeze every screen.
- **Android self-test on GitHub** (Actions › Android self-test): Android 12 and 14 emulators replay the full working session
  through the app's real engine (472 steps, compared with the Mac), screenshot every screen, then tap through billing,
  save & print, parties, stock and settings. Results land on the `selftest-results` branch.
- **Look**: a new default "Clean" theme on all three apps (calm greys, white panels, one indigo accent), quieter tables
  without column lines, and one type scale on Android. The old themes stay under Settings › Appearance.

## v15.2 — Marg numbering and more print settings (Mac, iPhone, Android)
- **Numbering like Marg**: each series has its own prefix and digits (A000001, P000001, DNB00001), and a new number always
  carries on after the last one used — so after the Marg bills imported up to A000422, the next bill is A000423. A Marg
  import switches to Marg's pattern by itself (unless you set your own); Settings › Numbering shows the last and next
  number of each series, can set where it carries on, and has a one-tap "Use Marg's numbering".
- **Printing**: show or hide the party's details, salesman, payment, GST table, terms and the Taxable column; print the
  party's previous balance and total due; item names in capitals; quantity in pieces only; smaller or larger text; a third
  copy; a line under the company name, bank details and a note at the bottom.

## v15.1 — iPhone billing search
- Typing an item name no longer makes the search field vanish under the top bar, and the bill scrolls again with the
  keyboard up: the suggestions now float over the bill (scrolling when there are many) instead of adding to its height.

## v15.0 — BillBox for Android, and two iPhone billing fixes
- **iPhone**: the number pad no longer closes when you tap Box or Pcs on a bill longer than the screen (every bill row is
  kept while you type, and scrolling never hides the keyboard); with the keyboard up, the item list no longer slides under
  the company name (the top bar stays solid).
- **Android app** (Android 12 and up) in `android/`, with every screen and setting of the iPhone app, built the Android way
  (Material 3, Jetpack Compose, dynamic colour from your wallpaper as one of the themes, dark mode, bottom tabs on phones and
  a side rail on tablets, Android's share sheet, file picker, print service and system Back). See `android/README.md`.
  - The **engine is the Mac's own** (`backend/src`), bundled and run inside the app, so the books, bill numbers, GST
    figures and backups are exactly the Mac's and iPhone's: a backup from any of the three restores on the others.
    `./build.sh test` replays the full parity scenario (445 steps, 1,647 random bills, parser, Marg import and the GST
    Excel file) through the bundled engine with Android's rules: 0 differences.
  - **Build and run**: plug the phone in (USB debugging on) and run `cd android && ./build.sh`. It finds Java and the
    Android SDK (Android Studio's, or `./build.sh setup` downloads just what is needed), builds, installs and opens BillBox.
    `./build.sh run` also shows the app's log; `./build.sh wifi IP:PORT` uses Wi-Fi debugging; `./build.sh apk` makes an
    APK to copy to any phone.

## v14.19 — payments-from-photo button and more settings
- **Payments from a photo**: on Parties › Customers a card above the list opens it (it was a small toolbar icon). In the
  sheet, *Take photo* and *Choose photo* are two equal tiles; on the iPhone a tap on one no longer also fires the other.
- **New settings**
  - Billing & Dashboard: a new line starts as one box or one piece; keep the party for the next bill; ask (or not) before
    billing over a credit limit; the screen BillBox opens on; **Numbering** — your own prefix for sale bills, receipts,
    purchases, payments and debit notes (e.g. "A" → A00001, "AKE" → AKE/26-27/00001), with or without the year, 3–6 digits.
  - Parties & Payments (new page): price tier, credit limit and credit days for new customers; default payment mode;
    print the receipt after saving a payment or not; show or hide the payments-from-photo card.
  - Stock: how many days ahead the dashboard warns about expiry.
- Engines: numbering and the expiry window follow the settings on both (parity-tested).

## v14.18 — e-way bill for a bill
- All Bills › a sale bill › **E-way bill…** (row menu, or the bill's own window), on Mac and iPhone.
  1. Transport: PIN codes (read from the two addresses when they contain one), distance, road / rail / air / ship,
     vehicle number (or transporter ID), transporter name, RR / airway bill number for rail and air.
  2. *Make the e-way bill file*: the JSON the government portal takes (ewaybillgst.gov.in › e-Waybill › Generate Bulk,
     NIC bulk format 1.0.0621): both parties, every item with HSN, quantity, taxable value and GST rates, bill totals.
     It checks the bill first (your GSTIN, PIN codes, HSN on every item, vehicle / transporter) and warns when the bill
     is under ₹50,000 or already has an e-way bill.
  3. Type the 12-digit number the portal gives (with its date and validity): it is saved on the bill and printed on it.
- Engine: `GET|POST|PUT /invoices/:id/ewaybill` (`ewayBill.js`, `EwayBill.swift`), parity-tested on both.
- Optional setting `company_pincode` is used when your address has no PIN code.

## v14.17 — wholesale customers
- A customer changed to the Wholesale price tier is billed at each item's wholesale price. Items with no wholesale price of
  their own (0) are billed at the retail price instead of at nothing (both engines and the live bill maths).
- Marg backups carry one sale rate, so imported items start with the same retail and wholesale price. The billing screen
  now says so under the customer ("N items have no separate wholesale price …") — set wholesale prices with
  Stock › More › Set prices from MRP (Wholesale % below MRP, or a wholesale price for each MRP).

## What changed in round 5 (v14.16, Mac and iPhone together)
- **Prices from MRP now bill exactly what was set.** The billing screen kept the item list it loaded when it first opened,
  so prices changed later (Set prices from MRP, item edits, imports, merges) were not used until the app was restarted —
  an old ex-GST price of 2,500 billed as 2,950. Billing now reloads its items whenever items or prices change.
- **Set prices from MRP rewritten** (`POST /items/set-prices`, `GET /items/mrp-table`; `pricing.js`, `Pricing.swift`):
  % below MRP or a price for each MRP, retail and/or wholesale, per box or per piece, with or without GST, rounding of
  the box price (rupee, ₹5, ₹10 or none). A live preview lists every item with its MRP (piece and box) and what one box
  comes to on a bill, using billing's own arithmetic; the old bill amount is shown struck through.
- **Similar-name duplicates**: Tidy names & merge duplicates finds the same name, similar names (Bhujia / Bhujiya, word
  order, capitals, a generic word like "Biscuit") or loosely similar ones; different pack sizes, MRPs and box sizes are
  never grouped. Any item can be left out of a group and the item to keep chosen. Stock › select items › *Merge selected…*.
- **Look**: panels with a soft shadow, outline or flat style; square, rounded or round corners; coloured settings icons.
- **More settings**: Appearance — panels, corners, table row height, text size (iPhone) / interface size (Mac).
  Billing & Dashboard — round the bill total to the rupee or not (amount in words then says the paise), discount % on
  every new line, GST % for new items.
- **Smoother**: the billing screen loads every item (the 1,000-item limit is gone), typing in a list's search loads once,
  and returning to Billing no longer loads twice.

## What changed in round 4 (v14.15, Mac and iPhone together)
- **Financial years as separate books (Marg style)**: Settings › Companies › *Financial years* starts a year as its own file,
  either carrying forward (items, parties, schemes, stock in hand and closing balances become the new year's opening) or
  empty (for an earlier year's Marg data). The year menu opens a year's own file; companies are listed once by name.
  Marg import refuses data that belongs to another year (`WRONG_YEAR`). Backups and restores keep every year file.
  Engine: `POST /companies/:id/years {fy, carry}` (`backend/src/services/years.js`, `Years.swift`).
- **Save now, print later**: Settings › Printing › *After saving a bill* (print / ask / keep for later); All Bills ›
  *Not printed* filter and *Print N bills* (one job, in date order); printed bills are marked. `POST /invoices/printed`.
- **Payments from a photo of a handwritten list**: Parties › *Payments from photo* (and the dashboard). One line per
  party: `name, bill, bill, … - payment`. The photo is read on the device (Apple Vision, handwriting included); every
  line is matched to a party and its bills, shown for checking, then all receipts are saved together.
  `POST /receipts/sheet/parse`, `POST /receipts/sheet` (`paymentSheet.js`, `PaymentSheet.swift`).
- **Items from the internet**: Stock › More › *Items from the internet…*: search for the company's price list, open a
  page or PDF (or paste a link or the list), names tidied ("200 GM" → 200g), items listed twice kept once, items you
  already have marked; add the ticked ones in one go. `POST /items/online/search|fetch|extract`, `POST /items/bulk-add`.
- **Tidy names & merge duplicates**: Stock › More: pack sizes / spacing / case tidied, and items entered twice merged
  (bill lines, purchases, debit notes, batches and schemes move to the item kept). `GET /items/clean-preview`,
  `POST /items/clean-names`, `POST /items/merge` (`itemTools.js`, `ItemTools.swift`).
- **Dashboard redesign**: today / month / year switch, quick actions, alerts (bills to print, low stock, expiry),
  cards and rows that open their screen, a month-by-month chart you can tap (sales, purchases or profit), best
  sellers and latest bills.
- **More settings**: Printing (bill title, columns, amount in words, signature line, copy labels, after-save action);
  *Billing & Dashboard* (payment and sale type of a new bill, the period the dashboard opens on, which sections it shows).
- **Speed**: compiled SQL statements are reused on the iPhone engine; Marg field cleaning and unzip are faster.

## What changed in v4
- **Native macOS app in Swift** (`macos/`, SwiftUI, macOS 14+): see `macos/README.md`. The Flutter app in `frontend/` still works and is kept for older macOS versions.
- **Adjustable columns** (resize, reorder, show/hide, remembered) on every table in the Swift app.
- **MRP extraction**: the bill's MRP column and names like `MRP-10/-`, `Rs.10/-`, `10/-`, `@25` are read; `POST /items/auto-mrp` fills missing MRPs
  (and empty selling prices) and reports found / missing per category.

## What changed in v3.1
- **Scan a supplier PDF and everything is filled in.** Supplier and every new item are created automatically with the printed
  HSN, GST rate (from the bill's CGST+SGST %, else the built-in HSN table), MRP and pieces per box read from the name
  (`(1X144)` means 144 pcs per box). Stock is kept in pieces: 2 BOX x 144 = 288 pcs. Discount, CGST, SGST, round off and the
  grand total are read from the bill and reconciled (a warning shows if they differ by even 1 paisa).
- **Category from the item name**: keyword rules first, then an internet lookup (Open Food Facts, 4 s timeout, never blocks).
  Stock has an "Auto categories" button for items that have none.
- **Indian dates (DD-MM-YYYY)** on every screen, print and report; calendar pickers everywhere a date is typed.
- **Batch and expiry removed** from screens and printouts. Stock is still tracked internally (hidden default batch).
- **Overflow fixed**: dropdowns are now ellipsis-safe pickers instead of Flutter's DropdownMenu.
- **Billing page**: type-ahead item suggestions with stock and MRP, S.No header, bill date picker.
- **Set prices from MRP** (Stock screen): pick a category (or all), enter retail and/or wholesale % below MRP; price = MRP without GST less that %. Preview first.
- Bikano and All Time Mix items always go to Namkeen & Snacks ("Auto categories" also moves existing ones).
- `file_picker` is pinned below 11 (v11 removed `FilePicker.platform`). Delete `pubspec.lock`, then `flutter pub get`.

## What changed in v3

1. **One look everywhere.** `buildTheme()` in `widgets.dart` sets the palette, one 44 px height for every text box and dropdown
   (`AppField`, `AppDropdown`), buttons, cards and tables. Long text is cut with an ellipsis, forms and toolbars wrap instead of
   overflowing, the sidebar collapses to icons under 900 px, and billing/purchase stack on narrow windows.
2. **Items** have no SKU, barcode or reorder level. Items are found by name or HSN. Existing databases are migrated on first start
   (the items table is rebuilt; every other column and all bills are kept). Low stock now uses one company level
   (Settings > Stock, default 10 pieces).
3. **PDF scanner reads only "Original" / "Original Copy" pages** and skips Duplicate, Triplicate, Transporter and Office copies.
   Pages with no label stay with the copy before them; identical repeated pages are dropped. Page headers, column headers,
   "Page x of y" and "Continued" lines are removed from later pages so item rows run on cleanly, and S.No is renumbered 1..n.
4. **Supplier details:** name, address, GSTIN, state code, Tel, Phone, several Mobile numbers, FSSAI, PAN (filled from GSTIN),
   email. Read from the bill, editable in Parties.
5. **Purchase bill rows:** Item name, HSN code, Qty, Unit, Price, Amount. The item name is read from the description (second)
   column and each value from its own column. A BOX/CASE unit is converted to pieces with the item's "pieces in one box".
6. **Totals:** Discount, CGST, SGST (IGST for other-state suppliers), Rounded off and the printed Grand total are read from the
   bill. Total = items − discount + taxes + round off. If a tax box is empty it is worked out from item GST rates ("Auto tax").
   A warning shows when the total differs from the printed one.
7. **Edit saved bills.** All bills > Edit opens a sale in Billing or a purchase in Purchases. Saving reverses the old stock and
   ledger entries and writes the corrected bill under the same number, in one transaction. A purchase cannot be edited if its stock
   was already sold.
8. **GST > Export month to Excel**: Summary, B2B Bills, B2C Bills and Rate-wise Summary sheets (`GET /reports/gst-outward.xlsx?month=YYYY-MM`).
9. **Printing:** sharper grid and totals box on invoices, and a new Receipt/Payment voucher (half-A4, party and office copy) that
   opens in the same print manager after recording a payment.
10. **Robustness:** validation on items, parties (GSTIN, PAN, FSSAI, email), purchases and dates; extra database indexes;
    debounced search; automated tests for all of the above.

**Upgrading from v2:** replace `backend/src`, `backend/package.json`, `backend/test` and all of `frontend/lib`,
`frontend/pubspec.yaml`, `frontend/setup.sh`; run `npm install` and `./setup.sh` again (it adds the permission to save
Excel files). Keep `backend/data`: the items table is migrated automatically. Back up first (Settings > Backup).

**Upgrading from v1:** keep your `backend/data` folder. On first start the old `distributor.db` is adopted as
company #1 and upgraded in place (new tables and the `pcs_per_box` column are added; nothing is deleted).
Copy the new `backend/src`, `backend/package.json`, `backend/test` and the whole `frontend/lib`, `frontend/pubspec.yaml`,
`frontend/setup.sh` over your project, run `npm install`, then `./setup.sh` again (it adds the printing and
file-picker permissions and new packages).

## Where each feature lives

| # | Feature | Backend | Flutter |
|---|---|---|---|
| 1 | Dashboard | `services/reports.js` `dashboard()` | `screens/dashboard_screen.dart` |
| 2 | Multi-company | `db.js` (one SQLite file per company + `registry.db`), `routes/companies.js` | `state/app_state.dart`, sidebar switcher, Settings > Companies |
| 3 | PDF bill scanner | `services/pdfExtract.js`, `services/pdfParser.js`, `POST /purchases/parse-pdf` | `screens/purchase_screen.dart` |
| 4 | Vendor payments + ledger | `services/vouchers.js`, `POST /vouchers`, `GET /parties/:id/ledger` | Parties > Payment / Ledger |
| 5 | Party CRUD + route on the fly | `routes/parties.js` (`new_route` in the same transaction) | `screens/parties_screen.dart` (`_PartyForm`) |
| 6 | Item CRUD | `routes/items.js` | `screens/inventory_screen.dart` |
| 7 | Purchase bills update stock | `services/purchases.js` | Purchases screen |
| 8 | Box + Pcs billing | `services/billing.js` (`boxes`, `pcs`, `pcs_per_box`) | `screens/billing_screen.dart` |
| 9 | HDD backup | `services/backup.js`, `routes/backup.js` | Settings > Backup |
| 10 | In-app print manager | `GET /vouchers/:no` | `print/print_dialog.dart`, `print/print_jobs.dart`, `print/voucher_pdf.dart` |
| 11 | Half-A4 dual-copy engine | `GET /invoices/:id` supplies `gst_summary`, `amount_words`, `supply` | `print/invoice_pdf.dart` |
| 12 | All Bills | `GET /bills` | `screens/bills_screen.dart` |
| 13 | Sales / Purchase book | `GET /reports/book/:type` | `screens/reports_screen.dart` |
| 14 | GST outward by slab + Excel | `GET /reports/gst-outward?month=`, `.xlsx`, `utils/xlsx.js` | `screens/reports_screen.dart` (GST tab) |
| 15 | Edit saved bills | `PUT /invoices/:id`, `PUT /purchases/:id` | All bills > Edit; Billing / Purchases screens |

## How the main pieces work

**Companies.** Each company is a separate database file, so books can never mix. Every request carries an
`X-Company-Id` header; `db.js` hands the right database to the existing query code through `AsyncLocalStorage`,
so routes and services still just `require('../db')`. Switching company in the app rebuilds every screen under a new key.
Back up copies every company plus the company list.

**Purchases.** `createPurchase` runs in one transaction: bill, lines, batch upsert (received pieces added to the batch,
same batch number tops it up), item cost update (landed cost after discount), supplier ledger credit, optional payment. The same
supplier invoice number from the same supplier is refused unless you confirm, so one PDF cannot be posted twice. Batches are internal only now (a hidden default batch per purchase).

**Ledger sign.** balance = debit − credit. Positive: they owe you (customers). Negative: you owe them (suppliers).
Dashboard "Outstanding dues" is receivables only; payables are shown in its subtext.

**PDF scanner.** Text-layer PDFs are read with `pdf-parse`. If a PDF has no text (a scan), it uses `pdftoppm` + `tesseract`
when installed (`brew install poppler tesseract`), otherwise it tells you so. The parser finds supplier (by GSTIN, then name),
invoice number, date and item rows, matches rows to your stock list, and leaves everything editable. It never saves anything.
Layouts differ between suppliers, so treat it as a fast first draft: expiry and batch are usually not printed in a readable
column and must be typed in. "View text read from PDF" shows exactly what the parser saw, which is the first thing to
check if a bill reads badly.

**Half-A4 printing.** A half-A4 sheet is 210 × 148.5 mm. Each sheet is built from fixed-height blocks and one-line item rows,
so capacity is arithmetic (`Geo.cap` in `invoice_pdf.dart`): about 15 items on a single sheet, 23 on a first sheet that continues,
27 on middle sheets, 19 on a last sheet that carries the totals. Longer invoices continue on the next half-sheet with a
"continued" header; totals appear only on the last sheet. Layouts: Original + Duplicate each on their own half-A4 sheet,
Original on top and Duplicate below on one A4 sheet (cut line), or Original only. Long item names are shortened with ".."
so a row never wraps. Prices print as "Rs." because the built-in PDF font has no rupee glyph.

**Print manager.** The preview is rendered inside the app from the same PDF that is sent to the printer. It lists
printers, sets layout and copies, and keeps a job list with status and reprint. It saves your choices per company.
"Print straight away" skips the preview. If macOS direct printing is unavailable, Print falls back to the system print sheet.

## Keyboard

F2 / ⌘K item box · F4 / ⌘N new bill · F9 / ⌘Enter save and print · ⌘1 to ⌘9 switch screens.
(F-keys need **fn** on a MacBook unless you set "Use F1, F2 etc. keys as standard function keys".)

## Not built yet

Login and roles · sales returns, credit notes, cancelling a saved bill · stock adjustments and
stock transfer · e-invoice (IRN) and e-way bill · GSTR JSON export (the GST tab copies as CSV) · Hindi or other non-Latin
text on printed invoices (needs a bundled TTF font in `invoice_pdf.dart`) · automatic restore from a backup (restore is the
manual copy described in Settings > Backup).
