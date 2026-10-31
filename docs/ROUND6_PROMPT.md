# Round 6 — iPhone fixes and the Android app

## iPhone fixes
1. **Number pad keeps closing while billing.** Once the bill has enough rows to fill the screen, tapping Boxes or Pcs on a
   row opens the number pad and it closes again. Keep every bill row alive while it is edited (the bill table must not
   recycle rows when the keyboard makes it shorter) and never dismiss the keyboard on scroll.
2. **Item name overlaps the company name when the keyboard is open.** The navigation bar must stay opaque so nothing slides
   under the company / year menu when the keyboard pushes the screen up.

## Android app (Android 12 / API 31 and up)
Port BillBox to Android with **every feature of the iPhone/Mac app** and Android design (Material 3, Jetpack Compose,
bottom navigation on phones and a navigation rail on tablets, top app bar, dialogs and bottom sheets, snackbars,
system back, dark theme, dynamic colour as one of the themes, Android share sheet, Storage Access Framework, Android
print framework).

- **Engine**: the Mac's own engine (backend/src, the code the parity tests check the iPhone engine against) runs inside the
  app, unchanged, in a hidden WebView. Small bridges give it Android's SQLite, files, network and text recognition.
  Same books, same numbers, same backups as the Mac and iPhone (a Mac or iPhone backup restores on Android and back).
  The bundled engine is replayed against the whole parity scenario in Node with the same bridge rules Android uses.
- **Screens** (all of them, as on the iPhone): Billing (search, boxes/pieces, discounts, rates, schemes, credit limit,
  edit, keep party, defaults, wholesale note), All Bills (filters, not printed, print many, edit, delete, e-way bill,
  WhatsApp, return goods), Stock (items, batches, schemes, categories, set prices from MRP, auto MRP / categories,
  items from the internet, tidy & merge, merge selected, delete), Parties (customers / suppliers, routes, ledger,
  receipts / payments, payments from a photo), Purchases (manual and from a supplier PDF), Debit Notes, Salesmen and
  beat plan, Books & GST (books, GST month with Excel, profit, outstanding, expiry, low stock), Dashboard, Settings
  (appearance, companies and year books, printing, WhatsApp, billing & dashboard, numbering, parties & payments,
  stock, backup, import from Marg).
- **Printing**: the bill layouts (half sheets A5, two on A4, full A4), copy labels, columns, words, signature, vouchers,
  debit notes, several bills in one job — drawn as PDF and printed through Android's print service, or shared.
- **Build and run**: `android/build.sh` checks Java and the Android SDK, builds with Gradle, installs on the phone
  connected by USB (or Wi-Fi debugging) and opens BillBox; also `apk`, `release`, `logcat`, `test` (engine parity).

Rules: no feature removed; engines give identical answers; existing tests keep passing; deliver one complete zip.
