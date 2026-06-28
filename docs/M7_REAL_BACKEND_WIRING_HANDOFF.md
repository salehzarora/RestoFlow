# M7 — Real Backend Wiring: Handoff & Parallel-Agent Plan

> **STATUS — PLANNING / HANDOFF (M7 kickoff).** This document is a handoff and a
> two-agent parallel plan. It does **not** implement M7, write migrations, or
> touch app code. It is written so Saleh can open **two fresh Claude Code chats**
> and paste an agent-specific prompt into each (see §10). It **references** the
> frozen canon; it never overrides it: contracts are owned by
> [API_CONTRACT.md](API_CONTRACT.md), decisions by [DECISIONS.md](DECISIONS.md),
> isolation by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md), the
> agent pipeline by [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) and
> [../CLAUDE.md](../CLAUDE.md) / [../AGENTS.md](../AGENTS.md), the M6 direction by
> [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md), and
> the demo boundaries by
> [M6_FINAL_QA_ISOLATION_RUN_GUIDE.md](M6_FINAL_QA_ISOLATION_RUN_GUIDE.md).
>
> Markers used: **DECISION D-xxx**, **RISK R-xxx**, **OPEN QUESTION Q-xxx**.
> Money is integer minor units (**DECISION D-007**). Platform admin is read-only
> (**DECISION D-026**). Sync is polling-first; Realtime is enhancement-only
> (**DECISION D-010**).

---

## 1. Current project state

- **Latest main:** `e03a763` (RF-121 merged). **M6 is Done** (epic RF-66 / M6 —
  Real product integration; all children Done). Repo is clean.
- **Four app surfaces, all demo-backed and isolated** (verified by the RF-121 QA
  guide). Each app runs on the Flutter web target, in demo mode by default
  (`RESTOFLOW_DEMO_MODE` defaults to `true`):
  - `apps/pos` — order build → table → send → cash pay → receipt/browser-print.
  - `apps/kds` — kitchen board + lifecycle actions + ticket print.
  - `apps/dashboard` — owner reports overview (RF-119).
  - `apps/admin` — platform overview (RF-120).
- **What is real vs demo today** (full table in
  [M6_FINAL_QA_ISOLATION_RUN_GUIDE.md](M6_FINAL_QA_ISOLATION_RUN_GUIDE.md) §11):
  - POS submit/outbox is the **real outbox + idempotency shape** but runs in a
    hardcoded demo org/branch/device context — no live session.
  - POS payment/receipt is demo cash-only with **provisional** receipt numbers
    (`PROV-<seq>`); printing is **browser preview only** (no hardware).
  - KDS shows a **demo fixture feed**, not synced to real POS orders.
  - Owner dashboard + platform admin render **computed demo datasets**.
  - Auth/session is **bypassed** in demo mode; Realtime is **not used**.
- **The backend mostly already exists and is frozen/contracted** (RF-050…RF-124,
  API_CONTRACT.md §4). M7 is largely a **client harness against existing public
  contracts**, plus a small amount of new backend (platform-admin public
  wrapper). See the inventories in §A (seams) and §B (contracts).
- **Seams already exist** (the swap points M7 wires behind) — §A.

---

## 2. M7 objective

> **M7 = real backend wiring while preserving demo mode and product honesty.**

Connect real Supabase/backend data **safely** for the five capability areas, each
behind the **existing repository seam** so demo mode stays intact:

1. **POS** submit / order / payment / outbox flow (via `sync_push` dispatch to
   `app.submit_order` / `app.record_payment`).
2. **KDS** live/polling kitchen tickets (via `public.sync_pull` + a real
   `KdsSyncSource`).
3. **Owner dashboard** real reports (via the `public.daily_branch_sales_report` /
   `dashboard_org_daily_sales` views — already callable today).
4. **Platform admin** real data (via the RF-091 RPCs — **needs a `public.*`
   wrapper first**).
5. **Auth / session / public API** (via `public.get_my_context` +
   `public.start_pin_session` — already ratified, **DECISION D-029**).

"Safely" means: real mode is opt-in and clearly gated; demo mode remains the
default and fully working; nothing claims live data it doesn't have; and no
client ever holds a service-role key or bypasses RLS.

---

## 3. Non-negotiable rules (binding on both agents)

- **No false live-data claims.** Every surface must stay honest (demo label when
  demo; real data only when truly wired and verified).
- **Demo mode must remain available** and is the default. Real mode is **opt-in**
  via configuration (e.g. `--dart-define=RESTOFLOW_DEMO_MODE=false` + Supabase
  URL/anon key dart-defines), clearly gated.
- **Money stays integer minor units** (**DECISION D-007**) — no float anywhere.
- **Platform admin stays read-only** (**DECISION D-026**) unless a ticket
  explicitly authorizes a mutation under the architecture-change procedure.
- **No secrets in clients. No service-role key in apps** (**DECISION D-011**) —
  clients use the **anon key + authenticated JWT** only.
- **No bypassing RLS.** Every client read/write goes through RLS-scoped
  views/wrappers; tenant/scope are derived server-side, never trusted from the
  client.
- **No backend changes without tests** (pgTAP / RLS isolation tests).
- **No app wiring to RPCs that are not safely exposed/contracted.** The `app`
  schema is **not** exposed via PostgREST; the client may only call `public.*`
  wrappers and RLS-scoped `public` views/tables. If a needed RPC has no public
  wrapper, Agent A must add one (change-controlled) before Agent B wires it.
- **No two agents editing the same working tree.** Separate branches + separate
  git worktrees (**AGENTS.md** §4; **DECISION D-016**). One active ticket per
  worktree.
- **No push / no force-push / no `git reset --hard` / no DB reset / no Jira
  changes** without explicit human approval (**AGENTS.md** §3).
- **Architecture-change procedure** (**candidate DECISION D-030**, AGENT_WORKFLOW
  §8) for any new backend surface: its own ticket, a DECISIONS entry, Codex
  review, human approval, green gate.

---

## 4. Parallel setup (two git worktrees)

Run these from the main repo root
`C:\Users\saleh\Desktop\ClaudeAi\RestoFlow\RestoFlow`. Worktrees let two chats
work on two branches in **two separate directories** off **one** repository — no
branch-switching collisions (**AGENT_WORKFLOW** §10.1: "use worktree tooling …
rather than switching branches in a shared directory").

```bash
# 0) Confirm a clean main at the verified commit.
git status --short                 # expect: clean
git checkout main
git pull --ff-only origin main     # expect: at e03a763 (or later)

# 1) Backend/contracts worktree (Agent A).
git worktree add -b m7/backend-contracts-real-wiring ../RestoFlow-m7-backend main

# 2) Client integration worktree (Agent B).
git worktree add -b m7/client-real-wiring ../RestoFlow-m7-client main

# 3) Verify.
git worktree list
```

Resulting layout:

| Agent | Branch | Worktree directory |
|---|---|---|
| A (backend/contracts) | `m7/backend-contracts-real-wiring` | `C:\Users\saleh\Desktop\ClaudeAi\RestoFlow\RestoFlow-m7-backend` |
| B (client integration) | `m7/client-real-wiring` | `C:\Users\saleh\Desktop\ClaudeAi\RestoFlow\RestoFlow-m7-client` |

> These two branches are the **track** branches for the worktrees. Each concrete
> M7 implementation ticket should still get its own `<type>/RF-<id>-<slug>`
> branch **inside that agent's worktree** (per CLAUDE.md §3). To remove a
> worktree later: `git worktree remove ../RestoFlow-m7-backend` (only after its
> work is merged or abandoned). Never run two chats in the **same** directory.

---

## 5. Agent split

### Agent A — Backend / contracts agent (worktree `RestoFlow-m7-backend`)

**Owns:**
- Supabase schema / RPC / public-API discovery and **contract ratification**
  (confirm the existing frozen contracts in API_CONTRACT.md §4 are accurate and
  callable; document any drift).
- **Safe `public.*` wrappers** where a needed capability is app-schema-only
  (notably the **platform-admin** RPCs — see §6/§B).
- RLS policies + **RLS isolation tests** and **pgTAP** tests.
- Backend **report/query contracts** (confirm `daily_branch_sales_report`,
  `dashboard_org_daily_sales`, `dashboard_restaurant_daily_sales`).
- Order-submission / payment / kitchen-ticket **backend contracts** (confirm
  `submit_order`, `record_payment`, `sync_push`/`sync_pull` dispatch shapes).
- Auth/session **contract docs** (confirm `get_my_context`, `start_pin_session`,
  **DECISION D-029**).
- Backend validation (Supabase local stack, migrations, pgTAP).

**Must avoid:**
- Flutter UI implementation; app design changes.
- l10n / UI wording (unless a contract doc requires a short note).
- Touching POS/KDS/dashboard/admin **UI** files (`apps/*/lib/src/**` widgets/
  screens).

### Agent B — Client integration agent (worktree `RestoFlow-m7-client`)

**Owns:**
- Flutter **repository wiring behind the existing seams** (§A) — real-mode
  implementations of `PaymentRepository`, `OutboxRepository`, `TablesRepository`,
  `KitchenOrdersRepository` (+ `KdsSyncSource`), `OwnerReportsRepository`,
  `PlatformAdminRepository`, and the auth/session/PIN flow.
- **Preserving the demo repositories** (the `Demo*` classes stay; real classes
  are added alongside and selected by mode).
- UI **loading / error / empty** states for real-backend failures (the seams are
  already async; extend the existing states).
- App **tests with mocked repositories** (no live network in tests).
- l10n **only** when a genuinely new real-mode/error label is needed.

**Must avoid:**
- SQL / migrations / RLS changes; backend RPC creation.
- Changing backend contracts independently.
- Touching `supabase/**` files **unless** Agent A explicitly hands off a contract
  and the change is a client-side type/transport mirror (not a schema change).

---

## 6. Dependency map

> Reality check from discovery: **most contracts already exist and are callable
> today.** The auth APIs (`get_my_context`, `start_pin_session`) are ratified
> (**D-029**); the report views are live; `sync_pull`/`sync_push` wrappers exist.
> The one genuinely **new** backend deliverable is the **platform-admin public
> wrapper**. So Agent B can make broad progress in parallel as soon as the
> auth/session client foundation lands.

| Task | Owner | Depends on | Can run now? | Must wait for | Output artifact |
|---|---|---|---|---|---|
| M7 contracts baseline (ratify API_CONTRACT §4, document drift) | A | — | **Yes** | — | `M7` contract notes (committed doc) |
| Auth/session contract confirm (`get_my_context`, `start_pin_session`, D-029) | A | contracts baseline | **Yes** | — | Auth contract note |
| RLS / pgTAP isolation tests (reports, orders, payments, kitchen redaction) | A | backend access | **Yes** | — | Passing pgTAP/RLS suite |
| Platform-admin **public wrapper** + MFA/RLS tests | A | platform-admin access decision | **Yes** (change-controlled) | DECISIONS entry + human approval | `public.platform_admin_*` wrapper + tests |
| Supabase auth/session client foundation (Supabase client init, JWT, `get_my_context`, PIN session) | B | Auth contract confirm | **Yes** (contract exists) | A's auth note (stable) | Real auth/session wiring + mock tests |
| POS real submit/order/payment repository | B | A order/payment RPC + `sync_push` contract | After auth foundation | A `submit_order`/`record_payment`/`sync_push` note | Real `OutboxRepository`/`PaymentRepository` + tests |
| KDS real polling repository (`KdsSyncSource`) | B | A kitchen-ticket `sync_pull` entity contract | After auth foundation | A `sync_pull` kitchen note | Real `KitchenOrdersRepository`/`KdsSyncSource` + tests |
| Owner dashboard real reports | B | A report-view contract (views already live) | After auth foundation | A report note (mostly confirm) | Real `OwnerReportsRepository` + tests |
| Platform admin real data | B | A **platform-admin public wrapper** | **No** — blocked | A's wrapper merged/committed | Real `PlatformAdminRepository` + tests |
| Real-mode config / env hardening (dart-defines, mode gating) | B | real repositories known | After repos exist | — | Config + demo/real switch + tests |
| UI real-mode error/empty labels | B | real repositories known | After repos exist | — | l10n + states + tests |
| End-to-end isolation/regression QA | A+B | all of the above | At the end | both branches merged | Updated QA run results |
| Security / RLS final sign-off (**RISK R-003**) | A (+ human) | RLS tests green | At the end | human RLS sign-off | Recorded sign-off |

---

## 7. Merge strategy

1. **Agent A merges first** for anything that creates/ratifies backend contracts
   or adds the platform-admin public wrapper. A's contract docs and wrappers are
   the foundation B builds on.
2. **Agent B must not merge** real backend-dependent code until either (a) Agent
   A's contract branch is **merged into main**, or (b) a **stable contract doc**
   for that capability is committed (so B is coding against a frozen shape).
3. **Agent B can work fully in parallel** by focusing on what doesn't need a
   missing endpoint: the **repository interfaces**, **dependency injection / mode
   switch**, **mock-backed tests**, and the **demo/real toggle** — without
   calling endpoints that aren't exposed yet. The platform-admin **real** repo is
   the one piece B should leave stubbed until A's wrapper lands.
4. **Before merging B**, rebase/merge **latest main after A** into the client
   branch, re-run the full gate, and resolve any contract drift.
5. **Saleh merges** (humans only); Codex reviews each branch read-only in its own
   worktree before merge. Keep each merge **small** (one capability per PR).

---

## 8. Communication protocol between agents

The two chats don't talk directly — they hand off through **committed notes** in
their own branch (and via Saleh / ChatGPT as control room). Use these exact
shapes.

**Agent A → contract note** (one per RPC/view/table, committed under `docs/` or
the ticket's report):

```
CONTRACT: <public.name | view name | table>
  schema:        public | app(+wrapper)
  input params:  <name type, …>
  output shape:  <jsonb {…} | view columns>
  auth/RLS:      <who may call; what RLS scopes it; MFA/PIN-session needs>
  demo/real:     <how the client should behave in demo vs real mode>
  tests run:     <pgTAP/RLS test ids + result>
  status:        callable-today | new-wrapper-added | needs-approval
```

**Agent B → integration note** (one per capability, committed in its report):

```
INTEGRATION: <capability> (<app>)
  repositories touched:  <RealXRepository, provider override>
  contract used:         <CONTRACT name + API_CONTRACT § + A's note ref>
  demo mode behavior:    <unchanged Demo* repo>
  real mode behavior:    <what it calls, error/empty handling>
  tests run:             <mock-backed test ids + result>
  blocked dependency:    <none | waiting on A's <contract>>
```

---

## 9. Jira strategy (proposed — do **not** modify Jira now)

**Proposed epic:** **M7 — Real backend wiring (demo-preserving)** — connect the
four app surfaces + auth to real Supabase contracts behind the existing seams,
keeping demo mode and product honesty.

Suggested implementation tickets (dependency order; A = backend, B = client):

| # | Ticket | Owner | Depends on | Acceptance criteria (summary) |
|---|---|---|---|---|
| 1 | M7 planning & contracts baseline | A | — | API_CONTRACT §4 ratified; per-capability CONTRACT notes committed; drift documented; no code. |
| 2 | Supabase auth/session real-mode wiring | B | #1 | Real Supabase client (anon key + JWT); `get_my_context` routing; PIN session via `start_pin_session`; demo mode still default; mock tests; **no service-role key**. |
| 3 | Platform-admin public wrapper + RLS/MFA tests | A | #1 | `public.platform_admin_*` wrapper (SECURITY INVOKER pass-through); aal2 + grant + reason enforced; pgTAP/RLS tests green; DECISIONS entry; **read-only** (D-026). |
| 4 | POS real submit/order/payment wiring | B | #2 | Real `OutboxRepository`/`PaymentRepository` via `sync_push`→`submit_order`/`record_payment`; server-authoritative receipt no.; integer-minor money; demo repo preserved; error/empty states; mock tests. |
| 5 | KDS real ticket polling wiring | B | #2 | Real `KitchenOrdersRepository`/`KdsSyncSource` via `sync_pull`; kitchen money-free (RLS redaction); polling-first (D-010); demo feed preserved; mock tests. |
| 6 | Owner dashboard real report queries | B | #2 | Real `OwnerReportsRepository` over `daily_branch_sales_report`/`dashboard_org_daily_sales`; RLS-scoped; integer-minor; demo dataset preserved; loading/error/empty; mock tests. |
| 7 | Platform admin real data wiring | B | #3 | Real `PlatformAdminRepository` over the new public wrapper; read-only; demo dataset preserved; states; mock tests. |
| 8 | Real-mode environment/config hardening | B | #2 | Dart-define config (URL/anon key/mode); clear real-vs-demo gating; honest labels in both modes; no secrets committed; tests. |
| 9 | Realtime-as-enhancement (optional) for KDS | B | #5 | Optional realtime invalidation **on top of** polling (never sole source, D-010); demo unaffected; tests. |
| 10 | End-to-end isolation/regression QA | A+B | #2–#8 | RF-121 guide re-run green for both demo and real modes; honesty table updated; full gate green. |
| 11 | Security / RLS final sign-off | A + human | #3,#5,#6,#10 | RLS isolation suite green; **human RLS sign-off recorded (RISK R-003)**; no cross-tenant read/write. |

(8–11 core tickets; 9 optional — within the requested 8–12 range.)

---

## 10. Agent prompts (copy-paste)

> Replace `<WORKTREE_PATH>` and, once the M7 tickets exist in Jira, the
> `RF-<id>` placeholders. Each agent reads the canon first.

### A. Prompt for Claude Code **Agent A — Backend / contracts**

```
You are Claude Code working ONLY in the backend/contracts worktree:
<WORKTREE_PATH = C:\Users\saleh\Desktop\ClaudeAi\RestoFlow\RestoFlow-m7-backend>
on branch m7/backend-contracts-real-wiring. This is M7 (real backend wiring).

READ FIRST (do not skip): CLAUDE.md, AGENTS.md, docs/AGENT_WORKFLOW.md,
docs/API_CONTRACT.md, docs/DECISIONS.md, docs/SECURITY_AND_THREAT_MODEL.md,
docs/M6_REAL_PRODUCT_INTEGRATION_PLAN.md, docs/M7_REAL_BACKEND_WIRING_HANDOFF.md.

ALLOWED SCOPE: Supabase contracts only — supabase/migrations/**, pgTAP/RLS tests,
docs/ contract notes. Ratify API_CONTRACT §4 against the real schema; add safe
public.* wrappers ONLY where a needed capability is app-schema-only (notably the
platform-admin RPCs), as a faithful SECURITY INVOKER pass-through that adds no
privilege; write/extend RLS isolation + pgTAP tests. Emit a CONTRACT note (the
§8 shape) for every capability the client will call.

FORBIDDEN: any apps/** UI/Flutter code; l10n/UI wording; changing app design;
weakening RLS; service-role key anywhere; exposing the app schema; new backend
surface without its own ticket + DECISIONS entry + human approval
(architecture-change procedure, AGENT_WORKFLOW §8); editing the client worktree.

DEPENDENCIES: you are the upstream — start with the contracts baseline and the
platform-admin public wrapper; Agent B waits on your CONTRACT notes.

VALIDATION (run before reporting): local Supabase stack + migrations apply;
pgTAP/RLS suite green; `dart format --output=none --set-exit-if-changed .`;
`git diff --check`. (Use Git Bash for *.sh on Windows.)

FINAL REPORT: per-capability CONTRACT notes (§8 shape); files changed; tests run
+ results; what is callable-today vs new-wrapper vs needs-approval; what Agent B
is unblocked to wire; validation results; final `git status --short`.

RULES: integer minor money (D-007); platform admin read-only (D-026); polling-
first (D-010). NO push, NO PR, NO merge, NO Jira. Create a LOCAL checkpoint
commit ONLY if validation is green: `feat(backend): <summary> [RF-<id>]`.
```

### B. Prompt for Claude Code **Agent B — Client integration**

```
You are Claude Code working ONLY in the client worktree:
<WORKTREE_PATH = C:\Users\saleh\Desktop\ClaudeAi\RestoFlow\RestoFlow-m7-client>
on branch m7/client-real-wiring. This is M7 (real backend wiring).

READ FIRST (do not skip): CLAUDE.md, AGENTS.md, docs/AGENT_WORKFLOW.md,
docs/API_CONTRACT.md (contract shapes), docs/DECISIONS.md,
docs/M6_REAL_PRODUCT_INTEGRATION_PLAN.md,
docs/M6_FINAL_QA_ISOLATION_RUN_GUIDE.md,
docs/M7_REAL_BACKEND_WIRING_HANDOFF.md (esp. §A seams).

ALLOWED SCOPE: Flutter client only — implement REAL repositories behind the
EXISTING seams (PaymentRepository, OutboxRepository, TablesRepository,
KitchenOrdersRepository + KdsSyncSource, OwnerReportsRepository,
PlatformAdminRepository) and the auth/session/PIN flow. Keep every Demo* repo
intact; select demo vs real by mode (RESTOFLOW_DEMO_MODE + Supabase URL/anon-key
dart-defines). Add loading/error/empty states for real failures. Add app tests
with MOCKED repositories (no live network). Add l10n only for genuinely new
real-mode/error labels. Emit an INTEGRATION note (the §8 shape) per capability.

FORBIDDEN: SQL/migrations/RLS; backend RPC creation; changing backend contracts;
touching supabase/** (unless mirroring a client-side type Agent A handed off);
service-role key; any secret committed; calling an endpoint that has no public
wrapper yet (leave the platform-admin REAL repo stubbed until Agent A's wrapper
is committed/merged).

DEPENDENCIES: start with the Supabase auth/session foundation and the repository
interfaces / DI / mode switch / mock tests (these need no missing endpoint).
Wire POS/KDS/dashboard real repos against the EXISTING public contracts once the
auth foundation lands; leave platform-admin REAL repo blocked on Agent A.

VALIDATION (run before reporting): `dart format --output=none
--set-exit-if-changed .`; `dart analyze apps packages`; `flutter test` for each
touched app + `packages/l10n`; `dart run tools/check_l10n.dart`;
`bash tools/check_no_hardcoded_strings.sh`; `bash tools/check_no_float_money.sh`;
`bash tools/check_secrets.sh`; `git diff --check`. (Git Bash for *.sh on Windows;
run check_secrets on its own if a combined command times out.)

FINAL REPORT: INTEGRATION notes (§8 shape); repositories touched + provider
overrides; demo vs real behavior; tests run + results; any blocked dependency;
validation results; final `git status --short`.

RULES: integer minor money (D-007), no float; platform admin read-only (D-026);
demo mode stays default + working; no false live-data labels. NO push, NO PR, NO
merge, NO Jira. Create a LOCAL checkpoint commit ONLY if validation is green:
`feat(<app>): <summary> [RF-<id>]`.
```

---

## 11. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| Two agents edit the same files | Merge conflicts, lost work | Separate worktrees + branches (§4); A owns `supabase/**`+`docs/` contracts, B owns `apps/**` client; never two chats in one dir. |
| Frontend calls a backend endpoint that doesn't exist | Runtime failures, false "real" claims | B only calls **public** wrappers/views that exist (§B); platform-admin real repo stays stubbed until A's wrapper lands; mock-backed tests. |
| Backend exposes the `app` schema unsafely | RLS bypass / privilege leak | Only `public.*` SECURITY INVOKER wrappers; app schema stays unexposed; A adds wrappers as faithful pass-throughs (D-029 pattern); pgTAP tests. |
| **RLS bypass** (**RISK R-003**, CRITICAL) | Cross-tenant data leak | No RLS weakening; RLS isolation suite green; **human RLS sign-off required before real pilot**. |
| Demo mode accidentally removed | Loss of safe fallback, broken QA | Demo repos preserved; demo is the **default**; QA guide re-run in both modes (ticket #10). |
| False live-data labels | Dishonest product | Honesty rule (§3); banners stay until a surface is truly wired + verified; QA honesty table updated. |
| Secrets leaked to client | Security breach | `check_secrets.sh`; anon key + JWT only; **no service-role key** (D-011); config via dart-defines, never committed secrets. |
| Money float regression | Financial error (**RISK R-008**) | `check_no_float_money.sh`; integer `_minor` everywhere; server recomputes totals (D-007). |
| Platform-admin mutation scope creep | Unauthorized writes | Read-only (D-026); any mutation needs an explicit ticket + architecture-change approval. |
| Flaky / slow tests; slow secrets scan | CI friction | Mock-backed app tests (no live network); run `check_secrets.sh` separately if a combined command times out (Windows). |
| Contract drift between A's note and real schema | B wires the wrong shape | A ratifies against the real schema and commits CONTRACT notes; B codes against the committed note; rebase latest main after A before merging B. |

---

## 12. Final recommendation — what Saleh should do next

1. **Review this handoff doc** (and skim the §A seam + §B contract inventories).
2. **Create the two worktrees** with the §4 commands (clean main first).
3. **Open two fresh Claude Code chats** — one per worktree directory.
4. **Paste the Agent A prompt** (§10.A) into the chat opened in
   `RestoFlow-m7-backend`.
5. **Paste the Agent B prompt** (§10.B) into the chat opened in
   `RestoFlow-m7-client`.
6. **Keep ChatGPT as the control room** for merge/order decisions: A's contracts
   merge first; B's backend-dependent code merges after A's contract is merged or
   committed; you merge (humans only) one capability at a time, with Codex review.
7. Land the **auth/session foundation** (ticket #2) early — it unblocks most of
   Agent B. Leave **platform-admin real** (ticket #7) until A's public wrapper
   (ticket #3) is in. Finish with **E2E QA** (#10) and the **human RLS sign-off**
   (#11) before any real pilot.

---

## Appendix A — Repository seam inventory (Agent B targets)

All swap points are Riverpod providers returning an abstract repo; the `Demo*`
class stays and a `Real*` class is added beside it, selected by mode.

| App | Abstract repo | Demo impl | Provider (swap point) | Key methods | Real source |
|---|---|---|---|---|---|
| POS | `PaymentRepository` | `DemoPaymentStore` | `paymentRepositoryProvider` (`apps/pos/lib/src/state/payment_controller.dart`) | `recordCashPayment(orderNumber, amountMinor, tenderedMinor, currencyCode) → CashPayment`; `shiftContext()`; `paymentFor(orderNumber)` | `sync_push`→`app.record_payment` (RF-054) |
| POS | `OutboxRepository` | `DemoOutboxStore` | `outboxRepositoryProvider` (`apps/pos/lib/src/state/outbox_controller.dart`) | `enqueue(OutboxEntry)`; `recentEntries()`; `push(id)`; `retry(id)` | `sync_push`→`app.submit_order` (RF-052) |
| POS | `TablesRepository` | `DemoTablesStore` | `tablesRepositoryProvider` (`apps/pos/lib/src/state/order_setup_controller.dart`) | `loadTables() → List<DemoTable>` | RLS-scoped `public.tables`/branch read (RF-114) |
| KDS | `KitchenOrdersRepository` | `DemoKitchenOrdersStore` | `kitchenOrdersRepositoryProvider` (`apps/kds/lib/src/state/kitchen_orders_controller.dart`) | `loadOrders() → List<KitchenOrderTicket>` | `public.sync_pull` (RF-064) orders/order_items |
| KDS | `KdsSyncSource` (injection) | none (demo falls back to board) | `kdsSyncSourceProvider` (`packages/feature_kitchen/lib/src/kds_providers.dart`; override in `apps/kds/lib/main.dart`) | sync source for live polling | authenticated `KdsSyncCoordinator` (`packages/data_remote`) |
| Dashboard | `OwnerReportsRepository` | `DemoOwnerReportsRepository` | `ownerReportsRepositoryProvider` (`apps/dashboard/lib/src/state/dashboard_providers.dart`) | `loadReport() → DashboardReport` | `public.daily_branch_sales_report` / `dashboard_org_daily_sales` (RF-075/092) |
| Admin | `PlatformAdminRepository` | `DemoPlatformAdminRepository` | `platformAdminRepositoryProvider` (`apps/admin/lib/src/state/platform_admin_providers.dart`) | `loadOverview() → PlatformOverview` | RF-091 RPCs **via a new `public.*` wrapper** |
| All | auth/mode | demo bypass | `AuthGatedHome` + `authDemoModeEnabled()` (`packages/feature_auth`) | `RESTOFLOW_DEMO_MODE` (default `true`) | Supabase Auth JWT + `public.get_my_context` |

## Appendix B — Backend contract inventory (Agent A surface)

**Callable today by an authenticated client (use these directly):**

- `public.get_my_context()` → `{app_user, is_platform_admin, memberships[]}`
  (RF-124, API_CONTRACT §4.22; **D-029**) — routing/scope.
- `public.start_pin_session(device_session_id, employee_profile_id, pin_verifier,
  local_operation_id?)` → `uuid` (RF-123, §4.21; **D-029**) — fast PIN session.
- `public.sync_pull(pin_session_id, device_id, entities[], cursors, limit)` →
  `{entities, tombstones, cursors, server_ts}` (RF-064, §4.15) — KDS + reads.
- Read-only RLS views (§4.19): `public.daily_branch_sales_report`,
  `public.daily_branch_shift_lines`, `public.daily_branch_void_discount_reasons`,
  `public.dashboard_org_daily_sales`, `public.dashboard_restaurant_daily_sales`.
- RLS-scoped `SELECT` on `public.orders/order_items/payments/shifts/
  cash_drawer_sessions/memberships/menu_*/audit_events` (writes are REVOKED —
  only via RPC). Kitchen roles are redacted from money (D-007/SECURITY T-003).

**Mutations via `sync_push` dispatch (app-schema SECURITY DEFINER, PIN-session
gated — not a direct API call):** `app.submit_order` (§4.1), `app.record_payment`
(§4.7), `app.open_shift`/`close_shift`/`reconcile_shift` (§4.8/4.9),
`app.revoke_device`/`revoke_employee`, `app.apply_discount`, `app.void_order`.

**Platform-admin RPCs (app schema; aal2 MFA + active `platform_admin_grants` +
mandatory reason; NO public wrapper yet — Agent A must add one):**
`app.platform_admin_organization_overview(reason)`,
`app.platform_admin_get_organization(org_id, reason)`,
`app.platform_admin_recent_audit(reason, limit)` (RF-091, §4.18; **D-026**).

**Deferred / not in MVP:** card/online payments, tips (Q-011), service charge
(Q-012), refunds / post-completion voids (D-023/D-024), Realtime as a sole
source (D-010), hardware printing (D-009/Q-006/Q-015).
