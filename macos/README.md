# BillBox for macOS (native SwiftUI)

A native macOS app (SwiftUI, AppKit printing, PDFKit). The server and its own copy of Node are packed **inside the app**:
nothing else to install, no Terminal needed to use it. Works on **macOS 12 Monterey or newer**.

## Build the app (once, needs Xcode or the command line tools + internet)

```bash
cd macos
./build_app.sh           # makes "BillBox.app"; drag it to Applications
```

The script builds the app, downloads Node 22 for your Mac, and packs the server into the app. Then just open the app.
Your books live in `~/Library/Application Support/DistributorPro/data` (books from an earlier `backend/data` are copied there
the first time), so rebuilding or replacing the app never touches them. Make backups from Settings.

Developer shortcut: `swift run` still works if Node 22 is installed and `npm install` was run in `backend`.

## What is native here

- Sidebar navigation (`NavigationSplitView`), toolbars, `.searchable` search, grouped forms in sheets, `Table`, popovers, context menus,
  Return / Esc / ⌘S / ⌘N / ⌘K / ⌘1…⌘9 shortcuts, light and dark mode, Swift Charts on the dashboard.
- **Adjustable columns on every table**: drag a header edge to resize, drag a header to reorder, right-click a header to show or hide
  columns. The layout is remembered. "Reset columns" is in each screen's toolbar.
- Printing through the macOS print system (PDFKit): half-A4 Original + Duplicate, A4 two-up, single copy, receipt vouchers; save as PDF.
- Indian formats everywhere: ₹1,23,456.00 and DD-MM-YYYY.

## New in this version

- **Auto-fill missing MRPs** (Stock ▸ ••• menu): reads the MRP printed in item names (`MRP-10/-`, `Rs.10/-`, `10/-`, `@25`) and the MRP
  column of scanned bills, then shows a per-category report of what was found and what is still missing. No outside AI service is used.
- **Set prices from MRP** for a whole category, **Auto categories** (Bikano / All Time Mix always go to Namkeen & Snacks).

## Not verified

This code was written without access to a Swift compiler, so expect a few compile errors on first build. Paste them back and they get
fixed quickly. The backend (shared with the Flutter app) has automated tests; the Swift UI does not.
