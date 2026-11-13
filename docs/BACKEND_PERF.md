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

## Not changed (yet)

- The Android app's bundled engine (`android/app/src/main/assets/engine/engine.js`) is rebuilt from `backend/src` by
  `cd android && ./build.sh engine`; npm was unreachable from the sandbox that made these changes, so the committed bundle
  is still the previous one (same answers, older speed). CI rebuilds it for the parity check and prints a notice.
- Excel export, backup / restore and PDF supplier-bill import were not profiled in this pass.
- The iPhone engine (`ios/BillBoxCore`) has its own SQL; its answers are unchanged and still match.
