# BillBox iOS: Feature Parity Contract

Source of truth: BillBox for macOS v14.11.0. Read in full: the SwiftUI app (`macos/Sources/DistributorPro`, 24 files) and the server baked inside it (`backend/src`, 33 files). The old Flutter app in `frontend/` is not part of the Mac app and is out of scope.

**How the Mac app is built (this matters for the port).** The Mac app is a SwiftUI front end that talks over HTTP to a Node.js server packed inside the app bundle. **All** business logic lives in that JavaScript: numbering, billing, stock, ledgers, reports, backup, the PDF parser and the Excel writer. iOS cannot run Node, so the iOS app gets a Swift port of every server function listed here, running on-device against the same SQLite files. The Swift UI screens are adapted from the Mac Swift code.

Status key: `[ ]` not done · `[x] ✅` done on iOS · `⚠` was a decision (section 0; all approved with the recommended option).

---

## 0. Decisions (approved: D1 (a), D2–D11 as recommended)

These are the places where a Mac feature cannot work identically on iOS, or where the code and your feature list disagree. Each needs a yes or a choice.

**⚠ D1: WhatsApp auto-send (Settings > WhatsApp, Bill detail > WhatsApp, auto-send after saving a bill).**
On the Mac, WhatsApp Web runs in a hidden window parked off-screen. The app opens the customer's chat, attaches the bill PDF and presses Send by itself, in the background. When scripted clicks fail it falls back to real macOS mouse clicks, key presses and the system clipboard. iOS does not allow hidden off-screen windows or synthetic mouse and keyboard events. It also suspends the app about 30 seconds after you leave it.
Closest iOS options:
- **(a) Same WhatsApp Web automation, foreground only.** An in-app web view with a desktop browser identity, the same QR linking and the same send steps, minus the macOS mouse, keyboard and clipboard fallbacks. Sending only works while BillBox is open on screen. It is more fragile than the Mac version.
- **(b) Share sheet.** The bill PDF and message open the iOS share sheet, and you tap WhatsApp and the chat. This is reliable but not automatic.
- **(c) WhatsApp link.** `whatsapp://send?phone=…&text=…` opens the customer's chat with the message typed. You then attach the PDF yourself.

**⚠ D2: "Also back up whenever I quit the app".**
iOS has no quit event. Apps are suspended and killed silently. The closest equivalent is to back up each time BillBox goes to the background. iOS allows about 30 seconds for this, which is enough for normal-size books.

**⚠ D3: Daily scheduled backup at a set time.**
The Mac checks every minute *while the app is open* and also catches up 5 seconds after launch. iOS can do exactly the same while BillBox is open, plus on launch and on return to the foreground. When BillBox is closed, iOS may run a background task (BGTaskScheduler), but iOS alone decides when that happens, sometimes hours late or not at all. Please confirm that this is acceptable.

**⚠ D4: Backup folder.**
On the Mac you type or choose any folder path (default `~/DistributorProBackups`). On iOS the default would be `On My iPhone › BillBox › DistributorProBackups` in the Files app, and "Choose…" lets you pick any Files folder: iCloud Drive, a USB drive or another provider. Backups use the identical folder layout (`FMCG_Backup_YYYYMMDD_HHMMSS/…db + registry.db + manifest.json`), so a Mac backup folder copied to the iPhone restores, and the reverse also works.

**⚠ D5: Scanned PDFs (no text layer).**
The Mac reads them with the `poppler` and `tesseract` tools only when you have installed them with Homebrew. Otherwise it shows "This PDF is a scan… install the OCR tools". iOS cannot run those tools. The options are Apple's on-device Vision text recognition (a different OCR engine, so results can differ from tesseract), or showing the same "this PDF is a scan" message and reading no text.

**⚠ D6: Reading text from PDFs (text-layer PDFs, the normal case).**
The Mac uses `pdf-parse` (Mozilla pdf.js) and joins text pieces into lines by their position on the page. iOS will use PDFKit with the same line-joining rule ported exactly. The parser that runs on that text is ported line for line and tested against your two fixture bills. The raw text the two PDF engines produce can still differ slightly for some supplier PDFs. To prove parity, please send 3–5 real supplier PDFs, and I will compare Mac and iOS text and parse results for each.

**⚠ D7: Printer choice and "Print straight to this printer (no preview)".**
The Mac lists every installed printer by name, including USB printers. iOS has no printer list. It can only show the AirPrint printer picker and remember the chosen printer by its address. Silent printing to that remembered printer works. The setting `print_printer` is stored inside the company database, which also goes into backups. My proposal is that iOS keeps its chosen printer on the iPhone and leaves the Mac's printer name untouched, so moving books between devices never breaks either side.

**⚠ D8: Building and testing.**
I can compile and run the shared Swift logic here (database, calculations, parser, Excel, backup and restore) and test it against your original Node engine for identical results, including backups in both directions. I cannot compile the iOS screens here because there is no Xcode, so you would build the app in Xcode on your Mac. If you build on macOS Monterey, the newest Xcode there is 14.2 (Swift 5.7, iOS 16.2 SDK), and I will keep all code compatible with it. Tell me if you use a newer Xcode.

**⚠ D9: Things in the code that differ from your feature list (code wins, so these are ported as the code does them).**
- The billing summary is a **bottom bar of three equal cards** (customer/payment · working · total with buttons), not a right sidebar at the top.
- A new bill line starts at **1 box only when the item has more than 1 piece per box**. Otherwise it starts at 1 piece.
- F2/F4/F9 shortcuts exist only in the old Flutter app. The Mac SwiftUI app uses ⌘K, ⌘N, ⌘S and ⌘1–⌘9 (section 14).
- Backup folders are named `FMCG_Backup_YYYYMMDD_HHMMSS`. The Indian date and time format appears in the backup list and "Last backup" line.
- Batches and expiry are hidden everywhere but still used internally: each purchase has a hidden batch, bills take stock first-expiry-first-out (FEFO) and skip expired batches.

**⚠ D10: Server functions that no Mac screen can reach.**
These exist in the server, but nothing in the Mac app calls them: re-read pieces per box from names (`/items/auto-pack`; the function exists but has no button), edit or deactivate a salesman, edit or delete a route, expiry report, outstanding report, low-stock list endpoint, day lists of invoices and receipts, HTML invoice page, scheme list and delete, demo seed data, and the old GST summary. Following "no new features", these are **not** added to iOS screens. The logic that screens or automatic processes use is ported.

**⚠ D11: Mac-only plumbing with no iOS counterpart (not features).**
The "Server is not running" screen, Start server, Choose backend folder, `server.log`, and the "Cannot reach the server" error do not apply, because everything runs inside the app. These are dropped.

---

## 1. App shell and navigation

- [x] ✅ App name **BillBox**, existing icon (`macos/Icon/AppIcon.png`), bundle category Business.
- [x] ✅ Launch: "Opening your books…" progress until the companies are loaded. Opens on **Billing**.
- [x] ✅ Locale `en_IN` everywhere (₹1,23,456.00, DD-MM-YYYY).
- [x] ✅ Nine sections, grouped as on the Mac sidebar:
  - Sell: **Billing**, **All Bills**
  - Buy & Stock: **Purchases**, **Stock**
  - People: **Parties**, **Salesmen**
  - Accounts: **Dashboard**, **Books & GST**
  - **Settings**
  - Icons: cart, doc.text, shippingbox, archivebox, person.2, figure.walk, gauge.with.dots.needle.67percent, books.vertical, gearshape.
- [x] ✅ iOS: TabView with 4 tabs plus a 5th "More" tab holding the rest, each with a NavigationStack. All nine are reachable.
- [x] ✅ Billing keeps its half-made bill while you visit other sections.
- [x] ✅ Every screen is rebuilt when the company or financial year changes.
- [x] ✅ **Company switcher** (top of sidebar → iOS: toolbar menu on every section): lists active companies with a checkmark on the open one. Choosing one calls activate (saves `last_company`), reloads settings and resets the year to the current one.
- [x] ✅ **Financial-year switcher**: each item reads "FY 2026-27  (01-04-2026 to 31-03-2027)", "· current" on the current year, and a checkmark on the open one. The label shows "Financial year X" with "Current year", or "Past year · view and edit" in orange.
- [x] ✅ **Toast banner** at the bottom: green check or red warning icon, text up to 4 lines and selectable, an X to close. It disappears after 3.5 s (errors after 7 s). Every failure anywhere shows here instead of crashing.
- [x] ✅ Theme tint and light/dark/automatic appearance applied app-wide (section 12).

## 2. Companies and financial years

- [x] ✅ Registry database `registry.db` holds the company list (`companies`) and app-level settings (`app_settings`). Each company has its own database file `company_<timestamp>.db`.
- [x] ✅ First start: if no company exists, create "My Company". If a legacy `distributor.db` exists, adopt it as company #1 and take its name from its settings.
- [x] ✅ Opening a company applies the schema and upgrades (section 15), then runs **tidy items**: for every item, pieces per box is taken from its name when the name has a pack size, and every item's unit is set to `PCS`.
- [x] ✅ On launch, open the last used company (`last_company`), else the first active one.
- [x] ✅ **Settings › Companies**: list with name and "GSTIN · address". The open company shows "Open ✓". Others have an **Open** button. Every row has **Edit…**. **New company…**.
- [x] ✅ **Company sheet** (new/edit). Fields and defaults:
  - Company / business name (required; Save disabled when blank)
  - GSTIN (blank if unregistered). Must match `^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$` (case-insensitive) and is stored uppercase.
  - State code. Default `09`. Must be 2 digits.
  - Address
  - Phone
  - Terms printed on invoices. Default "Goods once sold will not be taken back."
  - Saving a new company creates it and switches to it. Editing updates its settings and the registry name.
- [x] ✅ Error text inside the sheet when saving fails, for example "GSTIN format is not valid" or "State code must be 2 digits, e.g. 09".
- [x] ✅ **Financial year** = 1 April to 31 March, label `2026-27`. Accepted label forms are "2026-27", "2026-2027" and "2026". Non-consecutive years are refused.
- [x] ✅ Year list = every year from the earliest dated record (invoices, purchases, receipts, payments, ledger) through the latest invoice or purchase, always including the current year, newest first.
- [x] ✅ Every list, report and the dashboard show only the selected year (rules per screen below).
- [x] ✅ **dateInFY**: today clamped into the open year. This is the default date for new bills, purchases and vouchers. **monthStartInFY** = first day of that month.

## 3. Items and stock (Stock screen)

### 3.1 Screen
- [x] ✅ Title "Stock", subtitle "N items".
- [x] ✅ Search "Search item or HSN", debounced 250 ms. It matches name or HSN with LIKE, and Return also runs it.
- [x] ✅ Category filter: "All categories" plus every category.
- [x] ✅ Table (layout key `stock`). Columns in order: S.No · Item · Category (grey when empty) · HSN · Stock (box + pcs), bold and orange when stock ≤ low-stock level · Pcs per box ("–" when 1) · Total pcs (**hidden by default**) · MRP · Retail · Wholesale · Retail / box (incl. GST) = retail × ppb × (1+GST%), "–" when ppb is 1 · Wholesale / box (incl. GST), same rule · Cost · GST · Your margin · Retailer margin.
- [x] ✅ Item list query: active items, name or HSN LIKE, optional category, ordered by name, at most 1000. Stock is the sum of batch quantities.
- [x] ✅ Tapping a row opens Edit. Row menu: **Edit…**, **Add stock…**, **Add scheme…**, **Delete…**, and **Delete N selected…** when several are selected.
- [x] ✅ Multi-select with a selection bar: "N of M selected", Select all / Clear, **Delete selected…**.
- [x] ✅ Toolbar: **New item** and **More** menu: Auto categories (from item names) · Auto-fill missing MRPs · Set prices from MRP… · New category… · Delete items with 0 stock… (disabled when there are none).
- [x] ✅ Empty state "No items" with "Add an item, or scan a supplier bill in Purchases and items are created for you."

### 3.2 Item sheet (new / edit)
- [x] ✅ Title "New item" or "Edit <name>". Save is disabled while the name is blank.
- [x] ✅ Item name.
- [x] ✅ Category: "Choose automatically from the name" (blank) or a category.
- [x] ✅ HSN code.
- [x] ✅ GST rate %, default 18.
- [x] ✅ Pieces in one box (1 if sold loose only), default 1.
- [x] ✅ When the name contains a pack size, the note "The name says 1 box = N pieces. That is used automatically." appears.
- [x] ✅ Note "Stock and prices are kept per piece; bills show boxes and pieces."
- [x] ✅ MRP per piece (incl. GST).
- [x] ✅ Retail price per piece (ex-GST) · **Retail price per box (incl. GST)**. These two are linked:
  - The box field shows piece × ppb × (1+GST/100), rounded to 2 decimals.
  - Typing a box price sets piece = box ÷ ppb ÷ (1+GST/100), stored to 8 decimals.
- [x] ✅ Wholesale price per piece (ex-GST) · **Wholesale price per box (incl. GST)**, linked the same way.
- [x] ✅ Note "Type either the box price (with GST) or the piece price (ex-GST); the other follows…".
- [x] ✅ Purchase price per piece (ex-GST).
- [x] ✅ Validation (server rules):
  - name required, whitespace collapsed, at most 120 characters
  - prices are numbers ≥ 0 (blank = 0)
  - GST between 0 and 40 (blank = 18)
  - pieces per box is a whole number from 1 to 100000
  - HSN is 2–8 digits or blank
  - unit is always `PCS`
  - an active item with the same name (case-insensitive) is refused: "An item named "X" already exists"
- [x] ✅ On save, a pack size in the name overrides pieces per box.
- [x] ✅ New item with no category: guess it from the name (rules, then internet; section 3.8) and create the category if needed.
- [x] ✅ Toasts: "Item added. Record a purchase (or add stock) to start selling it." / "Item saved."

### 3.3 Add stock sheet
- [x] ✅ Title "Add stock · <name>".
- [x] ✅ Boxes (1 box = N pcs), shown only when ppb > 1.
- [x] ✅ Loose pieces (or "Pieces" when ppb is 1).
- [x] ✅ "Total N pcs = X box Y pcs" line.
- [x] ✅ Purchase price per piece (ex-GST), with the item's cost as placeholder.
- [x] ✅ Save is enabled when total > 0. It adds to batch `OPENING` with expiry 2099-12-31 (adds onto an existing OPENING batch). Price is blank → the item's purchase price.
- [x] ✅ Toast "Added X of <name>."

### 3.4 Scheme sheet
- [x] ✅ Scheme type:
  - "Buy X get Y free" (`FREE_QTY`, the default)
  - "Percent off from a minimum quantity" (`PERCENT`)
- [x] ✅ Buy quantity / minimum quantity (pieces), default 10.
- [x] ✅ Free pieces, default 1 (FREE_QTY) · Discount %, default 0 (PERCENT).
- [x] ✅ Valid from and Valid to (optional dates, clearable).
- [x] ✅ Saved with buy = int or 1, free = int or 0, percent = number or 0. Toast "Scheme saved."

### 3.5 Category sheet
- [x] ✅ Category name (required) → creates the category.

### 3.6 Set prices from MRP (bulk) sheet
- [x] ✅ Mode (segmented): **"Price for each MRP (5, 10, 20 …)"** | **"% below MRP"**.
- [x] ✅ Category: All categories or one category. It starts at the Stock screen's current filter. Changing it clears the preview and typed prices.
- [x] ✅ **MRP mode**:
  - One row per distinct MRP among active items with MRP > 0 (optionally one category): MRP, Items count, Retail price box (placeholder = current max retail), Wholesale price box (placeholder = current max wholesale).
  - "Typed prices are per": **Piece** | **Box (divided by each item's pieces per box)**, default **Box**.
  - Toggle "Typed prices include GST", default **on**.
  - Empty state: "No items with an MRP in this category yet. Use Auto-fill missing MRPs first."
- [x] ✅ **% mode**: Retail price % below MRP · Wholesale price % below MRP (each 0–99.99, at least one required).
- [x] ✅ **Preview** button. It shows "N items will change (K without MRP skipped)." plus up to 3 sample lines: "retail ₹old → new a piece, box ₹X incl. GST".
- [x] ✅ **Update prices** button. Toast "Prices updated for N items."
- [x] ✅ Formulas: section 13.6.

### 3.7 Auto-fill missing MRPs
- [x] ✅ For active items with MRP ≤ 0, read the MRP from the name (section 13.11).
  - If found: set the MRP. If retail or wholesale is ≤ 0, set it to MRP ÷ (1+GST%) rounded to 6 decimals.
  - Everything happens in one transaction.
- [x] ✅ The result sheet "MRP read from item names":
  - "F of C items without an MRP were filled in. M have no price in their name."
  - A table with Category, MRP found and Still missing (orange when > 0).
  - The list "Items still needing an MRP (first N)", up to 50 items.

### 3.8 Auto categories and category guess
- [x] ✅ First, pinned names are moved even when they already have a category: `all\s*time\s*mix` → "Namkeen & Snacks".
- [x] ✅ Then every uncategorised active item gets a guess:
  1. pinned rule
  2. clean the name: remove (…), everything from "MRP", N x N, sizes (g/gm/kg/ml/ltr/l/pkt/pcs) and non-letters, then lowercase
  3. keyword rules on the raw name, then on the cleaned name, first match wins. The 13 rule lists from `category.js` are ported verbatim: Namkeen & Snacks, Biscuits & Cookies, Noodles & Pasta, Beverages, Dairy, Chocolates & Confectionery, Staples & Grains, Oils & Ghee, Spices & Masala, Sauces & Spreads, Personal Care, Home Care, Stationery & General
  4. Open Food Facts search with a 4 s timeout: map its categories through the same rules, else take the first category, strip a language prefix and cut it to 40 characters
- [x] ✅ Results are cached per first 3 cleaned words while the app runs. The category is created if missing (case-insensitive match).
- [x] ✅ Toast "X of N items categorised (K found on the internet)."

### 3.9 Delete items
- [x] ✅ Confirmation "Delete <name>?" with "Items that were ever bought or sold are archived instead, so history stays intact."
- [x] ✅ Rules:
  - Stock > 0 and not forced → alert "Still in stock: <name> still has N units in stock… Delete it anyway?" with Delete anyway / Cancel.
  - The item was used in any bill → archive it (`active=0`).
  - Otherwise delete its schemes, batches and the item.
- [x] ✅ Toasts "<name> archived (it has history)." / "<name> deleted."
- [x] ✅ Bulk delete (selected items or all 0-stock items) runs one by one and never forces. Items still in stock are reported. One summary toast: "N deleted, M archived (had history)." plus "Could not delete K: …" listing the first 5.

## 4. Parties, salesmen and routes

### 4.1 Parties screen
- [x] ✅ Segmented **Customers** | **Suppliers**. Customers = type other than SUPPLIER.
- [x] ✅ Search "Search name, phone or GSTIN", debounced 250 ms. It matches name, phone, GSTIN, mobiles and tel.
- [x] ✅ Subtitle "N customers" or "N suppliers".
- [x] ✅ Table (layout key `parties`): S.No · Party · Type (capitalised) · GSTIN · Route · Price tier · Contact (mobiles, else phone, else tel) · Credit limit ("–" when 0) · Balance.
  - Balance shows as "₹X Dr" / "₹X Cr" / "Settled". Orange when > 0.5, red when < −0.5, else grey.
- [x] ✅ Balance = ledger debit − credit up to the end of the selected financial year.
- [x] ✅ Tapping a row opens the **Ledger**. Row menu: Ledger… · Record receipt… (customers) or Record payment… (suppliers) · Delete N selected… · Edit… · Delete….
- [x] ✅ Toolbar **New customer** / **New supplier**.
- [x] ✅ Empty states: "No customers / Add your first customer." · "No suppliers / Suppliers are added automatically when you scan their bill."
- [x] ✅ Delete: confirmation "Parties with bills or ledger entries are archived instead." A party with any ledger, invoice or purchase rows is archived, otherwise deleted. Bulk delete gives one summary toast.

### 4.2 Party sheet (new / edit)
- [x] ✅ Title "New party" or "Edit <name>". Save is disabled while the name is blank.
- [x] ✅ Party name.
- [x] ✅ Type: Retailer / Wholesaler / Supplier / vendor. Default = Supplier when opened from the Suppliers tab, else Retailer.
- [x] ✅ GSTIN (blank if unregistered). Typing uppercases it. When the first 2 characters are digits they fill the state code. At 15 characters, PAN is filled from characters 3–12 if PAN is empty.
- [x] ✅ State code (09 UP, 07 Delhi), default 09.
- [x] ✅ Address.
- [x] ✅ **Supplier fields**: Tel (landline) · Phone · Mobile numbers (comma separated) · Email · FSSAI number (14 digits) · PAN number.
- [x] ✅ **Customer fields**:
  - Phone
  - Price tier: Retail price / Wholesale price / MRP (default Retail)
  - Credit limit (0 = no limit), default 0
  - Credit days, default 0
  - Delivery / sales route: "No route", each route shown as "Name · Mon, Wed" (or its single old weekday), or "+ New route…"
- [x] ✅ With **+ New route…**:
  - New route name (required: "Enter a name for the new route")
  - Salesman for this route: "Not assigned yet", each salesman, or "+ New salesman…"
  - New salesman name (required: "Enter the new salesman's name") and Salesman phone (optional). The salesman is created first with target 0.
  - Visit days: 7 day chips, any number selectable, default **Mon**.
  - The route is created in the same transaction as the party.
- [x] ✅ **New party only**: Opening balance. Customers: "(they owe you)". Suppliers: "(negative = you owe them)". Default 0. It posts an `OPENING` ledger line dated today: positive = debit, negative = credit.
- [x] ✅ Validation (server):
  - name required, whitespace collapsed
  - address at most 400 characters
  - GSTIN uppercase without spaces; must match the GSTIN pattern ("GSTIN "X" is not valid (15 characters, e.g. 09ABCDE1234F1Z5)")
  - state code 2 digits; blank → first 2 GSTIN characters
  - PAN `^[A-Z]{5}\d{4}[A-Z]$`; blank → from GSTIN
  - FSSAI 14 digits
  - email `^[^@\s]+@[^@\s]+\.[^@\s]+$`, at most 120 characters
  - tel and phone at most 40 characters
  - mobiles split on , ; or newline, trimmed, de-duplicated, joined with ", "
  - type is one of RETAILER, WHOLESALER, SUPPLIER (else RETAILER); tier is one of RETAIL, WHOLESALE, MRP (else RETAIL)
  - credit limit and credit days ≥ 0; days are whole
- [x] ✅ Toast "Party saved."

### 4.3 Ledger sheet
- [x] ✅ Title "<name> · ledger · FY X".
- [x] ✅ Buttons **Record receipt / payment…** (closes the ledger, opens the voucher), **Copy** and Close.
  - Copy puts tab-separated text on the clipboard: Date, Type, Reference, Narration, Debit, Credit, Balance. Toast "Ledger copied. Paste into Excel or Numbers."
- [x] ✅ Headline balance "₹X Dr (they owe you)" / "₹X Cr (you owe them)" / "Settled", coloured orange, red or green.
- [x] ✅ When non-zero: "Opening balance for FY X, brought forward from earlier years: …".
- [x] ✅ Table (layout key `ledger`): S.No · Date · Type · Reference · Narration · Debit · Credit · Balance. Debit and credit are blank when 0.
- [x] ✅ Footnote "Dr = they owe you. Cr = you owe them."
- [x] ✅ Data: opening = sum of entries before the FY start. Entries within the FY ordered by date then id, with a running balance (section 13.5).

### 4.4 Voucher sheet (Record receipt / payment)
- [x] ✅ Title "Receipt from <name>" or "Payment to <name>".
- [x] ✅ Direction: "Received from them (money in)" / "Paid to them (money out)". Default Paid for suppliers, Received otherwise.
- [x] ✅ Amount. Save is enabled when it is > 0.
- [x] ✅ Mode: Bank transfer (BANK), Card (CARD), Cash (CASH), Cheque (CHEQUE), UPI. Default CASH.
- [x] ✅ Date, default dateInFY.
- [x] ✅ Reference / cheque no. (optional).
- [x] ✅ **Save and print** → toast "Saved <no>." and the voucher print preview opens (section 10).
- [x] ✅ Postings: section 13.4.

### 4.5 Salesmen screen
- [x] ✅ Salesman list showing name and phone. The first one is selected on open.
- [x] ✅ Toolbar **New route** (disabled when there are no salesmen) and **New salesman**.
- [x] ✅ Detail for the selected salesman:
  - Stat cards: "Target for YYYY-MM" · "Sales (N bills)" · "Achievement" (N% or "No target set"; green at ≥ 100, else orange) · "Collections this month".
  - Progress bar when a target exists.
  - "Today": "N bills · ₹ sold · ₹ given on credit · collected: CASH ₹…, UPI ₹…" (or "nothing yet").
  - **Beat plan**: day segmented Sun–Sat, default today.
  - Outlets table (layout key `beat`): S.No · Outlet · Route · Last order (DD-MM-YYYY or "Never") · Outstanding to collect (orange when > 0).
  - "To collect on this beat: ₹X".
  - Empty: "No outlets on <Day>. Create a route for this day and assign parties to it."
- [x] ✅ No salesman: empty state "No salesman selected / Add a salesman to start tracking targets, beats and collections."
- [x] ✅ **Salesman sheet**: Name (required) · Phone · Monthly sales target (₹), default 0.
- [x] ✅ **Route sheet**: Route name (required) · Salesman (default the first salesman when none picked) · Visit days (chips, default Mon). Toast "Route added."
- [x] ✅ Calculations: section 13.9.

## 5. Billing

### 5.1 Item entry
- [x] ✅ Search field "Type an item name or scan a barcode", focused on open. It also accepts input from a hardware barcode scanner, which types like a keyboard.
- [x] ✅ Suggestions (up to 8) appear under the field once text is typed:
  - match = every typed word is in the name, or the HSN starts with the text
  - sort: items in stock first, then by where the first word appears in the name, then by name
  - each row: name, "Stock X box Y pcs · MRP ₹ · GST N%", and red "Out of stock" when stock is ≤ 0
- [x] ✅ Keyboard: ↓/↑ move the highlight. Return adds the highlighted item. Esc clears the text (only when it is not empty).
- [x] ✅ Return with no suggestions: look up the item list with that text. Exactly one result → add it, else toast "No item matches "X"".
- [x] ✅ Adding an item already on the bill adds 1 box (ppb > 1) or 1 piece. A new item adds a fresh line: 1 box when ppb > 1, else 1 piece.

### 5.2 Lines table (layout key `billing`, row height 38)
- [x] ✅ S.No.
- [x] ✅ Item: name, plus "N pcs / box · Stock X box Y pcs · <scheme texts>".
- [x] ✅ Box: whole-number field when ppb > 1, else "–".
- [x] ✅ Pcs: whole-number field, at most 7 digits.
- [x] ✅ Total pcs = box × ppb + pcs.
- [x] ✅ Disc %.
- [x] ✅ Rate / pc (ex-GST): blank = price-list rate, which shows as the placeholder with up to 4 decimals. A typed rate overrides it and shows in orange.
- [x] ✅ Rate / box: shown when ppb > 1. It displays typed rate × ppb, rounded to 2 decimals. Typing a box rate sets the piece rate = box ÷ ppb with 8 decimals. Clearing it returns to the price list.
- [x] ✅ Free: "+N pcs free" in green, from schemes.
- [x] ✅ Amount.
- [x] ✅ Remove (×).
- [x] ✅ Empty state "Start a bill / Search an item above and press Return."

### 5.3 Summary bar (bottom, three cards of equal height)
- [x] ✅ **Customer card**:
  - Party: searchable picker with "Walk-in cash customer" plus customers (route name as detail). Button to **create a new party without leaving the bill**. The new party is selected after save.
  - Date (default dateInFY) · Salesman: "No salesman (counter)" or a salesman.
  - Sale: Counter / Van sale. Payment: Cash / UPI / Card / **Credit (default)**.
  - Paid now field. Its prompt reads "Walk-in: paid in full" / "Paid now (blank = on credit)" / "Paid now (blank = full)".
  - Dues line: "Dues ₹X of ₹L limit · Retail price" (red when dues are over the limit), or "Walk-in customer · retail price · paid in full".
- [x] ✅ **Working card**: Items · Discount ("- ₹") · Taxable · GST · Round off.
- [x] ✅ **Total card**:
  - "BILL TOTAL" (or "EDITING <no>"), a spinner while calculating, the total in large type, "N items · P pcs".
  - **Save & print** (⌘S), disabled while busy, with no lines, or while the server reports an error for the current bill.
  - **New** (or Cancel while editing).
- [x] ✅ Error banner (red) showing calculation errors such as "Not enough stock for X: short by N".
- [x] ✅ Toolbar: **New bill** (⌘N; "Cancel edit" while editing) and **Find item** (⌘K).

### 5.4 Calculation behaviour
- [x] ✅ Amounts are recalculated on every keystroke with the local formula (13.2).
- [x] ✅ Engine preview (13.1) runs 200 ms after the last change. Only the newest answer is used.
- [x] ✅ The screen shows the engine's answer **only** when it covers exactly the current lines and any line has free pieces or a scheme. Otherwise it shows the local result.

### 5.5 Save
- [x] ✅ Save re-runs the preview, then saves.
- [x] ✅ Effective pay mode: Credit with a walk-in, or Credit with a paid amount > 0 → CASH.
- [x] ✅ Payload: date, sale type, pay mode, lines (item, boxes, pcs, disc %, rate only when typed), party, salesman, paid amount when typed, override flag.
- [x] ✅ Credit limit exceeded → alert "Credit limit exceeded" with the engine's message, **Bill anyway** / Cancel. Bill anyway saves with the override.
- [x] ✅ After saving:
  1. toast "Saved <no> · ₹X" (or "Updated")
  2. clear the bill
  3. reload lists
  4. WhatsApp auto-send if on (D1)
  5. **print** (section 10)
- [x] ✅ The print preview appears only after any alert or sheet has closed.
- [x] ✅ Clear resets: lines, party = walk-in, paid blank, payment = Credit, date = dateInFY, edit mode off.

### 5.6 Edit a saved sale (from All Bills)
- [x] ✅ Banner "Editing <no>. Saving replaces the old bill; stock and ledger are corrected automatically." Title "Editing <no>".
- [x] ✅ Lines are grouped one per item: quantity split into boxes and pieces, the saved rate filled in (so it shows as typed), disc = the saved manual discount.
- [x] ✅ Party, salesman, sale type and pay mode are restored. Paid shows 2 decimals. Date = the bill date.
- [x] ✅ Save → update under the same number (13.1 edit rules).
- [x] ✅ When WhatsApp auto-send is on, opening Billing pre-loads WhatsApp (D1).

## 6. Purchases

### 6.1 Screen
- [x] ✅ Title "Purchase bill", or "Edit purchase bill <no>" while editing.
- [x] ✅ Edit banner "Editing a saved bill. Updating reverses the old stock and ledger entries and writes the corrected bill under the same number."
- [x] ✅ Header:
  - Supplier: searchable picker over suppliers with GSTIN as detail
  - Supplier invoice no.
  - Bill date (default dateInFY)
  - "Create supplier "<name>"" button when a scanned supplier was not matched
- [x] ✅ Toolbar: **View PDF text** (after a scan), **Scan PDF bill** (not while editing), **Add row**.
- [x] ✅ Lines table (layout key `purchase`, row height 44):
  - S.No.
  - **Item name**: searchable item picker (HSN as detail). Picking an item fills HSN if empty and price from the item's cost if empty, then recalculates the amount. An unmatched scanned row shows red "“X” is not in your stock list." with a **Create this item** button. The hint line shows "New item added", "On the bill: X", and "N box × P = Q pcs go into stock" or "1 box = P pcs · …".
  - HSN code.
  - Qty, default 1.
  - Unit: **BOX / PCS**.
  - Price (per unit).
  - Amount = qty × price, auto-filled until typed by hand.
  - Remove (disabled when only one row is left).
- [x] ✅ Totals box:
  - Discount, plus CGST and SGST (intra-state) or IGST (inter-state), plus Rounded off. Each shows the engine's suggested value as placeholder.
  - **Auto tax** clears the tax boxes so tax is worked out from item rates.
  - "Items ₹ · Taxable ₹".
  - Paid now · Mode CASH / UPI / BANK / CHEQUE (default CASH).
  - "Printed on bill: ₹X", red and bold when it differs from the total.
  - Total in large type.
  - **Clear** (or Cancel edit).
  - **Save and add to stock** (or Update bill) with ⌘S, disabled while busy or without a valid preview.
  - Error text.
- [x] ✅ Live preview 250 ms after any change (13.3).
- [x] ✅ Duplicate supplier invoice → alert "Possible duplicate / <message> Save it again anyway?" with **Save anyway** / Cancel.
- [x] ✅ Toast "Saved <no> · ₹X. Stock and ledger are up to date." Then reset the form and reload lists.

### 6.2 Scan PDF bill
- [x] ✅ Pick a PDF (iOS: Files picker). Overlay "Reading the bill and adding items…".
- [x] ✅ Extract text (D5, D6), parse it (section 7) and **auto-create the missing supplier and items** (7.7).
- [x] ✅ Fill the form:
  - rows: item, description, unit normalised (BOX for BOX/CTN/CASE/CARTON/DOZ/DZN/BX, else PCS), HSN, qty (whole numbers without ".0"), rate, amount. Amounts count as typed.
  - invoice no and date
  - supplier (matched), else the pending "Create supplier" button
  - discount, CGST, SGST, IGST (blank when 0)
  - round off
  - printed grand total
  - source = PDF
- [x] ✅ Yellow box "Filled in from the PDF (N Original pages read). Check every field against the paper bill before saving." with red warnings. The first warning is "Skipped page(s) 3 (duplicate), …".
- [x] ✅ Toast "Bill read: N items, K new items added to Stock, supplier added."
- [x] ✅ **View PDF text** sheet: the raw text (first 8000 characters, pages separated by "---- page ----"), monospaced and selectable.

### 6.3 Create supplier from the bill (sheet)
- [x] ✅ Fields pre-filled from the scan: Supplier name, Address, GSTIN, State code (default 09), Tel, Phone, Mobile numbers (comma separated), FSSAI number, PAN number, Email.
- [x] ✅ Saved as type SUPPLIER, tier WHOLESALE, then selected. Toast "Supplier added."

### 6.4 Create item from the bill (sheet)
- [x] ✅ Item name (= bill description) · HSN code · GST rate % (18) · Pieces in one box (from the name, else 1) · Purchase price per piece. The price defaults to the bill price ÷ pieces per box when the unit is BOX, 4 decimals. · MRP · Retail price · Wholesale price.
- [x] ✅ After save, the row is linked to the new item.

### 6.5 Edit a saved purchase (from All Bills)
- [x] ✅ Loads lines (item, unit, HSN, qty, rate, amount), supplier, invoice no, date, pay mode, paid (2 decimals), discount and taxes (blank when 0), round off and source.

## 7. PDF purchase bill parser (ported line for line from `pdfParser.js`)

- [x] ✅ **7.1 Page text**: items on the same visual row (y within 2 pt) are joined left to right. A gap greater than 1.2 pt becomes a space. Whitespace is collapsed. Rows go top to bottom.
  - A PDF with fewer than 40 non-space characters counts as a scan (D5). Scans are limited to 12 pages.
  - A file that is not a PDF (shorter than 100 bytes or not starting with `%PDF`) → "That file is not a PDF".
- [x] ✅ **7.2 Original pages only**:
  - The copy label is looked for in the first 14 and last 10 lines: original (not followed by "invoice no/number/date/ref"), duplicate, triplicate, or extra/office/transporter/customer/driver/accounts copy. Several labels on one page = "multi".
  - Pages without a label stay with the copy before them. Pages before the first label count as original.
  - No labels at all → all pages are read, with a note. No original found → all pages are read, with a note.
  - Repeated pages (fingerprint of lines with digits, Jaccard ≥ 0.85, at least 5 lines) are dropped as "repeat".
  - The result lists used and skipped pages.
- [x] ✅ **7.3 Merge pages**: page 2 onwards drops lines matching page 1's header, carry lines (b/d, b/f, c/o, c/f, brought or carried forward, page total), "code", "Page x of y", copy labels, column-header lines, and "continued" lines without big numbers.
- [x] ✅ **7.4 Items**:
  - Column header detection: sno, desc, hsn, qty, unit, mrp, rate, disc, tax, amount (needs desc + qty + amount or rate).
  - Column-aware row reading with glued qty+unit split ("10PCS"), dropping of bare unit words, and variants without disc/tax/mrp columns.
  - Plausibility check (floor 0.1 for column rows, 0.4 default).
  - Number-only fallback when no header is found.
  - Rows stop at total markers or continuation markers.
  - Wrapped name tails (up to 4 per row, at most 40 characters, no money or 5+ digit numbers) are folded back into the name, with "(x%)" fragments stripped.
  - Rows are renumbered 1..n.
  - Each row is matched to stock: token similarity + 0.25 for the same HSN, minimum 0.5. A different pack or MRP in the name blocks the match.
  - Row flags: amount differs, fractional qty.
- [x] ✅ **7.5 Totals**:
  - Discount, CGST, SGST/UTGST, IGST (several lines of the same tax are added), round off (sign from "( - )", "less" or a trailing "-"), grand total (several label forms).
  - Fallback "TOTAL <number> …" row.
  - Bill GST rate = CGST% + SGST% when a single rate is printed, or IGST%.
  - The tax-summary table gives the rates.
- [x] ✅ **7.6 Supplier details**: everything above "party details / bill to / buyer / consignee / ship to / invoice no / customer name / m/s":
  - GSTIN (not your own company's)
  - state code (else from GSTIN)
  - PAN (else from GSTIN)
  - FSSAI (14 digits)
  - email
  - Tel and Phone (10-digit mobiles move to mobiles)
  - several Mobiles, plus unlabelled 10-digit mobiles
  - name (line with a company suffix, else the first non-generic line, never your own company)
  - address (up to 4 lines after the name)
  - Matched to existing suppliers by GSTIN, else by name similarity.
- [x] ✅ **7.6b Invoice no and date**:
  - Invoice no from "invoice/inv/bill no" (must contain a digit), or a number from the 2 lines under a label line.
  - Date near "invoice/bill/proforma date / dated", else the first date. Accepted forms: d/m/y with / - or . separators, 2- or 4-digit year, and "d Mon yyyy".
- [x] ✅ **7.6c Per row**:
  - pieces per box from the name
  - MRP: the bill's MRP column first, then from the name
  - GST rate: bill rate, else the HSN table (2106→12, 2105→18, 1905→18, 1704→18, 1806→18, 1902→12, 1904→18, 2008→12, 2009→12, 2202→28, 2201→18, 0902→5, 1006→5, 1101→0, 1512→5, 1701→5, 0713→0, 3401/3402/3305/3306/3307→18, 2501→0)
- [x] ✅ **Warnings** (exact texts from the parser):
  - supplier name / invoice number / invoice date not found
  - header not recognised
  - no rows
  - not matched
  - fractional quantities
  - amount differs
  - grand total not found
  - taxes not found
  - "Items − discount + taxes + round off = X, but the bill's grand total is Y…" when they differ by more than 1
- [x] ✅ **7.7 Auto-create** after parsing:
  - Categories are guessed first, online, 5 at a time.
  - Then, in one transaction, the supplier is created if not matched by GSTIN or name: type SUPPLIER, tier WHOLESALE, state default 09, mobiles joined with ", ".
  - Each missing item is created once per name:
    - name as printed
    - HSN
    - GST = bill rate or 18 (flagged)
    - unit PCS
    - MRP from the name or column
    - retail and wholesale = MRP ÷ (1+GST%), rounded to 2 decimals (0 when no MRP)
    - purchase price per piece = rate ÷ ppb when the unit is a box (rounded to 2 decimals), else rate
    - pieces per box from the name, else 1
    - category
  - Warning texts:
    - "Supplier "X" was added to Parties."
    - "N new items added to Stock with HSN, GST rate, pieces per box and category taken from the bill (K categories found on the internet). Selling prices were set to MRP without GST; adjust them in Stock."
    - "N item(s) are bought in boxes but the pieces per box were not in the name; set it in Stock."
    - "N item(s) had no GST rate on the bill; 18% was assumed. Check it in Stock."
- [x] ✅ Tests: the parser cases in `backend/test/smoke.js` (including the two real fixture bills) pass on iOS with identical results.

## 8. All Bills

- [x] ✅ Title "All Bills". Search "Search bill no or party", debounced 250 ms.
- [x] ✅ Filters: segmented All / Sales / Purchases · From · To · toggle "Unpaid only".
  - Default dates: current FY → month start to today (clamped). Past FY → whole year.
  - Dates are clamped into the open year.
- [x] ✅ Table (layout key `bills`): S.No · Date · Type ("Sale" teal / "Purchase" orange) · Bill no · Supplier bill · Party ("Cash customer" for walk-in) · Total · Paid · Due (bold, red when > 0.5).
- [x] ✅ Results: at most 1000 rows, newest first. Unpaid = total − paid > 0.5. Search covers bill no, party and supplier bill no.
- [x] ✅ Footer: "N bills" · Sales ₹ · Purchases ₹ · **Due ₹**.
- [x] ✅ Row menu: View · Edit… · Delete… · Delete N selected…. Tapping a row opens View. Multi-select bar "Delete selected bills…".
- [x] ✅ **Delete one**: alert "Delete bill <no>?" or "Delete purchase bill <no>?".
  - Sale: "Its stock goes back on the shelf, and its ledger and receipt entries are removed. This cannot be undone."
  - Purchase: "…refused if some of that stock was already sold…".
  - Cancel is the default; Delete bill is destructive. Toast "Deleted <no>."
- [x] ✅ **Bulk delete**: confirmation text as on the Mac, one by one, one summary toast.
- [x] ✅ **Edit** opens Billing (sale) or Purchases (purchase) with that bill loaded.
- [x] ✅ **Bill detail sheet**:
  - Title "<no> · <party or Cash customer>".
  - Line "DD-MM-YYYY · Supplier bill X · Total · Paid · Due".
  - Lines table (layout key `billdetail`): S.No · Item · Qty (box + pcs) · Free pcs · Rate · Taxable · GST · Amount.
  - Buttons: **WhatsApp** (sales, D1) · **Print…** (sales; always shows the preview) · **Edit…** · **Delete…** · Close.

## 9. Books & GST

- [x] ✅ Segmented **Sales Book** | **Purchase Book** | **GST Outward**.
- [x] ✅ **Book**:
  - From and To dates (same defaults and clamping as All Bills).
  - **Copy** puts tab-separated text on the clipboard: Date, No, Supplier bill, Party, GSTIN, Taxable, CGST, SGST, IGST, Round off, Total. Toast "Copied. Paste into Excel or Numbers."
  - Table (layout keys `book-sales` / `book-purchase`): S.No · Date · Invoice / Our ref · Supplier bill · Party · GSTIN · Taxable · CGST · SGST · IGST · Round off · Total.
  - Footer: "N entries" · Taxable · CGST · SGST · IGST · **Total**.
  - Empty: "No entries in this period".
- [x] ✅ **GST Outward**:
  - Month title MM-YYYY with ‹ › arrows that stay inside the open FY. Default = dateInFY's month.
  - **Export month to Excel** (shows "Preparing…" while working) → save `GST-Outward-YYYY-MM.xlsx` (iOS: Files exporter / share).
  - Rate table (layout key `gst-rates`, no S.No column): GST rate · Taxable value · CGST · SGST · IGST (CGST+SGST) · Total tax · Invoice value, plus a bold **Total** row.
  - Rates shown: always 0, 5, 12, 18, 28, plus any other rate used.
  - Stat cards:
    - Invoices in YYYY-MM
    - B2B (party has GSTIN)
    - B2C (no GSTIN)
    - Input tax credit (purchases)
    - "Net GST payable (estimate)" in red, or "Credit carried forward" in green
  - Footnote as on the Mac.
- [x] ✅ **Excel workbook** (byte-for-byte the same structure as `xlsx.js`): 4 sheets, bold grey header row, frozen header, column widths, number formats.
  - **Summary**:
    - Title "GST Outward Supply - YYYY-MM - <Company>"
    - Columns: Particulars, Taxable Value, Tax
    - Rows: B2B (registered parties) · B2C (unregistered / cash) · Total outward supplies · Less: input tax credit (purchases) · Net GST payable
  - **B2B Bills**:
    - Title "B2B bills - YYYY-MM"
    - Columns: Invoice No, Date, Party Name, GSTIN, State, GST Rates, Taxable Value, CGST, SGST, IGST (CGST+SGST), Round Off, Invoice Value
    - Total row
  - **B2C Bills**: same columns without GSTIN, plus a Total row. A walk-in party is "Cash customer".
  - **Rate-wise Summary**:
    - Columns: GST Rate %, Invoices, Taxable Value, CGST, SGST, IGST (CGST+SGST), Total Tax, Total Value
    - Total row
  - Note: the date column holds YYYY-MM-DD text, exactly as the Mac export writes it.

## 10. Printing

- [x] ✅ **Layouts** (Settings › Printing):
  - `halfSheets` "Half-A4 sheets: Original + Duplicate, one copy per sheet" (default)
  - `a4TwoUp` "A4 sheet: Original on top, Duplicate below"
  - `single` "Half-A4: Original copy only"
  - `a4Full` "Full A4 page: Original + Duplicate, one copy per page"
  - `a4FullOriginal` "Full A4 page: Original copy only"
- [x] ✅ Copy labels: **ORIGINAL FOR RECIPIENT**, **DUPLICATE FOR TRANSPORTER/SUPPLIER**.
- [x] ✅ Page geometry (points):
  - half = 595.276 × 420.945, margin 14, row 12, first header 76, next header 30, table head 14, foot 22, totals 92, text × 1
  - full = 595.276 × 841.89, margin 24, row 16, first header 100, next header 36, table head 20, foot 30, totals 118, text × 1.15
  - Rows per page = ⌊(inner − header − table head − foot − totals when it is the last page) ÷ row⌋.
- [x] ✅ Pagination: one page if everything fits. Otherwise fill pages and always leave at least 1 row for the last page, so totals never sit alone. **Overflow continues on extra half-sheets.**
- [x] ✅ Two-up falls back to one copy per half sheet when the bill needs more than one page.
- [x] ✅ **Invoice sheet**:
  - First page header (boxed): company name (13 pt bold), address, "GSTIN: … Ph: …"; "TAX INVOICE" and the boxed copy label; "Bill to: <party or Cash customer>", address, "GSTIN: … State: …"; "Invoice no", "Date: DD-MM-YYYY", "<pay mode> <sale type> · <salesman>".
  - Later pages: "TAX INVOICE <no> (continued)" and "<copy> Page n of N".
  - Item table (ruled box): columns #, Item (cut to 58 characters half / 52 full with ".."), HSN, Qty (box / pcs, "+N free"), MRP (blank when 0), Rate, Disc% (blank when 0), Taxable, GST%, Amount. Fixed widths 16, flexible, 40, 86, 32, 36, 26, 46, 24, 52 × the width factor.
  - **Print gridlines**: vector column lines, row lines (0.6 pt), heading rule (1.2 pt), outer box (1.2 pt). The empty part of the table keeps its column lines.
  - Totals block on the last page:
    - GST summary per rate: GST%, Rows, Taxable, CGST, SGST, IGST
    - amount in words
    - Items · Discount (when > 0) · Taxable · CGST + SGST (when > 0) · IGST (when > 0) · Round off (when non-zero) · **TOTAL ₹** · Paid (when > 0)
  - Footer: invoice terms and "Page n of N".
- [x] ✅ **Voucher sheet** (half-A4; Original + Duplicate labels):
  - company block and copy label
  - "RECEIPT VOUCHER" or "PAYMENT VOUCHER"
  - Voucher No, Date
  - Received from / Paid to
  - Address, GSTIN (when present)
  - Payment mode (+ Ref)
  - Amount ₹
  - In words
  - Balance after (Dr/Cr/Settled)
  - "Receiver's signature" and "Authorised signatory"
- [x] ✅ PDFs are vector pages drawn from the same views, white background, always light mode.
- [x] ✅ **Print preview** (in-app, before printing):
  - title and "N pages"
  - scrollable page view
  - **Save PDF…** (iOS: share or save to Files) with file name `<invoice_no>.pdf`
  - **Close**
  - **Print…** (iOS: AirPrint panel)
- [x] ✅ After a bill is saved: when "print straight away" is on and a printer is saved, print silently and toast "Sent <no> to <printer>." Otherwise show the preview (D7).
- [x] ✅ From Bill detail › Print…: always the preview.
- [x] ✅ Printer setting: "Ask every time" or a saved printer (D7). Toggle "Print straight to this printer after saving a bill (no preview)", disabled without a printer. Explanatory note as on the Mac. **Save** → toast "Print settings saved."

## 11. Backup and restore

- [x] ✅ **Settings › Backup**:
  - Backup folder + **Choose…** (D4)
  - toggle "Back up automatically every day while the app is open"
  - toggle "Also back up whenever I quit the app" (D2)
  - Time picker (HH:MM, 24-hour stored; default from config 21:00)
  - note "Every backup is kept for good; nothing is deleted automatically."
  - "Last backup: DD-MM-YYYY, hh:mm AM · <status>". A FAILED status time is also shown in Indian format, in the Asia/Kolkata time zone.
  - **Save settings**. Toasts: "Saved. A backup will run every day at HH:MM while the app is open." / "Saved. Automatic backup is off."
  - **Back up now** (shows "Backing up…" while working)
- [x] ✅ **Back up now**:
  - Write test of the folder ("Cannot write to "X". Is the drive connected and the folder writable?").
  - New folder `FMCG_Backup_YYYYMMDD_HHMMSS`; `_2`, `_3`… when a folder from the same second exists.
  - For each active company: `VACUUM INTO <Company_slug>_<id>.db`. Slug = letters and digits with `_`, at most 40 characters.
  - Then `registry.db`. Each copy gets `PRAGMA integrity_check` and a SHA-256.
  - `manifest.json`: created (ISO), reason (manual / scheduled / before-restore), files[{company_id, company, file, bytes, sha256}].
  - Failure removes the folder and records `FAILED <ISO>: msg`. Success records last_run and `OK <folder>`.
  - Toast "Backup complete: <folder>".
- [x] ✅ **Scheduled**: when enabled, and the time has passed, and no backup has run today → run with reason "scheduled" (D3).
- [x] ✅ **Backup list** (layout key `backups`): S.No · Backup · Companies · Created (Indian date/time) · Company files · Size.
  - Only folders matching `^FMCG_Backup_\d{8}_\d{6}(_\d+)?$`, newest first.
  - Incomplete folders show 0 files.
  - Multi-select bar "Delete selected backups…". Row menu: Restore this backup… · Delete this backup… · Delete N selected….
- [x] ✅ **Restore** buttons: **Restore selected backup…** · **Restore from a backup folder…** · **Restore one company file (.db)…**.
  - Alert: "Restore <label>?" with the Mac's text explaining Replace and Merge, buttons **Replace** / **Merge** / Cancel.
- [x] ✅ **Restore rules**:
  - Every file is integrity-checked and must contain an `invoices` table. Folder files must match their manifest checksums. A missing file → nothing restored.
  - A **safety backup** (reason before-restore) runs first.
  - The company is matched by **name** (trimmed, case-insensitive). A missing company is created; an archived one is reactivated.
  - Single-file restore uses the company name stored in the file, else the open company.
  - **Replace**: close the company, copy to `.restoring`, remove `-wal`/`-shm`, rename into place.
  - **Merge**: add only what is missing, matched by natural keys:
    - categories, salesmen and routes by name
    - parties by name + customer/supplier
    - items by name
    - batches by item + batch no
    - schemes by item/type/qty/free/%
    - invoices and purchases by number (conflicts are reported and left alone) with their lines
    - receipts and payments by number
    - ledger lines not already present (OPENING only for new parties)
    - counters take the max
  - Afterwards reopen all companies and reload the company list.
  - Toasts: "Restored: A, B." / "Merged N new records into A. K bill numbers clashed and were left as they are."
- [x] ✅ **Delete backup(s)**: alert "Delete backup <name>? The backup folder is removed for good. Your current books are not affected." Only BillBox backup folder names are accepted.
- [x] ✅ Explanatory text under the list as on the Mac.
- [x] ✅ **Cross-platform**: a Mac backup restores on iOS and an iOS backup restores on the Mac, in both Replace and Merge modes (tested here against the original Node engine).

## 12. Settings, themes and columns

- [x] ✅ Settings sections: **Appearance · Companies · Printing · WhatsApp · Stock · Backup**.
- [x] ✅ **Appearance**:
  - Theme grid of 8 themes: two-colour swatch, name, check on the selected one.
  - Mode: Automatic / Light / Dark.
  - Note "The theme changes the accent colour and the page and panel backgrounds. It applies at once and is remembered."
  - Stored per device (`theme`, `appearance`).
- [x] ✅ Themes (accent / card / page, light and dark):
  - Classic (system accent and system backgrounds)
  - Ocean 0E7C9B/35B6D6
  - Forest 2E7D52/4FBF82
  - Sunset D9552B/FF7F50
  - Royal 6D3FD0/9B7BF0
  - Rose C9285F/F0608F
  - Marigold B7791F/F2B544
  - Slate 4A5C70/93A8BD
  - Card and page colours exactly as in `Themes.swift`.
- [x] ✅ **Stock settings**: "Low-stock warning at or below (pieces)", default 10, must be ≥ 0. Save → toast "Saved."
- [x] ✅ **WhatsApp settings** (D1):
  - Status line with an icon
  - Connect WhatsApp / Reconnect · Disconnect · Show page
  - toggle "After saving a bill, send the customer's copy on WhatsApp (in the background)" (saves at once)
  - test number field + **Send test** (a one-page test PDF)
  - Country code for 10-digit numbers, default 91
  - Message sent with the bill. Default "Hello {name}, thank you for your purchase. Your bill {invoice} for {total} is attached. - {company}". Placeholders {name}, {invoice}, {total}, {company}.
  - help text
  - "Last send: …"
  - Save
  - Number rules: digits only; strip a leading 00; strip a leading 0 from 11 digits; add the country code to 10 digits; valid = 11–15 digits. Uses the party phone, then mobiles.
  - The PDF sent = one Original copy (half or full layout following the print setting).
  - Toasts: "<who> has no mobile number on file.", "Sent <no> to <who> on WhatsApp.", "<n> is not on WhatsApp."
- [x] ✅ **Adjustable table columns** on every table:
  - resize a column by dragging its heading edge
  - move a column (iOS: drag, plus Move up/down in the column settings sheet)
  - show/hide columns from the "⋯" heading button or by long-pressing the heading
  - **Reset columns**
  - at least one column always stays visible
  - the S.No column is added to every table except the GST rate table
  - flexible columns take spare width
  - remembered per table key in device settings (`grid.<key>` = {order, hidden, widths}), the same format as the Mac
- [x] ✅ Tables scroll horizontally on iPhone with the heading pinned, and keep every column.
- [x] ✅ Multi-select (iOS: Select mode): Select all / Clear, plus the destructive bulk action.

## 13. Calculations (each ported exactly; unit tests compare against the original engine)

- [x] ✅ **13.0 Rounding**:
  - `r2(n) = Math.round((n + 2.220446049250313e-16) × 100) / 100`, where JavaScript `Math.round` rounds half toward +∞.
  - Bill totals use `Math.round(grand)`.
  - Swift reproduces this exactly. Number text is always `en_IN` with 2 decimals; rates show up to 4 decimals.
- [x] ✅ **13.1 Sale (engine)**:
  - price tier: party tier, walk-in = RETAIL
  - **intra** when there is no party, the party has no state code, or the party's state = the company state code
  - date must be YYYY-MM-DD, default today
  - For each line:
    - ppb = max(1, pcs_per_box)
    - qty = boxes × ppb + pcs (else qty)
    - qty must be > 0 ("Enter a quantity for X")
    - rate = typed rate, else WHOLESALE → wholesale price, MRP → MRP ÷ (1+GST/100) (not rounded), RETAIL → retail price
    - manual % clamped to 0..100
    - active schemes valid on the date: FREE_QTY = ⌊qty ÷ buy⌋ × free, taking the best one; PERCENT = the highest % with qty ≥ min. Both can apply.
    - pct = min(100, manual + scheme %)
    - need = qty + free
    - FEFO batches: qty > 0 and expiry ≥ bill date, ordered by expiry then id, minus quantities reserved by earlier lines of the same bill
    - paid pieces are taken first, then free pieces
    - per batch: gross = r2(rate × paid); disc = r2(gross × pct/100); taxable = r2(gross − disc); tax = r2(taxable × GST/100); intra → CGST = r2(tax/2), SGST = r2(tax − CGST), else IGST = tax; amount = r2(taxable + taxes)
    - stock short → "Not enough stock for X: short by N"
  - Totals: subtotal, discount, taxable and taxes = r2 of sums; grand = r2(taxable + taxes); total = Math.round(grand); round off = r2(total − grand).
  - Paid = typed amount, else 0 for CREDIT, else total; clamped to 0..total, r2.
  - Walk-in must pay in full ("Walk-in sales must be paid in full").
  - Credit limit check when limit > 0 and not overridden: balance + total − paid > limit → "Credit limit exceeded: dues would be ₹X against a limit of ₹Y".
  - Postings:
    - invoice number `INV/yy-yy/00001` (FY of the bill date, gapless)
    - lines with the manual % kept separately
    - batches decremented (refused if stock changed)
    - ledger `INVOICE` debit total, narration "Sale <no>"
    - paid > 0 → receipt `RCT/…` with reference "Paid at billing <no>" and ledger `RECEIPT` credit, narration "Received at billing (<mode>)"
  - **Edit**: restore batch stock, delete lines, delete receipt ledger lines and receipts, delete the INVOICE ledger line, rewrite under the same id and number, reuse the first receipt number. One transaction.
  - **Delete**: the same reversal, then delete the invoice.
  - Printable data: lines with item, HSN, ppb, MRP; edit lines grouped per item; supply INTRA or INTER; amount in words; GST summary per rate (rows, taxable, CGST, SGST, IGST).
- [x] ✅ **13.2 Sale (on screen)**: `BillMath` as written (line gross, discount, taxable, tax split, amount; totals; round off), with the price-list rate by tier and the typed rate overriding it.
- [x] ✅ **13.3 Purchase**:
  - Supplier required.
  - For each line:
    - an item must be chosen
    - qty must be a whole number ≥ 1
    - unit = upper-case, at most 8 characters
    - pieces = qty × ppb when the unit is BOX/BOXES/BX/CASE/CS/CTN/CARTON, else qty
    - amount = typed amount, else r2(qty × rate)
    - batch no default `AUTO-YYYYMMDD`
    - expiry default 2099-12-31
  - subtotal = r2 Σ amount
  - discount ≤ subtotal (+0.005)
  - taxable = r2(subtotal − discount); share = taxable ÷ subtotal
  - suggested tax = r2 Σ(amount × share × GST/100), split CGST = r2(t/2), SGST = r2(t − CGST), or IGST
  - typed taxes are used unless all are blank or Auto tax is on
  - grand = r2(taxable + taxes)
  - round off = typed (|x| ≤ 5, else an error), else r2(Math.round(grand) − grand)
  - total = r2(grand + round off)
  - mismatch = total − printed total when they differ by more than 1
  - Save:
    - duplicate supplier invoice no (case-insensitive, same supplier) refused unless allowed
    - paid clamped to 0..total
    - number `PUR/…`
    - for each line: line taxable = r2(amount × share); unit cost = r2(line taxable ÷ pieces); batch upsert adds pieces; the item's cost is updated when the unit cost > 0
    - ledger `PURCHASE` credit total, narration "Purchase <no> / <supplier no>"
    - paid > 0 → payment `PAY/…` "Paid at purchase <no>" and ledger `PAYMENT` debit
  - **Edit and delete**: reverse stock and postings. Refused with "X: N piece(s) from this bill were already sold…" when a batch would go negative.
- [x] ✅ **13.4 Vouchers**:
  - amount = r2, must be > 0; the party must exist
  - RECEIVED → `RCT/…` receipt and ledger credit, narration "Payment received (MODE) ref"
  - PAID → `PAY/…` payment and ledger debit, narration "Payment made (MODE) ref"
  - The reply includes the new balance.
- [x] ✅ **13.5 Ledger and balances**:
  - balance = Σdebit − Σcredit (positive = they owe you)
  - FY opening = entries before 1 April
  - running balance r2 after each line
  - party list balance = up to the FY end
- [x] ✅ **13.6 Bulk prices**:
  - **% below MRP**: per-piece incl. = MRP × (1 − off/100). When ppb > 1, round the box (incl. × ppb) to a whole rupee and divide back. Price = incl. ÷ (1+GST/100), rounded to 8 decimals. Box incl. = r2(price × ppb × (1+GST)). Items with MRP 0 are skipped.
  - **By MRP**: an item matches a row when |MRP − row MRP| < 0.005. Price = (include GST ? v ÷ (1+GST) : v) ÷ (per box ? ppb : 1), rounded to 8 decimals.
- [x] ✅ **13.7 Margins**:
  - your margin = (wholesale − cost) ÷ wholesale × 100
  - retailer margin = (MRP − wholesale × (1+GST)) ÷ MRP × 100
  - both r2, 0 when the divisor is 0
- [x] ✅ **13.8 Profit and dashboard**:
  - profit = Σ line taxable − Σ (qty + free) × (batch cost, else item cost, else 0); lines with unknown cost are counted
  - margin % = profit ÷ revenue × 100
  - "today" = today clamped into the FY
  - month = that month to today
  - 14-day series of sales and purchases totals (days inside the FY)
  - 12 months April–March: sales, purchases, profit
  - receivable and payable = per-party balances up to the FY end (positive vs negative)
  - GST liability = Σ invoice taxes − Σ purchase taxes for the month, and for the year
  - low stock = items that have batches with stock ≤ threshold (setting, default 10), first 8 shown
  - top 5 dues > 0.5
  - collections = receipts
  - **Dashboard screen**:
    - greeting by hour (< 12 "Good morning", < 17 "Good afternoon", else "Good evening")
    - company name and FY line
    - past-year banner
    - 7 cards: Profit, Sales, Purchases, Collections, Outstanding dues, GST liability, Low stock. Notes and colours exactly as on the Mac, including the "N bill lines have no purchase price…" note.
    - "Month by month, April to March" chart (3 bars per month, with legend)
    - "Sales and purchases, last 14 days" chart
    - "Low stock alerts" and "Top dues" lists (8 each)
    - Refresh button
- [x] ✅ **13.9 Salesman**:
  - month = today's month clamped into the FY
  - sales and bill count for the month
  - collections = receipts with that salesman
  - achievement = sales ÷ target × 100 (none without a target)
  - day: bills, sales, credit given = total − paid, collected per mode
  - beat: active parties on that salesman's routes visiting that weekday (the `days` list or the old `day_of_week`); outstanding up to the FY end; last order up to the FY end; total outstanding
- [x] ✅ **13.10 GST outward**:
  - per rate from invoice lines of the month
  - the IGST column carries CGST + SGST + IGST
  - B2B (party GSTIN not empty) and B2C splits
  - invoice count, round off
  - input credit = purchase taxes of the month
  - net payable
  - bill rows with a "5%, 18%" rate list
- [x] ✅ **13.11 Name readers**:
  - pieces per box `\(\s*(?:(\d+)\s*[xX*]\s*)?(\d{1,5})\s*(?:PKTS?|PCS?|NOS|PACKS?|UNITS?)?\s*\)`, else `\b\d+\s*[xX]\s*(\d{2,5})\b` not followed by a size unit
  - MRP: "MRP…N", then "Rs/INR/₹ N", then "N/-", then "@ N" (not sizes), with 0 < N < 100000
- [x] ✅ **13.12 Numbering**: prefix/FY/5-digit counter in the `counters` table, gapless, by the document's own date. Prefixes INV, RCT, PAY, PUR.
- [x] ✅ **13.13 Amount in words**: "Rupees … Only" in the Indian system (Crore, Lakh, Thousand, Hundred), from the rounded total.
- [x] ✅ **13.14 Formats**:
  - money ₹ en_IN with 2 decimals
  - box/pcs text "6 box 6 pcs" / "6 box" / "6 pcs"
  - DD-MM-YYYY (time kept)
  - Indian date/time "dd-MM-yyyy, hh:mm a" in Asia/Kolkata
  - Dr/Cr/Settled
  - "..": long text cut

## 14. Keyboard shortcuts (hardware keyboard on iPad/iPhone, each also tappable)

| Mac shortcut | Action | Tappable equivalent on iOS |
|---|---|---|
| ⌘1 … ⌘9 | Go to Dashboard, Billing, Purchases, All Bills, Stock, Parties, Salesmen, Books & GST, Settings | Tabs / More list |
| ⌘N | Billing: New bill / Cancel edit | toolbar button |
| ⌘K | Billing: focus item search | toolbar button |
| ⌘S | Billing: Save & print / Update · Purchases: Save and add to stock / Update bill | buttons |
| ↓ / ↑ | Billing search: move suggestion highlight | tap a suggestion |
| Return | Billing search: add highlighted / look up · searchable pickers: pick first match · sheets: Save · print preview: Print… | buttons |
| Esc | Billing search: clear text · sheets: Cancel / Close · print preview: Close | Cancel / Close |
| Click, ⌘-click, ⇧-click | Select row, add/remove a row, select a range | Select mode (tap rows, Select all) |
| Double-click a row | Open (Edit item, Ledger, Bill detail) | tap a row |
| Right-click a row | Row menu | long-press menu / swipe actions |
| Right-click a heading | Column menu | "⋯" button / long-press heading |

## 15. Database (identical to the Mac; one file per company plus `registry.db`)

**PRAGMAs on open**: `journal_mode=WAL`, `foreign_keys=ON`, `synchronous=NORMAL`. Registry: WAL.

**registry.db**
- [x] ✅ `companies(id INTEGER PK, name TEXT NOT NULL, file TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1, created_at TEXT DEFAULT (datetime('now','localtime')))`
- [x] ✅ `app_settings(key TEXT PK, value TEXT)`. Keys: last_company, backup_dir, backup_enabled, backup_time, backup_on_exit, backup_last_run, backup_last_status.

**company database**
- [x] ✅ `settings(key TEXT PK, value TEXT)`. Defaults: company_name 'My Company', company_gstin '', state_code '09', company_address '', company_phone '', invoice_terms 'Goods once sold will not be taken back.', print_layout 'halfSheets', print_printer '', print_auto '0', low_stock_qty '10'. Later keys: wa_auto, wa_cc, wa_message.
- [x] ✅ `counters(key TEXT PK, value INTEGER NOT NULL DEFAULT 0)`
- [x] ✅ `categories(id INTEGER PK, name TEXT UNIQUE NOT NULL)`
- [x] ✅ `items(id PK, name TEXT NOT NULL, category_id → categories, hsn TEXT, gst_rate REAL NOT NULL DEFAULT 18, unit TEXT DEFAULT 'PCS', mrp REAL NOT NULL DEFAULT 0, retail_price REAL NOT NULL DEFAULT 0, wholesale_price REAL NOT NULL DEFAULT 0, purchase_price REAL NOT NULL DEFAULT 0, pcs_per_box INTEGER NOT NULL DEFAULT 1, active INTEGER NOT NULL DEFAULT 1)`
- [x] ✅ `batches(id PK, item_id NOT NULL → items, batch_no TEXT NOT NULL, mfg_date TEXT, exp_date TEXT NOT NULL, qty INTEGER NOT NULL DEFAULT 0, purchase_price REAL, mrp REAL, UNIQUE(item_id,batch_no))`
- [x] ✅ `schemes(id PK, item_id NOT NULL → items, type TEXT NOT NULL CHECK IN ('FREE_QTY','PERCENT'), buy_qty INTEGER NOT NULL, free_qty INTEGER DEFAULT 0, percent REAL DEFAULT 0, valid_from TEXT, valid_to TEXT, active INTEGER NOT NULL DEFAULT 1)`
- [x] ✅ `salesmen(id PK, name TEXT NOT NULL, phone TEXT, monthly_target REAL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1)`
- [x] ✅ `routes(id PK, name TEXT NOT NULL, salesman_id → salesmen, day_of_week INTEGER CHECK 0..6, days TEXT)`. `days` = "1,3,5"; 0 = Sunday.
- [x] ✅ `parties(id PK, name TEXT NOT NULL, gstin, state_code, phone, address, type TEXT NOT NULL DEFAULT 'RETAILER', price_tier TEXT NOT NULL DEFAULT 'RETAIL' CHECK IN ('WHOLESALE','RETAIL','MRP'), credit_limit REAL NOT NULL DEFAULT 0, credit_days INTEGER NOT NULL DEFAULT 0, route_id → routes, active INTEGER NOT NULL DEFAULT 1, tel, mobiles, fssai, pan, email)`
- [x] ✅ `invoices(id PK, invoice_no TEXT UNIQUE NOT NULL, date TEXT NOT NULL, party_id → parties, salesman_id → salesmen, sale_type TEXT NOT NULL DEFAULT 'COUNTER', pay_mode TEXT NOT NULL DEFAULT 'CASH', subtotal, discount, taxable, cgst, sgst, igst, round_off REAL, total REAL NOT NULL, paid REAL NOT NULL DEFAULT 0, created_at TEXT DEFAULT (datetime('now','localtime')))`
- [x] ✅ `invoice_lines(id PK, invoice_id NOT NULL → invoices ON DELETE CASCADE, item_id NOT NULL → items, batch_id NOT NULL → batches, qty INTEGER NOT NULL, free_qty INTEGER NOT NULL DEFAULT 0, rate REAL NOT NULL, disc_pct REAL NOT NULL DEFAULT 0, disc_amt REAL NOT NULL DEFAULT 0, taxable, gst_rate, cgst, sgst, igst, amount REAL NOT NULL, manual_disc REAL NOT NULL DEFAULT 0)`
- [x] ✅ `receipts(id PK, receipt_no TEXT UNIQUE NOT NULL, date TEXT NOT NULL, party_id NOT NULL → parties, salesman_id → salesmen, invoice_id → invoices, mode TEXT NOT NULL DEFAULT 'CASH', amount REAL NOT NULL, reference TEXT)`
- [x] ✅ `ledger(id PK, party_id NOT NULL → parties, date TEXT NOT NULL, type TEXT NOT NULL, ref_no TEXT, debit REAL NOT NULL DEFAULT 0, credit REAL NOT NULL DEFAULT 0, narration TEXT)`. Types: OPENING, INVOICE, RECEIPT, PURCHASE, PAYMENT.
- [x] ✅ `purchases(id PK, purchase_no TEXT UNIQUE NOT NULL, supplier_invoice_no TEXT, date TEXT NOT NULL, party_id NOT NULL → parties, subtotal, discount, taxable, cgst, sgst, igst, round_off REAL, total REAL NOT NULL, paid REAL NOT NULL DEFAULT 0, pay_mode TEXT, notes TEXT, source TEXT NOT NULL DEFAULT 'MANUAL', created_at TEXT DEFAULT (datetime('now','localtime')))`
- [x] ✅ `purchase_lines(id PK, purchase_id NOT NULL → purchases ON DELETE CASCADE, item_id NOT NULL → items, batch_id → batches, batch_no TEXT NOT NULL, mfg_date TEXT, exp_date TEXT NOT NULL, qty INTEGER NOT NULL, free_qty INTEGER NOT NULL DEFAULT 0, rate REAL NOT NULL, disc_pct REAL NOT NULL DEFAULT 0, disc_amt REAL NOT NULL DEFAULT 0, mrp REAL, taxable, gst_rate, cgst, sgst, igst, amount REAL NOT NULL, unit TEXT DEFAULT 'PCS', pcs_qty INTEGER)`
- [x] ✅ `payments(id PK, voucher_no TEXT UNIQUE NOT NULL, date TEXT NOT NULL, party_id NOT NULL → parties, purchase_id → purchases, mode TEXT NOT NULL DEFAULT 'CASH', amount REAL NOT NULL, reference TEXT)`
- [x] ✅ **Indexes**:
  - idx_batches_fefo(item_id, exp_date)
  - idx_batches_item(item_id)
  - idx_inv_date(date)
  - idx_inv_sm(salesman_id, date)
  - idx_inv_party(party_id)
  - idx_invl_inv(invoice_id)
  - idx_invl_item(item_id)
  - idx_purl_pur(purchase_id)
  - idx_purl_item(item_id)
  - idx_pur_date(date)
  - idx_pur_party(party_id, supplier_invoice_no)
  - idx_receipts_inv(invoice_id)
  - idx_receipts_date(date)
  - idx_parties_name(name)
  - idx_items_name(name)
  - idx_ledger_party(party_id, date)
- [x] ✅ **Upgrades on every open**:
  - create missing tables
  - rebuild `items` without sku/barcode/reorder_level when they exist (ids kept, foreign-key check)
  - add `routes.days` and backfill it from day_of_week
  - add `items.pcs_per_box`
  - add parties tel/mobiles/fssai/pan/email
  - add purchase_lines unit/pcs_qty
  - add invoice_lines manual_disc
  - insert missing default settings
- [x] ✅ Data folder on iOS: Application Support/DistributorPro/data (same file names as on the Mac).

**Device settings (not in the database)**: `theme`, `appearance`, `grid.<table>` column layouts. iOS adds a saved printer (D7) and a backup-folder bookmark (D4).

---

## Progress

**All 268 items are implemented on iOS (100%).** Module order as agreed: database → companies/FY → items → parties/salesmen/routes → billing → purchases + PDF parser → payments/ledgers → reports/exports → printing → backup/restore → settings/themes/columns → dashboard.

How each part is verified:

| Part | Verified by | Result |
|---|---|---|
| Engine (everything the Mac server does: numbering, billing, stock, schemes, ledgers, vouchers, reports, GST Excel, parser, backup) | Same requests replayed on the Mac's own Node engine and on the iOS engine, every reply and every table compared (`tests/parity/run.sh`, `run_more.sh`) | 445/445 working-session steps (debit notes, year books, payment lists, item tools, prices from MRP, similar names and unrounded totals included), 1,647/1,647 random-bill steps, 24/24 parser steps, 21/21 Marg-import steps on your real 2026-27 backup, Excel 9/9 parts identical |
| Supplier PDFs (your 3 bills, watermarks left out) | Page text from the PDFs' text runs, Mac vs iOS | 3/3 bills, all 11 pages identical |
| Backups Mac ⇄ iPhone | `tests/parity/test_backup.py`: Mac backup restored on iOS, iOS backup restored on the Mac, Merge, single company file, refusals | 20/20 checks (year files included) |
| Unit tests in Xcode (`BillBoxTests`, also `swift test`) | Golden answers recorded from the Mac engine, replayed on the iOS engine | 16/16 tests pass (`swift test`) |
| Live bill arithmetic on the billing screen (BillMath, the Mac file unchanged) | 3,000 random bills vs the Mac's BillMath | identical to the paisa |
| iOS screens | Type-checked against the iOS 16 SDK surface (builders limited to 10 children as in Xcode 14), 0 errors, 0 warnings (`tests/typecheck/stubs/build.sh`) | Not yet run on a device: there is no Xcode here. First build on your Mac is the remaining check. |

Mac bugs found while porting (fixed in the Mac app too, so both behave the same):
- **Beat plan showed no outlets**: the weekday was bound as `'1.0'` instead of `'1'` (`backend/src/routes/salesmen.js`).
- **Printing a receipt / payment voucher failed with "not found"**: the voucher number's slashes were not encoded (`macos/Sources/DistributorPro/Print.swift`).


---

## Round 3 changes (Mac and iPhone together)

These were asked for after the port and are in both apps, with the same engine behaviour on both (parity tests above).

- [x] ✅ **Backup and restore on iPhone**: backups made by the Mac now restore even when they arrive zipped (Finder, Mail, WhatsApp, Files); picking a folder that only contains the backup folder, or a single company `.db`, works; the backup folder is shown with its place in the Files app and can be changed (saved at once); when iOS moves the app's folder after a reinstall the backup folder follows; a failed backup says why instead of "Server error".
- [x] ✅ **Retail / wholesale prices**: the box price field keeps exactly what you type ("2500.", "2,499.5") and uses the pieces per box from the name, as saving does (a "(1X144)" item was priced 144 times too high before the first save); Set prices from MRP shows today's price in the units you type (box or piece, with or without GST); the stock list shows the piece rate to 4 decimals and says "/ pc (ex-GST)".
- [x] ✅ **Printed bill**: Bill to shows the party's address, GSTIN, state, PAN, phone and mobiles, landline, e-mail and FSSAI (empty ones left out).
- [x] ✅ **Scanned supplier bills**: e-mail, phone, mobile, GSTIN and the like printed on the name or address line are cut off the supplier's name and address; the supplier block ends at the buyer's block (so a mobile / e-mail printed after "Invoice No." is still read); "Address:" labels, PIN codes on their own line and invocations ("JAI MATA DI") handled; phone numbers no longer run into the next line.
- [x] ✅ **WhatsApp sending is faster**: the bill is drawn while WhatsApp Web opens the chat, the open chat is reused for the next bill to the same customer, the way of attaching that worked last time is tried first, and waits poll four times as often.
- [x] ✅ **Debit notes** (goods returned to a supplier): screen *Debit Notes* (Mac sidebar under Buy & Stock, ⌘0; iPhone More tab), new / edit / delete / print (bill layouts, headed DEBIT NOTE), "Return goods…" on a purchase bill fills the rows from it. Numbered DN/26-27/00001. Pieces leave stock from the chosen batch or the earliest-expiring batches (refused if not in stock); the supplier's ledger is debited; GST on it is taken off the month's input tax credit (dashboard, GST report and Excel); shown in All Bills and as a Debit Notes book; included in backups and Merge.
- [x] ✅ **Import from Marg ERP** (Settings): reads Marg's CSV backup (.zip or folder), shows what it holds and checks it against Marg's own figures, then imports items (HSN, GST, pack, MRP, rates, category), customers and suppliers (address, GSTIN, PAN, mobiles, opening balance), sale bills, purchase bills, debit notes, receipts and payments. Your 2026-27 backup: 431/431 bill totals, 651/651 party closing balances and 356/356 item closing stocks match Marg. Importing again adds nothing twice. `backend/tools/marg_clean_csv.js` writes the cleaned data as plain CSV files.

---

## Round 4 changes (Mac and iPhone together)

- [x] ✅ **Financial years as separate books**: a year can be its own file (carry forward or empty), opened from the year menu; Marg data for another year is refused; backups keep every year. Parity: years section of the working session, Marg import into a year file, backup/restore with year files.
- [x] ✅ **Save now, print later**: after-save choice, *Not printed* filter, print many bills as one job, printed flag (reset when a bill is edited).
- [x] ✅ **Payments from a handwritten list** (photo → Vision text on the device → party and bill matching in the engine → check → save all). Parity: 14 written lines incl. OCR mistakes, lakh commas, "paid"/"Rs"/"/-", unknown and ambiguous parties; all-or-nothing save.
- [x] ✅ **Items from the internet** and **Tidy names & merge duplicates**. Parity: price-list page (tables, entities, scripts, comments), pasted lists, three name styles, merge with a shared batch number, bulk add. The web search and page download need the internet and are not part of the parity run (both engines answer "offline" the same way there).
- [x] ✅ **Dashboard redesign** and **Billing & Dashboard settings** (dashboard figures added to the engine: collections this month, bills to print, best sellers, latest bills).
- [x] ✅ **Speed**: statement cache in the iPhone engine's SQLite layer; faster Marg cleaning and unzip.

---

## Round 5 changes (Mac and iPhone together)

- [x] ✅ **Prices from MRP**: billing reloads items after any item or price change; new set-prices engine with a bill-check preview. Parity: % and price-table modes, rounding, per box / per piece, with / without GST, item subsets, errors, and a bill preview proving 2,500 for a 2,500 box.
- [x] ✅ **Similar-name merging** (exact / similar / loose; never across pack size, MRP or box) and **Merge selected**. Parity: 13 look-alike names in three strictness levels.
- [x] ✅ **Look and customisation**: panel style, corners, row height, text / interface size; round total on/off (engines and the live bill maths), default line discount, default GST for new items.
- [x] ✅ **Smoother**: no item limit on billing, one load per typed search, no double reloads.
- [x] ✅ **E-way bill** for a sale bill (portal JSON file, checks, number saved and printed). Parity: 35 steps of errors, files and saved numbers.
- [x] ✅ **Numbering and expiry-window settings** (both engines) and the new Billing, Parties & Payments and Stock options in both apps.
