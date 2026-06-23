# API_CONTRACT.md — RestoFlow RPC & Endpoint Contracts

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

**Status:** FROZEN for M0A (RF-001), frozen as the M0A architecture baseline at RF-004 approved into the frozen M0A baseline (RF-004). Documentation only — no implementation in this milestone.
**Owns:** RPC and endpoint contracts (names, fields, semantics). This document is the authoritative source of truth for the *shape and meaning* of every sensitive-mutation call between RestoFlow clients and the backend.
**Does NOT own:** entity field definitions ([DOMAIN_MODEL](DOMAIN_MODEL.md)), allowed status transitions ([STATE_MACHINES](STATE_MACHINES.md)), authorization rules and isolation tests ([SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)), money/tax/receipt arithmetic ([MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md)), sync mechanics ([OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md)), decisions ([DECISIONS](DECISIONS.md)), or open questions ([OPEN_QUESTIONS](OPEN_QUESTIONS.md)). This document references those; it does not redefine them.

> RestoFlow is a multi-tenant Restaurant Operating System. The tenant is the **Organization** (**DECISION D-003**). No contract in this document may assume a single organization, restaurant, or branch exists. No contract accepts a tenant identity or a role from the client as trusted input — tenant context and authorization are always derived server-side from the authenticated principal.

---

## 1. Principles

These principles are binding on every contract in this document.

### 1.1 Sensitive mutations go through PostgreSQL RPC
**DECISION D-011.** All sensitive mutations (anything that creates money, changes order/payment state, voids, opens/closes shifts, pairs/revokes devices, revokes employees, or establishes PIN sessions) are exposed **only** as PostgreSQL RPC functions written as `SECURITY DEFINER`. Each RPC is responsible for, in order:
1. Resolving the authenticated principal (human user, device identity, or PIN session — see [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) and the six identity concepts in **DECISION D-005**).
2. Deriving the tenant context (`organization_id`, and `restaurant_id` / `branch_id` / `device_id` / `station_id` where relevant) server-side.
3. Authorizing the action against the caller's **membership-scoped** role(s) (**DECISION D-004**), never against a global role on the user.
4. Validating inputs and current entity state against [STATE_MACHINES](STATE_MACHINES.md).
5. Performing the mutation under the four security layers (**DECISION D-012**: RLS / membership+scope / RPC / DB constraints).
6. Writing an append-only audit event (**DECISION D-013**).
7. Returning the new authoritative `revision` and any server-assigned identifiers.

**SECURITY REQUIREMENT:** No service-role key, admin key, or shared secret is ever embedded in or reachable by a Flutter client (**DECISION D-011**). Clients authenticate as a user, a device identity, or a PIN session only.

### 1.2 Tables are read-mostly via RLS
Reads of tenant-scoped tables are served through PostgreSQL Row-Level Security policies (**DECISION D-012**). Clients **never** issue direct table writes for sensitive entities; those go through RPC. Direct table reads are permitted only where RLS guarantees tenant isolation. The authoritative RLS policy definitions and the mandatory isolation tests live in [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md). **RISK R-003** (an RLS bug leaks cross-tenant data) is CRITICAL and gated by those tests.

### 1.3 All mutations are idempotent
**DECISION D-022.** Every mutating call carries an **idempotency key** composed of `device_id` + `local_operation_id`. The server maintains a processed-operation ledger (see [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md)). A replay of the same key returns the original result (the same server identifiers and the same `revision`) without re-applying the mutation. This is the foundation for safe offline retry and crash recovery (**DECISION D-010**).

### 1.4 Money is integer minor units
**DECISION D-007.** Every money field in every request and response is an integer in **minor units** (e.g. agorot/cents), with a column/field name suffixed `_minor`. There is **no floating point** for money anywhere in a request, response, or sync payload. Money arithmetic, rounding, discounts, and tax are owned by [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md); this document only carries the integer fields. Currency is per organization (overridable per restaurant) — see **OPEN QUESTION Q-007**.

### 1.5 Tenant context is derived, never trusted
Every RPC derives `organization_id` (the primary isolation boundary, **DECISION D-001**) from the authenticated principal and validates that the target rows belong to that organization. Where the client *does* supply `restaurant_id` / `branch_id` / `device_id` / `station_id`, the server treats them as a **selection** (which of the caller's authorized scopes to act in), never as an authorization grant: the server verifies the principal has a membership/scope that covers them. A request whose target rows resolve to a different organization fails with `tenant_isolation` (see §2) and is audited as an isolation violation.

### 1.6 Envelope shape
Every RPC accepts a common envelope alongside its specific payload:

```
{
  "idempotency": { "device_id": "<uuid>", "local_operation_id": "<uuid>" },  // D-022
  "context":     { "organization_id": "<uuid>",        // selection, re-verified server-side (§1.5)
                   "restaurant_id":   "<uuid|null>",
                   "branch_id":       "<uuid|null>",
                   "station_id":      "<uuid|null>" },  // note: device_id is NOT in context (see below)
  "client_ts":   "<iso8601>",                           // informational; server stamps authoritative time
  "expected_revision": <int|null>,                      // optimistic concurrency, where applicable
  "payload":     { ... }                                // RPC-specific
}
```

> **NOTE:** `device_id` is conveyed via the authenticated **device session** and the `idempotency` block (`idempotency.device_id`), not via the `context` selection object. The `context` object carries only the tenant-scope selection (`organization_id` / `restaurant_id` / `branch_id` / `station_id`) that §1.5 re-verifies server-side; the device identity is established by the session and the idempotency key, keeping the §1.5 prose and this §1.6 envelope consistent.

Every successful response carries:

```
{
  "ok": true,
  "revision": <int>,                 // new authoritative revision of the primary affected entity
  "server_ts": "<iso8601>",          // authoritative server timestamp
  "ids": { ... },                    // any server-assigned identifiers (e.g. authoritative receipt_number)
  "idempotency_replay": <bool>       // true if this was a replay (§1.3)
}
```

> **ASSUMPTION:** field names above are illustrative contract shapes for M0A; exact JSON wire encoding is finalized in M0B alongside the first migrations, but the *semantics* (idempotency key, derived tenant context, integer `_minor`, returned `revision`) are frozen as the M0A baseline at RF-004.

---

## 2. Error Model

Every RPC returns errors in a single consistent shape. Errors are **typed** by a stable `code`; clients branch on `code`, never on human-readable `message`.

```
{
  "ok": false,
  "error": {
    "code": "<error_code>",       // stable, enumerated below
    "message": "<human readable, localizable key>",
    "retryable": <bool>,          // whether a later retry could succeed unchanged
    "details": { ... }            // code-specific, e.g. server_revision on conflict
  }
}
```

### 2.1 Error codes (canonical, stable)

| `code` | Meaning | `retryable` | Typical client action |
|---|---|---|---|
| `auth` | Caller is not authenticated, token/session expired, or device session invalid. | no | Re-authenticate (user login, device session, or re-establish PIN session). |
| `permission_denied` | Authenticated but the membership-scoped role/scope does not grant this action (e.g. a cashier voiding a pre-completion order without void permission — note that an order with a **completed** payment cannot be voided at all in MVP, **DECISION D-023**/**DECISION D-024**). | no | Surface to user; do not retry. Audited. |
| `tenant_isolation` | Target rows resolve to a different organization than the caller's derived context (**DECISION D-001**). | no | Hard fail; treated as a security event and audited (**RISK R-003**). |
| `revision_mismatch` | Optimistic concurrency conflict: `expected_revision` does not match the server's current revision. | no (as-is) | Re-pull entity, reconcile per [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), resubmit. `details.server_revision` provided. |
| `conflict` | Multi-device/domain conflict that is not a simple revision bump (e.g. concurrent state change disallowed by [STATE_MACHINES](STATE_MACHINES.md)). | no (as-is) | Apply conflict-resolution policy — **OPEN QUESTION Q-010**. |
| `idempotency_replay` | Informational: not an error per se. Returned only when a replay is detected with a *different* payload under the same idempotency key (a true conflict). A clean replay instead succeeds with `idempotency_replay: true` (§1.3). | no | Treat as poison/duplicate; surface and audit. |
| `validation` | Input failed validation (missing field, illegal value, illegal state transition, non-integer money, negative `_minor`, etc.). | no | Fix input; do not blind-retry. |
| `precondition_failed` | A required precondition is not met (e.g. shift not open, device not `active`, code expired). | sometimes | Resolve precondition, then retry. |
| `rate_limited` | Caller is being throttled. | yes | Backoff and retry per [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md). |
| `server_error` | Unexpected server fault. | yes | Backoff and retry; eligible for poison handling after max retries. |

> **SECURITY REQUIREMENT:** error `message`/`details` must never leak cross-tenant data or the existence of rows the caller cannot see. A request for another organization's order returns `tenant_isolation` (or a not-found-shaped response), never the row's contents.

> A permanently rejected operation (e.g. `validation`, `permission_denied`, `tenant_isolation`) moves the corresponding sync operation to `rejected` (terminal). A repeatedly `server_error`/`rate_limited` operation that exhausts retries moves to `dead` (poison, terminal) — see the **Sync operation** state machine in [STATE_MACHINES](STATE_MACHINES.md).

---

## 3. Versioning & Contract-Change Procedure

### 3.1 Versioning
- Contracts are versioned at the **RPC level** via a `contract_version` integer documented per RPC group, plus this document's git history (Git is the source of truth for code/contract history — **DECISION D-015**).
- **Additive, backward-compatible** changes (new optional input field, new response field, new error `code` that old clients can treat as `server_error`-ish) bump a minor expectation but do not break existing clients.
- **Breaking** changes (renamed/removed field, changed semantics, changed authorization) require a **new RPC name or a new major `contract_version`**; the old contract is kept until clients are migrated. Offline clients may be running an older contract version (**DECISION D-010**), so breaking changes must support an overlap window.

### 3.2 Change procedure (binding)
Per **DECISION D-016** and the agent workflow:
1. Any change to this document or to a contract requires a **dedicated ticket** (`RF-<number>`); shared-package and API-contract changes always get their own ticket (no piggy-backing).
2. ChatGPT planning → human approval → Claude Code implements on its own branch/worktree.
3. **Codex** performs an independent, read-only review.
4. Claude Code applies fixes; **human approval** is required before merge.
5. No agent pushes without human approval; no force push; no silent scope expansion.
See [PROJECT_PLAN](PROJECT_PLAN.md) and the AGENT WORKFLOW canon (**DECISION D-016**) for the full pipeline.

---

## 4. Core RPCs

Each RPC below is a **contract**: name, purpose, inputs (in addition to the common envelope of §1.6), authorization, side effects, audit, idempotency behavior, offline behavior, and returned revision. Implementations are out of scope for M0A. All inputs are additionally subject to §1 principles. All state changes must be legal per [STATE_MACHINES](STATE_MACHINES.md); all authorization per [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).

> Membership role keys used below (from canon, **DECISION D-004**) are the **six tenant roles**: `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant` (strictly read-only — no mutation RPC, **DECISION D-028**; ships-or-not is **OPEN QUESTION Q-017**).
>
> **`platform_admin` is NOT a membership role** (**DECISION D-026**). Platform administration is a **separate privileged path** backed by the `platform_admin_grants` entity ([DOMAIN_MODEL](DOMAIN_MODEL.md) §3.7), not by any tenant membership. That path is MFA-gated (**OPEN QUESTION Q-008**) and fully audited (**DECISION D-013**), and never silently bypasses tenant RLS or membership scoping. See §4.16.

---

### 4.1 `submit_order`
- **Purpose:** Submit a `draft` order, transitioning it to `submitted`. Captures item and modifier **price snapshots** at order time (**DECISION D-008**); the order never recomputes from live menu prices afterward.
- **Inputs (payload):** `order_id` (client-generated UUID), `table_id` (nullable; dine-in vs takeaway), `order_type`, list of `order_items` each with `menu_item_id`, `quantity`, captured `unit_price_minor`, `item_size_id`/`item_variant_id` (nullable), and `modifiers` (each with `modifier_option_id` and captured `price_minor`), order-level `notes`. Currency is the order's single currency (**OPEN QUESTION Q-007**); single currency per order (**DECISION D-007**).
- **Authorization:** `cashier` (or higher: `manager`, `restaurant_owner`, `org_owner`) with a membership scoped to the target `branch_id`, acting on a paired+`active` device with a valid device session and (for staff) a valid PIN session (**DECISION D-006**).
- **Side effects:** Order `draft → submitted`; order items `pending → queued` per [STATE_MACHINES](STATE_MACHINES.md). Does *not* itself route to kitchen (see `route_to_kitchen`).
- **Audit:** `order.submitted` event with actor, device, org/restaurant/branch, timestamp, snapshot totals (**DECISION D-013**).
- **Idempotency:** Keyed by `device_id`+`local_operation_id`; replay returns the same `order_id` and `revision`.
- **Offline:** Fully offline-capable; order is created/submitted locally and pushed via `sync_push`. Price snapshots are taken from the locally cached menu at submit time (menu-changes-while-offline handling per [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md)).
- **Returns:** new order `revision`.

### 4.2 `update_order_item`
- **Purpose:** Modify an order item before production (quantity, modifiers, notes) or transition its status within legal bounds.
- **Inputs:** `order_id`, `order_item_id`, `expected_revision`, and the mutation (e.g. `quantity`, `modifiers[]` with captured `price_minor`, `target_status`).
- **Authorization:** `cashier`+ scoped to the branch. Reducing/altering items already in production may require `manager` per [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).
- **Side effects:** Legal order-item transitions only (`pending → queued → preparing → ready → served`, or `voided`/`cancelled`) per [STATE_MACHINES](STATE_MACHINES.md). Modifier changes re-snapshot prices (**DECISION D-008**).
- **Audit:** `order_item.updated` with old/new values (**DECISION D-013**).
- **Idempotency:** Keyed; replay returns same `revision`.
- **Offline:** Capable; uses `expected_revision` for optimistic concurrency, `revision_mismatch`/`conflict` on push.
- **Returns:** new order_item `revision` (and order `revision` if totals change).

### 4.3 `route_to_kitchen`
- **Purpose:** Create kitchen ticket(s) and kitchen station item(s) for a submitted order, routing items to the correct station(s).
- **Inputs:** `order_id`, optional explicit `station_id` routing overrides, `expected_revision`.
- **Authorization:** `cashier`+ scoped to the branch (typically triggered on submit/accept); device must be `active`.
- **Side effects:** Creates `kitchen_tickets` (`new`) and `kitchen_station_items` (`queued`); may move order `submitted → accepted` per [STATE_MACHINES](STATE_MACHINES.md). Routing rules belong to [DOMAIN_MODEL](DOMAIN_MODEL.md)/[ARCHITECTURE](ARCHITECTURE.md).
- **Audit:** `kitchen_ticket.created` / `order.accepted`.
- **Idempotency:** Keyed; replay does not create duplicate tickets — duplicate-mutation prevention per [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
- **Offline:** Capable; tickets created locally and reconciled on sync.
- **Returns:** order `revision` and created kitchen ticket id(s).

### 4.4 `bump_kitchen_item`
- **Purpose:** Advance a kitchen ticket / station item through the kitchen workflow (acknowledge, start, ready, bump) from the KDS.
- **Inputs:** `kitchen_ticket_id` and/or `kitchen_station_item_id`, `target_status`, `expected_revision`.
- **Authorization:** `kitchen_staff` (or higher) with a membership scoped to the branch/station, on an `active` KDS device. **SECURITY REQUIREMENT:** KDS principals must not be able to read financial reports (canonical isolation test, [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).
- **Side effects:** Kitchen ticket `new → acknowledged → in_preparation → ready → bumped` (with audited `recalled` from `bumped → in_preparation`); station item `queued → in_preparation → ready → bumped` per [STATE_MACHINES](STATE_MACHINES.md). May propagate order item status.
- **Audit:** `kitchen_ticket.transition` / `kitchen_ticket.recalled` (recall is explicitly audited).
- **Idempotency:** Keyed; replay returns same `revision`.
- **Offline:** KDS may operate offline; transitions reconciled with multi-device conflict rules (**OPEN QUESTION Q-010**).
- **Returns:** new kitchen ticket/station item `revision`.

### 4.5 `apply_discount`
- **Purpose:** Apply an order-level or item-level discount (percentage or fixed) to a non-terminal order.
- **Inputs:** `order_id`, scope (`order` | `order_item` + `order_item_id`), `discount_type` (`percentage` | `fixed`), `value` (integer: basis points for percentage, or `amount_minor` for fixed), `reason`, `expected_revision`.
- **Authorization:** `cashier` for permitted thresholds; discounts above policy thresholds require `manager`+ per [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).
- **Side effects:** Recomputes order/item totals using snapshot prices and the rounding rules owned by [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md). All amounts remain integer `_minor` (**DECISION D-007**).
- **Audit:** `order.discount_applied` with type, value, reason, old/new totals (**DECISION D-013**).
- **Idempotency:** Keyed; replay does not stack the discount twice.
- **Offline:** Capable; totals computed locally with the same rounding rules, re-validated on push.
- **Returns:** new order `revision`.

### 4.6 `void_order` / `void_item` (pre-completion only)
- **Purpose:** Void a **pre-completion** order or an order item (post-submission, terminal). Distinct from cancellation (pre-production) and refund (**DEFERRED**, see [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md)). **`Order.completed` is TERMINAL** (**DECISION D-024**): `completed → voided`/`cancelled` is FORBIDDEN, and historical completed records are never rewritten.
- **Inputs:** `order_id` (and `order_item_id` for `void_item`), **mandatory** `reason`, `expected_revision`.
- **Authorization:** Requires explicit void permission + a mandatory `reason` + audit. **A cashier cannot void an order without void permission** (canonical isolation/permission test, [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)); otherwise `permission_denied`. `manager`+ is typically required.
- **Precondition (D-024):** Void/cancel is allowed **only when no completed payment exists** for the order. If a **completed** payment exists, the operation is **REJECTED** (`precondition_failed`) because reversing it would require the deferred refund flow (**DECISION D-023**, refunds **DEFERRED** — no hidden refund). A pre-completion `paid` state here means an order carrying only `pending`/`tendered` payments (not yet `completed`); such payments must be voided first via `void_payment` (§4.7a) before the order is voided, and the void accounts for any cash physically received before finalization.
- **Side effects:** Order `submitted/accepted/preparing/ready/served → voided` (terminal); item `→ voided` (terminal) per [STATE_MACHINES](STATE_MACHINES.md). Associated kitchen station items may move to `voided`. `completed → voided` is never produced.
- **Audit:** `order.voided` / `order_item.voided` with actor, reason, old/new values — **non-negotiable** (**DECISION D-013**).
- **Idempotency:** Keyed; voiding an already-voided entity under the same key is a clean replay; under a different key returns `conflict`/`precondition_failed`.
- **Offline:** **Online-only by default** (per the STATE_MACHINES Shift/Order ASSUMPTION); voids are not queued offline in the default posture. Offline-provisional voids are a **deferred/open consideration**, not the default — governed by the offline authorization validity window in **OPEN QUESTION Q-009**, where a revoked employee/device acting offline would be rejected on reconnect (**RISK R-007**). See [STATE_MACHINES](STATE_MACHINES.md) and [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
- **Returns:** new `revision`.

### 4.7 `record_payment` (cash) + `assign_receipt_number`
- **Purpose:** Record a cash payment against an order and assign the authoritative per-branch receipt number. (Card/other tenders **DEFERRED** beyond cash for MVP scope per [MVP_SCOPE](MVP_SCOPE.md); tips **DEFERRED**, **OPEN QUESTION Q-011**.)
- **Inputs:** `order_id`, `tender_type` = `cash`, `amount_tendered_minor`, `expected_revision`, optional client `provisional_receipt_number`. Service charge rules **OPEN QUESTION Q-012**.
- **Authorization:** `cashier`+ scoped to the branch, on an `active` device with valid PIN session, with an `open` shift and `active` cash drawer session bound to it (else `precondition_failed`).
- **Precondition — eligible order states (DECISION D-025):** Payment and fulfillment are **independent**; **pay-first is supported**. The order must be in one of `submitted`, `accepted`, `preparing`, `ready`, `served` to **start** a payment; `draft`, `cancelled`, `voided`, and `completed` are excluded (else `precondition_failed`). The contract does **not** require `ready`/`served` before payment.
- **Side effects:** Creates a `payment` (`pending → tendered → completed`); computes `change_due_minor` (integer). Payment **completion does not auto-advance fulfillment** (**DECISION D-025**) — it does not by itself move the order to `served`/`ready`. Order `→ completed` occurs only when both payment and fulfillment are satisfied per [STATE_MACHINES](STATE_MACHINES.md). **`assign_receipt_number`** assigns a **per-branch monotonic server-assigned sequence** (**DECISION D-021**); offline a provisional id is used locally and **reconciled to the authoritative number on sync**. Numbering legal rules are **OPEN QUESTION Q-004**.
- **Audit:** `payment.recorded` and `receipt_number.assigned` with branch, sequence, amounts (**DECISION D-013**).
- **Idempotency:** Keyed (**DECISION D-022**) — critical to prevent double-charging / double receipts (**RISK R-002**). Replay returns the same payment id and the same authoritative `receipt_number`.
- **Offline:** Capable; payment recorded against the local cash drawer session, receipt number provisional until reconciled. Order/payment duplication prevention per [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
- **Returns:** payment `revision`, order `revision`, and authoritative `ids.receipt_number` (post-reconciliation).

### 4.7a `void_payment` (pre-completion only)
- **Purpose:** Void a payment that has **not yet completed**. **`Payment.completed` is TERMINAL** (**DECISION D-023**): a completed payment **cannot be voided or reversed in MVP** — post-completion corrections, refunds, and reversals are **DEFERRED** (no hidden refund; see [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md)).
- **Inputs:** `payment_id` (and/or `order_id`), **mandatory** `reason`, `expected_revision`.
- **Authorization:** Requires an authorized actor with explicit void permission (`manager`+ typically) + mandatory `reason` + audit; `accountant` cannot call this mutation (**DECISION D-028**).
- **Precondition (D-023):** Allowed **only before payment completion**. Legal transitions: `pending → voided` and `tendered → voided`. `completed → voided` is **FORBIDDEN** (returns `precondition_failed`). A `tendered → voided` void must **account for cash physically received before finalization** (the counted cash is reconciled against the drawer per [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md)).
- **Side effects:** Payment `pending/tendered → voided` (terminal) per [STATE_MACHINES](STATE_MACHINES.md). Does not by itself void the order (see §4.6).
- **Audit:** `payment.voided` with actor, reason, old/new values — **non-negotiable** (**DECISION D-013**).
- **Idempotency:** Keyed; voiding an already-`voided` payment under the same key is a clean replay; a `completed` payment returns `precondition_failed`.
- **Offline:** Same online-only default posture as voids (§4.6); offline-provisional payment voids are a **deferred/open consideration** governed by **OPEN QUESTION Q-009** (**RISK R-007**).
- **Returns:** payment `revision` (and order `revision` if affected).

### 4.8 `open_shift`
- **Purpose:** Open a staff shift and its bound cash drawer session with an opening float.
- **Inputs:** `shift_id` (client UUID), `branch_id` (from context), `opening_float_minor`.
- **Authorization:** `cashier`+ (per policy `manager` to open on behalf of others) scoped to the branch, on an `active` device.
- **Side effects:** Shift `opening → open`; cash drawer session `opened(opening float) → active`, bound to the shift, per [STATE_MACHINES](STATE_MACHINES.md).
- **Audit:** `shift.opened` with opening float (**DECISION D-013**).
- **Idempotency:** Keyed; replay returns the same shift/drawer ids and `revision`.
- **Offline:** Capable; shift opened locally and pushed.
- **Returns:** shift `revision` and cash drawer session `revision`.

### 4.9 `close_shift` and `reconcile_shift` (two separate RPCs)
Shift close and shift reconciliation are **two distinct RPCs** (**DECISION D-028**). A single RPC must **not** perform both: closing/counting is the operator step; reconciliation is the separate review/sign-off step. `accountant` is strictly read-only and **cannot call either** mutation (**DECISION D-028**).

#### 4.9.1 `close_shift`
- **Purpose:** Close a shift and count the cash drawer, recording the counted amount and the resulting variance. Does **not** reconcile.
- **Inputs:** `shift_id`, `counted_amount_minor`, optional `notes`, `expected_revision`.
- **Authorization:** Actor is the owning `cashier` (close own shift per policy) **or** an authorized `manager`+ (to close on behalf of others) scoped to the branch ([SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).
- **Side effects:** Shift `open → closing → closed`; cash drawer session `active → counting → closed(counted + variance)` per [STATE_MACHINES](STATE_MACHINES.md). `variance_minor` = counted − expected (integer; expected computed per [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md)).
- **Audit:** `shift.closed` with counted, expected, variance (**DECISION D-013**).
- **Idempotency:** Keyed; replay returns the same `closed` `revision`.
- **Offline:** Capable; counting can occur offline, with close pushed on sync.
- **Returns:** shift `revision` and cash drawer session `revision`.

#### 4.9.2 `reconcile_shift`
- **Purpose:** Review and sign off a **closed** shift: confirm expected/counted/variance and record reconciliation. This is the separate, sensitive approval step.
- **Inputs:** `shift_id`, optional `reason`/`note` (required when variance exceeds the policy threshold), `expected_revision`.
- **Authorization:** `manager`, `restaurant_owner`, or `org_owner` scoped to the branch/restaurant ([SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)); not the read-only `accountant` (**DECISION D-028**).
- **Side effects:** Shift `closed → reconciled`; cash drawer session `closed → reconciled` per [STATE_MACHINES](STATE_MACHINES.md). No change to counted amounts (review-only finalization).
- **Audit:** `cash_drawer.reconciled` (sensitive) with counted, expected, variance, reason/note, approver (**DECISION D-013**).
- **Idempotency:** Keyed; replay returns the same terminal `reconciled` `revision`.
- **Offline:** Reconciliation is finalized on sync; the review/sign-off is a server-authoritative step.
- **Returns:** shift `revision` and cash drawer session `revision`.

### 4.10 `pair_device` (issue / redeem expiring code)
- **Purpose:** Enroll a POS/KDS device as a distinct **device identity** (**DECISION D-005**) via a short-lived enrollment code. Two operations under one contract group:
  - **issue:** an authorized human issues an expiring enrollment code for a branch/station.
  - **redeem:** the unpaired device redeems the code to obtain its device identity + credentials.
- **Inputs (issue):** `branch_id`, optional `station_id`, `device_label`, `intended_role` (POS/KDS). **Inputs (redeem):** `enrollment_code`, device fingerprint/attributes, generated `device_id`.
- **Authorization:** issue requires `manager`+ (or `restaurant_owner`/`org_owner`) scoped to the branch. Redeem is performed by an unauthenticated-as-human device presenting a valid, unexpired code only.
- **Side effects:** Device pairing `code_issued → pending → paired → active`; expired codes go to `code_expired`, refusals to `rejected` per [STATE_MACHINES](STATE_MACHINES.md). On redeem, a device identity and (subsequently) a device session are established. **SECURITY REQUIREMENT:** no shared restaurant password; codes are short-lived/expiring (**DECISION D-006**).
- **Audit:** `device.code_issued`, `device.paired` with issuer, device, branch (**DECISION D-013**).
- **Idempotency:** Keyed; redeeming the same code twice is a clean replay for the same device, `precondition_failed` (`code_expired`) otherwise.
- **Offline:** Pairing requires connectivity (issuance + redemption are online operations). **DEFERRED**: offline re-pairing.
- **Returns:** device pairing `revision`; on redeem, device identity reference.

### 4.11 `revoke_device`
- **Purpose:** Revoke a paired device so it can no longer sync new operations.
- **Inputs:** `device_id`, `reason`.
- **Authorization:** `manager`+ scoped to the branch, or `restaurant_owner`/`org_owner`.
- **Side effects:** Device pairing `active/suspended → revoked` (terminal) per [STATE_MACHINES](STATE_MACHINES.md). Invalidates the device session. **A revoked device cannot sync new operations** (canonical isolation test) — enforced server-side on `sync_push` (**RISK R-007**).
- **Audit:** `device.revoked` with reason (**DECISION D-013**).
- **Idempotency:** Keyed; revoking an already-revoked device is a clean replay.
- **Offline:** Revocation is a server-side authoritative action; a device offline at revocation time is rejected when it reconnects to push. Offline validity window is **OPEN QUESTION Q-009**.
- **Returns:** device pairing `revision`.

### 4.12 `revoke_employee`
- **Purpose:** Remove an employee's future access within an organization (suspend/terminate employment and revoke membership-derived access).
- **Inputs:** `employee_profile_id` (and/or `membership_id`), `reason`, effective scope.
- **Authorization:** `manager`+ (per policy `restaurant_owner`/`org_owner`) scoped to the organization/restaurant; cannot cross organizations (**DECISION D-001**).
- **Side effects:** Employment status set to revoked; PIN credential reference invalidated; **disable all memberships resolved from this `employee_profile` within the organization** (the `employee_profile`↔`membership` association is defined in [DOMAIN_MODEL](DOMAIN_MODEL.md)). **A removed employee cannot create new valid operations** (canonical isolation test) — enforced on reconnect (**RISK R-007**).
- **Audit:** `employee.revoked` with reason, actor (**DECISION D-013**).
- **Idempotency:** Keyed; replay is clean.
- **Offline:** Server-authoritative; operations created by a revoked employee during the offline window (**OPEN QUESTION Q-009**) are rejected on push and audited.
- **Returns:** employee profile / membership `revision`.

### 4.13 `start_pin_session`
- **Purpose:** Establish a short, fast **human PIN session** layered on top of an existing device session, on a paired+authorized device (**DECISION D-006**, **DECISION D-005**).
- **Inputs:** `employee_number` or employee selection, `pin` (transmitted/handled per [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md); never logged, never stored plaintext), device session context.
- **Authorization:** Requires a valid, `active` device session on a paired device whose branch matches the employee's membership scope. PIN verifies against the employee profile's PIN credential reference. **SECURITY REQUIREMENT:** PIN sessions exist **only** on a paired+authorized device; no shared accounts (**DECISION D-004**).
- **Side effects:** Issues a short-lived PIN session recording the `resolved_membership_id` per the DOMAIN_MODEL membership-resolution precedence (`employee_profiles.membership_id` first, else the unambiguous `app_user` membership; refused if ambiguous/empty), bound to (device session, employee profile, resolved membership). Validity/offline duration is **OPEN QUESTION Q-009**.
- **Audit:** `pin_session.started` (success) and failed-attempt events (rate-limited; **DECISION D-013**).
- **Idempotency:** Keyed; repeated start under same key returns the same session.
- **Offline:** Capable **only** if cached credentials/permissions are within the offline validity window (**OPEN QUESTION Q-009**); a revoked employee is rejected (**RISK R-007**).
- **Returns:** PIN session reference and `revision`.

### 4.14 `sync_push` (batch outbox)
- **Purpose:** Push a batch of queued local outbox operations to the server inbox/processed-operation ledger (**DECISION D-010**).
- **Inputs:** ordered array of operations, each a full RPC envelope (§1.6) with its own idempotency key (**DECISION D-022**), client/server timestamps, entity `revision`/`version`, and dependency ordering metadata.
- **Authorization:** Device must be `active` (not `suspended`/`revoked`); each contained operation is independently authorized by its own RPC rules. **A revoked device cannot push** (returns `auth`/`precondition_failed`; **RISK R-007**).
- **Side effects:** Applies each operation idempotently and in dependency order; duplicates are absorbed by the ledger; poison operations move to `dead`, permanent rejections to `rejected` (**Sync operation** state machine, [STATE_MACHINES](STATE_MACHINES.md)).
- **Audit:** Per-operation audit as defined by each underlying RPC (**DECISION D-013**).
- **Idempotency:** The core idempotency surface (**DECISION D-022**); replays and partial-batch retries are safe.
- **Offline:** This is the offline reconciliation entry point. Conflict handling per **OPEN QUESTION Q-010**; full mechanics owned by [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
- **Returns:** per-operation result array (each with `ok`/`error`, server ids, and new `revision`).

### 4.15 `sync_pull` (since revision)
- **Purpose:** Pull authoritative changes for the caller's tenant scope since a given revision/cursor, including tombstones for deletions (**DECISION D-020**).
- **Inputs:** `since_revision`/cursor per entity domain, requested scope (`organization_id` + optional `restaurant_id`/`branch_id`), page size.
- **Authorization:** RLS-enforced read scope (**DECISION D-012**); returns only rows within the caller's organization (**DECISION D-001**). **Org A cannot read Org B's data** (canonical isolation test). KDS scope excludes financial data.
- **Side effects:** None (read). Returns changed rows + tombstones (`deleted_at`) for sync-relevant deletions.
- **Audit:** Not audited as a mutation; platform-admin pulls are on a separate, explicitly audited path ([SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).
- **Idempotency:** Naturally idempotent (read); safe to repeat.
- **Offline:** Provides the data clients cache for offline operation; **Supabase Realtime is an enhancement only**, never the source of truth (**DECISION D-010**) — `sync_pull` is the authoritative catch-up mechanism, with Realtime limits/fallback polling tracked in **OPEN QUESTION Q-014**.
- **Returns:** changed entities, tombstones, and a new `cursor`/`revision` watermark.

### 4.16 Platform-admin operations (separate privileged path)
- **Purpose:** Platform-wide administrative operations (cross-organization support, provisioning, incident access) run through a **separate, privileged, explicitly audited path** — **not** any tenant RPC and **not** any membership role (**DECISION D-026**).
- **Authorization:** Backed by the `platform_admin_grants` entity ([DOMAIN_MODEL](DOMAIN_MODEL.md) §3.7), not by `organization_id`-scoped membership. Such operations are **MFA-gated** (**OPEN QUESTION Q-008**) and authorized only against an `active` grant.
- **Tenant isolation:** Platform-admin operations **never silently bypass** tenant RLS or membership scoping; any cross-tenant access is an explicit, narrowly scoped, fully audited action.
- **Audit:** All platform-admin actions, including platform-admin `sync_pull`/reads (§4.15), are written to the append-only audit trail on a dedicated path (**DECISION D-013**, [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).

### 4.17 `create_organization` (self-serve onboarding, RF-090)
- **Purpose:** A new authenticated user provisions its OWN tenant: an `organization` + first `restaurant` + `branch` (+ an optional default `station`) + the first `org_owner` **membership**, fully isolated by `organization_id` (**DECISION D-001/D-002/D-004**).
- **Auth:** Authenticated Supabase principal only; the caller is derived from `auth.uid()` and **never** from input. Unauthenticated calls are rejected (`42501`).
- **Inputs:** `p_client_request_id` (uuid, idempotency key), `p_organization_name`, `p_organization_slug` (`^[a-z0-9]+(-[a-z0-9]+)*$`, globally unique), `p_restaurant_name`, `p_branch_name`, `p_currency_code` (`^[A-Z]{3}$`), `p_timezone` (IANA, validated against `pg_timezone_names`), optional `p_default_station_name`.
- **Returns:** jsonb `{ ok, idempotent_replay, organization_id, restaurant_id, branch_id, station_id, membership_id, app_user_id, slug }`.
- **Side effects:** Bootstraps the caller's `app_users` row (linked to `auth.uid()`, email from the JWT claim — **no shared accounts**, **DECISION D-004**); creates the org/restaurant/branch/station and the `org_owner` membership; writes an `organization.created` audit event (**DECISION D-013**).
- **Authorization model:** The owner is a **membership-scoped** role (`org_owner`), never a global/platform role. The RPC accepts **no** `role`, `app_user_id`, `organization_id`, or platform input, and **never** writes `platform_admin_grants` — `platform_admin` remains the separate, audited plane (**DECISION D-026**).
- **Idempotency:** Keyed on `(caller, p_client_request_id)` via `organizations.creation_request_id` (a partial unique index). Same caller + same key returns the existing org (no duplicate); reuse with conflicting org-level input fails (`42501`). A different key may create another org (multi-org ownership).
- **Security:** `SECURITY DEFINER`, locked `search_path`, granted to `authenticated` only (never `anon`/`service_role`). The new org is RLS-isolated; cross-tenant access is impossible (isolation test, **RISK R-003**).
- **Offline:** Online-only (tenant creation is not an offline/outbox operation).

### 4.18 Platform-admin read-only panel RPCs (RF-091)
Read-only platform overview surface on the separate platform plane (§4.16). All three share one gate (`app.platform_admin_guard`): authenticated principal → **active `platform_admin_grant`** (`app.is_platform_admin()`; a tenant membership, even `org_owner`, can **never** satisfy it — **DECISION D-026**, T-008) → **MFA assurance `aal2`** → **non-empty `reason`**. Each writes a `platform_admin_audit_events` row on success and returns only narrow summary fields. **Read-only:** no tenant mutation, no impersonation, no generic cross-tenant `select *`, no grant/revoke. `SECURITY DEFINER`, locked `search_path`, granted to `authenticated` only (self-gated); never `anon`/`service_role`.
- **`platform_admin_organization_overview(p_reason)`** — platform-wide org summary: `{id, name, status, created_by_app_user_id, creation_request_id, restaurants_count, branches_count, active_memberships_count}[]`. Audited `platform.organizations.overview` (`target_organization_id` null = platform-wide).
- **`platform_admin_get_organization(p_organization_id, p_reason)`** — one org's detail + restaurant/branch summary + counts; fails clearly (`42501`) if the org does not exist. Audited `platform.organization.read` with `target_organization_id = p_organization_id`.
- **`platform_admin_recent_audit(p_reason, p_limit default 50)`** — recent `platform_admin_audit_events` (newest first, `p_limit` capped to [1,200]). Audited `platform.audit.read`.
- **MFA note (Q-008):** these RF-091 RPCs require `aal2` (checked directly via `app.current_auth_assurance_level()`, since `app.require_mfa_for_privileged()` is membership-scoped and does not gate a membership-less platform admin). The pre-existing `platform_admin_list_organizations` (§4.16) is **not** yet `aal2`-gated — closing that inconsistency is a **Q-008 / hardening follow-up**.

### 4.19 Reporting read views — daily reports + dashboard rollups (RF-075 / RF-092)
Read-only reporting is exposed as **RLS-scoped views** (the "read-mostly via RLS" pattern, §1.2), not RPCs. All are `security_invoker = true`, so the RF-059 SELECT gate `app.can_read_financials(org, restaurant, branch)` applies **as the caller** — `org_owner`/`restaurant_owner`/`manager`/`accountant` see their scoped rows, a **branch-scoped manager sees only their branch**, and **kitchen_staff/KDS and cross-tenant callers get zero rows**. All figures are integer `_minor`; nothing is recomputed (the rollups are integer `SUM`s and reconcile to the per-branch report). Read-only; no mutation; the platform plane (§4.16/§4.18) is separate. Dashboard **UI is deferred**.
- **`daily_branch_sales_report`** (RF-075) — per `(organization_id, restaurant_id, branch_id, business_day, currency_code)`: `order_count`, `gross_minor`, `discount_total_minor`, `net_sales_minor`, `tax_total_minor`, `void_count`, `void_total_minor`, `collected_total_minor`, `collected_cash_minor` (+ companion `daily_branch_shift_lines`, `daily_branch_void_discount_reasons`).
- **`dashboard_org_daily_sales`** (RF-092) — org-level rollup per `(organization_id, business_day, currency_code)`: `restaurant_count`, `branch_count`, and the summed `_minor` buckets above. An org_owner aggregates all visible branches across all their restaurants (**D-002**); a branch-scoped manager aggregates only their branch.
- **`dashboard_restaurant_daily_sales`** (RF-092) — restaurant-level rollup per `(organization_id, restaurant_id, business_day, currency_code)`: `branch_count` + the summed `_minor` buckets. Reconciles to `daily_branch_sales_report` by construction.

### 4.20 Basic billing — plans, subscriptions, entitlements (RF-093)
Internal, per-organization subscription state only — **no payment provider, no checkout, no payment links, no webhooks, no invoices, no tax/legal accounting, no secrets** (the billing model **Q-016** stays deferred). Money is integer `_minor` (**D-007**); RF-093 placeholder prices are `0`. Billing attaches to the **Organization** (**D-003**).
- **`plans`** (table) — shared (non-tenant) plan catalog: `code` PK, `display_name`, `price_minor` (integer minor), `currency_code`, `max_branches` (null = unlimited), `is_active`. Seeded `free` (max_branches 1) and `basic` (unlimited), both `price_minor 0`. Readable by `authenticated`; **no tenant writes**.
- **`organization_subscriptions`** (table) — one row per org: `organization_id` PK, `plan_code`, `status` (`trialing`/`active`/`past_due`/`canceled`), `current_period_start`/`current_period_end`. RLS: SELECT only to `org_owner`/`accountant` in the org; managers/cashiers/kitchen/KDS and cross-tenant get **zero rows**; all direct tenant writes **denied** (only the RPC below mutates).
- **`organization_entitlements`** (view, `security_invoker`) — tenant read surface: `organization_id`, `plan_code`, `plan_display_name`, `subscription_status`, `price_minor`, `currency_code`, `max_branches`, period dates. Inherits the subscription RLS (org_owner reads own; others/cross-tenant see nothing). Read-only.
- **`app.org_plan_limit(p_organization_id, p_key)`** — entitlement/limit primitive (`max_branches` today). SECURITY INVOKER: returns the org's own limit under the caller's RLS, `null` when unauthorized for the org / unlimited / unknown key — **cannot leak another org's limit**. RF-093 does **not** wire call-site blocking (deferred).
- **`app.set_organization_plan(p_organization_id, p_plan_code, p_status, p_reason, p_current_period_start?, p_current_period_end?)`** — **platform-admin** manual assignment. SECURITY DEFINER, locked `search_path`; gated via `app.platform_admin_guard` (active platform grant + MFA `aal2` + non-empty reason — **D-026**, never a tenant role; **org_owner cannot call it**). Validates org/plan/status/period, upserts the subscription, and writes a `platform_admin_audit_events` row (`platform.org.plan_set`, target org, reason, old/new). Granted to `authenticated` (self-gated). **No self-serve plan change.**

---

## 5. Cross-References
- Decisions: [DECISIONS](DECISIONS.md) (D-001, D-003, D-004, D-005, D-006, D-007, D-008, D-010, D-011, D-012, D-013, D-015, D-016, D-018, D-020, D-021, D-022, D-023, D-024, D-025, D-026, D-028).
- Open questions: [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (subset of the Q-001..Q-024 range: Q-004, Q-007, Q-008, Q-009, Q-010, Q-011, Q-012, Q-014, Q-017).
- State transitions: [STATE_MACHINES](STATE_MACHINES.md).
- Authorization, RLS, isolation tests, audit: [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).
- Money/tax/receipt arithmetic: [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md).
- Sync mechanics: [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
- Entities/fields: [DOMAIN_MODEL](DOMAIN_MODEL.md).
- System structure: [ARCHITECTURE](ARCHITECTURE.md).
- Scope: [MVP_SCOPE](MVP_SCOPE.md). Plan/workflow: [PROJECT_PLAN](PROJECT_PLAN.md).
