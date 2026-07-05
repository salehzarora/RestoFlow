# Design Implementation Notes — Phase 1 (DESIGN-001)

> Status: DESIGN-001 implemented on `design/DESIGN-001-kds-pos-polish` (no push/PR/merge — human-gated).
> Scope: apply the approved **Design Language v2** direction to the shipped Flutter apps, KDS + POS critical
> polish first. Design/UI only — **no backend, RLS/RPC, migration, money-logic, or auth change**.
> Ticket-ID note: `DESIGN-xxx` is the owner-directed ID for this phase; it is not an `RF-<n>` Jira ticket
> (Jira is Codex-controlled and was not touched). The shared-package edit below is explicitly flagged per
> the CLAUDE.md shared-package rule.

## 1. Design direction applied

From the approved audit/mockups ("calm counter, loud status"): keep the shipped identity (seed green
`#1B7A52`, semantic green/amber/red/blue tones, flat outlined cards, Arabic-default RTL) and finish its
application — statuses speak ONE vocabulary everywhere, failures are visible, and the kitchen gets its
urgency signal. Owners stay authoritative: tokens/components in `packages/design_system`
([ARCHITECTURE.md](ARCHITECTURE.md) §3); this file only records what phase 1 changed.

### design_system additions (additive only)

| Addition | What it is |
|---|---|
| `RestoflowShadows` (tokens.dart) | 4 soft elevation tiers (xs/sm/md/lg), green-black ink `#10201A` at low alpha. Tokens only — nothing consumes them implicitly yet. |
| `RestoflowUrgency` (tone.dart) | The shared elapsed-time thresholds (10 min → warning, 20 min → danger) hoisted from the demo kitchen card so demo + live boards can never disagree. Maps onto the EXISTING five `RestoflowTone`s (frozen 5-value contract). |

### KDS (apps/kds + shared packages/feature_kitchen)

* **Elapsed/urgency signal on the LIVE board** — the audit's top finding (a 2-minute and a 40-minute
  ticket looked identical):
  * `KdsTicketView.submittedAt` (nullable, display-only) + `KdsTicketMapper` pluck of `orders.created_at`
    (stable server insert time; `client_created_at` fallback; unparseable → null, **never a fabricated
    age**). **Shared-package change, flagged**: additive nullable field in `packages/feature_kitchen`;
    no migration/RPC/transport change — the timestamp was already in the `sync_pull` payload and was
    being dropped client-side.
  * `KdsTicketCard` renders a `Key('elapsed-<ticketId>')` pill (same anatomy as the demo card) toned by
    `RestoflowUrgency`. Computed at build from ONE board-level clock read — **deliberately no timer**
    (13 of 22 KDS test files `pumpAndSettle`; the live board rebuilds on every ~5 s sync poll, which
    refreshes elapsed for free). Negative skew clamps to 0.
* **Status vocabulary reconciled where safe**: `kdsStatusTone(newTicket)` neutral → **info** so a new
  card matches its blue "New" column header (approved mapping: blue = new). Chip text stays the raw
  `canonicalName` (pinned test contract, deferred below).
* **Print failures look like failures**: `KdsTicketPrintStatus.isError` (true for failed / bridge
  unavailable / not configured) renders the status line in the danger tone, w600, instead of the same
  muted grey as success.
* **Cleared work dims** (demo AND live cards): bumped tickets render at 62 % opacity; cancelled keeps
  full contrast (its danger accent IS the signal).
* **Big-TV layout** (demo AND live boards): when all four columns fit at their 340 px minimum, they now
  GROW to fill the width (e.g. 1920 px kitchen TVs) instead of clustering in a start-aligned horizontal
  scroller. At every tested viewport (≤1400 px) behavior is pixel-identical to before
  (4 × (340 + 12) + 12 = 1420 px is the fill threshold).

### POS (apps/pos)

* **Silent payment failure fixed** (audit's top POS finding): `PaymentException` now pins a danger
  `RestoflowNoticeBanner` (`Key('payment-failed-banner')`, new l10n `posPaymentFailedTitle/Body`) inside
  the sheet; the sheet stays open, Confirm doubles as retry and shows an in-flight spinner; any new
  input (keypad, quick-cash, tender switch, or hardware-keyboard typing) clears the stale banner. Copy
  is honest: nothing was recorded, order stays unpaid. The sheet body is scrollable so the failure
  state — its tallest configuration — fits short POS displays (1366×768) without clipping the retry;
  the success `pop()` is mounted-guarded against mid-flight dismissal.
* **Cart line hierarchy**: `× qty · unit price` (new l10n `posCartQtyUnit`, tabular figures) sits directly
  under the item name as its own Text (the name stays an exact-match standalone string — test contract);
  the buried bottom unit-price line is gone; the line total uses `minWidth: 76` instead of a clipping
  fixed-width box.
* **One sync vocabulary**: the app-bar outbox indicator now speaks `RestoflowTone`
  (danger/warning/info/success) instead of raw `colorScheme.error/primary/tertiary`. Labels, keys, and
  the single-spinner contract unchanged.
* **Touch floor**: modifier-sheet quantity steppers raised 40 → 44 px (the product's minimum).

### l10n (ar/he/en, add-only)

`posPaymentFailedTitle`, `posPaymentFailedBody`, `posCartQtyUnit` — all three locales + committed
gen-l10n output regenerated (`tools/check_l10n.dart` green). No existing value changed (the Playwright
smoke suite is Arabic-value-keyed; policy is add-only).

## 2. Intentionally NOT implemented (and why)

| Deferred | Reason |
|---|---|
| Localized KDS status-chip labels | Raw `canonicalName` chip text is pinned in 4+ test files and localized labels collide with the localized column headers (`find.text('New')` ambiguity); needs a deliberate contract redesign. |
| Modifier sheet single-total (remove the duplicated total row) | The twice-rendered total (summary row + Add-button label) is a frozen `findsNWidgets(2)` contract across ~6 `modifier_flow_test` cases. |
| Demo/live KDS board-stack unification | The two stacks bucket `acknowledged` into different columns and both bucketings are load-bearing in tests; unification is real engineering, not polish. |
| Live "updated hh:mm:ss" health chip on the KDS app bar | Needs `KdsSyncState.serverTs` threaded through `KdsViewState` (another shared-package change); the negative stale/offline banners already exist. |
| A ticking elapsed timer | `Timer.periodic` hangs the `pumpAndSettle` corpus and leaks pending timers in plain-pump tests; the poll-driven rebuild refresh is the repo-safe pattern. A test-safe optional ticker is a DESIGN-002 candidate. |
| Send-order failure banner in the cart (replacing the SnackBar) | `posSubmitFailed` SnackBar timing is a pinned test contract; payment failure was the silent (worse) path and is fixed. |
| Dashboard/Admin polish, shadows applied product-wide, cart-line edit, send+pay-cash split action | Out of DESIGN-001 scope per the phase definition. |

## 3. Recommended DESIGN-002 scope

1. **Admin MFA trust polish** (QR render, correct banner copy — the purpose-built `adminMfaRequired*`
   ARB strings exist unused; "signed in as" surfacing; **LTR-force the `otpauth://` URI** — an RTL bug
   candidate found in audit).
2. **KDS status-label localization** with a deliberate test-contract migration (descendant-scoped
   finders), plus the live health chip (`serverTs` threading).
3. **Dashboard Overview v2** (rename, 4 KPI + deltas, sales-by-hour chart, meters, setup-ring card) and
   the entity-card/section-card/pill/page-header consolidation into `design_system`.
4. **POS flow ergonomics**: cart-line edit (reopen modifier sheet pre-filled), send+pay-cash split
   action, skeleton loading states, `RestoflowShadows` adoption on light surfaces.
5. Optional test-safe elapsed ticker (injectable `Ticker`/interval, disabled by default in tests).

## 4. Manual validation checklist (demo mode, no backend needed)

- [ ] `cd apps/kds && flutter run -d chrome` → demo board: elapsed pills tick up across the seeded
      2/4/9/13/16-minute tickets; ≥10 min amber, ≥20 min red; "new" card edge + chip are blue like the
      column header; drive a ticket to Complete → its card in "Cleared" is dimmed.
- [ ] Wide window (≥1440 px): columns fill the width evenly; ~1000–1400 px: horizontal scroll as before;
      narrow: stacked sections.
- [ ] Arabic (default) + Hebrew: board mirrors, elapsed pill sits at the header's reading end, no overflow.
- [ ] `cd apps/pos && flutter run -d chrome` → add item ×2: cart line shows name, then `× 2 · ₪42.00`,
      modifiers/note lines unchanged, bold end-aligned total.
- [ ] Payment sheet: enter cash → change-due goes green; (failure needs real mode or a dev fake — covered
      by widget tests); Confirm shows a spinner while in flight.
- [ ] Modifier sheet: −/+ steppers comfortably tappable (44 px); running total row + Add-button total.
- [ ] No money anywhere on any KDS surface (spot-check with elapsed pills visible).

## 5. Validation commands run

See the DESIGN-001 final report (branch summary): full suite = `dart format --set-exit-if-changed`,
`dart analyze apps packages`, per-app/per-package `flutter test` (dashboard/pos/kds/admin +
design_system/l10n/feature_kitchen/feature_auth), `dart run tools/check_l10n.dart`, and the three Git
Bash guards (`check_secrets.sh`, `check_no_hardcoded_strings.sh`, `check_no_float_money.sh`), per
[LOCAL_RUNBOOK.md](LOCAL_RUNBOOK.md) §9.
