# RestoFlow — Design Polish Audit (sprint scope)

> Part A of the UI/UX Design Polish Sprint (2026-07-03, branch
> `feature/product-rescue-visible-mvp`). Design/UX only: no backend, RLS, RPC,
> auth/session, order, printer, or business-rule changes. Companion final
> review: `DESIGN_POLISH_FINAL_REVIEW.md` (written at the end of the sprint).

## 1. Where the product stands visually

The app is functionally ~90% demo-ready but looks like a careful prototype,
not a product. The good news from the audit: styling debt is unusually low —
**zero** `Colors.*` literals, **zero** raw `fontSize:`, **zero** literal corner
radii; ~780 token references (`RestoflowSpacing`/`Radii`/`Tone`) already flow
through `packages/design_system`. The problems are higher-level:

- **No real semantic colors.** `RestoflowTone.success/warning` resolve to M3
  roles derived from the green seed, so "success" and "warning" are two barely
  distinguishable green-beige pastels. Status at a glance (KDS columns, device
  states, sync states) does not read green/amber/red anywhere.
- **No visual identity.** Every app is the same light green-tinted M3 default:
  stock `NavigationRail`, stock `AppBar`, no brand mark, no dark sidebar, no
  warm accent. The login screen — the first thing a restaurant owner sees — is
  a bare form with no branding at all.
- **Prototype-grade key screens.** The auth-gate states are bare icon+text;
  the membership picker is a `label: value` dump; the KDS's four column
  headers are four identical brand-green bars; the PIN screen is a lone OS
  text field instead of a touch keypad; POS touch targets (steppers, chips,
  option rows) sit under the 48dp minimum.
- **Fragmented chrome.** Three pill implementations (`RestoflowStatusPill`,
  `AdminPill`, `MenuPill`), three demo-banner styles, five copies of the same
  64px-icon-circle empty state, a byte-identical `LanguageSelector` copied
  into all four apps, two parallel KDS board/card stacks, seven copies of the
  spinner-in-button pattern, and per-file breakpoint constants (900 in six
  files, 820 in POS).
- **Empty/loading/error states exist everywhere** (honest, l10n'd — good) but
  are visually minimal and inconsistent; loading is always a bare spinner.

## 2. Design principles chosen

1. **Arabic-first, RTL-first.** The codebase is already directional-primitive
   clean (audit found zero `EdgeInsets.only(left:)`-class hazards); the sprint
   keeps that discipline in every new component and converts the 16 remaining
   symmetric `EdgeInsets.fromLTRB` sites to `EdgeInsetsDirectional`.
2. **One semantic status language.** True green (success) / amber (warning) /
   red (danger) / blue (info) introduced **once**, in the design system, as a
   `ThemeExtension` consumed by the existing `RestoflowTone` seam (25 files
   inherit it with no per-screen change). No random colors per screen.
3. **Soft dark sidebar, clean light content** for the dashboard; a **dark,
   high-contrast board** for the KDS; POS stays light and touch-first.
4. **Warm restaurant accent** (terracotta/amber family) used sparingly for
   brand moments (login hero, totals, active nav) — never for statuses.
5. **Touch-first operations**: ≥48dp targets on POS/KDS actions, a real
   on-screen numeric keypad for PIN and cash, larger read-at-distance type on
   kitchen tickets.
6. **Intentional states**: one shared empty/loading/error/state component with
   tone-aware icons, explanation text, and a recovery action — replacing the
   five hand-rolled variants.
7. **No fake anything**: every honesty guard (demo banners, "configuration
   only" printer notices, disabled test print, real/demo pills) is restyled,
   never removed or weakened.
8. **The test corpus is a frozen API.** ~118 `Key(...)` strings, the byIcon
   contracts (`Icons.add_shopping_cart` alone gates 10+ POS tests), widget
   types used with `find.byType`, l10n copy asserted verbatim in en/ar/he,
   breakpoint safe-bands (POS two-pane ≤1100, dashboard wide ≤1200, KDS wide
   in 720–1400), and "denser is safe, taller is risky" viewport limits are
   all honored; where a test pins an old visual detail, the test is updated
   deliberately in the same commit.

## 3. What will be improved (by part)

**B — design system** (the foundation, done first):
- Semantic color extension (success/warning/danger/info + warm accent +
  sidebar palette), light and dark presets; `RestoflowTone` resolves through
  it with a safe fallback for themeless test harnesses.
- Token growth: `xxs` spacing, icon-size scale, `xl` radius, breakpoints,
  standard panel widths, motion durations.
- Theme coverage for the ~15 widget families currently on Flutter defaults:
  inputs, dialogs, sheets, navigation rail/bar, list tiles, snackbars,
  segmented buttons, outlined/elevated/icon buttons, progress, popup menus.
- Typography scale with baked-in weights (removing 71 scattered
  `fontWeight:` copyWith calls over the sprint).
- New components: page header, state view (empty/loading/error/denied),
  static skeleton blocks, step/checklist tiles, numeric keypad, brand mark,
  LTR code block, button-style helpers (big/danger/success), shared language
  selector, demo banner recipe.

**C — dashboard**: dark sidebar + branded header (org/branch context, real
/demo pill, sign-out); login/signup/onboarding get a brand hero; overview
cards and setup checklist restyled on the new components; menu builder loses
its duplicated title and gets cleaner modifier editing; tables page reads as
a floor manager (status-colored tiles); devices page explains POS vs KDS with
icon cards; printers wizard softened (pill overflow fixed); staff page
simplified; honest Users/Settings states restyled.

**D — POS**: cashier-grade hierarchy (bigger cart, stronger totals, clear
send/pay), ≥48dp targets everywhere, keypad-driven cash sheet with a large
change-due figure, polished modifier sheet (obvious required groups, visible
running total), table picker with clearer status coding, warm category
palette from tokens, add-to-cart feedback, readable shift bar.

**E — KDS**: dark high-contrast theme; semantically colored column headers
(New=info, Preparing=amber, Ready=green, Cleared=muted) with empty-column
placeholders; bigger ticket numbers/quantities; 48dp action buttons; elapsed
pill kept on the demo card with age-based tone escalation (the live ticket
model carries no timestamp — adding one is sync-layer work, out of scope);
language selector restored on the live board; visible stale-data pill.

**F — auth/pairing**: branded pairing screen with a formatted code field;
staff picker as large touch tiles with initials avatars and role pills; PIN
keypad; the "No staff PINs yet" guidance on the shared checklist component;
tone-aware gate states (denied/error no longer render brand-green icons);
membership picker cards with monogram + role pill; help pages on one shared
layout with the LTR code block.

**G — RTL/language pass**: `fromLTRB` → `fromSTEB` sweep, manual mirroring
for the two non-auto-mirrored directional icons (login/logout), removal of
`letterSpacing` from receipt titles (it breaks Arabic glyph joining), bidi
review of composed strings, and a re-run of the five RTL suites.

**H — consistency cleanup**: single language selector, one pill family, one
demo banner, one state view, shared spinner-in-button, category hexes →
named palette, `SizedBox(height: 2)` → `xxs` token, the sole raw `TextStyle`
fixed, per-file breakpoints → shared tokens (values unchanged).

**I — subtle motion (optional)**: 120–200ms implicit transitions on selected
states, hover/pressed feedback, KDS ticket movement feedback. Finite
animations only (several test harnesses `pumpAndSettle`); no shimmer loops.

## 4. Key components to improve or create

| Component | Today | Sprint |
|---|---|---|
| Tone/status colors | seed-derived M3 roles | true semantic extension, light+dark |
| Status pill | 3 implementations | one (`RestoflowStatusPill`) |
| Page header | 2 near-copies (admin/menu) | shared `RestoflowPageHeader` |
| Empty/error/loading | 5+ hand-rolled variants | shared `RestoflowStateView` (+ static skeletons) |
| Checklist/steps | hand-rolled (setup center, PIN steps) | shared step tiles |
| Numeric entry | OS keyboard text fields | shared touch keypad (PIN, cash) |
| Demo banner | 3 styles | one notice-banner recipe |
| Language selector | 4 identical copies | one shared widget |
| Buttons | partial theme | full variant set incl. big/danger/success |
| Navigation | stock light rail/bar | dark sidebar (dashboard), themed bar |

## 5. Pages touched

Dashboard: login, signup, onboarding, membership picker, shell (sidebar,
header), overview + setup checklist, menu (incl. modifier editor), tables,
devices, printers (list + wizard), staff, users (honest state), settings
(read-only state), unconfigured help page. POS: pairing, PIN, menu grid +
cards + category chips, modifier sheet, cart, order setup + table picker,
confirmation + sync states, cash sheet, receipt previews, shift bar. KDS:
pairing, PIN, both boards (live + demo), ticket cards, print preview, state
messages. Admin: overview banner/pills/states brought onto the same
semantics (lower priority). Shared: all feature_auth screens, feature_admin
and feature_menu chrome, design_system everything.

## 6. Intentionally NOT changed

- **Any behavior**: sync, orders, payments, PIN/session logic, pairing,
  printer honesty guards, RLS/RPC/migrations — untouched.
- **All l10n copy that tests assert** (banner sentences, wizard step titles,
  checklist copy, wrong-PIN text, raw KDS status labels per RF-102, admin
  wire-status strings). New strings are added via new l10n keys in all three
  ARBs; existing strings are not reworded in this sprint.
- **The test-contract surface**: every `Key`, byIcon identity (incl.
  `Icons.add_shopping_cart`, table-status icons, `Icons.delete_outline`),
  byType-found widget classes (`DevicePairingScreen`, `PinLoginScreen`,
  `RestoflowStatusPill`, POS menu tiles staying `Card`, …), the exactly-4
  setup metrics with `n/m` values, the two disabled "Test print" buttons,
  and the `'<name> ×<qty>'` KDS line format.
- **Breakpoint behavior at test viewports** (values may move to shared
  tokens but resolve identically at 720/820/880/900/1100–1400 px).
- **The live KDS ticket model** (no timestamp/money fields added — the
  elapsed indicator on the live board needs a sync-layer field and is
  deferred with a note in the final review doc).
- **Dependencies**: no new packages (no google_fonts etc. — AGENTS.md gates
  dependency changes); typography improves via weights/sizes and a
  `fontFamilyFallback` list only.
- The deprecated legacy demo-gate path and print-builder output strings
  (pinned by golden-structure tests) are restyled nowhere.
