# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-DASHBOARD-VERIFICATION — execution packet: Dashboard and report verification of `method='card'`, TEST isolation and the 001D card audit presentation (local, tests only)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-DASHBOARD-VERIFICATION`, approved by the owner on 2026-10-21
(**D-053** point 10) under the umbrella [BIZBOT-PAYMENTS-ZCREDIT-PILOT-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md).
Backlog row: [IMPLEMENTATION_CHECKLIST](IMPLEMENTATION_CHECKLIST.md) (`001G-DASHBOARD-VERIFICATION`, tests only).
Controlling contract: [API_CONTRACT](API_CONTRACT.md) §4.33 (the `card_attempt.*` audit family: "001G-DASHBOARD-VERIFICATION
… only verifies rendering") and §4.55.8 (TEST mode), with **D-051** point 3 (the `payments` row shape) and **D-056**
point 11 / **D-057** point 8 / **D-058** point 4 (the separate `DASHBOARD-COLLECTED-LABEL-001`). This packet records
no **DECISION**, adds no **OPEN QUESTION** and allocates no ID.

This packet was written and committed (`356708f4`) before any test file (request §1). §3, §4.4, §6 and §7 were then
brought in line with the delta review (§9.7), and §9 records the results.

## 1. Request and boundary

- Command-room authorization of 2026-10-31, "LOCAL DASHBOARD / REPORT VERIFICATION, TESTS ONLY". Its verdict accepts
  001F (journal, UI and recovery) locally with rollout gates, at the accepted correction head
  `bd2817217b1eaabc3e5284e5eaef7c27e4833003` (tree `6db8434f26333a400d607e132f770b65d6e15d7c`; reviewed package
  `095c1c0af90f6b6d6bae9fb0670940498cdbd7e066e8ea80ea19c71e8e48c2c5`). The request is kept outside Git with a SHA-256
  sidecar (`5a1cdc1e958e94f128ad97192c77963e051be40fce3f22fd1c325803958353a2`).
- Owner decisions carried by the verdict: **D4** accepted in its corrected form; **D8** accepted as a mandatory 001H
  rollout rule (§5); **D9** approved as one future ar / he / en safety sentence before the physical TEST run — not part
  of 001G and never widening it. No Codex review is requested.
- Scope: Dashboard and report tests only, with synthetic or fake repository data only. No production Dashboard file,
  no l10n or generated localization, no `packages/l10n`, no SQL or migration, no POS / KDS / Kiosk / Storefront /
  printing / Edge source, no `providerProfile`, no manifest, lockfile, CI or deployment file, no #370 / #371 file and
  no accepted payment source changes. A production defect that blocks a required verification is reported with its
  exact surface and routed to its owning Work ID, never fixed here.
- Not authorized: a push, a PR, a merge, a hosted action, a deployment, a migration, a secret or configuration change,
  a provider request, a terminal or card action, a printer or APK action.
- Branch `test/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-dashboard-verification` in its own worktree, created from the exact
  accepted head `bd281721`; no upstream. The 001F branches, #370 / #371, #314 / #315 and every earlier payment branch,
  commit, package and evidence folder stay as they are (no amend, rebase, reset, deletion or history rewrite). Current
  `origin/main` is recorded only (§2), never merged into this stacked branch.

## 2. Source anchor (preflight 2026-10-31T14:31:47Z, read-only)

| Source | Head | State |
|---|---|---|
| Base: the accepted 001F correction (`fix/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001-recovery-cap-uniqueness`) | `bd2817217b1eaabc3e5284e5eaef7c27e4833003` | tree `6db8434f26333a400d607e132f770b65d6e15d7c`; its worktree clean; no upstream; its package and evidence folder verify (97 OK) |
| 001F (`feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-pos-card-flow`) | `d7ce9990482e57c67e499bca2cf8c3ed07ba253c` | tree `8b5cb04e`; an ancestor of the base; unchanged; its package and evidence folder verify (144 OK) |
| 001D ledger publication (#370, draft) | `54b19ab58ce72a2fa9a43860e31181a08222b254` | tree `2bbbb1f694c9157f77535bec4d5fb16d0397e7ea`; an ancestor of the base; unchanged. Its Dashboard commit `40147318` added the 12 `card_attempt.*` registry entries, the presenter's card family and its ar / he / en titles |
| 001D ledger integration (local) | `ce3c67c81c32993afbfff44146d402959313bf7a` | the same tree `2bbbb1f6` as #370; unchanged |
| 001D server ledger (local, the C2 snapshot) | `75ef9d7455e97fa69a6770a363c61364834e4e97` | tree `b71237c8b253afbc1250aca2393ba41fee3fbbff`; not an ancestor of the base; unchanged |
| D-061 route r2 (#371, draft) | `53d6a6adc38f308b7ed6b0dd62177e6edd5ad5ce` | unchanged |
| 001C correction / 001C / profile candidate / D-064 / W1 / G1 / 001E | `148df092` / `71bfef5b` / `cf1ffacf` / `ca8edb03` / `140be040` / `295cacb6` / `d5456624` | unchanged; their packages verify |
| 001A / 001B / D-061 / D-061 r1 | `c8a883c8` / `e7df3132` / `bfbab91b` / `e246492d` | unchanged |
| #314 / #315 (reserved) | `54346b37b35679c21248a64e40dcb3b0ca894673` / `4e8c81f6bd7249f3a44d1089c6253ad84df7f413` | unchanged; never edited here |
| `origin/main` (`git ls-remote`) | `8ee132d5ef214fd92afc14f0ba2735059a643e77` | recorded only; merge base with the base `d2079820`, 16 commits / 78 files since, 18 of them under `apps/dashboard` (Storefront SEO consent and online-order settings sources and their tests); none is a file of §3 |

- `supabase/functions/pos-card-charge/index.ts` line 19: `providerProfile: null,` (blob `7a3c5c97`), unchanged.
- Between `d2079820` and the base, the only `apps/dashboard` files changed are 001D's
  `lib/src/data/audit_action_registry.dart`, `lib/src/data/audit_log_presentation.dart` and
  `test/card_attempt_activity_log_test.dart`; 001G verifies them and changes none.
- The worktree's packages were resolved with `flutter pub get --offline --enforce-lockfile` (Flutter 3.44.2);
  `pubspec.lock` stayed byte-identical.

## 3. Test-only file allowlist

001G may add or change exactly these paths:

| Path | Purpose |
|---|---|
| `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001G_DASHBOARD_VERIFICATION_EXECUTION.md` | this packet |
| `apps/dashboard/test/zcredit_001g_card_reporting_surfaces_test.dart` | request §3: the eight reporting surfaces |
| `apps/dashboard/test/zcredit_001g_test_isolation_test.dart` | request §4: TEST isolation |
| `apps/dashboard/test/zcredit_001g_card_audit_presentation_test.dart` | request §5: the 12-action audit presentation |
| `apps/dashboard/test/zcredit_001g_collected_label_known_defect_test.dart` | request §6: the known defect, recorded without blessing it (§4.4) |

- Any further file would be a new `apps/dashboard/test/zcredit_001g_*.dart` test or test-only helper, recorded in §9
  with its reason; none was needed. The `zcredit_001g_` prefix keeps these files apart from the unrelated
  `order_edit_001g_*` tests of ORDER-EDIT-001G.
- No existing test file is edited. The request allows a narrowly scoped edit "where required"; none was required.
  `apps/dashboard/test/card_attempt_activity_log_test.dart` belongs to #370; the tests that encode the fallback mirror
  (§4.3) belong to `DASHBOARD-COLLECTED-LABEL-001`.
- Every other path is protected, in particular `apps/dashboard/lib/**`, `apps/dashboard/web/**`,
  `apps/dashboard/pubspec.yaml`, `packages/**` (`packages/l10n`, which holds the Dashboard's l10n, included),
  `supabase/**`, `apps/pos/**`, `apps/kds/**`, `apps/kiosk/**`, `apps/admin/**`, `storefront/**`, `.github/**`,
  `tools/**` and every `pubspec.yaml` / `pubspec.lock`.
- Coordination points, recorded only: #370 is the only open PR that touches `apps/dashboard` files (the three 001D
  files above). Two other worktrees hold uncommitted Dashboard test changes —
  `BIZBOT-DASHBOARD-ONLINE-ORDER-CONTROLS-001-ui` (3) and `BIZBOT-STOREFRONT-SEO-CONSENT-001-dashboard` (6) — none of
  them under a `zcredit_001g_` name.

## 4. Known Dashboard defect — `DASHBOARD-COLLECTED-LABEL-001` (recorded, not fixed)

An approved, separate Work ID (**D-053** point 10, as amended by **D-058** point 4; backlog row in
[IMPLEMENTATION_CHECKLIST](IMPLEMENTATION_CHECKLIST.md)). 001G does not relabel "Cash collected", does not change the
`sales_summary` fallback and writes no passing test that treats either as correct.

### 4.1 The all-tender total is labelled "Cash collected"

- l10n key `dashboardCashCollected`: en "Cash collected" (`packages/l10n/lib/l10n/app_en.arb:1672`), ar
  "النقد المُحصَّل" (`app_ar.arb:716`), he "מזומן שנאסף" (`app_he.arb:716`).
- Used twice in `apps/dashboard/lib/src/dashboard_home_screen.dart`: the Overview Daily summary row
  (lines 1453–1456, `money(report.collectedMinor)`) and each per-currency card of the mixed-currency split
  (lines 3030–3037, Key `currency-split-collected-<CCY>`, `total.collectedMinor`).
- The value is all-tender: `owner_report_range` and `owner_daily_report` sum `amount_minor` over completed, non-deleted
  payments of every method into `collected_minor`, while `cash_minor` is the separate `method = 'cash'` sum. A card,
  Bit or external amount therefore reads under a cash label in those two places only. The per-shift chip already uses
  the tender-neutral `dashboardShiftCollected` ("Collected").

### 4.2 The latent `sales_summary` fallback mirrors gross into cash

- `apps/dashboard/lib/src/data/real_owner_reports_repository.dart`: `_loadFromSalesSummary` (from line 380) sets
  `netSalesMinor`, `collectedMinor` and `cashSalesMinor` to the all-tender `gross_minor` (lines 415, 417, 418);
  `_priorDayComparison` sets `cashSalesMinor: priorGross` (line 465). The comment that justifies it ("cash-only
  payments in this build") has been stale since RF-117 added card, Bit and external.
- It runs only when `owner_report_range` and then `owner_daily_report` are both missing (a non-auth PGRST202 / 404 /
  "could not find the function" error) on the `today` preset, for a caller of manager rank or above. The Overview
  currency guard then hides merged money unless the order count is zero, so on screen it is reachable only on a
  zero-order day with a positive gross (or in tests that override the guard). The `DashboardReport` model carries the
  mirrored figure whenever the path runs.

### 4.3 Existing tests that encode the mirror (unchanged here)

- `apps/dashboard/test/real_owner_reports_repository_test.dart`: the test at line 277 asserts
  `report.collectedMinor` / `report.cashSalesMinor` = 12000 = gross (lines 321–322); the LIVE-UX-001 test at line 427
  asserts `c.cashSalesMinor` = 8000 = prior gross (line 457).
- The `_LimitedRepo` fixtures of `dashboard_home_screen_test.dart` (line 20) and `rf132_visual_fidelity_test.dart`
  (line 51) are `sales_summary`-shaped (gross = net = collected = cash); `report_calculator_test.dart:35` comments
  "cash collected == cash sales", true only for the demo's cash-only data.
- No test asserts the label text "Cash collected" or the `currency-split-collected-*` key.
- These tests belong to `DASHBOARD-COLLECTED-LABEL-001`, which changes them with the fix.

### 4.4 How 001G treats it

- No 001G card test asserts the "Cash collected" row or the mixed-currency split, and every 001G report fixture uses
  the `owner_report_range` path, never the fallback (the TEST-isolation fake server records that `owner_daily_report`
  and `sales_summary` are never called).
- `zcredit_001g_collected_label_known_defect_test.dart` states the correct behaviour in nine checks — K1 (Daily
  summary) and K2 (mixed-currency split), each in en / ar / he: the all-tender total is not under a cash-specific label;
  K3a / K3b: the fallback does not report the all-tender gross as today's or "vs yesterday" cash sales (a refusal of the
  fallback, or no comparison, is accepted as correct); K4: on the fallback no cash-named KPI and no payment-summary
  "Cash sales" row shows the all-tender gross, and an absent KPI must be explained by the report or its error state. The
  checks are skipped by default, so the default suite neither fails on the known defect nor blesses it; run with
  `--dart-define=ZCREDIT_001G_KNOWN_DEFECTS=true`, all nine fail on exactly the defect (§9.2).
- `DASHBOARD-COLLECTED-LABEL-001` removes the `ZCREDIT_001G_KNOWN_DEFECTS` skip gate when it ships, so K1–K4 run by
  default (if it chooses to refuse the fallback, it pins K3's refusal branch to that refusal), or it replaces these
  checks with its own focused tests carrying the same assertions. The test file's header says the same.
- Surfaces the defect does not touch, each verified by §6.1: the per-method rows of the payment summary, the "Cash
  sales" KPI and row and "Last cash payment" on the `owner_report_range` path, the payment mix, the per-method trend,
  the shift card, the Orders history card filter, the order drawer, the receipt preview, the labels and tender colours,
  and the Activity log. Affected: the Daily summary "Cash collected" row and the mixed-currency split rows (label), and
  on the `sales_summary` fallback the "Cash sales" KPI and row, their "vs yesterday" delta and the report model's cash
  figures.
- Remaining LIVE-gate decision (DEPLOYMENT §18.1 step 9; **D-057** point 8, **D-058** point 4): deploy
  `DASHBOARD-COLLECTED-LABEL-001` (the label and the fallback), **or** record the owner's explicit acceptance of the
  all-tender "Cash collected" mislabel and of the `sales_summary` fallback. 001G closes neither.

## 5. Remaining provider and physical gates (held; 001G changes none)

- `providerProfile: null` (§2). No provider, Z-Credit, terminal or card call; no secret, credential record or terminal
  binding.
- **Q-047** (the non-settling TEST facility, sealed evidence) and **Q-049** (provider key formats) stay **Open**: hard
  owner gates before any provider secret, provider call, test-card use or terminal payment action (**D-051** point 7,
  **D-052** point 2, **D-058**). **Q-048** (status lookup semantics), **Q-050** (the delivered terminal) and **Q-052**
  (the card-present receipt) stay as the register records them.
- `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001H-PILOT-OPS` (owner-executed, each step separately approved): deploy with every
  flag off, the sealed **Q-047** / **Q-049** evidence, the TEST secret setup, the terminal binding only through
  `app.set_payment_terminal`, the read-only Card Attempts incident view over `owner_card_attempts`, the physical TEST
  run (DEPLOYMENT §18.4: the facility armed first, an owner-arranged quiet window, PRE / POST compared) and the sealed
  evidence review.
- **D8**, a mandatory 001H rollout rule: no TEST attempt on a customer order; unresolved TEST rows are held and never
  purged; every TEST attempt is final or operator-closed before the quiet window ends; the physical PRE / POST ends with
  zero unresolved unheld TEST rows.
- **D9**: one ar / he / en safety sentence before the physical TEST run, under its own approval (not 001G).
- Production enablement (DEPLOYMENT §18.1 step 9) stays a separate approval: the LIVE credential record and the
  designated device's `live` mapping, the LIVE operator revision with its `max_live_amount_minor`, the accountant's
  confirmation of the receipt flow (**Q-052**), the orphan runbook rehearsed ([RUNBOOKS](RUNBOOKS.md) §8), **Q-048**
  resolved or its interim accepted, `DASHBOARD-COLLECTED-LABEL-001` deployed or the owner's recorded acceptance (§4.4),
  and the LIVE activation gate (**D-057** point 4).
- #370 / #371 stay unmerged drafts; their publication follows **D-061** and needs human approval.

## 6. Verification plan

Data rules: synthetic values only; fake transports and fake repositories only; no `is_test` payment row (no such model
exists); no private provider value — the provider-like values in the tests are invented `MARKER-…` strings that no
provider emits. Every UI test runs in en, ar and he unless a row says otherwise. What a client test proves is kept
apart from what rests on the server: 001G runs no database suite and cites the server basis instead.

### 6.1 Reporting surfaces (request §3) → `zcredit_001g_card_reporting_surfaces_test.dart`

| # | Surface | Client-proven by this file | Server basis (cited; not run by 001G) |
|---|---|---|---|
| R1 | Overview payment summary | through the real `RealOwnerReportsRepository` over a fake `owner_report_range`: the completed card tender is the localized Card row with its count and amount; the "Cash sales" KPI and row and "Last cash payment" carry the cash figure only | `owner_report_range` sums only `p.deleted_at is null and p.status = 'completed'` payments (`supabase/migrations/20260904090000_platform_support_scope_pii_126c.sql:704-705`); `cash_minor` is the `method = 'cash'` sum |
| R2 | Payment mix | the Card segment's label, amount, share, meta line and tender colour (`primaryNavy`, never the cash `accentOrange`) | as R1 (the same `tenders`) |
| R3 | Per-method trend | with no cash in the window the heading names Card and the bars are the card amounts; with cash present the strip stays on cash and never adds card | `owner_sales_series` filters completed, non-deleted payments (`20260903090001_platform_support_sessions_126.sql:1825-1826`); pgTAP `dashboard_owner_analytics_a_owner_sales_series_test.sql:128` (a pending payment excluded from `collected_minor`) |
| R4 | Shift card | the per-shift "Collected" includes card; "Cash sales", expected, counted and variance stay cash-only, and do not move when the card amount changes | per-shift sales filter completed, non-deleted payments (`126c:837-838`); expected, counted and variance are the shift's stored close values |
| R5 | Orders history | demo repository: the card filter lists only the order with a completed card payment (pending, tendered, failed, voided and deleted card orders excluded by the client's completed-only selection); the filter reads Card; real repository: `p_payment = card` on the wire and `payment_method` `card` mapped | `owner_order_history`'s `pay` lateral keeps the latest completed, non-deleted payment and filters `pay.method = p_payment` (`20261009100100_order_edit_001g_dashboard_reads.sql:646-647`); pgTAP `dashboard_owner_analytics_b_comparisons_and_payment_filters_test.sql:231-237` (a pending card is not selected) |
| R6 | Order drawer | the payment row reads Card and the amount (also after a failed card attempt); an order whose card rows are only pending / tendered / failed / voided / deleted shows the unpaid settlement row, never Card | `owner_order_detail` returns non-deleted payments of every status (`…dashboard_reads.sql:941`); the client picks the completed one (`OrderDetail.completedPayment`) |
| R7 | Receipt preview | a "Card" line with the amount and no Paid / Change lines; cash keeps Paid / Change; non-completed card rows print Unpaid | — (pure client builder over the stored detail) |
| R8 | Labels and colours | the four wire tokens map to four distinct localized labels and four distinct colours; Card is never the Cash label or colour; the filter labels follow | — (pure client mappers) |
| X1 | Provider-recorded vs hand-recorded | the same RPC JSON with invented provider, attempt, terminal and credential markers maps to equal report, history and detail models field by field and renders identical text (R1, R2, R5, R6) | **D-051** point 3: a provider-recorded payment is `record_payment`'s ordinary row (`method='card'`, `status='completed'`, tendered = amount, change 0) — pgTAP RR-002 and RR-043 (`bizbot_zcredit_001d_recording_recovery_test.sql:459, 877`) |
| X2 | No marker in models or UI | no marker value reaches a mapped report, history row, order detail, sales series or currency breakdown, or the rendered Overview, Orders list or drawer | the reporting reads project no provider field (§6.2 T4) |
| X3 | Static | none of the 22 injected provider-field spellings (snake and camel case, derived from the markers) occurs in any of the Dashboard's `lib` sources | — |
| X4 | Cash, Bit, external | unchanged labels, amounts and colours whether or not a card tender is in the window; their history filters keep only their own completed order | as R1 / R5 |

- What the client proves about non-completed and deleted rows: R5 (demo), R6 and R7 exercise the client's own
  completed-only selection; a deleted row is modelled as absent, because every money read filters `deleted_at is null`
  on the server. R1–R4 and the real-mode R5 list render aggregates the server already restricted to completed,
  non-deleted payments: their exclusion rests on the SQL above. I found no pgTAP assertion that seeds a non-completed
  or soft-deleted payment into `owner_report_range`'s current window (`rf_report_004_owner_report_range_test.sql`
  seeds none) — a server-side coverage note outside 001G's file scope (§9.8).

### 6.2 TEST isolation (request §4) → `zcredit_001g_test_isolation_test.dart`

| # | Property | Dashboard-side proof | Server-side basis (cited; 001G runs no database suite) |
|---|---|---|---|
| T1 | no completed payment, receipt or revenue | the Dashboard reads money only through the reporting RPCs over `payments` / `orders`; a recording fake server that also offers TEST attempts on private channels is never asked for them, and every total stays the same | TI-47, TI-71, TI-74, TI-75 in `supabase/tests/bizbot_zcredit_001d_test_isolation_test.sql` |
| T2 | no change to payment mix, sales, shift totals or order payment status | differential A/B: the same Dashboard flows with and without TEST attempts render identical text from identical models, and the TEST order stays unpaid | TI-19 (no order, shift or drawer on a TEST row), TI-90 |
| T3 | no tenant Activity-log rows | the Activity log shows only what `owner_audit_events` returns; with TEST attempts present it is unchanged | TI-24, TI-61, TI-62, TI-68, TI-74 |
| T4 | only private ledger / private-event / operator surfaces | a static scan finds no reference in `apps/dashboard/lib` to the card-attempt ledger, `owner_card_attempts`, `card_attempt_context`, private events, provider configuration or attempt classifications; no `test.` / `operator.` / `security.` action is registered | the five private tables are RLS-forced deny and in no publication — pgTAP SA-004, SA-012, SA-015, SA-016 (`bizbot_zcredit_001d_schema_acl_test.sql:426, 501, 515, 518`); `app` is not exposed to the Data API |
| T5 | never a LIVE `approved_unrecorded` incident | the LIVE incident leaves `card_attempt.approved` (success) and `card_attempt.recording_refused` (warning) rows and an unpaid order; a TEST attempt for the same order leaves none of that (the TEST world renders exactly what a LIVE-only render of the same feed does); an out-of-vocabulary `test_*` state token renders raw, never a LIVE state label, while title and tone follow the action | TI-42, TI-98 (`test_<state>`), API_CONTRACT §4.55.8; the LIVE-only tenant audit writers |

The revoked-device carve-out (a TEST identity pushed by a revoked device is recorded as `sync.operation_rejected`,
TI-112 – TI-115) is device evidence, not an attempt fact; T6 shows it renders as a rejected sync operation with no card
title, card field or money.

On a `card_attempt.*` result action the Dashboard cannot tell a TEST-derived row from a LIVE one: title and tone follow
the action, and a TEST row would be byte-identical. Keeping TEST out of the Activity log is server-enforced (every
tenant `card_attempt.*` writer is LIVE-only; TI-24, TI-61, TI-62); 001G proves the client half — the `classification`
is never rendered (A8b) and the Dashboard reads no private channel (T1–T4). See §9.8 (observation O1).

### 6.3 The 12-action audit presentation (request §5) → `zcredit_001g_card_audit_presentation_test.dart`

Widget level, through the real Activity-log path (a fake transport answering `owner_audit_events` →
`RealAuditLogRepository` → the Activity log screen → the detail dialog), for each of the 12 LIVE actions —
`started`, `approved`, `declined`, `unknown`, `released`, `provider_anomaly` (raised, cleared and generic),
`release_requested`, `release_failed`, `recording_refused`, `order_freed`, `recording_resume_requested` (dispatched
and refused) and `denied` — in en, ar and he: the localized title; exactly the action's projected fields; no old value,
free-text reason, provider / credential / terminal reference, merchant key, payload, Resume requester internals or
money outside `.started`; integer money in the row currency; the raw-token fallback for unknown closed tokens; the tone
and icon (approved is the only success, declined neutral, unknown / release_failed / recording_refused warning, the
anomaly danger only while raised); the Denied pill only on `card_attempt.denied`; and for TEST-only tokens: mode `test`
reads Test (never Live), an out-of-vocabulary `test_*` state token renders raw (never a LIVE state label) while title
and tone follow the action, and the owner-read `classification` / `recorded` keys never render (A8b). The registry's
exact `card_attempt.*` set is pinned. The existing presenter tests of #370 stay as they are.

### 6.4 Known defect (request §6) → `zcredit_001g_collected_label_known_defect_test.dart`

As §4.4.

## 7. Mutation and differential checks (request §7)

Each mutation runs in a scratch copy of the branch head (made by `git archive`; the worktree is never touched),
against the 001G test files, and counts as killed only when the run fails and every expected test-name fragment fails:

- Card mapped to Cash (C1–C6): the label mapper, the tender colour, the payment-summary label alone, the report's tender
  mapping, the receipt preview and the history filter token.
- A non-completed payment counted as the completed one (S1).
- A TEST attempt entering revenue, the Activity log or an order's payment status (T1–T3); TEST tokens shown as LIVE
  (T4, T5).
- An unsafe field entering the card audit presentation (U1–U6): a provider reference, the free-text reason, old values,
  a Resume `local_operation_id`, money on a result row, the owner-read `classification`.
- A wrong tone / title / registry / Denied-pill / currency / raw-token mapping (W1–W13).
- A provider marker reaching a mapped model, or a provider field declared on a money model (X1–X3).

## 8. Checks and review

- The new focused tests; the full Dashboard suite; the existing audit / Activity-log, analytics, reporting and reprint
  tests (part of the full suite, listed by name in the evidence).
- `dart format --set-exit-if-changed` and `flutter analyze` over `apps/dashboard`; `dart run tools/check_l10n.dart`
  (structural, no regeneration); the no-float-money, secrets and hardcoded-string guards; `git diff --check`.
- One focused fresh-context Claude delta review; only test and evidence defects are fixed under this Work ID.

## 9. Results

### 9.1 Commits and scope

- On the base `bd281721` (oldest first): `356708f4` this packet (before any test); `28927471` the reporting surfaces;
  `437c5a7e` TEST isolation; `dbeed7a2` the audit presentation; `dd54f824` the known defect; `772949fb` the delta
  review's test fixes; then the commit that records these results (docs only). Every commit names the Work ID.
- Changed paths: exactly the five of §3; no existing test file; no production, l10n, SQL, POS, Edge, manifest,
  lockfile or CI path. The review package's `IDENTITIES.txt` and `CHANGESET.txt` carry the exact head, tree, parent and
  per-path blob hashes, and its builder asserts the unchanged files and branches.
- `providerProfile: null` at the head (`index.ts` blob `7a3c5c97`, unchanged).

### 9.2 Validation (evidence `logs/CHECKS_<head>.txt`)

| Check | `dd54f824` (first head) | `772949fb` (test head) |
|---|---|---|
| `git diff --check` (branch, worktree, index) | no whitespace errors | no whitespace errors |
| `dart format --output=none --set-exit-if-changed apps/dashboard` | 324 files, 0 changed | 324 files, 0 changed |
| `flutter analyze --no-pub` (apps/dashboard) | no issues | no issues |
| `dart run tools/check_l10n.dart` (no regeneration; porcelain 0 before and after) | OK | OK |
| hardcoded-string / no-float-money / secrets guards | OK / OK / OK | OK / OK / OK |
| focused: the four 001G files | 120 passed, 8 skipped | 124 passed, 9 skipped |
| known defect, run with `--dart-define=ZCREDIT_001G_KNOWN_DEFECTS=true` | 8 of 8 fail on the defect | 9 of 9 fail on the defect |
| whole Dashboard suite (`flutter test --no-pub`) | 2,773 passed, 24 skipped | 2,777 passed, 25 skipped |
| of it: existing audit / Activity-log (13 files) | 145 passed | 145 passed |
| of it: analytics / reporting (18 files) | 339 passed | 339 passed |
| of it: orders / reprint (6 files) | 61 passed | 61 passed |

- The skips are the 16 pre-existing opt-in tests (dart-define gated) plus the known-defect checks.
- The known-defect run at `772949fb` fails exactly on: "Cash collected" / "النقد المُحصَّل" / "מזומן שנאסף" as the
  Daily summary and split label (K1, K2 × 3); `cashSalesMinor` 12000 (K3a) and the "vs yesterday" `cashSalesMinor` 8000
  (K3b); the Cash sales KPI `₪120.00` (K4). The JSON reporter records the seven widget tests as `error` and the two
  plain tests as `failure`; each is the expectation mismatch shown in the log.
- Test counts per matrix ID at `772949fb`: R1 3, R2 3, R3 6, R4 3, R5 7, R6 3, R7 3, R8 7, X1 9, X2 5, X3 1, X4 6;
  T1/T2 13, T3 3, T4 3, T5 12, T6 6; A1–A8, A8b and A10 3 each, A9 1; K 9 (skipped by default).

### 9.3 Reporting-surface matrix (request §3)

Every row of §6.1 passes in en, ar and he at `772949fb` (R1–R8, X1–X4: 56 tests). The client / server split of §6.1
stands: R5 (demo), R6 and R7 prove the client's completed-only selection; R1–R4 and the real-wire R5 list prove the
rendering of server aggregates whose completed-only, non-deleted restriction is cited, not run.

### 9.4 TEST-isolation matrix (request §4)

Every row of §6.2 passes in en, ar and he at `772949fb` (T1–T6: 37 tests). The calls the flows make are exactly
`owner_report_range`, `owner_report_currency_breakdown`, `owner_sales_series`, `owner_top_items`, `owner_order_edits`,
`owner_order_history`, `owner_order_detail`, `owner_audit_events`, `list_org_structure` and `list_staff`; no private
channel is ever called in either world, and `owner_daily_report` / `sales_summary` never.

### 9.5 The 12-action audit-presentation matrix (request §5)

Every row passes in en, ar and he at `772949fb` (A1–A10 and A8b: 31 tests). Titles are the
`activityLogTitleCardAttempt*` getters (en shown); fields are the projected keys' labels, in projection order.

| Action (variant) | Title (en) | Projected fields | Tone / icon | Denied pill |
|---|---|---|---|---|
| `card_attempt.started` | Card payment started at the terminal | Card payment state, Payment mode, Amount (row currency), Currency | info / `credit_card_outlined` | no |
| `card_attempt.approved` | Card payment approved by the provider | Card payment state, Release status, Provider anomaly, Release requested | **success** / `credit_card_outlined` | no |
| `card_attempt.declined` | Card payment declined by the provider | as approved | neutral / `credit_card_off_outlined` | no |
| `card_attempt.unknown` | Card payment result unknown | as approved | warning / `help_outline` | no |
| `card_attempt.released` | Card payment request released at the terminal | as approved | info / `credit_card_outlined` | no |
| `card_attempt.provider_anomaly` raised (`unknown` / `released`) | Card payment flagged: a charge may exist | as approved | **danger** / `report_problem_outlined` | no |
| `card_attempt.provider_anomaly` cleared (`approved` / `declined`) | Card payment flag cleared by the provider result | as approved | info / `credit_card_outlined` | no |
| `card_attempt.provider_anomaly` generic (other state) | Card payment provider anomaly | as approved | warning / `report_problem_outlined` | no |
| `card_attempt.release_requested` | Card payment release requested | Card payment state | info / `credit_card_outlined` | no |
| `card_attempt.release_failed` | Card payment release failed | Card payment state | warning / `report_problem_outlined` | no |
| `card_attempt.recording_refused` | Approved card payment could not be recorded | Recording refusal | warning / `report_problem_outlined` | no |
| `card_attempt.order_freed` | Order unlocked after a card payment check | Card payment state, Confirmed via | warning / `lock_open_outlined` | no |
| `card_attempt.recording_resume_requested` dispatched | Card payment recording retry requested | Card payment state, Previous refusal (Release status for `release_failed`), Earlier retries, Retry result | info / `replay_outlined` | no |
| `card_attempt.recording_resume_requested` refused | Card payment recording retry requested | as dispatched, plus Reason | warning / `replay_outlined` | no |
| `card_attempt.denied` | Card payment action denied | Reason | warning / `block_outlined` | **yes** |

- Across all variants and locales: no old → new arrow, no Reason row from the free-text reason, no hostile key (19
  invented provider / credential / terminal / merchant / requester keys, a nested payload map and a Resume history
  list), no money or currency on any non-`.started` row; `.started` money in the row's ISO currency (USD over an ILS
  page), the page currency when the row has none, and no Amount row for a non-integer amount; every unknown closed
  token renders verbatim; an unregistered `card_attempt.mystery` gets the category title, no rows and the generic note
  (A10); the registry holds exactly these 12 `card_attempt.*` keys, all `payments` with a title, and no `test.` /
  `operator.` / `security.` key (A9).

### 9.6 Mutations (request §7; evidence `logs/MUTATIONS_<head>.txt`)

| Round | Head | Tool | Result |
|---|---|---|---|
| 1 | `dd54f824` | `tools/mutate_001g_round1.py` (the definitions as run) | 31 of 31 killed; the three suites pass unmutated before and after |
| 2 | `772949fb` | `tools/mutate_001g.py` (round 1 plus U5, U6 and X3) | 34 of 34 killed; the three suites pass unmutated before and after |

### 9.7 Delta review and dispositions

One focused fresh-context Claude review of `bd281721..dd54f824`, then one skeptic per finding (evidence
`review/`). Seven findings; all fixed under this Work ID in tests or this packet, none needed a production change.

| # | Severity | Finding | Verdict | Disposition |
|---|---|---|---|---|
| F1 | major | the TEST-token cases used a state token the server cannot write, and the text claimed more than they prove | confirmed | the comments and §6.2 / §6.3 now say what is proven; A8 also pins that title and tone follow the action; new A8b proves the owner-read `classification` / `recorded` never render; T5 pins the approved title and success tone for a TEST token (`772949fb`); observation O1 (§9.8) |
| F2 | major | §6.1 presented server-enforced exclusions as client-proven | confirmed | §6.1 now separates client proof from the cited server basis, with the SQL lines and pgTAP IDs, and records the coverage note |
| F3 | minor | K3 / K4 could pass vacuously once the fix ships, and no one was told to lift the skip gate | partly | K3 split into K3a / K3b; K4 fails on an unexplained absence and covers any cash-named KPI and the payment-summary row; the hand-off is in §4.4 and the file header |
| F4 | minor | X3 scanned 12 spellings in 12 files; series and currency-breakdown models unmarked | confirmed | X3 scans every `lib` file for 22 derived spellings; a new X2 test covers the sales series and the currency breakdown through the real repositories |
| F5 | minor | §9 was a placeholder and §4.4 / §6 were in the future tense | partly | this section; §4.4 and §6 record facts |
| F6 | nit | no 001G fixture put money on a non-`.started` card row | confirmed | A3 adds it to every non-`.started` hostile row and asserts no Amount / Currency row; mutation U5 |
| F7 | nit | the TEST-world Activity-log check forbade any money on screen, LIVE rows included | confirmed | it now compares with a LIVE-only render of the same feed |

### 9.8 Known failures and observations, routed

- `DASHBOARD-COLLECTED-LABEL-001` (§4): the nine K checks fail on exactly the defect; the existing tests of §4.3 encode
  the fallback mirror and stay for that Work ID. LIVE-gate decision open (§4.4).
- O1, route to the 001D owner (#370), owner decision only: on a `card_attempt.*` result action the client cannot tell a
  TEST-derived row from a LIVE one (title and tone follow the action in `audit_log_presentation.dart` `_title` /
  `_cardToneIcon`). Under the accepted contract no such row exists (LIVE-only writers; TI-24 / TI-61 / TI-62). A client
  guard could not catch a regressed server gate, because the row would be byte-identical. Not a 001G defect.
- O2, route to the 001D owner, hardening only: a non-card action (an unregistered `test.*` or a `sync.*` row) takes the
  presenter's generic path, which renders allowlisted keys such as `amount_minor` as money. Today only the server keeps
  such rows money-free (private events never reach `audit_events`; `app.audit_safe_detail` projects nothing for
  `test.*` / `sync.*`; the `sync.operation_rejected` writer stores no amount). T5 / T6 use the real payload shapes.
- O3, route to the 001D owner, latent: `_cardFieldKinds` labels a `denied_reason` of `permission_denied` with the card
  permission label on every card action (`audit_log_presentation.dart:286`), while the 001D packet §15.4a and
  `app_en.arb:4214` scope that label to `card_attempt.denied`; unreachable today (the Resume guard never writes
  `permission_denied`), so 001G pins nothing about it.
- O4, server-test coverage (outside 001G's file scope): no pgTAP assertion seeds a non-completed or soft-deleted
  payment into `owner_report_range`'s current window (§6.1); the SQL filter is cited.
- Seen while reading, not asserted by any 001G test and outside its scope (for the owners of those surfaces): the
  payment summary renders opening float / expected / counted / variance rows as `₪0.00` when the report carries no
  shift data (`dashboard_home_screen.dart` 1495–1517, reachable on the fallback); the receipt preview prints "Unpaid" for
  a zero-total order whose drawer and history say "No charge" (`order_preview_builders.dart` 148–150); `loadReport`
  ignores a committed custom window when `owner_report_range` is missing (`real_owner_reports_repository.dart` 109–115).

### 9.9 Not validated

- No database suite: every server-side statement in §6 is cited from the migrations and pgTAP sources, not run.
- No hosted read, device, browser or web build: the widget tests run on the Dart VM at wide test surfaces (about 1400
  logical pixels); narrow layouts and the web build (where an integral number also satisfies `is int`) are not covered.
- No push, PR, merge, hosted action, deployment, migration, secret or configuration change, provider request, terminal
  or card action, printer or APK action.

### 9.10 Disclosures

- The three larger test files were drafted, and later corrected, by agents in scratch copies of the branch head (made
  with `git archive`); each ran only its own file there with `flutter test --no-pub`. The files were then reviewed,
  copied into the worktree and committed; nothing else ran in the worktree but the recorded checks.
- `git init` was run by mistake inside one first-round scratch copy (the reporting author's, outside the
  repository; a stray command meant for all three ran only there); it touched neither the worktree nor the
  repository.
- The TEST rows of the isolation fake deliberately exceed the real TEST-shape CHECK (they carry an order id, an amount
  equal to the order's total and provider markers) so that any leak would be visible.
- `tools/mutate_001g_round1.py` was rebuilt from the round-2 tool after round 1 ran; its definitions equal what ran,
  and only its header comment differs.
