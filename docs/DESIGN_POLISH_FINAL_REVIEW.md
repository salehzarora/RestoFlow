# RestoFlow — Design Polish Final Review

> Closing document of the UI/UX Design Polish Sprint (2026-07-03, branch
> `feature/product-rescue-visible-mvp`). Scope doc: [DESIGN_POLISH_AUDIT.md](DESIGN_POLISH_AUDIT.md).
> Design/UX only — backend, migrations, RLS, RPC signatures, auth/session,
> order/printer/business logic untouched.

## 1. Design system changes (`packages/design_system`)

- **True semantic colors** — `RestoflowSemanticColors` `ThemeExtension`
  (light + dark presets): success **green**, warning **amber**, danger
  **red**, info **blue** (+ `on`/`Container` pairs), the warm **terracotta
  accent** for brand moments, and the dark-sidebar palette. `RestoflowTone`
  gained `styleOf(theme)` — theme-aware with a scheme fallback, so every
  existing pill/banner/chip in 25 files switched to real status colors with
  no per-screen change, and bare-`MaterialApp` test harnesses keep working.
- **Theme coverage** — inputs (filled, rounded), dialogs (radius 20), bottom
  sheets, snackbars (floating), popup menus, segmented buttons, list tiles,
  navigation bar, progress, FAB; buttons ≥44dp with baked text styles;
  typography scale with baked weights (headlineSmall w800 … labelLarge w600)
  and **zero letter-spacing** (Arabic glyph joining) + ar/he-friendly font
  fallbacks.
- **Tokens** — `xxs` spacing, `xl` radius, icon-size scale, shared
  breakpoints (560/820/900 — values identical to what the test corpus pins),
  standard panel widths, motion durations; `RestoflowCategoryPalette` (the
  warm menu-category accents, replacing duplicated hex literals).
- **New components** — `RestoflowPageHeader`, `RestoflowStateView`
  (empty/loading/error/denied; tone-aware; not Card-based),
  `RestoflowSkeleton` (static — never breaks `pumpAndSettle`),
  `RestoflowStepTile` (checklist), `RestoflowNumericKeypad` (PIN + cash),
  `RestoflowBrandMark`, `RestoflowCodeBlock` (forced-LTR),
  `RestoflowLanguageSelector`, `RestoflowButtonStyles`
  (big 52dp / danger / success / dangerGhost), `RestoflowInlineSpinner`.
- 36 design-system tests (13 new) pin the extension, fallback, tokens, and
  every new component.

## 2. What each surface looks like now (before → after)

**Dashboard** — was: stock light `NavigationRail`, thin header, bare login
form, four identical-looking tabs of outlined cards. Now: a **soft dark
green sidebar** with the brand lockup and an animated active pill over clean
light content; a branded header (org · branch context, Real/Demo pill,
language, sign-out); login/signup/onboarding with a brand hero; Overview
with a proper page header + tone-coded KPI tiles and intentional
loading/error/empty states; the setup checklist as a **numbered step list
with a progress bar**; the menu builder without its duplicated title and
with the modifier editor de-nested; Tables as a **floor-manager grid**
(status accent edge per tile, tone pills); Devices with unmistakable POS
(terracotta) vs KDS (blue) identity tiles; Printers with wrap-safe pills, a
step-dot wizard, and larger choice tiles; Staff/Users/Settings on the same
pill + state-view language.

**POS** — was: generic M3 with 36px steppers, OS-keyboard cash entry, demo
pastel statuses. Now: touch-first (≥44–48dp steppers, chips, option rows,
quick-cash), price-forward menu cards, a stronger cart with an amber
pending-sync pill and a big Send, a modifier sheet with selectable bordered
tiles + a **visible running total**, a cash sheet with an **on-screen
keypad** and the change-due as the loudest (green) element, a compact
success confirmation, receipts without Arabic-breaking letter-spacing, and a
readable cash-in-drawer figure.

**KDS** — was: light board, four identical green column headers, small
type. Now: **dark high-contrast kitchen theme**; columns colored by meaning
(New=blue, Preparing=amber, Ready=green, Cleared=muted) with icons, count
badges, and empty-column placeholders; tickets with big order numbers,
status accent edges, one unified card design across live/demo boards, ≥48dp
action buttons; age-escalating elapsed pill (demo board); a **stale-data
banner** when polling fails; the language switcher restored on the live
board; the print preview stays paper-white inside the dark app.

**Auth/pairing** — was: bare forms and icon+text gate states that looked
identical for success and failure. Now: brand hero on pairing (+ "where do
I get a code" helper), large touch staff tiles with initials avatars and
role pills, an on-screen **PIN keypad**, tone-aware gate states (failures
look like failures), a membership picker with monograms and role pills, and
both help pages on one pattern with LTR code blocks.

**Cross-cutting** — one language selector implementation (was 4 copies),
one pill family, one demo-banner recipe, one state-view family, shared
inline spinner, named category palette, `Icons.login`/`Icons.logout`
mirrored under RTL, zero `EdgeInsets.fromLTRB`/left-right primitives in lib
code, subtle 120ms selection animations (sidebar, modifier options, table
tiles — all finite).

## 3. What to visually test (manual checklist)

Launch `.\_run_dashboard_real.bat`, `.\_run_pos_real.bat`,
`.\_run_kds_real.bat` and check:

1. Arabic RTL first launch on all three; switcher persists after refresh.
2. Dashboard: dark sidebar + light content; active nav pill animates; header
   shows org · branch + Real pill; sign-out icon points *out* in Arabic.
3. Login/signup: brand mark + tagline above the card; filled inputs.
4. Overview: KPI tiles, setup checklist steps with progress bar; refresh.
5. Menu: single title; category/item tiles; modifier editor nesting.
6. Tables: floor grid, status colors (green/amber/blue/red), set-status menu.
7. Devices: POS vs KDS tile identity; status pills green/amber/red.
8. Printers: pills wrap with long Arabic labels; wizard step dots; disabled
   test print explanation.
9. POS: category chips, price-forward cards, modifier sheet selection tint +
   running total, table picker fills, cart, cash keypad + green change-due,
   receipt preview (Arabic titles join correctly).
10. KDS: dark board, colored columns, empty-column placeholders, big ticket
    numbers, paper-white print preview; stale banner if Supabase is stopped.
11. Hebrew + English: nothing overflows or misaligns on the pages above.

## 4. Known remaining design limitations

- **Live KDS tickets have no elapsed-time indicator** — the ticket view
  model carries no timestamp; adding one touches the frozen sync mapper
  (needs its own ticket). The demo board's pill (with age escalation) shows
  the intended design.
- 'New' tickets keep a neutral (grey) status chip/edge while their column is
  info-blue — the chip's tone-per-status map is test-frozen (RF-102 raw
  labels; kds_status_chip_test pins tones).
- KDS status chips show raw wire statuses (`in_preparation`) by design
  (RF-102); localizing them is a deliberate follow-up ticket.
- Copy was frozen this sprint: dead-end gate messages ("Account access
  denied") still lack a "who to contact" line; admin pills show raw wire
  strings (`sync_warning`) — both need synchronized l10n+test tickets.
- Dark-theme contrast (KDS) passed no automated color checks — needs the
  human visual pass; card borders (`outlineVariant`) are subtle in dark M3.
- Typography still uses the system font stack (adding a brand font is a
  dependency decision, gated by AGENTS.md).
- The demo/live KDS boards still differ in one bucketing rule (behavioral,
  out of scope).
- No screenshots in this doc — web builds are run manually; capture list
  below.

## 5. Screenshot checklist (for the owner to capture)

Dashboard: login (ar), shell Overview wide (ar + en), setup checklist,
menu builder + item editor with modifiers, Tables grid, Devices, Printers
list + wizard step 2, Staff. POS: menu + cart (ar), modifier sheet with a
required group, table picker, cash sheet with keypad + change due, order
confirmation, receipt preview. KDS: dark board with tickets in all four
columns (ar), ticket print preview, pairing screen. One Hebrew shot of the
dashboard shell for RTL parity.
