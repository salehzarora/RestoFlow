# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-SERVER-FILTER-COVERAGE-001 — execution packet: pgTAP coverage of the owner report's completed / non-deleted payment filter (local, test only)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-SERVER-FILTER-COVERAGE-001`, a test-only follow-up of
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-DASHBOARD-VERIFICATION](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001G_DASHBOARD_VERIFICATION_EXECUTION.md)
(its §9.8 observation O4). Controlling contract: `app.owner_report_range` as last defined in
`supabase/migrations/20260904090000_platform_support_scope_pii_126c.sql` and its public wrapper in
`supabase/migrations/20260812090000_dashboard_owner_analytics_range_top_items.sql`; settlement by
`app.order_is_fully_settled` (`supabase/migrations/20260714090000_order_auto_completion_001_served_paid.sql`). This
packet records no **DECISION**, adds no **OPEN QUESTION** and allocates no ID.

This packet was written and committed (`5a269ed2`) before the test file. §4, §5.1–§5.4 and §6 were then updated with
the observed fixture role, the tendered cash row P11, the review's corrections (among them the deleted completed cash
row P12), the corrections of a read-only check of this packet's draft and the validation as run (§8.1, §8.7), and §8
records the results.

## 1. Request and boundary

- Command-room authorization of 2026-11-01, "OWNER REPORT CARD FILTER PGTAP COVERAGE". Verdict
  `ACCEPT_LOCAL_001G_WITH_EXPLICIT_DB_FILTER_AND_LIVE_LABEL_GATES`: 001G is accepted at head
  `b1586d6f09f92518937ab65cf8ed425d39e42cf6` (tree `d4f84ff6a63bc258ce51526d3210115b95694781`; reviewed package
  `4b07f054c1e952fbf1f011b27a1ea57dd3ac55f85f50167236a75c6bb86b6395`) and needs no correction. The request is kept
  outside Git with a SHA-256 sidecar (`8d69ec9da2309185434ed2f65f1ea06f53fb6f282c0442db45a808a802bcfa58`).
- The gap it closes: `owner_report_range` filters `p.deleted_at is null and p.status = 'completed'`, but no focused
  pgTAP test seeded every excluded card status and a soft-deleted completed card inside the current report window.
- Scope: one new pgTAP file `supabase/tests/bizbot_zcredit_001g_owner_report_filter_coverage_test.sql` and this packet;
  test and evidence tooling stays outside Git. No migration or production SQL, no Dashboard production or test file,
  no POS, Edge, l10n, `config.toml` or CI change, no #370 / #371 file, no `providerProfile` change. No Codex review.
- Not authorized: a push, a PR, a merge, a hosted action, a deployment, a migration application to any non-disposable
  database, a secret or configuration change, a provider request, a terminal or card action, a printer or APK action.
- Branch `test/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-SERVER-FILTER-COVERAGE-001` in its own worktree, created from the
  exact accepted 001G head; no upstream. Every earlier payment and Dashboard branch, package and evidence folder stays
  as it is; `origin/main` is recorded only (§2), never merged.

## 2. Source anchor (preflight 2026-11-01T01:40:53Z, read-only)

| Source | Head | State |
|---|---|---|
| Base: 001G (`test/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001G-dashboard-verification`) | `b1586d6f09f92518937ab65cf8ed425d39e42cf6` | tree `d4f84ff6`; its worktree clean; no upstream; its package and evidence folder verify (79 OK) |
| 001F correction (JRC-001) / 001F | `bd281721` / `d7ce9990` | unchanged; their packages verify |
| 001D ledger publication (#370, draft) | `54b19ab58ce72a2fa9a43860e31181a08222b254` | an ancestor of the base; unchanged |
| D-061 route r2 (#371, draft) | `53d6a6adc38f308b7ed6b0dd62177e6edd5ad5ce` | unchanged |
| 001D integration / server ledger, 001C correction / 001C, 001E family, 001A / 001B / D-061 / D-061 r1 | as recorded in the 001G packet §2 | unchanged |
| #314 / #315 (reserved) | `54346b37` / `4e8c81f6` | unchanged; never edited here |
| `origin/main` (`git ls-remote`) | `8ee132d5ef214fd92afc14f0ba2735059a643e77` | recorded only; merge base `d2079820`, 16 commits / 78 files since, 14 under `supabase/` (POS alert, online-order controls and Storefront SEO migrations and tests); none touches `owner_report_range` or the new file |

- `supabase/functions/pos-card-charge/index.ts` line 19: `providerProfile: null,` (blob `7a3c5c97`), unchanged.
- Ownership of the new path: no commit on any local or remote-tracking ref, no open PR and no worktree holds
  `supabase/tests/bizbot_zcredit_001g_owner_report_filter_coverage_test.sql` or this packet.

## 3. File allowlist

| Path | Purpose |
|---|---|
| `supabase/tests/bizbot_zcredit_001g_owner_report_filter_coverage_test.sql` | the focused pgTAP test |
| `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001G_SERVER_FILTER_COVERAGE_001_EXECUTION.md` | this packet |

Every other path is protected, in particular `supabase/migrations/**`, `supabase/config.toml`,
`supabase/functions/**`, every other `supabase/tests/**` file, `apps/**`, `packages/**`, `.github/**`, `tools/**` and
every manifest and lockfile.

## 4. The production predicates under test (unchanged)

- `app.owner_report_range`, `payment_win` CTE (126c lines 704–705): `and p.deleted_at is null` /
  `and p.status = 'completed'`. It feeds `current.collected_minor`, `current.cash_minor`,
  `current.last_cash_payment_minor` and `current.tenders`, and `comparison.collected_minor` /
  `comparison.cash_minor` (the last cash payment and the tenders have no comparison twin).
- The same function, `shift_sales` CTE (126c lines 837–838): the same two predicates. It feeds each closed shift's
  `order_count`, `collected_minor` and `cash_sales_minor` (`shift_cash.last_closed_shift`, `recent_closed_shifts`).
- `current.order_count`, `completed_count` and `open_count` count billed ORDERS by order status; `unpaid_count` counts
  billed orders that `app.order_is_fully_settled` does not settle (an order with a total above 0 is settled only by a
  live completed payment covering its current total; a zero-total order is settled with no payment row; every fixture
  total is above 0).
- The public wrapper `public.owner_report_range` is `SECURITY INVOKER` with a locked `search_path` and executable by
  `authenticated` only; it calls `app.owner_report_range` (`SECURITY DEFINER`).

## 5. Test design

### 5.1 Fixture pattern

The fixture follows `rf_report_004_owner_report_range_test.sql` and
`dashboard_owner_analytics_b_comparisons_and_payment_filters_test.sql`: one transaction rolled back at the end, the
session pinned to UTC, hex-only UUIDs, and rows inserted by the test session's own connection role. As in
rf_report_004, each report is then read after `set local role authenticated` (analytics B never switches role: it sets
only the identity GUC and reads as the connection role). On the disposable stack the connection role is `postgres`:
not a superuser, with BYPASSRLS. Row level security is enabled and FORCED on `orders`, `payments` and `shifts` (rf052
line 194, rf054 line 193, rf055 line 225), every policy on them binds `authenticated` (rf059: per table one select
policy and the insert / update / delete deny policies), and `postgres` owns all three; the test's two diag lines record
the role's attributes and, per table, the owner and the enabled / forced flags (§8.2). Table ownership therefore
exempts nothing: forced row level security binds the owner too, and without BYPASSRLS the fixture DML would be blocked
either way, by the rf059 insert / update / delete deny policies if they apply to `postgres` (a member of
`authenticated`, since the test can `set local role authenticated`) or by the default deny if no policy applies.
BYPASSRLS alone lets the fixture DML through. That DML also bypasses every write RPC, not only the payment ones:

- Orders are inserted directly in their final status: no `order.submit`, no status transition and no auto-completion.
  O7 stays `served` while the live P7 covers it, a state auto-completion would not leave.
- The shift is inserted already `closed`: no `app.open_shift` / `app.close_shift` call and no `shift.*` or
  `cash_drawer.*` audit. Its expected 11400, counted 11400 and variance 0 are hand-set to the opening float 5000 plus
  the live completed cash P2 6400, so SFC-22 reads stored values back and does not test `close_shift`.
  `app.close_shift`'s own cash sum (last defined in
  `20260710110000_staff_cashier_permissions_001_default_capabilities.sql`, lines 699–702) has no `deleted_at` filter,
  so on this fixture it would also count the deleted P12 (§8.10). Its drawer stays at the default `active`, which
  `close_shift` would have closed. Its `closed_at` is fixed at 20:00 UTC, in the future for a run before then (as
  rf_report_004's 18:00 is); the report's `closed_shifts_cur` compares `closed_at` with the clock only by date: it
  requires `closed_at`'s branch-local date to fall in the current window (126c line 826, whose bounds derive from
  `now()`), never that the `closed_at` instant has passed.
- The payments are stamped to a shift that was never open. No `payment.recorded` audit is written and no receipt
  number is assigned.

As in `rf062_non_completed_payment_and_lock_test.sql`, no current writer produces these payment states: all seven
production `insert into public.payments` sites write `'completed'`, and no migration updates or deletes `payments`.
So P3–P6, P11, the deleted P12 and the soft-delete UPDATE of P7 exist only through this pattern, and the coverage is
defensive. Every CHECK constraint, unique index and foreign key still applies, and so does the
`payments_set_updated_at` trigger (the only trigger on `payments`); no trigger is disabled and no constraint is
altered. The two `app_users` rows carry plain lowercase names (`sfc-owner-a`, `sfc-owner-b`), which the
`app_users.email` CHECK (rf015 line 70: non-blank and lowercase) accepts. The report is then read through
`public.owner_report_range` as `authenticated` with the identity GUC `app.current_app_user_id`, the convention of the
existing report tests.

### 5.2 Fixture matrix (Org A, Restaurant A1, Branch A1a, all inside today's window)

Every payment has its own order (one completed payment per order) and its own `local_operation_id`; the amounts are
distinct powers of two times 100, so any leak changes a total by a unique amount (in units of 100: P3 1, P4 2, P5 4,
P6 8, P7 16, P1 32, P2 64, P8 128, P9 256, P10 512, P11 1024, P12 2048; the excluded rows make the mask 3103).

| Row | Order status / total | Payment method / status / `deleted_at` | Amount | Stamped to the closed shift | Counted |
|---|---|---|---|---|---|
| P1 | completed / 3200 | card / completed / null | 3200 | yes | yes |
| P2 | completed / 6400 | cash / completed / null | 6400 | yes | yes |
| P3 | served / 100 | card / pending / null | 100 | yes | no |
| P4 | served / 200 | card / tendered / null | 200 | yes | no |
| P5 | served / 400 | card / failed / null | 400 | yes | no |
| P6 | served / 800 | card / voided / null | 800 | yes | no |
| P7 | served / 1600 | card / completed / null, then set by the deletion control | 1600 | yes | before the deletion yes; after it no |
| P11 | served / 102400 | cash / tendered / null (created 14:05, after P2) | 102400 | yes | no |
| P12 | served / 204800 | cash / completed / set at insert to 14:45 (created 14:35, the latest cash row of the day) | 204800 | yes | no |

Scope rows (completed card, today, outside Branch A1a): P8 on Branch A1b of Restaurant A1 (12800), P9 on Branch A2a
of Restaurant A2 (25600), P10 in Organization B (51200, EUR). One closed shift on Branch A1a (opening float 5000,
stored expected 11400, counted 11400, variance 0) carries P1–P7, P11 and P12 through `shift_id` /
`cash_drawer_session_id`.

### 5.3 Expected aggregate matrix (`today`; "—" = not asserted)

| Scope / state | collected | cash | tenders | last cash | orders / completed / open / unpaid | net | closed shift: orders / collected / cash | Assertions |
|---|---|---|---|---|---|---|---|---|
| Branch A1a, before the deletion | 11200 | — | card 2 / 4800, cash 1 / 6400 | — | as after / as after / — / 6 | as after | 3 / 11200 / 6400 | SFC-06 – SFC-09, SFC-19 |
| Branch A1a, after the deletion | 9600 | 6400 | card 1 / 3200, cash 1 / 6400 | 6400 | 9 / 2 / 7 / 7 | 319900 | 2 / 9600 / 6400 | SFC-12 – SFC-23 |
| Restaurant A1 (both branches), after | 22400 | 6400 | card 2 / 16000, cash 1 / 6400 | — | 10 / — / — / 7 | — | — | SFC-24, SFC-26 |
| Organization A (all), after | 48000 | 6400 | card 3 / 41600, cash 1 / 6400 | — | 11 / — / — / — | 358300 | — | SFC-25, SFC-26 |
| Organization B, read by its own owner | 51200 | — | card 1 / 51200 | — | — | — | — | SFC-27 |

- P3–P6, the deleted P7, the tendered cash P11 and the deleted completed cash P12 appear nowhere in
  `collected_minor`, `cash_minor`, `tenders`, `last_cash_payment_minor` or the shift breakdown (SFC-17 and SFC-21
  bit-test `collected_minor`, `cash_minor`, every tender total and the closed shift's collected and cash against the
  mask 3103; SFC-18 pins `last_cash_payment_minor` to exactly 6400, which is P2); Organization B's 51200 appears in no
  Organization A result (SFC-26), and each owner's read of the other organization is refused with 42501 (SFC-28,
  SFC-29).
- Order metrics follow the orders, not the excluded payments: `net_minor`, `order_count` and `completed_count` do not
  change with the deletion (SFC-19), and `unpaid_count` is 6 before and 7 after it, the billed orders
  `app.order_is_fully_settled` does not settle (SFC-05, SFC-08, SFC-11, SFC-20, SFC-23).
- Fixture sanity: all nine Branch A1a payments are inside today's branch-local window on live billed orders and
  stamped to the closed shift, and the twelve payments and twelve orders have pairwise-distinct amounts and operation
  identities (SFC-01 – SFC-04), so the exclusions can only come from the payment predicates.

### 5.4 Negative proof (request §5)

On the disposable local stack only, `app.owner_report_range` is replaced (`create or replace function`) by the 126c
text with exactly one predicate line removed — `payment_win`'s `p.status = 'completed'`, `payment_win`'s
`p.deleted_at is null`, and the same two in `shift_sales` — the focused test is run and must fail on the matching
assertions, and the original 126c text is applied again (its `pg_get_functiondef` hash must equal the pre-mutation
hash) before the next one. No migration file is edited, in the worktree or anywhere else. From `a216b29c` on, each
statement is streamed from the harness copy of the 126c migration into psql and never written to disk
(`tools/negative_proof_sfc.py`); the two earlier rounds wrote the statements to a scratch folder outside the
repository and the evidence, and those mutant files were deleted after the review (§8.4). The evidence keeps the
removed line, the SHA-256 of each statement, the run summary `logs/NEGATIVE_PROOF_<head>.txt` and, from `a216b29c` on,
every focused run's output (`logs/negative_proof_runs_<head>/`, local paths replaced by labels).

## 6. Validation

- A guarded disposable local Supabase stack: its own project id (`BIZBOTZC001GSFC`) and port range (57120–57129) in a
  scratch harness outside the repository; no `--linked`, no project ref, no remote URL or token in the environment;
  the repository's `config.toml` unchanged. `tools/zc_sfc.sh` checks this before each of its actions (reset, test,
  psql) and confirms the target container on its local port. The psql TAP transcript (a direct `docker exec` into
  `supabase_db_BIZBOTZC001GSFC`) and the three node runners (`--container supabase_db_BIZBOTZC001GSFC`, each behind its
  own allowlist) target that named local container without this guard.
- Base test set: a second harness folder holds `git archive <base> supabase/tests` with the same config (the same
  stack); a check proves the migrations are identical at the base and the head and that the two test folders differ
  by exactly the new file. Each pass starts with a fresh reset. Pass B's whole suite runs right after it. Pass H's
  whole suite runs after the refused runners and the focused, TAP and 24-file runs. All of those roll back, but
  sequences still advance (`app.kitchen_print_containment_revision`, through the `branches` insert trigger, and the
  001D revisions identity).
- The negative proof runs on the same stack just before the DB checks; each of its focused runs rolls back, its last
  restore returns the function to the migration's bytes (the hash), and pass B then resets the database.
- Pass H also runs the three concurrency runners CI runs before the suite. Each allowlists its own disposable container
  or CI's `supabase_db_RestoFlow`, so each refuses this stack before starting any process; the refusal is recorded,
  never bypassed. The CI-only pgTAP guards are left in place.
- `git diff --check`; the secrets, float-money and hardcoded-string guards.
- One focused fresh-context Claude delta review; only test and evidence defects are fixed under this Work ID.

## 7. Gates held (unchanged)

`DASHBOARD-COLLECTED-LABEL-001` (mandatory before the first LIVE charge, not blocking a zero-financial-effect
physical TEST); **Q-047** / **Q-049**; E2-B / **Q-048** / **Q-050**; TEST tenant-audit isolation; provider-profile
wiring (`providerProfile: null`); **D9** and the 001H physical procedure; every merge, deployment and hosted gate.

## 8. Results

### 8.1 Commits and scope

- On the base `b1586d6f`: `5a269ed2` this packet (before the test); `8caf8b6e` the focused test; `72c0a97e` the
  tendered cash row P11, added after the first green run (with only card rows excluded, removing the status predicate
  could not move `cash_minor` or the last cash payment); `f07d4060` the first results (docs only), the head the delta
  review read; `a216b29c` the review's test fixes (P12, the plain `app_users` names, the precise bypass header and the
  second diag line, the literal in SFC-20); `f1892bfa` a comment-only correction found while writing this update (with
  P12 in the fixture, the shift comment's "RF-055 close values" no longer matched `app.close_shift`'s formula; §5.1);
  `fe94f03c` two corrections from the read-only check of this packet's draft (§8.7): SFC-03 now also checks the
  order totals its description names, and the header no longer credits `dashboard_owner_analytics_b` with the role
  switch; then the commit that records these results (docs only). Every commit names the Work ID; none was amended,
  rebased or reset.
- Exactly the two paths of §3 change; the new file is the only change under `supabase/tests`. The review package,
  built from the final head after the last commit, carries in `IDENTITIES.txt` / `CHANGESET.txt` the exact head, tree,
  parent and blob hashes; its builder asserts the unchanged migrations, configuration, Edge sources, documents and
  branches, and that the head the checks below ran at (`fe94f03c`) differs from the final head only in this packet.

### 8.2 The disposable stack (evidence `logs/DB_CHECKS_fe94f03c.txt`)

Supabase CLI 2.107.0; PostgreSQL 17.6; containers `supabase_{db,auth,rest,storage,pg_meta,inbucket,analytics}_BIZBOTZC001GSFC`;
the database on local port 57122. The test's diag lines: `fixture role postgres: superuser=f, bypassrls=t`;
`table orders: owner postgres, row security enabled=t, forced=t`, and the same for `payments` and `shifts`. A read-only
query of the same stack (`logs/db_policies_fe94f03c.txt`) lists the twelve policies on the three tables, all bound to
`authenticated` (one select and three deny policies each), and `payments_set_updated_at` as the only trigger on
`payments`. The local stack applies the working copy of the migrations, which this Windows checkout holds with CRLF
line endings, so function bodies carry carriage returns; the negative proof restores those exact bytes.

### 8.3 Focused test (`fe94f03c`)

`Files=1, Tests=29 … Result: PASS` (`supabase test db`), and the psql TAP transcript lists 29 `ok` and no `not ok`
(`logs/db_focused_tap_fe94f03c.txt`). Every row of §5.3 holds.

### 8.4 Negative proof (`logs/NEGATIVE_PROOF_fe94f03c.txt`; every run's output in `logs/negative_proof_runs_fe94f03c/`)

| Mutant | Removed line (126c) | Focused run | Failing assertions | Restore |
|---|---|---|---|---|
| M1 | `payment_win`: `and p.status = 'completed'` (705) | FAIL | SFC-06, 07, 13, 14, 15, 17, 18, 24, 25 | hash back to `ec0d4d38…`; PASS |
| M2 | `payment_win`: `and p.deleted_at is null` (704) | FAIL | SFC-06, 07, 13, 14, 15, 17, 18, 23, 24, 25 | hash back to `ec0d4d38…`; PASS |
| M3 | `shift_sales`: `and p.status = 'completed'` (838) | FAIL | SFC-09, 21 | hash back to `ec0d4d38…`; PASS |
| M4 | `shift_sales`: `and p.deleted_at is null` (837) | FAIL | SFC-09, 21, 23 | hash back to `ec0d4d38…`; PASS |

- Why: under M1 the card rows P3–P6 and the tendered cash P11 enter `payment_win` (collected and tenders before and
  after, cash and the last cash payment through P11, the scope reads); under M2 the deleted P12 enters every
  Organization A read (before, after, restaurant and organization) and P7 stays counted after its deletion (the
  deletion control SFC-23 then sees no change); under M3 P3–P6 and P11 enter the shift; under M4 P12 enters the shift
  and P7 stays in it.
- The `pg_get_functiondef` hash is `ec0d4d3866ce9d133443f663d865ac4c` before, between and after the mutants; the
  worktree stays clean. Each statement's SHA-256 is in the log (the original 126c lines 456–967: `4bb1d976…`).
- Earlier rounds: at `8caf8b6e` (before P11) all four mutants failed, but M1 could not reach SFC-14 or SFC-18, which is
  why P11 was added; at `72c0a97e` (before P12) M2 could not reach SFC-14 or SFC-18 and M4 could not reach the shift's
  cash (review finding SFC-COV-01), which is why P12 was added; at `a216b29c` and `f1892bfa` the kill lists were the
  ones above.
- After the review the eight scratch mutant files of the two earlier rounds (`np1/sql` and `np2/sql`: `M1.sql`–`M4.sql`)
  were deleted; their SHA-256 values are in those rounds' logs, and `tools/negative_proof_sfc.py` rebuilds them
  byte-identically from the unchanged 126c migration. The two unmodified `original.sql` copies stay in scratch.

### 8.5 Regression (`logs/DB_CHECKS_fe94f03c.txt`)

| Run | Result |
|---|---|
| The relevant report tests (`rf_report_001` – `004`, the analytics A / B and visual-range S0 suites, the ORDER-EDIT-001G order-history and detail reads, settlement and auto-completion, the OPS-043 report-currency suites, the owner-report family and public-surface ACL suites, the 126c scope and 126 restaurant-operations suites, the sales summary) and the seven 001D lanes: 24 files | `Files=24, Tests=2418 … Result: PASS` |
| Whole suite, the base's test set (327 files), right after a fresh reset | `Files=327, Tests=12953 … Result: FAIL`, exit 1 |
| Whole suite, the head (328 files), after a fresh reset and the rolled-back focused, TAP and subset runs | `Files=328, Tests=12982 … Result: FAIL`, exit 1 |

- In both whole-suite runs exactly two files fail and every other file passes:
  `zz_storefront_content_contract_001_concurrency_test.sql` and `zz_storefront_featured_items_001_concurrency_test.sql`
  exit 3 with "No plan found": their CI-only guards refuse a non-CI database before any test runs (the known local
  execution limitation). They fail the same way at the base, so the new file adds no failure; the guards were not
  bypassed, and CI's Featured authorization step, which needs `GITHUB_ACTIONS` and `CI`, was never run.
  12982 − 12953 = 29, the new file's assertions.
- The three concurrency runners CI runs before the suite refused this stack before starting any process
  (`run_platform_online_orders_353_concurrency.mjs` and `run_acceptance_eta_001_concurrency.mjs`: "Only this task
  fixture or the exact disposable GitHub CI database is permitted"; `run_bizbot_zcredit_001d_concurrency.mjs`:
  "refused: only supabase_db_BIZBOTZCREDIT001D … or, inside GitHub Actions CI, supabase_db_RestoFlow"); they were not
  run on this stack and were not bypassed.

### 8.6 Static checks

At `fe94f03c`: `git diff --check` (branch, worktree, index): no whitespace errors; the secrets, no-float-money and
hardcoded-string guards: OK. The results commit (this packet only) is checked again at the final head after it is
made (`postflight/`).

### 8.7 Review and dispositions

One focused fresh-context Claude delta review of `b1586d6f..f07d4060`, then one skeptic per finding, all read-only
(`review/DELTA_REVIEW_f07d4060.json`; local paths replaced by labels, see `logs/SANITIZED.txt`). It found no
production-code defect and confirmed the fixture, the assertions, all four kill lists and the logs. Its eight findings
were all dispositioned under this Work ID, in the test, this packet or the evidence tooling; none needed a production
change.

| Finding | Severity / skeptic | Claim | Disposition |
|---|---|---|---|
| SFC-PKG-01 | major / confirmed | The two `app_users` values were e-mail-shaped (reserved `.test` domain); the builder's forbidden-value check and the package scan refuse any e-mail address, so no package could be built. | Fixed in the test (`a216b29c`): plain lowercase names `sfc-owner-a` / `sfc-owner-b`; no tool rule was relaxed. |
| SFC-COV-01 | minor / confirmed | The only soft-deleted row was a card, so a lost `deleted_at` filter could not move cash, the last cash payment or the shift's cash. | Fixed in the test (`a216b29c`): P12 on its own served order O12; mask 1055 → 3103; expectations updated. M2 now also fails SFC-06, 07, 14 and 18, and M4 also fails SFC-09 (§8.4). |
| SFC-DOC-01 | minor / partly | The bypass statement credited ownership, listed only payment side effects and said the diag recorded ownership and forced row level security. | Fixed (`a216b29c`, `f1892bfa`, §5.1): BYPASSRLS alone exempts the DML; the bypassed order, shift and payment writers, the hand-set close values, the drawer state and the possibly-future `closed_at` are listed; the rf062-style sentence is added; a second diag line records each table's owner and flags. |
| SFC-PKG-02 | minor / confirmed | Three evidence tools hard-coded local profile paths with the account name; the sanitizer's docstring and comment carried placeholder profile-path text. | Fixed in the evidence tools: paths derived at run time or from `ZC_SFC_MAIN_HARNESS`; the sanitizer's docstring and comment reworded; the scanner itself was not changed. The package build (after the last commit) stops unless its scan, which covers `tools/`, is clean (`scan/PACKAGE_SCAN.txt`) and the scanner self-test passes (`scan/SCANNER_SELF_TEST.txt`). |
| SFC-PKG-03 | minor / partly | §8.1 described package contents that did not exist yet. | Reworded (§8.1): the package is built from the final head after the last commit; the packet does not carry its own ids. |
| SFC-NP-01 | minor / partly | The mutant statements were still in scratch; §5.4 said the evidence kept "the run logs". | Fixed: the eight scratch mutant files deleted (SHA-256 kept in the logs); later rounds stream the SQL and write no file; every focused run's output is copied into the evidence, sanitized; §5.4 reworded. |
| SFC-DOC-02 | nit / confirmed | "Fresh reset", "checked before every action", the §8.8 runner list and the bit-test label overstated. | Reworded as the skeptic proposed (§5.3, §6, §8.5, §8.8). |
| SFC-TST-02 | nit / partly | SFC-20 restated the implementation and never asserted its number. | Fixed in the test (`a216b29c`): SFC-20 asserts the literal 7 and keeps the helper equality. |

Before the results commit, a second read-only check of this packet's draft ran: three lenses (evidence, source,
arithmetic), then one skeptic per reported item (`review/PACKET_DRAFT_CHECK_f1892bfa.json`, sanitized like the review;
its line numbers refer to the draft). It re-derived and confirmed every result, number, kill list and cited line, and
reported 15 items: 14 survived their skeptic (12 distinct; none changed a result) and were applied, 1 was refuted. Two
were test defects, fixed in `fe94f03c`: SFC-03's description named order totals that its SQL did not check, and the
header credited `dashboard_owner_analytics_b` with the role switch. The others were wording in this packet or the
evidence: the review file was not yet sanitized when the draft said it was (it now is, `logs/SANITIZED.txt`); the
scanner self-test had no record yet (the SFC-PKG-02 row now points to the package build); the SFC-PKG-02 count; the
analytics B attribution, the default-deny parenthetical and the `closed_shifts_cur` clock phrase in §5.1; the
comparison twins and the settlement parenthetical in §4; P12's timestamps in §5.2; and "every read" for M2 in §8.4.

### 8.8 Not validated

- No hosted database, no linked project and no other local stack was touched.
- The seven 001D lanes ran as pgTAP files only. None of the three concurrency runners CI runs before the suite
  (`run_platform_online_orders_353_concurrency.mjs`, `run_acceptance_eta_001_concurrency.mjs`,
  `run_bizbot_zcredit_001d_concurrency.mjs`) ran: each refused this stack (§8.5).
- The two CI-only `zz_storefront_*_concurrency_test.sql` files and CI's Featured authorization step did not run (§8.5).
- `app.close_shift` and `app.get_open_shift_summary` are not exercised: the shift's close values are hand-set (§5.1).

### 8.9 Disclosures

- The first DB-checks attempt (kept in `logs/attempt1_72c0a97e/`) passed a 327-path argument list for the base set and
  the CLI could not start it (`ENAMETOOLONG`), so no base suite ran in that attempt. The base set then ran from the
  second harness folder (§6).
- P11 was added after the first green run (`72c0a97e`); P12, the plain `app_users` names, the second diag line and the
  literal in SFC-20 after the review (`a216b29c`); `f1892bfa` and `fe94f03c` after that (§8.1). Each test change was
  followed by a new negative proof and new DB checks; the earlier rounds' logs stay in the evidence (`*_8caf8b6e`:
  negative proof only; `*_72c0a97e`, `*_a216b29c` and `*_f1892bfa`: both, plus `db_policies_f1892bfa.txt`), and the
  results above are those of `fe94f03c`. `f1892bfa` changes two comments only, and `fe94f03c` a comment and the
  fixture-sanity check SFC-03; neither changes a report expectation, and both runs were repeated each time so that the
  package is source-matched.
- The two synthetic e-mail-shaped values of SFC-PKG-01 remain in the history of `8caf8b6e`–`f07d4060` (no history
  rewrite is authorized). They use the reserved `.test` domain, belong to no one, and are not in the package's patch,
  source ZIP or logs.

### 8.10 Observation (routed; no change under this Work ID)

`app.close_shift`'s expected-cash sum (`20260710110000_staff_cashier_permissions_001_default_capabilities.sql` lines
699–702) and `app.get_open_shift_summary`, which copies it (`20260720120000_pilot_ops_corrections_001_shift_recovery.sql`
lines 152–157), count the completed cash payments on the drawer without a `deleted_at` filter, while
`owner_report_range` (`payment_win`, `shift_sales`) excludes soft-deleted payments. No writer soft-deletes a payment
today (§5.1), so the two agree in production. If payment soft-deletion is ever introduced, a shift's closing expected
cash and the report's shift cash would disagree. This is routed to the owner and the planner as an observation; this
test-only Work ID neither makes nor proposes a production change.
