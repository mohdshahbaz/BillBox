# Round 5 — Mac app and iPhone app (same engine behaviour on both, parity-tested)

1. **Prices from MRP must give the bill total you expect.** Example: MRP 3,000 (box, GST included), selling price 2,500
   (GST included) = 16.67% below MRP; a new bill for that box must come to 2,500, not 2,950.
   - Find and fix every reason a bill can disagree with the price that was set: the billing screen keeps the item list it
     loaded when it first opened, so prices changed later (Set prices, item edits, imports, merges) are not used until the
     app restarts; prices are ex-GST in the books, so any price typed or imported without backing GST out shows 18% more.
   - Rewrite "Set prices from MRP" (engine and both screens): one clear sheet — % below MRP or a price for each MRP;
     retail, wholesale or both; typed per piece or per box; GST included or not; rounding of the box price (none, nearest
     rupee, nearest 5/10). The preview lists every item with its MRP (piece and box), the new box price with GST and what
     one box will total on a bill — the same arithmetic as billing — so what you see is what you bill.
2. **Merging items with similar names.** "Tidy names & merge duplicates" only found names that were identical after tidying.
   Find similar names too (spelling variants such as Bhujia / Bhujiya, word order, extra words, capitals, pack written
   differently) but never join different pack sizes or different MRPs. Matching strictness can be chosen; every group can be
   checked, items can be taken out of a group, and the item to keep chosen. Also: select items in Stock and "Merge selected…".
3. **A more modern, appealing look** on both apps: accent colour, softer cards, clearer headers, consistent spacing.
4. **More customisation throughout the app**: accent colour, text size, row density; billing (round the total to the rupee
   or not, default discount, default GST for new items); everything saved per company or per device as appropriate.
5. **Smoother, more efficient apps**: no item-list limit on the billing screen, item search that does not re-scan
   everything on each key, fewer reloads, faster dashboard and lists on both engines.

Rules: no feature removed; Mac (Node) and iPhone (Swift) engines give identical answers (tests/parity); iOS and Mac
sources type-check; existing tests keep passing; deliver one complete project zip.
