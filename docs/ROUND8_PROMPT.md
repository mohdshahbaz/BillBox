# Round 8 — Marg numbering and more print settings (Mac, iPhone and Android)

## 1. Follow Marg's invoice numbering and carry on from the last bill
- Marg numbers bills as a prefix and a fixed number of digits, with no year: sale bills A000001…, purchases P000001…,
  debit notes DNB00001… (seen in the AK Enterprises Marg backup: A000001–A000422, P000001–P000014, DNB00001–DNB00002).
- Each series gets its own number of digits (1–9), besides its prefix; the year in the number stays optional.
- A new number always carries on after the highest number already used with the same prefix — bills imported from Marg,
  bills made before the numbering changed — so after A000422 comes A000423 and numbers never clash.
- After a Marg import, BillBox takes Marg's pattern by itself (prefix and digits read from the last bill of each kind),
  unless numbering was already chosen in Settings; the import result says which numbers come next.
- Settings › Billing & Dashboard › Numbering: a "Use Marg's numbering" button; per series the prefix, digits, the last number
  used, the next number, and "start the next one at" (it must come after the last one used).
- Engine: GET /numbering, PUT /numbering {series, next}; same answers on the Mac engine and the Swift engine (parity).

## 2. More options for the printed bill (Settings › Printing)
- Show or hide: the party's address / GSTIN / phone, salesman, payment mode, the GST rate-wise table, terms, the Taxable
  column (besides HSN, MRP, Disc %, GST %).
- The party's previous balance, this bill and the total now due (from the ledger; the engine adds it to the bill).
- Item names in capitals; quantity as boxes and pieces or pieces only.
- Text size smaller / normal / larger (rows grow with the text, so nothing is cut).
- A third copy (Triplicate) with its own label.
- Your own lines: a line under the company name, bank details, a note at the bottom.
- The same on the Mac, iPhone and Android bills.

Rules: nothing removed; engines give identical answers; all type-checks and parity tests pass; one complete zip.
