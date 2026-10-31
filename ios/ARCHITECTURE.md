# BillBox iOS: architecture

## Two layers

```
ios/
├── BillBoxCore/                 Swift package: everything the Mac's embedded Node server does, in Swift
│   ├── Sources/BillBoxCore/     (compiled into the iOS app, and on Linux/macOS for the parity tests)
│   │   ├── SQLite.swift         thin sqlite3 wrapper with the same API the server used (prepare/run/get/all, nested transactions)
│   │   ├── Schema.swift         CREATE TABLEs, indexes, every upgrade step, default settings      ← backend/src/schema.js
│   │   ├── Engine.swift         registry.db + one database file per company, open/close/create     ← backend/src/db.js
│   │   ├── Router.swift         "/items", "/invoices/preview" … dispatched in-process               ← backend/src/server.js + routes/*.js
│   │   ├── Billing / Purchases / Vouchers / Reports / Category / AutoCreate / PDFParser / Backup / XLSX …
│   │   └── JS.swift             JavaScript number, rounding and regex behaviour reproduced exactly
│   ├── Sources/ParityKit/       replays a scenario on the engine (used by bbcheck and the unit tests)
│   ├── Sources/bbcheck/         command-line runner used only by the parity tests
│   └── Tests/BillBoxCoreTests/  unit tests + Golden/ (answers recorded from the Mac engine); `swift test` or ⌘U in Xcode
├── BillBox/                     the iOS app (SwiftUI); screens adapted from macos/Sources/DistributorPro
├── BillBox.xcodeproj           targets BillBox (app) and BillBoxTests (unit tests), made by tools/make_xcodeproj.py
├── tests/parity/                parity harness: the same scenarios run through the Mac's Node code and through BillBoxCore
└── tests/typecheck/             iOS 16 SDK stubs to type-check the app on Linux
```

**Why an in-process router.** The Mac screens talk to the server with `API.obj("POST", "/invoices", body)` and read the JSON
reply. On iOS, `API` has exactly the same signatures, but instead of an HTTP request it calls `Router.handle(method, path, query, body)`
inside the app. Consequences:

- Every screen of the Mac app can be ported almost line by line: the request it makes and the reply it reads are unchanged.
- The business logic has one entry point that can be tested from the command line. The same request scenario runs through the
  Node route handlers (the Mac app) and through `Router` (the iOS app), and the replies and resulting database files are compared.
- Errors behave the same: status code, error text and `code` (`CREDIT_LIMIT`, `DUPLICATE`, `HAS_STOCK`, `NO_STOCK`, `ALREADY_SOLD`).

**Database.** It uses the same SQLite schema and file names (`registry.db`, `company_<timestamp>.db`) in Application Support/DistributorPro/data.
It goes through plain `sqlite3` (built into iOS; no third-party packages), with the same PRAGMAs (WAL, foreign keys, synchronous NORMAL). All database work runs on one
serial actor, the way the Node server ran it on one event loop.

**Exactness.** JavaScript and Swift round and print numbers differently. `JS.swift` reproduces:
- `Math.round`
- `r2` with the server's epsilon
- `Number("…")` parsing
- JavaScript number-to-text, used in messages such as "dues would be ₹1234.5"
- `toFixed`
- the regex flags the parser uses

The parity tests check these against Node directly.

**What iOS replaces.**

| Mac (Node / AppKit) | iOS |
|---|---|
| `node:sqlite` | `sqlite3` C API |
| pdf-parse (pdf.js) text runs | PDFKit characters, grouped into runs, then the same row-joining and watermark rules |
| `poppler` + `tesseract` OCR | Vision text recognition (D5) |
| `crypto` SHA-256, `zlib` deflate | own SHA-256 (tested against Node), Apple Compression framework |
| `fetch` (Open Food Facts) | URLSession, same 4 s timeout |
| AppKit printing, NSPrinter | ImageRenderer → PDF, UIPrintInteractionController, UIPrinter (D7) |
| WhatsApp Web in a parked window | WhatsApp Web in an in-app web view, foreground only (D1) |
| Timer every minute + launch catch-up | the same while the app is open, plus BGTaskScheduler when closed (D3) |
| NSOpenPanel / NSSavePanel | fileImporter / document picker / share sheet / Files |

## iOS UI layer

- The 9 Mac sections become **5 tabs**: Billing · All Bills · Stock · Parties · More. More holds Purchases, Salesmen, Dashboard,
  Books & GST and Settings. Each tab has its own NavigationStack.
- The company switcher and the financial-year switcher are in the navigation bar of every section.
- Sheets use Form inside NavigationStack with Cancel / Save. Destructive actions use `.confirmationDialog`.
- Mac **DataGrid** becomes `DataGrid` for iOS. It keeps the same column definitions, the same `grid.<key>` saved layout, horizontal scrolling, a pinned
  heading, drag-to-resize, and a column settings sheet (show/hide, move up/down, reset). Long-press a row opens its menu, and swipe gives the main
  actions. Select mode handles multi-select.
- Billing on iPhone: search, lines, then the three summary cards stacked under the lines. The Save button stays on screen at the bottom. On wider screens the cards sit side by side.
- Dynamic Type, light/dark, the 8 themes, safe areas. Layouts are checked against 414×896 pt (iPhone XR) up to Pro Max.

## Tests

1. `backend/test/smoke.js`: the Mac's own 72 checks (including the watermark and the three AK Enterprises bills).
2. `ios/tests/parity`: a scenario of over 200 requests runs through both engines. It covers companies, items, bulk prices, parties and routes,
   bills with schemes and FEFO, edits, deletes, credit-limit refusals, purchases, vouchers, ledgers, books, GST, the Excel workbook, and the dashboard.
   Every reply and every table row are compared.
3. Parser parity: every fixture bill parsed by both, outputs compared field by field.
4. Backup: Swift backup → Node restore (replace and merge), and Node backup → Swift restore. The restored databases are compared.
5. Unit tests (`BillBoxTests` in Xcode, `swift test` in `BillBoxCore`): `tests/parity/make_golden.py` records the Mac engine's answers
   (working session, random bills, parser, PDF page text, restoring a Mac backup by Replace / Merge / single file, BillMath on 3,000 bills).
   The tests replay them on the iOS engine with the clock fixed at the recording time and compare field by field. They also check that an
   iPhone backup has the Mac's layout (manifest key order, SHA-256, integrity) and restores unchanged.
6. The app code is type-checked on Linux against stubs of the iOS 16 SDK, with result builders capped at 10 children as in Xcode 14.
