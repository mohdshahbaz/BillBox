# Round 4 — Mac app and iPhone app (same engine behaviour on both, parity-tested)

1. **Items from company price lists online.** Stock › "Find items online": type a company (e.g. Bikano) and optionally a
   category; BillBox searches the web for that company's price list (its website pages and PDF price lists), reads the
   item names from it, cleans them (spacing, case, "20 gm"/"20GM" → "20g", prices and pack noise removed) and merges
   duplicates, then shows a list to tick and add (category and company set, items already in stock skipped).
   Also "Clean names & merge duplicates" for the items already in stock: preview, then merge (bills, stock and schemes move
   to the kept item).
2. **Separate financial years (Marg style).** Each year of a company is its own set of books (its own file). "Start
   new year" carries the masters, party closing balances and closing stock forward as the new year's opening.
   "Add an earlier year" makes empty books for a past year (e.g. to import that year's Marg data). The year
   switcher opens that year's books; Marg import goes into the open year. Backups keep every year.
3. **Save now, print later.** Setting: after saving a bill — print now / ask / keep for later. All Bills gets a
   "Not printed" filter, multi-select and "Print selected" (one print job, every bill in order, both copies).
4. **Payments from a photo of a handwritten list.** Camera (iPhone) or an image file (Mac): each row is
   `party name, bill amount, bill amount, … payment`. Text is read on the device (Vision), cleaned, each row matched to a
   party (fuzzy) and to its unpaid bills; a review table (editable) then records all receipts at once.
5. **Dashboard redesign**: period switch (today / month / year), tappable cards that open the matching screen,
   interactive sales-vs-purchases chart (tap a bar for its figures), top dues, low stock, quick actions.
6. **More settings**: printed bill (title, which columns, amount in words, terms, signature line, copy labels), billing
   defaults (pay mode, sale type), dashboard cards, after-save action.
7. **Speed**: indexes for the heavy queries, fewer queries per screen, faster lists on both apps.

Rules: no feature removed; Mac (Node) and iPhone (Swift) engines give identical answers (tests/parity); iOS and Mac
sources type-check; existing tests keep passing.
