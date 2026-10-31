# Round 7 — iPhone billing: item search hides and the bill will not scroll

## Report
While making a bill on the iPhone, typing an item name in the search field makes the search field disappear right after
the first letters, and the bill can no longer be scrolled up and down.

## Cause
The suggestion list was laid out *beside* the bill table (a ZStack), so its full height (up to 8 rows, about 400 points)
counted towards the screen's height. With the keyboard up, that is more than the space left between the top bar and the
keyboard: the billing column overflowed, SwiftUI centred it, and its top — the search field — went under the solid top
bar (made solid in round 6). The overflowing layout also left the table without a usable height, so it would not scroll,
and the suggestion list itself could not scroll either.

## Fix
1. Draw the suggestions *over* the table (an overlay), so they never change the layout; they get at most the table's
   height and scroll inside it when there are more than fit (a short list keeps its own height).
2. Pin the billing column to the top, so whatever happens the search field stays in view under the top bar.
3. Keep the bill table scrollable with the keyboard up (rows stay alive while typing, as in round 6).
4. Check the Android billing screen for the same problem (its suggestions already float over the table and scroll).

Rules: nothing else changes; iPhone type-check and all parity tests keep passing; deliver one complete zip.
