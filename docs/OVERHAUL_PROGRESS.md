# UI overhaul — progress

Branch: `ui-overhaul` (from `ios-design-refresh`). Prompt: `docs/UI_OVERHAUL_PROMPT.md`. Never push to `main`.

## Stages
- [x] 1. Design research and `docs/DESIGN_SYSTEM.md`
- [x] 2. iPhone: shared components to the design system
- [ ] 3. iPhone: screen by screen, self-test screenshots reviewed (in progress)
- [ ] 4. Android: theme and components (Material 3), then screens; Android self-test
- [ ] 5. Windows/Linux (Flutter): Material 3 theme, navigation rail, tables; Desktop workflow
- [ ] 6. Mac (Monterey-safe): sidebar, toolbar, tables; Mac build in CI
- [ ] 7. Backend: profile, indexes, prepared statements, `docs/BACKEND_PERF.md`; parity checks green
- [ ] 8. Bills: every style and layout checked from self-test PDFs
- [ ] 9. Docs updated, one pull request into `main` (not merged)

## Log
- 2026-11-12 (run 2): stage 2 done — `DS` tokens (space, pad, radius, width, hit target, tint, motion), type tokens
  (`Font.dsMoney` …), semantic roles `Theme.positive/negative/warning/info`, `SkeletonRows`, `ErrorState`, `EmptyState`
  with action; StatCard, SummaryCard, StatusPill, Banner, toasts, FormSheet errors on tokens. Linux stubs: `repeatForever`,
  `accessibilityReduceMotion`.
  Stage 3 so far: skeleton + error state (Try again) on All Bills, Stock, Parties, Debit Notes; semantic colours on every
  screen (52 lines); Billing bar shows "Save" (was cut "Save & pri…"), steady total; dashboard alert chips wrap instead of
  being cut, plurals; bill / invoice / note numbers truncate in the middle; S.No header on one line; Debit Notes totals
  as a SummaryCard; Purchase title short; no update banner during the self-test.
  Self-test runs 43308039503 and 43309774766: build OK, 543/543 steps match, no crash reports. CI green (43309774159).
- 2026-11-13: stage 1 done — docs/DESIGN_SYSTEM.md (principles, colour roles, type, spacing, components, motion, per-platform, printing).
- 2026-11-13: branch created; already done on the way (from ios-design-refresh): iOS 18 target, Swift Charts dashboard,
  Pow effects, PopupView toasts, tables as rounded cards with sorting and status pills, summary cards, real IGST in
  GST outward (all engines), classic bill band with receiver/authorised signature boxes.

## Open problems
- Local Swift toolchain download is blocked (403) in the cloud sandbox, so the Linux type-checks cannot run here; the
  iPhone self-test build (Xcode) is the compile check.
- Stocks / Bills tables run past the screen edge (scroll sideways by design); consider hiding low-value columns by
  default on compact width.

## Next
Stage 3: check the latest self-test (commit 5f4f197); then Billing keyboard/scan flow, Settings sub-pages, sheets;
one run with unit tests on; then tick stage 3 and move to stage 4 (Android).
