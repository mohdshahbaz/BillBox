# Windows/Linux app: parity with the Mac

The Windows and Linux app (`frontend/`, Flutter) runs the same books engine as the Mac (`backend/src`), so every figure
is the same. This page lists which Mac features have a screen on Windows/Linux. Updated 2026-11-13.

## Added on 2026-11-13

| Feature | Where on Windows/Linux | Engine routes | Differences from the Mac |
|---|---|---|---|
| Debit notes | Sidebar › **Debit notes** (Ctrl+0), under Purchases: list with search, new/edit with live totals, view, print, delete | `/debit-notes`, `/debit-notes/preview`, `/debit-notes/:id` | none |
| Return goods from a purchase | All bills › right-click a purchase › **Return goods (debit note)…** (opens a note filled from that bill) | `GET /purchases/:id` | none |
| Debit note printing | Same print manager, layouts and printer as bills | `GET /debit-notes/:id` (`print_lines`, `doc_title`) | none |
| E-way bill JSON | All bills › right-click a sale › **E-way bill…**: transport details, saves the portal's bulk-upload JSON, stores the e-way bill number | `/invoices/:id/ewaybill` (GET, POST, PUT) | none |
| Send a bill on WhatsApp | All bills › right-click a sale › **Send on WhatsApp…**; Settings › Printing › WhatsApp (country code, message) | none (`GET /invoices/:id`) | The Mac sends by itself in the background. Windows/Linux saves the bill PDF and opens the customer's chat with the message; you attach the PDF and press Send. |
| Salesman edit, merge, delete | Salesmen › ⋯ menu, or right-click a salesman | `PUT/DELETE /salesmen/:id`, `POST /salesmen/:id/merge` | none |
| Stock tools | Stock › **More**: Auto-fill missing MRPs, Pieces per box from item names, Price for each MRP, Tidy names & merge duplicates, Items from the internet. Right-click an item: **Set stock count**, **Merge duplicates into this** | `/items/auto-mrp`, `/items/auto-pack`, `/items/mrp-table`, `/items/set-prices`, `/items/clean-preview`, `/items/clean-names`, `/items/merge`, `/items/online/*`, `/items/bulk-add`, `/items/:id/set-stock` | Merge: the Mac merges the rows selected in the table; Windows/Linux picks the duplicates in a list. |
| Reports | Books & GST tabs: **Debit notes book**, **Profit**, **Outstanding** (copy as CSV), **Expiry** (30/60/90/180 days) | `/reports/book/debit`, `/reports/profit`, `/reports/outstanding`, `/reports/expiry` | The Mac shows profit and expiry on the dashboard only. |
| Marg import | Settings › **Marg import**: choose the Marg CSV backup folder or .zip, see what is in it and the checks against Marg, import, and correct item prices | `/import/marg/preview`, `/import/marg`, `/import/marg/prices` | none |
| A new year's books | Settings › Companies › **Financial years**: start a year as its own file (carried forward or empty), open another year's file | `POST /companies/:id/years`, `POST /companies/:id/activate` | none |
| Payments from a list | Parties › Customers › **Payments from a list**: type or paste "name bills - paid" lines, check the matches, save all | `/receipts/sheet/parse`, `/receipts/sheet` | The Mac also reads the list from a photo (Apple Vision). Windows/Linux has no text recognition, so the list is typed or pasted. |

Also fixed on the way: the Marg import read every file in the chosen folder and stopped with "Server error" on a
special file. It now reads only `.csv` files, in the backend and the iPhone engine.

## Still Mac-only

- **Print designs**: Marg, Busy and Bizom bill designs. Windows/Linux prints the BillBox design only.
- **Payment photo text recognition** (see above).
- **Sending on WhatsApp without a click** (see above).

## How it is tested

- `desktop/ci/api-check.mjs` runs inside the Desktop workflow against the app's own engine. It checks every engine route
  these screens use, and that each reply has the fields the Dart code reads (17 checks).
- `desktop/ci/linux-ui-test.sh` opens all 10 screens in light and dark mode. It fails on Flutter errors, or if the
  screens do not change. Screenshots go to `selftest-results/desktop-linux`.
- `flutter analyze` runs with no errors on Linux and Windows.
