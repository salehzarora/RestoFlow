# TESTING_STRATEGY.md — RestoFlow Test Strategy

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

**Status:** FROZEN for M0A (RF-001), frozen as the M0A architecture baseline at RF-004 (approved into the frozen M0A baseline (RF-004)). **Owner doc:** This document owns the RestoFlow testing strategy.
**Authoritative cross-references (reference, never redefine):**
[SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) (source of the isolation/permission cases and RLS model),
[STATE_MACHINES.md](STATE_MACHINES.md) (source of every transition table),
[DOMAIN_MODEL.md](DOMAIN_MODEL.md) (entities/fields),
[MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) (money/tax/receipt rules),
[OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) (sync rules),
[API_CONTRACT.md](API_CONTRACT.md) (RPC/endpoint contracts),
[DECISIONS.md](DECISIONS.md) (D-xxx), [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) (Q-xxx).

This document defines WHAT must be tested, WHERE each test lives, and WHICH tests gate a merge. It does not implement tests (M0A is documentation-only) and does not redefine the contracts it tests — it points at the owning documents.

---

## 0. Principles

- **DECISION D-016**: every test is associated with a ticket (RF-`<number>`); Codex reviews are read-only; Claude Code and Codex never edit the same working tree simultaneously. Test code follows the same branch/worktree rules as production code.
- **SECURITY REQUIREMENT**: the tenant-isolation and permission suite (Section 2) is a **hard merge gate**. A red isolation test blocks merge with no override by an agent; only the human owner may waive, and a waiver is itself an audited event.
- **Deny-by-default**: tests assert that the absence of an explicit grant produces denial, never accidental access. This applies to RLS, RPC authorization, and membership/scope checks alike (the four layers of **DECISION D-012**).
- **No floating point anywhere** (**DECISION D-007**): money tests assert integer minor-unit arithmetic end to end; a test that introduces a `double`/`float` for money is itself a defect.
- **Multi-tenant always** (**DECISION D-001/D-002/D-003**): every layer's fixtures seed **at least two organizations**, and where relevant two restaurants and two branches under one organization. No test may assume a single organization, restaurant, or branch.
- **No shared accounts** (**DECISION D-004**): test actors are always individual identities with membership-scoped roles; PIN sessions exist only on paired+authorized devices (**DECISION D-005/D-006**).
- Tests are **deterministic**: fixed seeds, injected clocks, no reliance on wall-clock or network timing. Sync/offline tests inject both client and server clocks.

---

## 1. Test pyramid — what lives where

We use a conventional pyramid: many fast unit tests, fewer widget tests, fewer integration/contract tests, very few end-to-end tests. Each layer has a clear home in the **DECISION D-009** stack (Flutter/Dart, Drift/SQLite, Supabase/PostgreSQL, RLS, RPC).

| Layer | Scope / SUT | Runs against | Speed | Primary owners of the rules tested |
|---|---|---|---|---|
| **Unit** | Pure Dart domain logic: money math, discount precedence, rounding, state-transition guards, idempotency-key construction, conflict-resolution functions, mapping/serialization. No I/O. | In-memory, injected clock/RNG | ms | [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md), [STATE_MACHINES.md](STATE_MACHINES.md), [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) |
| **Widget** | Flutter UI components/screens in isolation: POS cart, KDS ticket tile, sync-status indicator, RTL/LTR layout, ar/he/en localization (**DECISION D-014**). | Flutter test harness, mocked providers (Riverpod) | ms–s | [PRODUCT_SPEC.md](PRODUCT_SPEC.md), [ARCHITECTURE.md](ARCHITECTURE.md) |
| **Integration (local)** | Repository + Drift/SQLite + outbox/inbox wiring; offline ops, crash recovery, replay. No real backend (M1-style). | Real local SQLite (Drift), fake/in-memory server | s | [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) |
| **Integration (backend)** | PostgreSQL RLS policies, RPC (SECURITY DEFINER) functions, DB constraints, audit-event writes. | Real PostgreSQL (Supabase project/branch) with seeded multi-org data | s–min | [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) |
| **Contract** | Each RPC's request/response/error/authorization contract; idempotency-key handling; receipt-number assignment contract. | Real PostgreSQL RPC behind the documented signature | s | [API_CONTRACT.md](API_CONTRACT.md) |
| **End-to-end (e2e)** | Thin set of full-flow journeys spanning client + sync + backend: place order offline → reconnect → reconcile → pay → receipt; KDS bump; shift open/close. | App build + real backend (test project) | min | [ARCHITECTURE.md](ARCHITECTURE.md), [PILOT_PLAN.md](PILOT_PLAN.md) |

**ASSUMPTION:** backend integration/contract/RLS tests run against an ephemeral Supabase branch (or local Supabase stack) seeded fresh per run; they never touch a shared or production database (**DECISION D-016** forbids database reset/production changes — test infra uses throwaway databases instead).

**DEFERRED:** load/performance testing, chaos/network-fault injection at scale, and certified fiscal-device conformance testing are out of MVP test scope; flagged for later (fiscal depends on Q-001..Q-004).

---

## 2. MANDATORY tenant-isolation & permission tests (HARD MERGE GATE)

These restate the canonical isolation cases owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) as concrete automated tests. They run at the **backend integration** layer (RLS + RPC + constraints) and, where a client path exists, are mirrored at integration level. **SECURITY REQUIREMENT:** all of these must be green to merge; this suite directly mitigates **RISK R-003** (RLS cross-tenant leak — CRITICAL) and **RISK R-007** (offline authorization staleness).

Common fixture (`seed_isolation`): Organization **Org-A** and Organization **Org-B**; under Org-A, Restaurant **R-A1** with Branch **B-A1a** and Restaurant **R-A2** with Branch **B-A2a**; under Org-B, Restaurant **R-B1**/Branch **B-B1a**. Individual users with membership-scoped roles (`org_owner`, `manager`, `cashier`, `kitchen_staff`, and `accountant` pending **Q-017**). Platform admin is **not** a membership role (**DECISION D-026**): the fixture models it via a separate `platform_admin_grants` grant ([DOMAIN_MODEL.md](DOMAIN_MODEL.md) §3.7) on a principal that holds **no** tenant membership and carries **no** `organization_id` — never as a `platform_admin` membership row. Registered devices/stations per branch. Orders, payments, and financial report rows seeded in each org.

| Test ID (suite) | Canonical case | Concrete assertion | Layer(s) |
|---|---|---|---|
| `iso_org_read` | Org A cannot read Org B orders | A user whose only membership is in Org-A queries `orders`; rows scoped to Org-B return **zero rows** (RLS deny), and direct fetch by Org-B `order.id` (IDOR attempt) returns **not found / denied**, not the row. | RLS + RPC |
| `iso_cross_restaurant_write` | Cashier cannot modify another restaurant | A `cashier` scoped to R-A1/B-A1a attempts to mutate an order in R-A2 (same org) and in R-B1 (other org); both are **rejected** by scope check + RLS, with no row change and an audit entry for the denied sensitive attempt. | RLS + RPC + scope |
| `iso_kds_no_finance` | KDS cannot read financial reports | A device identity / `kitchen_staff` PIN session queries financial report data (totals, payments, takings); result is **denied / empty**. KDS-scoped roles have no grant to money-bearing aggregates. | RLS + RPC |
| `iso_revoked_device_sync` | Revoked device cannot sync new operations | A device whose `device_pairings` state is `revoked` (terminal, per **DECISION D-018**) submits a `sync_operations` batch; server **rejects** all ops (permanent), writes an audit event, and applies nothing. | RPC + RLS |
| `iso_removed_employee_ops` | Removed employee cannot create valid ops | An employee whose membership/`employee_profiles` employment status is terminated submits an op; server **rejects**; mitigates **RISK R-007**; cross-check with offline window **Q-009**. | RPC + RLS |
| `iso_void_paid_unauthorized` | Cashier cannot void a paid order without permission | A `cashier` lacking void permission calls the void RPC on a paid order; RPC **denies** with authorization error; order/payment state unchanged; denied attempt is audited. With the void permission, voiding an order that has a **completed** payment is **still rejected** (**DECISION D-024**: completed orders are terminal and a chargeable order with a completed payment cannot be voided/cancelled; refunds are **DEFERRED** per **DECISION D-023**) — the test asserts no `completed → voided` transition occurs. Authorized void succeeds **only** on a pre-completion order with no completed payment, transitioning order → `voided` (terminal) and recording actor + **reason** (**DECISION D-013**). | RPC + state |
| `iso_platform_admin_audited` | Platform-admin access is explicitly audited | Every platform-admin (via `platform_admin_grants`, **not** a membership role — **DECISION D-026**) cross-tenant access goes through the separate platform path and **emits an append-only `audit_events` row** (actor, device, org/restaurant/branch, timestamp, action, reason, old/new values). Test asserts the audit row exists and is **not updatable/deletable** by app roles. | RPC + audit |
| `iso_idempotency_replay_reject` | Replayed/duplicated op is rejected as a duplicate (no double effect) | A submitted op replayed with the same idempotency key (`device_id` + `local_operation_id`) is recognized by the server inbox/processed-operation ledger and the **original outcome is re-returned with no second effect**; N submissions yield exactly one effect. This is the mandatory-gate counterpart of the Section-5 idempotency/replay test (**DECISION D-022**) and is the cross-link target for **SECURITY TH-4** (replay/duplicate-submission threat). | RPC + RLS |

Additional deny-by-default isolation assertions (same fixture):
- A user with **no** membership in any org sees **zero** tenant-scoped rows across all tables.
- A `manager` scoped to B-A1a cannot read/modify B-A2a data unless an explicit branch-scoped membership grants it.
- An `accountant` (if shipped — **Q-017**) is **strictly read-only** (**DECISION D-028**): **any** mutating RPC is denied — including `close_shift` and `reconcile_shift`, void, discount, and grant changes — and no state changes (see T-011 below and Section 7).
- Audit-event tables reject UPDATE/DELETE from all application roles (**DECISION D-013**).

**Platform-plane separation tests (mandatory gate, T-008..T-011 — owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) Section 14, **DECISION D-026/D-028**).** This gate enumerates and runs the four canonical platform/accountant cases (the SECURITY document owns their full definitions; restated here as concrete tests):
- **T-008 — Membership cannot grant platform-admin.** No tenant membership (any role, any scope, any combination) confers platform-admin authority; a principal holding only org memberships cannot invoke the platform-admin path. (**DECISION D-026**)
- **T-009 — Platform-admin grant is not an org membership.** A `platform_admin_grants` row carries **no `organization_id`**, never satisfies tenant RLS membership predicates, and grants no tenant-scoped read/write through the normal app surface. (**DECISION D-026**)
- **T-010 — Platform-admin operations enforce the privileged path / cannot bypass tenant RLS.** A platform-admin actor cannot read or mutate tenant data via the normal tenant code path; the four defence layers and tenant RLS are not bypassed; legitimate access occurs only via the separate, time-bounded, reason-tagged privileged path. (**DECISION D-026**, **DECISION D-012**)
- **T-011 — Accountant strictly read-only; reconciliation is privileged.** An `accountant` invoking **any** mutating RPC (including `reconcile_shift`, `close_shift`, void, discount, grant changes) is **denied** with no state change; `reconcile_shift` (closed → reconciled) succeeds only for `manager`/`restaurant_owner`/`org_owner`, separately from the cashier's `close_shift` close/count; denied attempts are audited. (**DECISION D-028**, **DECISION D-012/D-013**)

**PROVISIONAL (pending Q-008):** MFA enforcement tests are provisional until the MFA method is decided (**Q-008**). At minimum the suite carries a role-driven placeholder assertion — **`mfa_required_for_privileged_role`**: a privileged actor (e.g. `org_owner`/`manager`, or a platform admin holding a `platform_admin_grants` grant — not a membership role, **DECISION D-026**) for whom MFA is required cannot complete a privileged action without a satisfied MFA factor. The concrete factor and enforcement points stay open and the assertion is non-blocking until **Q-008** resolves; it is enumerated here so the gate has a hook to tighten once the method is chosen.

---

## 3. State-machine tests

[STATE_MACHINES.md](STATE_MACHINES.md) owns the transition tables; this section defines the test pattern applied to **every** PROPOSED state machine in **DECISION D-018** (state enumerations are PROPOSED, approved into the frozen M0A baseline (RF-004); RF-001 §8 directs us to evaluate, not assume final). For each machine we run a **transition matrix test**: for every (state × event) pair, assert the result is exactly the documented next state **or** an explicit rejection — there is no third outcome and no undocumented transition is silently allowed.

Pattern (per machine):
1. **Allowed transitions pass**: each documented edge moves source → target and emits the required side effects (e.g. void requires authorization + reason and an audit event).
2. **Forbidden transitions are rejected**: every (state, event) pair not in the table raises a domain error and leaves state unchanged.
3. **Terminal states are sinks**: no event moves a row out of a terminal state.
4. **Guards enforced**: transitions with conditions (authorization, reason, takeaway routing) fail closed when the guard is unmet.

Machines covered (PROPOSED enumerations from **DECISION D-018**, approved into the frozen M0A baseline (RF-004)):

| Machine | Notable assertions |
|---|---|
| **Order** | `draft→submitted→accepted→preparing→ready→served→completed`; takeaway skips `served` (`ready→completed`); `cancelled` only pre-production (terminal); `voided` only post-submission, requires authorization + reason (terminal). `completed` is **terminal** (**DECISION D-024**): assert `completed→voided` and `completed→cancelled` are **rejected** (no test may expect a paid-order void after completion). Assert a pre-completion `cancel`/`void` is **rejected when a completed payment exists** (**DECISION D-024**: a chargeable order with a completed payment cannot be cancelled/voided). Terminal set {`completed`,`cancelled`,`voided`} is a sink. |
| **Order item** | `pending→queued→preparing→ready→served`; plus `voided`,`cancelled` terminal. |
| **Kitchen ticket** | `new→acknowledged→in_preparation→ready→bumped`; `recalled` (`bumped→in_preparation`) is **audited**; `cancelled`. Terminal {`bumped`,`cancelled`}. |
| **Kitchen station item** | `queued→in_preparation→ready→bumped`; plus `voided`. Terminal {`bumped`,`voided`}. |
| **Payment** | `pending→tendered→completed`; plus `voided`,`failed`. `completed` is **terminal** (**DECISION D-023**): assert `completed→voided` is **not reachable** (rejected), so a completed payment can never be voided; valid voids are only `pending→voided` and `tendered→voided` (pre-completion). `refunded` is **DEFERRED** (**DECISION D-023**; **Q-011** context) — test asserts the state is not reachable in MVP. Terminal {`completed`,`voided`,`failed`}. |
| **Shift** | `opening→open→closing→closed→reconciled`. Terminal {`reconciled`}. |
| **Cash drawer session** | `opened(opening float)→active→counting→closed(counted+variance)→reconciled`; bound to a shift (test asserts the binding). Terminal {`reconciled`}. |
| **Print job** | `created→queued→printing→printed`; `failed→retrying`; `cancelled`; `abandoned` after max retries. Terminal {`printed`,`cancelled`,`abandoned`}. |
| **Device pairing** | `code_issued→pending→paired→active→suspended→revoked`; plus `code_expired`,`rejected`. Terminal {`revoked`,`code_expired`,`rejected`}. Enrollment codes expire (test the expiry edge). |
| **Sync operation** | `created→pending→in_flight→applied`; `rejected`(permanent); `dead`(poison after max retries); `conflict→resolved`. Terminal {`applied`,`rejected`,`dead`}. |

**Payment / fulfillment independence (DECISION D-025).** Payment and fulfillment are **independent** axes; a dedicated cross-machine test asserts:
- **Pay-first is supported**: a cash payment may be `tendered` then `completed` while the order is in `submitted`/`accepted`/`preparing` (i.e. not requiring `ready`/`served`).
- **Payment completion does not advance fulfillment**: completing a payment leaves the order's fulfillment state unchanged (no implicit `→ready`/`→served`/`→completed`).
- **Order completion is gated on both**: an order reaches `completed` only when fulfillment is satisfied **and** (for a chargeable order) payment is `completed`.
- **Eligible payment-start states**: starting a payment is **rejected** when the order is in `draft`, `cancelled`, `voided`, or `completed`; permitted only from `submitted`/`accepted`/`preparing`/`ready`/`served`.

State-machine guard tests are pure **unit** tests; their integration counterparts (Section 2/5) verify the same guards survive the RPC + RLS layers.

---

## 4. Money tests

[MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) owns the rules; these tests enforce them. **DECISION D-007** (integer minor units, no float, currency per org), **DECISION D-008** (price/modifier snapshots at order time), **DECISION D-021/D-022** (receipt numbering, idempotency).

- **Integer-only / no float**: all money values are integers in `_minor` columns and Dart `int`. A static/unit check asserts no `double`/`num`-as-float flows through money paths. Serialization (sync payloads, RPC JSON) carries money as integers; a test round-trips and asserts no float coercion.
- **Rounding**: rounding occurs only where the spec defines it and uses the spec's rule on integer minor units; assert no intermediate float rounding. Tax/rounding edge values stay **OPEN** pending jurisdiction (**Q-001/Q-002**) and so are tested against the spec's currently-documented (proposed, pending review) rule set only (**RISK R-008**).
- **Discount precedence**: order-level vs item-level, percentage vs fixed, applied in the spec's defined order; test fixed worked examples and assert deterministic integer results.
- **Price snapshots (D-008)**: changing a live `menu_items`/`modifier_options` price after an order is created does **not** change that order's totals; order recomputes only from snapshots.
- **Single currency per order (Q-007)**: an order mixing currencies is rejected; currency resolves org → restaurant override.
- **Totals worked example** (illustrative, integer minor units, currency per org): item 1 200 (×2 = 2 400) + item 850, item-level fixed discount 100 on the second item → line subtotal 2 400 + 750 = 3 150; order-level 10% discount → 315 off → 2 835; tax (rate **OPEN**, **Q-002**) applied per spec. Each step asserts integer arithmetic and the documented precedence.
- **Receipt numbering monotonic per branch (D-021)**: assigned sequence is strictly increasing **per `branch_id`**, server-authoritative; an offline provisional id is reconciled to the authoritative number on sync without gaps that violate the spec's rules; two branches have **independent** sequences; concurrent assignment never duplicates a number.

---

## 5. Offline / sync tests

[OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) owns the rules; tests cover idempotency, dedupe, ordering, recovery, poison handling, revoked-actor rejection, and conflicts. Mitigates **RISK R-002** (sync conflicts/duplicates) and **RISK R-007**. **DECISION D-010/D-020/D-022**.

- **Idempotency / replay (D-022)**: replaying an op with the same idempotency key (`device_id` + `local_operation_id`) produces **no duplicate** — server inbox/processed-operation ledger returns the prior result; assert exactly one effect for N submissions.
- **Outbox/inbox dedupe**: a local outbox entry retried after a flaky ack is processed **once**; the server inbox recognizes the duplicate and re-returns the original outcome.
- **Ordering of dependent ops**: dependent operations (e.g. create order → add item → pay) apply in dependency order even when delivered out of order or batched; a payment for a not-yet-applied order is held/ordered correctly, never applied against a missing parent.
- **Crash recovery**: simulate process kill mid-flush; on restart no op is lost and none is double-applied (outbox + idempotency guarantee). Drift store reopens consistently.
- **Poison-op handling**: an op that permanently fails transitions `sync_operation` → `dead` after max retries (per **DECISION D-018**), is quarantined, surfaced to the cashier, and does **not** block subsequent healthy ops.
- **Revoked-actor-offline rejection (R-007)**: ops created on a device while offline by a since-revoked device or removed employee are **rejected** on reconnect (server is authoritative); cross-references offline validity window **Q-009**; nothing is applied; rejection is audited.
- **Conflict resolution**: multi-device conflicting edits resolve per the per-entity policy — which is **OPEN QUESTION Q-010** (LWW vs domain rules). Tests assert the spec's currently-documented rule per entity and explicitly mark entities whose policy is still **Q-010-pending** so the suite fails loudly if an undocumented policy is assumed.
- **Tombstones (D-020)**: a sync-relevant delete propagates as a `deleted_at` tombstone, not a hard delete; replaying a delete is idempotent.
- **Realtime is enhancement only (D-010)**: a test disables Realtime entirely and asserts the outbox/inbox path still converges — Realtime is never the source of truth or the only sync mechanism.
- **Sync status visibility**: cashier-facing sync status reflects pending/in_flight/applied/rejected/dead accurately (widget + integration).

---

## 6. RLS test harness approach

[SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) owns the RLS model; this is the harness that proves it. **DECISION D-011/D-012**, mitigates **RISK R-003** (CRITICAL).

- **Seed multiple orgs**: reuse `seed_isolation` (Org-A with two restaurants/branches, Org-B). Every RLS test runs with at least two organizations present so a passing query must be actively scoped, not merely "the only data".
- **Run as real principals**: tests execute SQL under the same role/JWT/`organization_id` claims the app uses (not as a superuser/service role). **SECURITY REQUIREMENT:** the service-role key is never used by tests that assert policy behavior, mirroring the client constraint that no service-role credential ships in Flutter (**DECISION D-011**).
- **Deny-by-default assertions**: for every tenant-scoped table, assert (a) in-scope rows are visible, (b) out-of-scope rows return **zero rows** on SELECT, (c) cross-tenant INSERT/UPDATE/DELETE are blocked, (d) IDOR-by-id returns nothing. A newly added table with no policy must **fail** the harness (default-deny presence check), preventing accidentally unguarded tables.
- **Constraint backstop (layer 4)**: tests confirm DB constraints reject malformed/cross-tenant rows even if a higher layer were bypassed (e.g. `organization_id` mismatch between parent and child rows).
- **Audit immutability**: assert `audit_events` is append-only for app roles (no UPDATE/DELETE) (**DECISION D-013**).

---

## 7. Contract tests for each RPC

[API_CONTRACT.md](API_CONTRACT.md) owns the RPC signatures; contract tests pin each sensitive-mutation RPC (**DECISION D-011/D-012**). For **every** RPC, assert:

1. **Authorization**: callers without the required membership/role/scope are denied; callers with it succeed (deny-by-default).
2. **Input/output shape**: request and response match the documented contract, including money as integer `_minor` and enums from **DECISION D-018**.
3. **Idempotency (D-022)**: passing the same `device_id` + `local_operation_id` twice yields one effect and a consistent response.
4. **Error contract**: documented error codes/reasons returned for invalid input, forbidden action, conflict, and not-found (IDOR → not-found, never leak existence).
5. **Audit side effect (D-013)**: sensitive mutations write an append-only audit row with actor/device/org/restaurant/branch/timestamp/action/reason/old/new.
6. **State legality**: the RPC only performs transitions legal in [STATE_MACHINES.md](STATE_MACHINES.md) (e.g. void RPC ↔ order `voided` rules).

RPC families to cover (final list owned by [API_CONTRACT.md](API_CONTRACT.md)): order create/submit/accept/void/cancel; order-item add/void; payment tender/complete/void; receipt-number assignment; shift open/close/reconcile; cash-drawer open/count/close/reconcile; device pairing/enrollment/revoke; PIN-session establish; sync-operation submit/apply; print-job lifecycle.

**Shift close vs reconcile are separate RPCs (DECISION D-028).** Contract tests assert `close_shift` and `reconcile_shift` are **distinct operations** and neither performs the other:
- `close_shift` (shift close + cash count) is authorized for `cashier` / authorized `manager`; it performs **only** the close/count and does **not** reconcile (no `closed → reconciled` transition).
- `reconcile_shift` (closed → reconciled) is a privileged mutation authorized **only** for `manager` / `restaurant_owner` / `org_owner`; it does **not** perform the cashier's close/count.
- An `accountant` is denied **both** (strictly read-only — **DECISION D-028**; cross-ref Section 2, T-011).

**ASSUMPTION:** contract tests are versioned with the API_CONTRACT; any change to an RPC contract requires a dedicated ticket (**DECISION D-016**) and updates the matching contract test in the same change.

---

## 8. CI gates and coverage expectations

**DECISION D-009** (GitHub Actions CI), **DECISION D-015** (Git = source of truth for code; Jira = task status), **DECISION D-016** (workflow/guardrails).

### Hard gates — a red result BLOCKS merge
1. **Tenant-isolation & permission suite (Section 2)** — non-negotiable; **SECURITY REQUIREMENT**; only the human owner may waive, audited (**RISK R-003**). Includes `iso_idempotency_replay_reject` (replay/duplicate rejection, cross-linked to **SECURITY TH-4**).
2. **RLS harness (Section 6)** including the default-deny presence check for new tables.
3. **State-machine matrix tests (Section 3)** for all machines in **DECISION D-018**.
4. **Money tests (Section 4)** including the no-float check and receipt-number monotonicity-per-branch.
5. **Offline/sync core tests (Section 5)**: idempotency/replay, dedupe, crash recovery, poison-op, revoked-actor-offline.
6. **Contract tests (Section 7)** for every RPC touched by the change (and the full set on the main branch).
7. **Static analysis / lint / format** clean; build succeeds for all packages in the Melos monorepo.
8. **l10n/RTL smoke** for ar/he/en where UI changed (**DECISION D-014**).

### Workflow gates (process, not a test runner)
- Every change carries a ticket ID (**DECISION D-016**); no agent push without human approval; no force push / no `reset --hard` / no database reset / no production change.
- Codex independent review is required before Ready-for-Merge; Codex is read-only.

### Coverage expectations (DECISION-candidates — to be ratified)
- **ASSUMPTION (DECISION-candidate):** the tenant-isolation, RLS, state-machine, money, and sync suites must cover **100% of the enumerated canonical cases and transition edges** — these are checklist-complete, not percentage-based. This is the gating notion of "coverage" for safety-critical areas.
- **ASSUMPTION (DECISION-candidate):** line/branch coverage targets for general domain code — proposed floor **80%** on `packages/*` domain logic, with money and sync modules expected near-100% — pending owner ratification into [DECISIONS.md](DECISIONS.md). Until ratified, coverage is **reported** in CI but the percentage threshold is non-blocking; the checklist-complete safety suites above are blocking regardless.
- **OPEN QUESTION:** exact numeric coverage thresholds and whether they block merge — to be raised for a decision ID; cross-reference [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) for the ticket.

### Test data and environments
- **ASSUMPTION:** backend suites run on an ephemeral Supabase branch or local stack seeded per run and torn down after; never a shared/production DB (consistent with **DECISION D-016** prohibitions). Mitigates **RISK R-005** by making the suite reproducible by any single builder.

---

## 9. Traceability

- Canonical isolation cases ← [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) (Section 2, 6).
- Transition tables ← [STATE_MACHINES.md](STATE_MACHINES.md) (Section 3).
- Money/receipt rules ← [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) (Section 4).
- Sync rules ← [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) (Section 5).
- RPC contracts ← [API_CONTRACT.md](API_CONTRACT.md) (Section 7).
- Decisions/questions ← [DECISIONS.md](DECISIONS.md) / [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

Open questions touching testing: **Q-009** (offline validity window — drives revoked-actor-offline tests), **Q-010** (per-entity conflict policy — drives conflict tests), **Q-001/Q-002/Q-004** (jurisdiction/tax/receipt rules — keep tax/rounding/receipt-format tests provisional, **RISK R-008**), **Q-017** (accountant role inclusion). Risks driving the gate: **R-002, R-003, R-005, R-007, R-008**.
