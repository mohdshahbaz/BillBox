# BillBox — UI/UX overhaul and backend optimisation (agent prompt)

Paste everything below the line into a new Claude Code session that has the `mohdshahbaz/BillBox` repository attached.

---

You are working on **BillBox**, an FMCG distributor billing / ERP app (GST invoicing, batches, schemes, purchases,
stock, parties and ledgers, salesmen and routes, Books & GST reports, backups and sync). It is used daily by a
distributor (AK Enterprises) in India, often on a phone at the counter, so speed, clarity and correctness of money
figures matter more than decoration.

Your job: a **complete, modern UI/UX overhaul** of the iPhone, Mac and Windows/Linux apps, and an **optimisation of
the Node.js backend**, without changing any figure the app calculates or prints. Work autonomously, in stages, and
keep going until every acceptance check at the end passes.

## 1. Repository map (read these first)

| Part | Stack | Where | Minimum OS |
|---|---|---|---|
| iPhone app | Swift 5 + SwiftUI, engine in Swift (`BillBoxCore`) | `ios/` | **iOS 18.0** (already set) |
| Mac app | Swift + SwiftUI (AppKit where needed) | `macos/` (`Package.swift`, `Sources/DistributorPro`) | **macOS 12 Monterey** |
| Android app | Kotlin + Jetpack Compose, engine = bundled `backend/src` (`android/engine`) | `android/` | **Android 12 (minSdk 31)** |
| Windows + Linux app | Flutter (`frontend/`) + Node 22 running `backend/src` | `frontend/`, `desktop/` | **Windows 10** and Ubuntu 22.04 / Debian 12 |
| Books engine (backend) | Node.js 22, built-in SQLite | `backend/src`, tests in `backend/test` | — |

Read before changing anything: `README.md`, `ios/README.md`, `ios/ARCHITECTURE.md`, `ios/FEATURE_PARITY.md`,
`desktop/README.md`, `docs/CI_CD.md`, and every workflow in `.github/workflows/`.

## 2. Hard rules (never break these)

1. **Figures never change.** Totals, GST (CGST/SGST/IGST), rounding, stock, ledgers, numbering and backups must stay
   identical across engines. `ci.yml` › "Engines agree (Mac, iPhone, Android)" and the iPhone unit tests
   (`ios/BillBoxCore/Tests`, golden answers in `Golden/`) must pass. If a test fails, fix the code, not the test,
   unless the test encodes behaviour the owner has asked to change.
2. **Feature parity.** Every screen and setting keeps working on every platform. `ios/FEATURE_PARITY.md` is the
   contract; update it when you change a screen.
3. **Minimum OS versions above are fixed.**
   - **Mac (Monterey):** any SwiftUI or AppKit API newer than macOS 12 goes behind `if #available(macOS 13, *)` (or
     14/15) with a good-looking fallback. Never raise `.macOS(.v12)`.
   - **iPhone:** iOS 18 APIs are allowed. Code for the real SDK (packages, iOS 17/18 APIs) goes behind
     `#if XCODE_BUILD`, so the Linux type-check (`ios/tests/typecheck`) keeps working.
   - **Android:** keep `minSdk 31`.
   - **Windows and Linux:** Flutter must build for Windows 10 x64 and Ubuntu 22.04.
4. **Printing.** Bill layouts (classic, Marg, Busy, Bizom; half-sheet, A4, two-on-A4) are business documents.
   - Change their look only where asked.
   - Never lose a field.
   - Check every change against the drawn bills from the iPhone self-test (`bill_*.pdf` on the `selftest-results`
     branch).
5. **Accessibility.** Keep or improve the following:
   - Dynamic Type / text size settings.
   - VoiceOver / TalkBack labels.
   - Contrast of at least WCAG AA 4.5:1 for text.
   - Hit targets of at least 44 pt (iOS/macOS) and 48 dp (Android/Flutter).
   - Dark mode on every platform.
6. **Existing appearance settings stay working:** the 25 themes, accent colour, page background, panel style,
   corners, table row density, striped rows, text size, typeface (Settings › Appearance).
7. **Git:**
   - Work on a branch, e.g. `ui-overhaul`, never directly on `main`; every push to `main` starts an admin release.
   - Small, focused commits with clear messages, including `[skip release]`.
   - Push after every stage so work is never lost.
   - Do not merge to `main`; open one pull request at the end.
8. **Dependencies:** only well-maintained, permissively licensed packages (MIT/BSD/Apache), via SPM / Gradle / pub.
   Already in use on iOS: Pow (effects), PopupView (toasts), Swift Charts. Prefer the platform's own components.
   Add a library only when it clearly beats the built-in one.

## 3. Design research (do this first, keep it short)

Look up current guidance and apply it; cite what you used in `docs/DESIGN_SYSTEM.md`:

- Apple **Human Interface Guidelines** (iOS 18 and macOS): navigation, lists, tables, forms, sheets, toolbars,
  materials, SF Symbols, typography, colour, dark mode.
- **Material 3 / Material You** for Flutter (Windows/Linux) and Android: colour roles, typography scale, elevation,
  navigation rail vs drawer, data tables, density.
- **Microsoft Fluent 2** for how Windows 10/11 users expect a desktop app to feel: title bar, keyboard focus,
  density, shortcuts.
- Data-heavy / business app patterns: tables with sticky headers and sorting, filter chips, summary cards, empty
  states, skeleton loading, inline validation, undo instead of confirm where safe.

Then write **`docs/DESIGN_SYSTEM.md`**: one shared design language for all apps. It covers:
- **Colour tokens:** semantic roles mapped onto the existing themes.
- **Typography scale:** body, caption, title, money figures (monospaced digits).
- **Spacing:** a 4/8 pt grid.
- **Radii, elevation and shadows.**
- **Component specs:** cards, tables, buttons, fields, chips, pills, toasts, sheets, empty states, charts.
- **Motion:** durations and when to animate (never on money figures while typing).
- **Per-platform mapping:** SwiftUI, AppKit/SwiftUI on Mac, Flutter.

Every platform implements tokens from this one file.

## 4. iPhone app (Swift, iOS 18+): UI/UX overhaul

Start from the shared components so every screen benefits:
- `ios/BillBox/Shared/`: `Components.swift`, `Compat.swift`, `Themes.swift`, `DataGrid.swift`,
  `DesignSystem.swift`, `Effects.swift`.

Then go screen by screen: Dashboard, Billing, All Bills, Purchases, Stock, Parties (and ledger), Salesmen,
Debit Notes, Books & GST, Settings (every sub-page), onboarding / licence, sync, backup, print preview.

What good looks like:
- **Billing (most used):**
  - Fastest possible entry: search, scan, quantity, save.
  - Big readable total.
  - Clear error states.
  - Nothing jumps while typing.
  - The keyboard never hides the active field.
- **Tables:**
  - Sticky header with a proper margin, sorting, comfortable density.
  - No clipped dates or amounts.
  - Status pills for state.
  - A summary card for totals.
- **Navigation:** clean titles that are never cut off. The company / year switcher is tidy in the top bar.
- **Visual quality:**
  - Consistent spacing.
  - iOS 18 materials and MeshGradient where they add clarity.
  - SF Symbols with consistent weight.
  - Subtle motion (Pow) and haptics on save/add/error only.
- **Reliability:** empty states, loading (skeletons), and error states on every screen.
- **Platform fit:** iPad layout where cheap (the app already runs on iPad sizes in the simulator).

## 5. Mac app (Swift, macOS 12 Monterey+): UI/UX overhaul

- **Code:** `macos/Sources/DistributorPro`. Same design system, adapted to the Mac:
  - Sidebar navigation.
  - Toolbar actions.
  - Full keyboard support (existing ⌘1–⌘0 shortcuts, ⌘S save, ⌘F search, Esc close).
  - Hover states and context menus.
  - Resizable split views.
  - Window state remembered.
- **Native table look:** use Monterey-safe APIs. Newer APIs go behind `#available`, with fallbacks that look right
  on Monterey.
- **Type-check:** run `macos/tests/typecheck/build.sh` on Linux after every change. It shares stubs with iOS.

## 6. Windows and Linux app (Flutter): UI/UX overhaul

- **Material 3:**
  - `useMaterial3: true` with a `ColorScheme` built from the selected theme's accent.
  - Light and dark.
  - Desktop density.
- **Navigation:** `NavigationRail` (or a collapsible side rail) for the main sections, a top app bar with the
  company / year switcher, and full keyboard shortcuts matching the Mac.
- **Tables:** sticky header, sorting, resizable columns, hover rows, right-aligned monospaced money.
- **Windows 10 fit:** respect Fluent expectations (keyboard focus rings, mouse wheel, right-click menus, window
  title), and scale correctly at 100–200% DPI.
- **Check:** `flutter analyze` is clean, and the `desktop.yml` workflow builds both Windows and Linux.

## 7. Backend (Node.js 22): optimise and clean up

`backend/src` is also the engine inside Android, Windows, Linux and the Mac. Goals, in this order:
1. **Correctness first.** Every existing test passes: `backend/test/smoke.js` and the parity checks in `ci.yml`.
2. **Performance:**
   - Profile the slow paths: dashboard, All Bills with filters, stock list, GST reports and Excel export, backup and
     restore, PDF supplier-bill import.
   - Add SQLite indexes where queries scan.
   - Batch writes in transactions.
   - Use prepared statements, cached once.
   - Avoid N+1 queries.
   - Stream large exports.
   - Record before/after timings in `docs/BACKEND_PERF.md`.
3. **Design:**
   - Clear module boundaries (routes → services → data).
   - Consistent error objects (`{ code, message }`).
   - Input validation on every route.
   - No silent catches.
   - Small pure functions for GST and rounding (already in `utils/gst.js`).
4. **No behaviour changes** without updating every engine. The iPhone engine (`ios/BillBoxCore`) mirrors the Node
   one; keep them answering identically, and keep the Android bundle in step (`android/engine` builds from
   `backend/src`).

## 8. Build, run and test loop (repeat until done)

There may be no Mac in your environment; use GitHub Actions for everything Apple. After each stage:

1. **Local:**
   - `node --check` on changed JS.
   - The backend smoke tests (`node backend/test/smoke.js` when dependencies are installed).
   - The iOS and Mac Linux type-checks.
   - `flutter analyze` if Flutter is available.
2. **Push the branch.** CI runs the engine parity checks and the Android build; Desktop builds Windows and Linux.
3. **iPhone:** run **Actions › iPhone self-test** on the branch (`gh workflow run ios-selftest.yml --ref <branch>`).
   - Leave unit tests on when engine code changed, off for pure UI.
   - Read the results from the `selftest-results` branch, folder `ios/`:
     - `unit-tests.log`, `build-errors.txt`, `compare.txt`, `crash-reports.txt`.
     - Screenshots in `shots/` (every screen, light and dark).
     - Drawn bills (`bill_*.pdf`; render with `pdftoppm -r 200` to check details).
   - Look at every screenshot yourself. Fix anything clipped, misaligned, cramped, low-contrast or inconsistent with
     `DESIGN_SYSTEM.md`, then run again.
4. **Android:** **Actions › Android self-test** (`android-selftest.yml`) for screenshots on Android 12 and 14.
5. **Mac:** the Release workflow's Mac job (`platform=mac`, artifacts only, no publish) proves it builds on the
   runner's Xcode. Monterey compatibility comes from the `#available` rules and the type-check.
6. **Windows/Linux:** **Actions › Desktop** artifacts.

Stop a stage only when its checks are green **and** the screenshots look right.

## 9. Acceptance checklist (the work is done when all are true)

- [ ] `docs/DESIGN_SYSTEM.md` exists and every platform uses its tokens.
- [ ] iPhone: all 11 self-test screens plus dark mode look consistent. Nothing is clipped (dates, amounts, titles),
      every table sorts, and empty/loading/error states exist. The unit tests pass, the engine matches the Mac
      (543/543 steps) and there are no crash reports.
- [ ] Mac: builds in CI, type-check passes, and no API above macOS 12 is used without `#available`.
- [ ] Android: builds, the self-test screenshots look right on Android 12 and 14, and `minSdk` is still 31.
- [ ] Windows/Linux: `flutter analyze` is clean and both builds succeed in the Desktop workflow.
- [ ] Backend: all tests and parity checks pass. `docs/BACKEND_PERF.md` shows measured improvements on the slow
      paths, with no figure changed.
- [ ] Bills: every print style and layout still prints every field, and the self-test PDFs look right.
- [ ] `ios/FEATURE_PARITY.md`, the READMEs and `docs/CI_CD.md` are updated.
- [ ] One pull request into `main` with before/after screenshots and a summary per platform. Not merged.

## 10. Working across sessions and usage limits

You may hit a usage limit or the session may end. Make the work resumable:

- Keep **`docs/OVERHAUL_PROGRESS.md`** on the branch, updated and pushed after every stage. It records:
  - What is done and what is next.
  - Open problems.
  - The last self-test run id and its result.
- At the start of every session (or scheduled run): `git fetch`, check out the branch, read
  `docs/OVERHAUL_PROGRESS.md`, and continue from the first unfinished item. Never redo finished stages.
- If scheduled tasks are available, create one that runs this prompt again every few hours until the acceptance
  checklist is complete. It must stop itself (delete or disable the task) when everything is ticked.

## 11. Permissions

Before starting, list in one message every permission you will need, so the owner can approve them once. For
example: running shell commands, editing files, `git push` to the branch, `gh workflow run`, reading Actions logs,
web search for design guidance. After that, do not stop to ask again unless an action is destructive or outside the
branch (deleting data, pushing to `main`, publishing a public release, changing repository settings). Never do those
without asking.
