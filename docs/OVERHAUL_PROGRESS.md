# UI overhaul — progress

Branch: `ui-overhaul` (from `ios-design-refresh`). Prompt: `docs/UI_OVERHAUL_PROMPT.md`. Never push to `main`.

## Stages
- [x] 1. Design research and `docs/DESIGN_SYSTEM.md`
- [ ] 2. iPhone: shared components to the design system
- [ ] 3. iPhone: screen by screen, self-test screenshots reviewed
- [ ] 4. Android: theme and components (Material 3), then screens; Android self-test
- [ ] 5. Windows/Linux (Flutter): Material 3 theme, navigation rail, tables; Desktop workflow
- [ ] 6. Mac (Monterey-safe): sidebar, toolbar, tables; Mac build in CI
- [ ] 7. Backend: profile, indexes, prepared statements, `docs/BACKEND_PERF.md`; parity checks green
- [ ] 8. Bills: every style and layout checked from self-test PDFs
- [ ] 9. Docs updated, one pull request into `main` (not merged)

## Log
- 2026-11-13: stage 1 done — docs/DESIGN_SYSTEM.md (principles, colour roles, type, spacing, components, motion, per-platform, printing).
- 2026-11-13: branch created; already done on the way (from ios-design-refresh): iOS 18 target, Swift Charts dashboard,
  Pow effects, PopupView toasts, tables as rounded cards with sorting and status pills, summary cards, real IGST in
  GST outward (all engines), classic bill band with receiver/authorised signature boxes.

## Next
Stage 2: bring iPhone shared components (Components, Compat, Themes, DataGrid, DesignSystem, Effects) fully onto the design system tokens (semantic colour roles, type tokens, skeleton loading, empty/error states), then stage 3 screen by screen with self-test screenshots.
