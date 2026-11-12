# UI overhaul — progress

Branch: `ui-overhaul` (from `ios-design-refresh`). Prompt: `docs/UI_OVERHAUL_PROMPT.md`. Never push to `main`.

## Stages
- [x] 1. Design research and `docs/DESIGN_SYSTEM.md`
- [x] 2. iPhone: shared components to the design system
- [x] 3. iPhone: screen by screen, self-test screenshots reviewed
- [x] 4. Android: theme and components (Material 3), then screens; Android self-test
- [ ] 5. Windows/Linux (Flutter): Material 3 theme, navigation rail, tables; Desktop workflow (in progress)
- [ ] 6. Mac (Monterey-safe): sidebar, toolbar, tables; Mac build in CI
- [ ] 7. Backend: profile, indexes, prepared statements, `docs/BACKEND_PERF.md`; parity checks green
- [ ] 8. Bills: every style and layout checked from self-test PDFs
- [ ] 9. Docs updated, one pull request into `main` (not merged)

## Log
- 2026-11-12 (run 3): stage 5 part 1. Flutter `Palette` now holds the design-system Clean colours (indigo accent,
  AA-contrast warning/negative/positive), `DS` tokens, radii 14/12, table heading band tinted + upper case,
  `SummaryCard`/`StatusPill` (All Bills uses both), Ctrl+1…9 on Windows/Linux (⌘ kept for Mac keyboards), window
  title "BillBox — Company"; analyzer infos cut from 43 to the deprecation notes. Desktop workflow 43324558941:
  Linux and Windows build + smoke test green; `flutter analyze`: 0 errors, 0 warnings (infos only:
  `package:flutter/material.dart` deprecated in Flutter 3.50 in favour of material_ui — not migrated).
- 2026-11-12 (run 2, end): stage 4 done. Android: status pills (bill type, printed, party type), tabular figures for
  amounts, summary card clears the floating button, self-test now also shoots 5 screens in dark mode.
  Android self-test 8ed38b7: API 31 and API 34 both 543/543 steps match (API 31 had 499 differences before the
  randomUUID fix); light and dark screenshots reviewed. CI green on be32f31 (engines agree, Android builds).
  Last iPhone self-test: 43314544985 (b293417) green.
- 2026-11-12 (run 2, later): stage 3 done. iPhone self-test 43314544985 (b293417, unit tests on): 17 tests passed,
  543/543 steps match, no crash reports, screenshots reviewed (no banner, chips wrap, summary cards, nothing cut).
  Stage 4 started: Android `DS` tokens; semantic colours `Good/Bad/Warn/Info/Money` now light/dark pairs with AA
  contrast (old orange #E08A00 was ~2.4:1); Android 12 splash (windowSplashScreen*), predictive back
  (enableOnBackInvokedCallback); tables are rounded cards with a tinted upper-case heading band; `SummaryCard`,
  `StatusPill`, `SkeletonRows`, `ErrorState`; Bills / Debit Notes / Books footers as summary cards; dashboard chips wrap.
  Fixed a real Android 12 bug found by the self-test: `crypto.randomUUID` missing in the WebView engine made every company
  save fail (android/engine/shims/crypto.js falls back to getRandomValues). Parity compare ignores the device-local
  `license_*` app settings. Android typecheck stubs fixed (PaddingValues(bottom=), PrintAttributes.Builder).
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
- Local Swift toolchain download is blocked (403) in the cloud sandbox, so the iOS/Mac Linux type-checks cannot run here;
  the iPhone self-test build (Xcode) is the compile check.
- The Android typecheck stubs do not know @Composable rules; the CI Android build is the real check (a composable
  getter read inside a Canvas block broke e03c89e, fixed in f33071b).
- iPhone/Android tables still run past the screen edge (sideways scroll by design).

## Next
Stage 5 part 2 (Flutter): dark mode and the 25 themes need `Palette` to stop being `const` (≈136 uses, many in
`const` widgets) — plan: a `ThemeExtension<BillBoxColors>` read via `context.bb`, migrate screen by screen, then
`darkTheme` + `themeMode`, plus an Appearance section in Settings (theme, light/dark) stored in app_settings;
sticky table headings (header outside the vertical scroll); summary cards on Books & GST and Debit Notes;
keyboard focus rings. Check every step with the Desktop workflow (push to ui-overhaul runs it; ~6 min).
Then stage 6 (Mac), 7 (backend perf), 8 (bills), 9 (docs + PR).
