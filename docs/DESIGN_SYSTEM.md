# BillBox design system

One design language for every BillBox app: iPhone (SwiftUI), Mac (SwiftUI/AppKit), Android (Jetpack Compose, Material 3)
and Windows/Linux (Flutter, Material 3). Each platform keeps its own native controls and conventions, and implements the
tokens below. Money and GST figures are the heart of the app: they are always easy to read, never animated while typing,
and never cut off.

Sources:
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines.md)
- [Material 3 theming codelab (Android)](https://developer.android.com/codelabs/m3-design-theming)
- [Fluent 2 layout](https://fluent2.microsoft.design/layout)
- [Windows app design guidelines](https://learn.microsoft.com/windows/apps/design/guidelines-overview)
- [Style for Windows apps](https://developer.microsoft.com/design/style)

## 1. Principles

1. **The counter comes first.** Billing is the most used screen. Every design choice favours speed: search, quantity,
   save, with no extra taps, no layout jumps, and the keyboard never hiding the active field.
2. **Figures are content.** Totals, dues and GST use monospaced (tabular) digits, right alignment in tables, and a
   clear hierarchy: one strong figure per card, everything else secondary.
3. **Quiet chrome, clear state.** Backgrounds and panels stay calm. Colour is kept for meaning (status, money owed,
   errors) and for the user's accent.
4. **Native on each platform.** We follow each platform's own navigation and controls (Apple HIG, Material 3, Fluent
   expectations on Windows) rather than one custom skin everywhere.
5. **Every state is designed:** loading (skeletons), empty (icon + one line + action), error (what happened + what to
   do), and success (toast + haptic on phones).
6. **Accessible by default:**
   - Text contrast of at least 4.5:1, and 3:1 for large text and icons.
   - Hit targets of at least 44 pt (Apple) / 48 dp (Android, Flutter).
   - Dynamic Type and text size settings respected.
   - Full keyboard use on Mac and desktop.
   - Screen-reader labels on every control.

## 2. Colour

The 25 themes (`ios/BillBox/Shared/Themes.swift`; the same list on Mac, Android and Flutter) each give an **accent**,
**page** and **card** colour for light and dark. Every other colour is a semantic role:

| Role | Use | Light | Dark |
|---|---|---|---|
| `accent` | primary actions, selection, links, totals heading | theme accent | theme accent (dark variant) |
| `page` | screen background | theme page | theme page |
| `card` | cards, tables, sheets | theme card | theme card |
| `text` | primary text | system label | system label |
| `textSecondary` | captions, labels, table headers | secondary label | secondary label |
| `line` | separators, table rules | separator (≈ 12% black) | separator (≈ 16% white) |
| `positive` | profit, paid, success | green 600 | green 400 |
| `negative` | due, loss, errors | red 600 | red 400 |
| `warning` | not printed, expiring, low stock | orange 600 | orange 400 |
| `info` | bills to print, notices | blue 600 | blue 400 |
| `tint(x)` | pill / badge background | role at 12–14% opacity | role at 18% opacity |

Rules:
- Text on the accent is white; check contrast for light accents (Marigold, Sand) and darken the accent's text variant
  when needed.
- Status always has text as well as colour (a pill says "Not yet", it is not only orange).
- Material 3 platforms build their `ColorScheme` from the accent (`primary` = accent, `surface` = card,
  `background` = page, `outlineVariant` = line). Dynamic colour (Material You) is an option in Settings › Appearance,
  off by default.

## 3. Typography

| Token | Apple (SwiftUI) | Material 3 (Compose / Flutter) | Use |
|---|---|---|---|
| `display` | `.largeTitle` rounded, bold | `displaySmall` | Dashboard hero figure |
| `title` | `.title2` semibold | `titleLarge` | Screen sections, card titles |
| `headline` | `.headline` | `titleMedium` | Card headers, list titles |
| `body` | `.body` | `bodyLarge` | Default text, table cells |
| `callout` | `.callout` | `bodyMedium` | Secondary rows, chips |
| `caption` | `.caption` | `labelMedium` | Labels above figures, table headers (upper case, semibold) |
| `money` | `.title2` rounded semibold + `.monospacedDigit()` | `titleLarge` + tabular figures | KPI and summary figures |
| `moneyCell` | `.body` + `.monospacedDigit()` | `bodyLarge` + tabular figures | Amounts in tables, right aligned |

- At most three sizes on one card.
- Table headers are `caption`, upper case, semibold, secondary colour.
- The user's typeface and text size settings scale everything.

## 4. Spacing, size and shape

- **Grid:** 4 pt base. The steps used are 4, 8, 12, 16, 20, 24, 32.
- **Screen padding:** 16 (phone), 20 (tablet / Mac / desktop).
- **Card padding:** 14. Gap between cards: 12.
- **Table cell padding:** 8 horizontal. Row height 36 (regular), ×0.82 compact, ×1.22 roomy. Header 34.
- **Corner radii:**

  | Element | Radius |
  |---|---|
  | Cards and tables | 14 |
  | Hero | 22 |
  | Buttons and fields | 12 |
  | Chips / pills | capsule |
  | Sheets | platform default |

  The user's Corners setting scales these (square ×0.45, round ×1.6).
- **Elevation** (soft panel style): two-layer shadow, contact (5% black, radius 1.5, y 1) plus ambient (7% black,
  radius 14, y 6), drawn from the shape only (never on content, for scrolling speed). Outlined style: 1 pt line at
  16%. Flat: hairline at 6%.
- **Minimum widths so nothing is cut off:**

  | Content | Minimum width |
  |---|---|
  | Date (DD-MM-YYYY) | 122 pt |
  | Money | 90 pt |
  | Status pill | its text + 16 |

## 5. Components

| Component | Spec |
|---|---|
| **Card** | `card` background, radius 14, soft elevation, padding 14. |
| **KPI card** | Icon in a 30 pt rounded square tinted 14%; title `callout` secondary; value `money`; note `caption` (two lines reserved, so cards line up). Pressing sinks it slightly (push-down). Tapping opens the screen behind it. |
| **Table** | Rounded card with a 10 pt side margin and an 8 pt margin above. Sticky header band tinted with accent at 6%. Tap a header to sort (arrow shows direction; S.No restores order). Inset separators at 45%. Optional stripes. Long-press menu per row. Select mode with a bar. |
| **Summary card** | Under tables. Label (`caption`) above value (`callout` medium), adaptive grid of 104 pt cells; the key figure bold and coloured by role. |
| **Status pill** | Capsule, `caption` semibold, role colour on a 13% tint. An empty pill keeps its width. |
| **Buttons** | One prominent action per screen (filled, accent). Others bordered (radius 12) or plain. Destructive actions are red with confirmation, or undo where safe. |
| **Fields** | Label above or leading. Inline validation under the field in `negative`. Number pads for quantities and money. |
| **Date button** | Capsule tinted with accent at 10%: calendar icon, small grey label, date in `callout` medium. Never truncated. |
| **Toasts** | Float at the top (PopupView on iOS; SnackBar on Material). Coloured badge, selectable text, close button, swipe to dismiss. 3.5 s for success, 7 s for errors. Shown over sheets. |
| **Empty state** | SF Symbol / Material icon 34 pt, `title3` line, one secondary sentence, optional action. |
| **Loading** | Skeleton rows for tables and cards. A spinner only for full-screen first load. |
| **Charts** | Swift Charts / native charts. Value axis with short Indian figures (1.2k, 3.4 L, 1.5 Cr). Tap a bar to read its figure. Sales teal, purchases orange, profit green / red for loss. |
| **Navigation** | iPhone: tab bar (Billing, All Bills, Stock, Parties, More). iPad and Mac: sidebar. Android: NavigationBar on phones, NavigationRail on large screens. Windows/Linux: NavigationRail. The company / year switcher sits leading in the top bar, max 150 pt. |

## 6. Motion and feedback

- **Durations:** 0.2–0.35 s with spring or ease-out. Nothing longer than 0.45 s.
- **What animates:**
  - Figures roll (numeric content transition) when a period or total changes.
  - Toasts slide in from the top.
  - Cards sink on press.
- **What never animates:** a field being typed in, or table rows while scrolling.
- **Effects and haptics (phones):** success spray on save, shine and a light tap on adding an item, shake and an error
  tap on a refused save.
- **Reduce Motion:** turns effects off and keeps fades.

## 7. Per-platform notes

- **iPhone (iOS 18+):**
  - MeshGradient hero, materials for floating elements, Swift Charts, SF Symbols (one weight per screen).
  - Code for the real SDK sits behind `#if XCODE_BUILD`.
- **Mac (macOS 12+):**
  - Sidebar plus toolbar, hover states, context menus, keyboard shortcuts (⌘1–⌘0, ⌘S, ⌘F, Esc).
  - Anything newer than Monterey goes behind `#available` with a Monterey-quality fallback.
- **Android (12+, minSdk 31):**
  - Material 3 with edge-to-edge, the Android 12 splash screen, predictive back on 14+, and window size classes.
  - 48 dp targets.
- **Windows 10+ / Linux:**
  - Flutter Material 3 at desktop density, `NavigationRail`.
  - Keyboard focus rings, right-click menus, mouse-wheel scrolling.
  - Correct at 100–200% display scaling.
  - Window title "BillBox — Company · FY".

## 8. Printing (bills)

Bills are business documents.
- Changes are deliberate and checked on the drawn PDFs.
- The ruled frame, the band dividers (fine 0.5 pt grey between words, bank, receiver and signature; heavier rule
  before the totals) and the shaded heading rows are the visual language.
- New fields must never push others off the page.
