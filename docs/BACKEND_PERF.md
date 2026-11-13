# Backend performance (books engine, `backend/src`)

How to measure: `cd backend && node test/bench.js [bills]` builds a throwaway company (20 000 sale bills with 4 lines
each, 2 000 purchases, 400 items with 3 batches, 300 parties, ledger rows), times each slow path (median of 7 after a
warm-up) and prints a **checksum of every answer**. A speed change is accepted only when the checksum is unchanged, so
no figure moved. `BENCH_DUMP=file` writes the answers out for a diff.

Machine: the cloud build sandbox, Node 22.23 (built-in SQLite). Two runs each; numbers are the mean of the two medians.

| Path | Before | After | Change | What changed |
|---|---:|---:|---:|---|
| Dashboard | 204 ms | 156 ms | −24 % | 14-day chart and 12-month sales/purchases from 4 grouped queries instead of 52; profit reads lines from a covering index |
| Profit (whole year) | 72 ms | 42 ms | −42 % | covering index `idx_invl_cover` on invoice_lines (invoice, item, batch, qty, free, taxable, rate) |
| GST outward (month) | 27 ms | 16 ms | −41 % | month as a date range (`date BETWEEN m-01 AND m-31`) so the date index is used; `substr(date,1,7)=?` scanned every line |
| GST workbook (month) | 51 ms | 29 ms | −43 % | same, for the bill list and the rate list |
| All bills (year / search / unpaid) | 34 / 23 / 23 ms | 34 / 24 / 21 ms | — | already index-driven; capped at 1 000 rows |
| Sales book (year) | 63 ms | 66 ms | — | 20 000 rows to JSON; the time is the copy, not the query |
| Low stock | 0.2 ms | 0.2 ms | — | — |

Answers checksum before and after: `6a04214f8649d201` (identical). `node test/smoke.js`: 89 checks pass.

## Changes

- **Prepared statements cached** (`src/sqlite.js`): each SQL text is compiled once per id range and reused (500
  statements, oldest dropped first; cleared by `exec`, which runs DDL, and on close). Saves the compile and the
  parameter-name scan on every call; the effect is small on these read paths (the time is in the scans) but every
  billing / sync call benefits.
- **Covering index** `idx_invl_cover` (`src/schema.js`, created on open for existing books too).
- **Month ranges instead of `substr`** in `gstOutward` / `gstOutwardDetail`. The GST workbook's "GST Rates" column
  keeps line order with `INDEXED BY idx_invl_inv`, exactly as before and as the iPhone engine lists them.
- **Grouped dashboard series** (`sumsBy`): one `GROUP BY date` / `GROUP BY month` query per table. Monthly profit stays
  one query per month: a single grouped query needed a temporary sort and was slower (86 ms vs 65 ms).

## Second pass (2026-11-13): Excel export, backup / restore, PDF import

`test/bench.js` now also times these (backup and restore once each, as they write files). The restore prints its own
**merge checksum** of every row it wrote, which must stay the same; `answers checksum` covers the Excel bytes.

| Path | Before | After | What changed |
|---|---:|---:|---|
| **Restore, merge into empty books** (20 000 bills) | **64.8 s** | **1.9 s** | each bill looked for its lines by scanning *all* bill lines (20 000 × 80 000); lines are now grouped by bill once. Same for purchases and debit notes (and their stock rows). Column lists read once per table. Ported to the iPhone engine (`Backup.swift`). |
| Excel: sales book of the year as .xlsx | ~0.19 s | ~0.17 s | `zlib.crc32` (native) instead of the JS loop when Node has it; the rest is building the sheet XML, fine as it is |
| Backup now (VACUUM INTO + integrity check + SHA-256) | 0.21 s | 0.21 s | nothing to gain: SQLite's own copy |
| PDF import: parse a 40-line supplier bill against 400 items | 62 ms | 62 ms | fine for one bill at a time |

Merge checksum before and after the fix (3 000-bill run): `1c7550c93636db54` (identical). Answers checksum unchanged.
The Android bundle is rebuilt from these sources (`./build.sh engine`), parity 543/543, fuzz 1647/1647.

## Not changed (yet)

- The iPhone engine (`ios/BillBoxCore`) has its own SQL; its answers are unchanged and still match.
