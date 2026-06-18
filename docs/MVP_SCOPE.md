# MVP_SCOPE.md — RestoFlow MVP Scope (Candidate)

> **Status — DRAFT (candidate), not yet frozen.** Drafted by Claude Code (RF-001) · pending ChatGPT review · pending independent Codex review · pending human approval (Saleh). Only the explicit RF-001 invariants (below/where cited) are binding requirements; every other architectural choice is a **PROPOSED DECISION** pending review and human approval. Architecture freeze happens only after independent review, required fixes, and Saleh's approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> **Ownership.** This document is the single authoritative source for **what is IN and OUT of the RestoFlow MVP**. It owns the in-scope / deferred boundary and the scope guardrail. It does **not** redefine decisions ([DECISIONS.md](DECISIONS.md)), open questions ([OPEN_QUESTIONS.md](OPEN_QUESTIONS.md)), product vision/personas ([PRODUCT_SPEC.md](PRODUCT_SPEC.md)), milestones/timeline ([PROJECT_PLAN.md](PROJECT_PLAN.md)), or the ticket backlog ([IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) + JIRA_IMPORT.csv). Those topics are referenced, not restated.
>
> **Scope governance.** This scope boundary is part of the candidate set proposed for the **RF-004 architecture freeze** under milestone **M0A** (**DECISION D-019**, RF-001), pending review and approval; the freeze has **not** occurred yet. Changes require a new decision in [DECISIONS.md](DECISIONS.md) and human approval per the agent workflow (**DECISION D-016**).

---

## 1. Purpose

RestoFlow is a **multi-tenant Restaurant Operating System** serving many independent restaurant customers on one platform (**DECISION D-001**, **DECISION D-002**, **DECISION D-003**). This document fixes the functional boundary of the Minimum Viable Product so that:

- Every **IN-SCOPE** capability is committed to MVP delivery (milestones **M1–M3**, **DECISION D-019**) and maps to at least one ticket family.
- Every **DEFERRED** capability is explicitly out of MVP, mapped to **M4 or later/none**, and **must not leak into MVP tickets** (see §5 Scope Guardrail; **RISK R-004**).

The MVP is **not single-tenant**. Even though the first pilot ([PILOT_PLAN.md](PILOT_PLAN.md)) may run a single organization, restaurant, and branch, no schema, API, authorization policy, local store, or app architecture in the MVP may assume only one organization/restaurant exists (**DECISION D-001**, **DECISION D-003**).

---

## 2. IN SCOPE (MVP — must deliver)

Each item below is a checkable deliverable. Mechanics live in the owning specification documents (linked); this list defines only inclusion.

### 2.1 Tenancy, identity, and access
- [ ] **Multi-tenant architecture from the first migration** — `organization_id` present on every tenant-scoped row from migration #1; no retrofitting later (**DECISION D-001**; entities in [DOMAIN_MODEL.md](DOMAIN_MODEL.md)).
- [ ] **Organization → Restaurant → Branch hierarchy** — full hierarchy modelled even when an org owns exactly one restaurant/branch (**DECISION D-002**, **DECISION D-003**).
- [ ] **Owner / manager / cashier / kitchen permissions** — membership-scoped roles `org_owner`/`restaurant_owner`, `manager`, `cashier`, `kitchen_staff`; no shared accounts; roles never a permanent global field on the user (**DECISION D-004**, **DECISION D-005**; authorization in [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)).
- [ ] **Device enrollment + revocation** — device identity, expiring enrollment codes, device pairing lifecycle `code_issued → pending → paired → active → suspended → revoked` (+ `code_expired`, `rejected`), and revocation that removes **future** access including the offline window (**DECISION D-005**, **DECISION D-006**, **DECISION D-018**; **OPEN QUESTION Q-009**; **RISK R-007**).
  - **SECURITY REQUIREMENT**: no service-role credentials in Flutter clients; no shared restaurant password (**DECISION D-006**, **DECISION D-011**).

### 2.2 Menu
- [ ] **Menu categories** (`menu_categories`) — org/restaurant-scoped (**DECISION D-017**).
- [ ] **Menu items** (`menu_items`).
- [ ] **Sizes & variants** (`item_sizes`, `item_variants`).
- [ ] **Modifiers & extras** (`modifiers`, `modifier_options`).
- [ ] Menu pricing in **integer minor units** with **price snapshots captured at order time**; orders never recompute from live menu prices (**DECISION D-007**, **DECISION D-008**; rules in [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md)).

### 2.3 Ordering and tables
- [ ] **Dine-in & takeaway** order types — order lifecycle `draft → submitted → accepted → preparing → ready → served → completed`; takeaway skips `served` (`ready → completed`); plus `cancelled` and `voided` (**DECISION D-018**; transitions in [STATE_MACHINES.md](STATE_MACHINES.md)). `completed` is **TERMINAL** in MVP: `completed → voided` / `completed → cancelled` are **FORBIDDEN**, and cancelling/voiding an order that already has a **completed payment** is **REJECTED** (it would require the deferred refund flow) (**DECISION D-024**; payment & fulfillment are independent and pay-first is supported, **DECISION D-025**).
- [ ] **Basic table management** (`tables`) — assign/seat/free tables for dine-in; advanced floor-plan/reservation features are **DEFERRED** (see §3).
- [ ] **Fast cashier cart** — quick item add, size/variant/modifier selection, line edits before submission.
- [ ] **Order submission** — `draft → submitted` with item snapshots; idempotent (see §2.7).

### 2.4 Kitchen (KDS)
- [ ] **Routing items to kitchen stations** — order items routed to `stations`; produces `kitchen_tickets` and `kitchen_station_items`.
- [ ] **KDS states** — kitchen ticket `new → acknowledged → in_preparation → ready → bumped` (+ `recalled`, `cancelled`); kitchen station item `queued → in_preparation → ready → bumped` (+ `voided`); order item `pending → queued → preparing → ready → served` (+ `voided`, `cancelled`) (**DECISION D-018**; [STATE_MACHINES.md](STATE_MACHINES.md)).
- [ ] **Kitchen ticket printing** — print job lifecycle `created → queued → printing → printed` (+ `failed → retrying`, `cancelled`, `abandoned`) behind a replaceable ESC/POS adapter (**DECISION D-009**, **DECISION D-018**; printing in [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md); **OPEN QUESTION Q-015**; **RISK R-001**, **RISK R-006**).

### 2.5 Payments, shifts, and cash
- [ ] **Customer receipt printing** — localized receipts with Arabic/Hebrew/English encoding/raster fallback (**DECISION D-014**; [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md); **OPEN QUESTION Q-015**).
- [ ] **Cash payment** — payment lifecycle `pending → tendered → completed` (+ `voided`, `failed`); `completed` is **TERMINAL** — payment void is allowed **only pre-completion** (`pending → voided`, `tendered → voided`); `completed → voided` is **FORBIDDEN** (**DECISION D-023**). Refunds and any post-completion reversal are **DEFERRED** (no MVP refund; `refunded` state **DEFERRED**) (**DECISION D-018**, **DECISION D-023**). Online/card payments are **DEFERRED** (see §3).
- [ ] **Shift open/close** — shift lifecycle `opening → open → closing → closed → reconciled` (**DECISION D-018**).
- [ ] **Opening cash** — cash drawer session `opened(opening float) → active → counting → closed(counted+variance) → reconciled`, bound to a shift (**DECISION D-018**).
- [ ] **Cash reconciliation** — counted vs expected variance at close (**DECISION D-018**).
- [ ] **Receipt numbering** — per-branch monotonic server-assigned sequence; offline provisional id reconciled to authoritative on sync (**DECISION D-021**; [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md)).

### 2.6 Adjustments, audit, and reporting
- [ ] **Discounts** — order-level and item-level, percentage and fixed, with defined rounding (integer minor units, no floating point); rules owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) (**DECISION D-007**).
- [ ] **Voids with reason + authorization** — `voided` is post-submission, terminal, requires authorization and a reason; distinct from cancellation and refund (**DECISION D-018**; authorization in [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)). A void/cancel is **REJECTED** once a **completed payment** exists, because `completed` order and `completed` payment are terminal and post-completion reversal (refund) is **DEFERRED** (**DECISION D-023**, **DECISION D-024**).
- [ ] **Append-only audit trail** (`audit_events`) — actor, device, organization, restaurant, branch, timestamp, action, reason, old/new values; never updatable/deletable by app roles (**DECISION D-013**).
- [ ] **Basic daily reports** — per-branch daily sales, cash reconciliation summary, voids/discounts summary. Advanced analytics/dashboards are **DEFERRED** (see §3).

### 2.7 Cross-cutting platform capabilities
- [ ] **Offline-first** — SQLite/Drift local operational store; POS keeps working with no internet; local outbox + server inbox/processed-operation ledger; tombstones for deletions; reconciliation on reconnect; Supabase Realtime is enhancement only (**DECISION D-009**, **DECISION D-010**, **DECISION D-020**; rules in [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md); **RISK R-002**). Sync operation lifecycle `created → pending → in_flight → applied` (+ `rejected`, `dead`, `conflict → resolved`) (**DECISION D-018**). Per-entity conflict policy is **OPEN QUESTION Q-010**.
- [ ] **Idempotent mutations** — every mutating client op carries an idempotency key `device_id + local_operation_id`; duplicate submissions deduplicated server-side (**DECISION D-022**; [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md)).
- [ ] **ar / he / en + RTL/LTR** — Arabic, Hebrew, English with full right-to-left and left-to-right layout across POS/KDS surfaces (**DECISION D-014**).

---

## 3. DEFERRED (explicitly OUT of MVP)

Each item is **DEFERRED**. Target milestone is **M4 or later / none** (**DECISION D-019**). These must not appear in M1–M3 tickets (§5).

- **DEFERRED — Online payments** (card/wallet/gateway). MVP supports cash payment only. Maps to: M4.
- **DEFERRED — Delivery provider integrations** (aggregator/3rd-party delivery). Maps to: M4 or later.
- **DEFERRED — Advanced inventory** (stock counts, depletion, purchasing, recipes/BOM). Maps to: M4 or later.
- **DEFERRED — Loyalty** (points, rewards, customer profiles). Maps to: M4 or later.
- **DEFERRED — Customer mobile app**. Maps to: later / none for MVP.
- **DEFERRED — QR self-order** (table QR ordering). Maps to: M4 or later.
- **DEFERRED — Advanced reservations** (booking engine, waitlists, table-plan reservations). Basic table management only is in scope (§2.3). Maps to: later.
- **DEFERRED — Full accounting** (GL, exports to accounting systems). The read-only `accountant` role itself is **OPEN QUESTION Q-017** (ship in MVP or later). Maps to: M4 or later.
- **DEFERRED — Automated subscription billing** (self-serve SaaS billing). Billing model is **OPEN QUESTION Q-016**. Maps to: M4.
- **DEFERRED — Advanced multi-branch operational UI** (cross-branch consolidated operations console). The multi-tenant data model is in scope from migration #1 (§2.1); only the advanced operational UI is deferred. Maps to: M4 or later.
- **DEFERRED — Complex refunds** (partial/multi-tender refunds; payment `refunded` state) — until the payment model is frozen. Maps to: later (post payment-model freeze).
- **DEFERRED — Advanced tax / fiscal integrations** (certified fiscal devices, e-invoicing, statutory numbering) — until jurisdiction is confirmed (**OPEN QUESTION Q-001**, plus Q-002, Q-003, Q-004; **RISK R-008**). Money stays in integer minor units with tax rules kept open in [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md). Maps to: later.
- **DEFERRED — Tips** (Q-011) and **service charge** (Q-012) handling — flagged in [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md). Maps to: later.

---

## 4. IN-SCOPE → ticket-family / DEFERRED → milestone cross-check

The ticket backlog itself is owned by [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) + JIRA_IMPORT.csv. This table is a **traceability cross-check only**: every IN-SCOPE item maps to at least one M1–M3 ticket family; every DEFERRED item maps to M4 or later/none.

| IN-SCOPE item | Ticket family (indicative) | Milestone |
|---|---|---|
| Multi-tenant from first migration | tenancy-migrations | M0B→M2 |
| Org/Restaurant/Branch hierarchy | tenancy-model | M0B→M2 |
| Owner/manager/cashier/kitchen permissions | identity-access, rls-authz | M2 |
| Device enrollment + revocation | device-pairing | M2 |
| Menu categories / items / sizes & variants / modifiers & extras | menu-catalog | M1→M2 |
| Dine-in & takeaway | ordering-core | M1 |
| Basic table management | tables-basic | M1 |
| Fast cashier cart | pos-cart | M1 |
| Order submission | ordering-core, sync-outbox | M1→M2 |
| Routing items to kitchen stations | kds-routing | M1 |
| KDS states | kds-states | M1 |
| Kitchen ticket printing | printing-kds | M3 |
| Customer receipt printing | printing-receipt | M3 |
| Cash payment | payments-cash | M1→M2 |
| Shift open/close; opening cash; cash reconciliation | shifts-cash | M2→M3 |
| Discounts | money-discounts | M1→M2 |
| Voids with reason + authorization | void-authz, audit | M2 |
| Append-only audit trail | audit | M2 |
| Basic daily reports | reporting-daily | M3 |
| Offline-first | sync-outbox-inbox | M2 |
| Idempotent mutations | sync-idempotency | M2 |
| ar/he/en + RTL/LTR | l10n-rtl | M0B→M1 |

| DEFERRED item | Milestone |
|---|---|
| Online payments | M4 |
| Delivery provider integrations | M4 or later |
| Advanced inventory | M4 or later |
| Loyalty | M4 or later |
| Customer mobile app | later / none |
| QR self-order | M4 or later |
| Advanced reservations | later |
| Full accounting (and Q-017 accountant role) | M4 or later |
| Automated subscription billing (Q-016) | M4 |
| Advanced multi-branch operational UI | M4 or later |
| Complex refunds | later (post payment-model freeze) |
| Advanced tax/fiscal integrations (Q-001) | later |
| Tips (Q-011) / service charge (Q-012) | later |

> Milestone placements above are **indicative** and defer to [PROJECT_PLAN.md](PROJECT_PLAN.md) and the backlog if they diverge; they exist to prove every IN-SCOPE item has an M1–M3 home and every DEFERRED item is M4+/none.

---

## 5. Scope guardrail (RISK R-004)

**Deferred items must NOT leak into MVP tickets.** This is the primary mitigation for scope creep (**RISK R-004**) and supports the single-builder bus-factor risk (**RISK R-005**).

- No M1–M3 ticket may implement, partially scaffold, or add schema/columns/UI dedicated to a §3 DEFERRED capability. Forward-compatible neutral design (e.g. integer minor-unit money, multi-tenant keys) is allowed; deferred-feature-specific work is not.
- Any proposal to pull a DEFERRED item into the MVP requires a new **DECISION D-xxx** in [DECISIONS.md](DECISIONS.md) and human approval (**DECISION D-016**); it is a **silent scope expansion** violation otherwise.
- Reviewers (Codex) should reject MVP tickets/PRs whose scope touches §3 items without such a decision.
- **ASSUMPTION**: the §2 list is complete for MVP; any capability not listed in §2 is treated as out of MVP by default and must be added via a decision before implementation.

---

## 6. Related documents

[DECISIONS.md](DECISIONS.md) · [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) · [PRODUCT_SPEC.md](PRODUCT_SPEC.md) · [DOMAIN_MODEL.md](DOMAIN_MODEL.md) · [STATE_MACHINES.md](STATE_MACHINES.md) · [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) · [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) · [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) · [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md) · [API_CONTRACT.md](API_CONTRACT.md) · [TESTING_STRATEGY.md](TESTING_STRATEGY.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [PROJECT_PLAN.md](PROJECT_PLAN.md) · [IMPLEMENTATION_CHECKLIST.md](IMPLEMENTATION_CHECKLIST.md) · [PILOT_PLAN.md](PILOT_PLAN.md) · [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md)
