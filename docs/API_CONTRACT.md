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
- **Authorization:** a `cashier` may apply discounts **by default** (STAFF-CASHIER-PERMISSIONS-001; disableable per-cashier via an explicit `apply_discount='false'` deny override), **but a full comp** — any discount that reduces a positive order/item target **to zero** (100% percentage, a percentage that rounds to the full base, or a fixed amount ≥ base) — requires `manager`/`restaurant_owner`/`org_owner` per [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) §4.4/§4.5. A cashier full-comp is **rejected** (`permission_denied`, audited `order.discount_denied`, no state change) — **never** silently clamped to a 100% discount. Higher configured thresholds (if/when added) likewise require `manager`+ per [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).
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
- **Implementation:** `app.sync_push(p_pin_session_id uuid, p_device_id uuid, p_operations jsonb)` (RF-056, `SECURITY DEFINER`, locked `search_path`, granted to `authenticated`). It validates the PIN session + active device/pairing + device match, derives org/restaurant/branch **server-side** (never from the payload), dedups/replays via the `sync_operations` inbox/ledger (transport identity `device_id`+`local_operation_id`, **DECISION D-022**), checks `depends_on` edges, and dispatches each ordered op to the matching business RPC (`shift.open→open_shift`, `order.submit→submit_order`, `order.discount→apply_discount`, `payment.create→record_payment`, `shift.close→close_shift`) inside per-operation `EXCEPTION` subtransactions; money/sequences/receipt numbers stay server-authoritative inside the dispatched RPCs (**DECISION D-007/D-021**). Returns `jsonb { ok, results:[ per-op {local_operation_id, operation_type, ok, status, error?, idempotency_replay} ], server_ts }`.
- **Data-API exposure (RF-126, PROPOSED DECISION D-036):** `app.sync_push` lives in the `app` schema, which is **not** Data-API-exposed (only `public`/`graphql_public` per `supabase/config.toml`), so a client has no entry point to it. RF-126 adds one thin **`public.sync_push(uuid, uuid, jsonb)` `SECURITY INVOKER` wrapper** — a faithful pass-through with the **same params/types/order** and the same `jsonb` return; it adds **no new privilege** (the RF-064 `public.sync_pull` / RF-123 `public.start_pin_session` / RF-109 `public.menu_*` / RF-125 `public.platform_admin_*` pattern) — the entire whole-batch gate, the idempotency ledger, the per-op dispatch, the money authority, and the audit writes stay inside the **unchanged** `app.sync_push` body. Left **VOLATILE** so PostgREST POST-routes the write in a writable context; grants mirror the app RPC (`revoke all from public` + `grant execute to authenticated`; never `anon`/`service_role` — **no anon writes**, **DECISION D-011**). The `app` schema stays **unexposed** and **only** `sync_push` is wrapped — the dispatched mutators (`submit_order`/`record_payment`/`apply_discount`/`open_shift`/`close_shift`) remain reachable **only** through the dispatcher (`public.sync_push` is the single, narrow POS write entry point, **not** a generic write proxy). *Status: PROPOSED — pending Codex review + human approval at the merge gate; RF-060 isolation suite green before merge (**RISK R-002/R-003**).*

### 4.15 `sync_pull` (since per-entity cursor)
- **Purpose:** Pull authoritative changes for the caller's tenant scope since a given **per-entity cursor**, including tombstones for deletions (**DECISION D-020**).
- **Inputs (RF-064):** `public.sync_pull(p_pin_session_id uuid, p_device_id uuid, p_entities text[], p_cursors jsonb, p_limit int)` — `p_cursors` is a per-entity map of `{updated_at, id}` keyset cursors (there is no global `since_revision`); the scope (`organization_id` + `restaurant_id`/`branch_id`) and role are derived **server-side** from the PIN session, never trusted from the payload.
- **Authorization:** RLS-enforced read scope (**DECISION D-012**); returns only rows within the caller's organization (**DECISION D-001**). **Org A cannot read Org B's data** (canonical isolation test). KDS scope excludes financial data.
- **Side effects:** None (read). Returns changed rows + tombstones (`deleted_at`) for sync-relevant deletions.
- **Audit:** Not audited as a mutation; platform-admin pulls are on a separate, explicitly audited path ([SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).
- **Idempotency:** Naturally idempotent (read); safe to repeat.
- **Offline:** Provides the data clients cache for offline operation; **Supabase Realtime is an enhancement only**, never the source of truth (**DECISION D-010**) — `sync_pull` is the authoritative catch-up mechanism, with Realtime limits/fallback polling tracked in **OPEN QUESTION Q-014**.
- **Returns (RF-064):** `{ ok, server_ts, changes: { <entity>: { rows, next_cursor, has_more } }, operation_statuses }` — each entity carries its own `rows`, a `next_cursor` `(updated_at, id)` keyset, and a `has_more` flag; deletions are inline `deleted_at` tombstones on the returned rows. There is **no** global `revision`/watermark.
- **Menu reference entities (RF-109, DECISION D-031):** `sync_pull` also carries the read-only menu reference entities (`menu_categories`, `menu_items`, `item_sizes`, `item_variants`, `modifiers`, `modifier_options`) to **price-capable** roles only — `cashier`, `manager`, `restaurant_owner`, `org_owner` (and the read-only `accountant` if shipped, **OPEN QUESTION Q-017**). **`kitchen_staff` is excluded** from the menu entities because menu prices are money (**DECISION D-007**); a KDS/`kitchen_staff` request for a menu entity is rejected (`42501`), and KDS derives item names from order snapshots (written by `submit_order` §4.1; snapshot fields in [DOMAIN_MODEL](DOMAIN_MODEL.md) §6, **DECISION D-008**), never the live menu. The entity/role allowlist is enforced inside `app.sync_pull` / `app.sync_pull_changes`; the **`public.sync_pull` wrapper signature is unchanged** (RF-064). Menu **writes** are online-direct RPCs (§4.23), never the outbox (§4.14).

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
- **Data-API exposure (RF-125, PROPOSED DECISION D-035):** the three RF-091 RPCs live in the `app` schema, which is **not** Data-API-exposed (only `public`/`graphql_public` per `supabase/config.toml`), so a client has no entry point to them. RF-125 adds three thin **`public.platform_admin_*` `SECURITY INVOKER` wrappers** (`public.platform_admin_organization_overview(text)`, `public.platform_admin_get_organization(uuid, text)`, `public.platform_admin_recent_audit(text, integer)`) — faithful pass-throughs with the **same params/types/order incl. `p_limit default 50`** and the same `jsonb` return; they add **no new privilege** (the RF-064 `public.sync_pull` / RF-123 `public.start_pin_session` / RF-109 `public.menu_*` pattern) — the entire `app.platform_admin_guard` gate, the audited reads, and the read-only posture stay inside the unchanged `app.*` bodies. Grants mirror the app RPC (`revoke all from public` + `grant execute to authenticated`; never `anon`/`service_role`); the `app` schema stays **unexposed** and **only** these three read-only panel RPCs are wrapped (`platform_admin_list_organizations` and the mutating `set_organization_plan` are **not**). **Read-only (D-026).** *Status: PROPOSED — pending Codex review + human approval at the merge gate; RF-060 isolation suite green before merge (**RISK R-003**).*

### 4.19 Reporting read views — daily reports + dashboard rollups (RF-075 / RF-092)
Read-only reporting is exposed as **RLS-scoped views** (the "read-mostly via RLS" pattern, §1.2), not RPCs. All are `security_invoker = true`, so the RF-059 SELECT gate `app.can_read_financials(org, restaurant, branch)` applies **as the caller** — `org_owner`/`restaurant_owner`/`manager`/`accountant` see their scoped rows, a **branch-scoped manager sees only their branch**, and **kitchen_staff/KDS and cross-tenant callers get zero rows**. All figures are integer `_minor`; nothing is recomputed (the rollups are integer `SUM`s and reconcile to the per-branch report). Read-only; no mutation; the platform plane (§4.16/§4.18) is separate. Dashboard **UI is deferred**.
- **`daily_branch_sales_report`** (RF-075) — per `(organization_id, restaurant_id, branch_id, business_day, currency_code)`: `order_count`, `gross_minor`, `discount_total_minor`, `net_sales_minor`, `tax_total_minor`, `void_count`, `void_total_minor`, `collected_total_minor`, `collected_cash_minor` (+ companion `daily_branch_shift_lines`, `daily_branch_void_discount_reasons`).
- **`dashboard_org_daily_sales`** (RF-092) — org-level rollup per `(organization_id, business_day, currency_code)`: `restaurant_count`, `branch_count`, and the summed `_minor` buckets above. An org_owner aggregates all visible branches across all their restaurants (**D-002**); a branch-scoped manager aggregates only their branch.
- **`dashboard_restaurant_daily_sales`** (RF-092) — restaurant-level rollup per `(organization_id, restaurant_id, business_day, currency_code)`: `branch_count` + the summed `_minor` buckets. Reconciles to `daily_branch_sales_report` by construction.

### 4.19a `owner_daily_report` (client-callable owner daily report, RF-REPORT-001 Slice 1 + RF-REPORT-002 hourly + RF-REPORT-003 shift/cash)
The §4.19 report **views** are `security_invoker` over the GUC-pinned RF-059 SELECT policies, so a real **anon-key + JWT** dashboard client reads **zero rows** from them (same reason RF adds a GUC-free RPC for `sales_summary`). RF-REPORT-001 Slice 1 adds a **GUC-free** owner daily report the Dashboard Overview can actually call, splitting **billed sales** from **collected payments** (the earlier MVP `sales_summary` conflated them). Read-only; no mutation; the platform plane (§4.16/§4.18) is separate.
- **Implementation / exposure:** `app.owner_daily_report` (`SECURITY DEFINER`, locked `search_path=''`, granted to `authenticated` only) + a thin **`public.owner_daily_report` `SECURITY INVOKER` wrapper** — the `app` schema is not Data-API-exposed (the RF-064 / `sales_summary` pattern); the wrapper adds **no new privilege**.
- **Params:** `p_organization_id uuid` (required; null → `42501`), `p_restaurant_id uuid default null`, `p_branch_id uuid default null` (downward-only scope narrowing).
- **Authorization (GUC-free, DECISION D-033):** caller via `auth.uid()` → `app.current_app_user_id()` (null → `42501`); tenant scope validated by `app.actor_rank_in_scope` over the **passed** scope (0 covering membership → `42501`, no cross-tenant). **Role gate = `app.can_read_financials`** (the SAME financial-read allowlist as the money-table RLS: `cashier` / `manager` / `restaurant_owner` / `org_owner` / **`accountant`**; `kitchen_staff` → `{ok:false, error:'permission_denied'}`) — it exposes no figure a permitted caller could not already `SELECT`+`SUM` under RLS. `platform_admin` is never a tenant path (**DECISION D-026**); no `service_role` / `anon` (**DECISION D-011**).
- **Money (D-007):** integer `_minor` only; every `SUM(bigint)` cast back to `bigint`, never float. **Billed sales** (from `orders`+`order_items`, excluding `voided`/`cancelled`/`draft`): `gross_minor` = `SUM(line_total_minor + line_discount_minor)`, `discount_minor` = item + order discount, `net_minor` = `SUM(subtotal_minor − discount_total_minor)` — the SAME definitions as `daily_branch_sales_report` (reconciles, zero drift). **Voids:** `void_count`, `void_total_minor`. **Collected** (from `payments`, `status='completed'`, joined to live non-void/cancel orders): `collected_minor`, `cash_minor`, `last_cash_payment_minor`, and a per-method `tenders: [{method, count, total_minor}]`. **Counts:** `order_count`, `completed_count`, `open_count`, `unpaid_count` (feed the KPI cards + a client-side `avg = net_minor // order_count`).
- **Business day (matches RF-075):** each order/payment is bucketed by its **branch-local** business day, `(created_at at time zone COALESCE(branch.timezone, restaurant.timezone))::date`, so the report **reconciles** with §4.19; branches with **no timezone** (branch + restaurant) are **excluded** (configure a timezone to include them). The `today`/`prior_day` reference is the server date; a full per-branch-timezone "today" for multi-timezone orgs is **DEFERRED**.
- **Sales-by-hour (RF-REPORT-002):** a top-level `hourly` array of **24 zero-filled buckets** `[{hour: 0..23, net_minor}]` for **TODAY** — `net_minor` = **billed** net (`SUM(subtotal_minor − discount_total_minor)`) bucketed by the order's **branch-local hour** (`extract(hour from created_at at branch tz)`), over the **same** billed orders as the daily figures (`voided`/`cancelled`/`draft` + `deleted_at` + tz-less **excluded**). Derived from **billed order data, not payments** (matches the daily `net_minor` and the demo chart). Integer minor only; an empty day is an honest all-zero series (never fabricated); prior-day hourly and per-branch-timezone "today" remain **DEFERRED**.
- **Shift / cash (RF-REPORT-003):** a top-level `shift_cash` object for **TODAY's** cash reconciliation. It **reads the values `close_shift` (RF-055) already persisted on `shifts`** — it NEVER recomputes cash: `expected_total_minor` (= opening float + completed **cash** payments for the drawer; **card/online tenders are NOT included** — an RF-055 invariant), `counted_total_minor` (the operator's actual counted amount), `variance_minor` (= counted − expected, **SIGNED**; negative = shortage). CLOSED shifts (`status in ('closed','reconciled')`) are bucketed by their **branch-local `closed_at` day** (RF-075 zone; tz-less **excluded**), and only **today's** closes count — a shift spanning midnight is attributed to the day it was **closed** (cash-count day). OPEN shifts (`opening`/`open`/`closing`) are counted **live** in scope (point-in-time; not day/tz-bucketed). `deleted_at IS NULL` throughout. `closed_by_name` = `employee_profiles.display_name` (same-org). `opened_at` / `closed_at` are returned as **branch-local `YYYY-MM-DD HH24:MI` display strings** (via `to_char(ts at time zone branch tz, …)`), consistent with the branch-local `closed_at` bucketing — never a raw UTC ISO whose calendar date could contradict the "today" bucket. Shape: `shift_cash:{closed_shift_count, open_shift_count, expected_cash_minor, counted_cash_minor, cash_variance_minor, last_closed_shift:{shift_id, branch_id, branch_name, opened_at, closed_at, closed_by_name, expected_cash_minor, counted_cash_minor, cash_variance_minor}|null, recent_closed_shifts:[…same, newest-first, cap 5]}`. No closed shift today → zeros + `last_closed_shift: null` + `recent_closed_shifts: []` (never fabricated). Prior-day shift/cash remains **DEFERRED**.
- **Returns:** `jsonb` — `{ok, entity:'owner_daily_report', currency_code, business_date, today:{order_count, completed_count, open_count, unpaid_count, gross_minor, discount_minor, net_minor, void_count, void_total_minor, collected_minor, cash_minor, last_cash_payment_minor, tenders:[{method,count,total_minor}]}, prior_day:{order_count, gross_minor, net_minor, cash_minor}, hourly:[{hour, net_minor} × 24], shift_cash:{…above}}`. Empty scope/day → honest zeros + empty `tenders` + all-zero `hourly` + empty `shift_cash` (never fabricated).
- **Side effects / Audit:** none — a scoped **read** writes no `audit_events` row (audit is reserved for sensitive mutations; the platform-plane reason/audit pattern of §4.18 is **not** used).
- **Scope:** RF-REPORT-001 Slice 1 (billed/collected split, tenders, prior-day) + RF-REPORT-002 (`hourly`) + RF-REPORT-003 (`shift_cash`). Still **DEFERRED** to later RF-REPORT slices: per-branch breakdown, top items, recent orders — the Overview leaves those empty (its data-gated cards simply do not render) and the RF-140 "live · limited" banner stays until they land.
- *Status: RF-REPORT-001 Slice 1 + RF-REPORT-002 (`20260706090000`) + RF-REPORT-003 (`20260706100000`) are forward-only `CREATE OR REPLACE` migrations, reviewed and **applied to the hosted DB (2026-07-06)** after the **RISK R-003** RLS/security sign-off (shared gate with `sales_summary`); the Overview now reads the real `owner_daily_report` (the `sales_summary` fallback stays a permanent safety net). See DEPLOYMENT §13 for the current reporting rollout state.*

### 4.19b `owner_report_range` (client-callable owner RANGE report, RF-REPORT-004 — Dashboard reporting v2)
Extends §4.19a for the Dashboard Overview's **date-range controls** (Today / Yesterday / Last 7 days / Last 30 days) with a **prior-period comparison**, an accurate **branch-local "today"**, single-day **hourly**, and a **deeper `shift_cash`**. It is a **NEW, additive function** — `owner_daily_report` (§4.19a) is left **untouched** and remains the compatibility fallback for the "today" view. Read-only; no mutation; the platform plane (§4.16/§4.18) is separate.
- **Implementation / exposure:** `app.owner_report_range` (`SECURITY DEFINER`, `language plpgsql stable`, locked `search_path=''`, granted to `authenticated` only) + a thin **`public.owner_report_range` `SECURITY INVOKER` wrapper** — the `app` schema is not Data-API-exposed (the RF-064 / `sales_summary` pattern); the wrapper adds **no new privilege**.
- **Signature:** `public.owner_report_range(p_organization_id uuid, p_restaurant_id uuid default null, p_branch_id uuid default null, p_range text default 'today')` (downward-only scope narrowing on restaurant/branch).
- **Accepted ranges (`p_range`):** `today` · `yesterday` · `last7` · `last30`. An **unknown range** raises SQLSTATE **`22023`** (`invalid_parameter_value`) — a safe **bad request**, NOT an auth denial and NOT a silent default; the deployed client only ever sends the four valid values.
- **Range windows (branch-local, DECISION D-033 / RF-075):** the current AND the immediately-preceding **equal-length** window are computed **PER BRANCH** from that branch's own local today, `(now() at time zone COALESCE(branch.timezone, restaurant.timezone))::date`. `today` = that single branch-local day; `yesterday` = the prior branch-local day; **`last7` / `last30` = ROLLING windows of the last 7 / 30 branch-local days INCLUDING today**. `comparison` = the **immediately-preceding equal-length** window (yesterday vs day-before; last7 vs the previous 7; last30 vs the previous 30) — no overlap, no gap. This also **FIXES the latent §4.19a "today" drift** (which used the SERVER/UTC `current_date`) and handles multi-timezone orgs correctly.
- **Authorization (GUC-free, identical to §4.19a):** caller via `auth.uid()` → `app.current_app_user_id()` (null → `42501`); tenant scope validated by `app.actor_rank_in_scope` over the **passed** scope (0 covering membership → `42501`, no cross-tenant); org not found/deleted → `42501`. **Role gate = the financial-read allowlist** (`cashier` / `manager` / `restaurant_owner` / `org_owner` / **`accountant`**; **`kitchen_staff` → `{ok:false, error:'permission_denied'}`**) — exposes no figure a permitted caller could not already `SELECT`+`SUM` under RLS. Tenant scope is validated **inside** the definer; `branch_tz_base` is **org-filtered at the source** so an org-wide call's `range_start`/`range_end` can never be derived from another tenant's branches (D-001 / RISK R-003). **Grants:** `revoke all … from public` + `grant execute … to authenticated` on **both** the `app` fn and the `public` wrapper — **anon / PUBLIC cannot execute**; no `service_role` dependency (**DECISION D-011**); no GUC trusted.
- **Money (D-007):** integer `_minor` only; every `SUM(bigint)` cast back to `bigint`, **never float**. ILS-only pilot; the org's `default_currency` is returned as `currency_code`.
- **`current` totals (billed vs collected split, SAME defs as §4.19a — reconciles):** `order_count`, `completed_count`, `open_count`, `unpaid_count`, `gross_minor`, `discount_minor`, `net_minor`, `void_count`, `void_total_minor`, `collected_minor`, `cash_minor`, `last_cash_payment_minor`, `tenders:[{method, count, total_minor}]`. **`comparison` totals** (the prior equal-length window): `order_count`, `gross_minor`, `net_minor`, `cash_minor`, `collected_minor`.
- **Hourly (real data only):** `hourly` = **24 zero-filled branch-local buckets** `[{hour:0..23, net_minor}]` for **single-day ranges ONLY** (`today` / `yesterday`) — billed net per branch-local hour over the same billed orders as `current` (`voided`/`cancelled`/`draft` + `deleted_at` + tz-less **excluded**). **Multi-day ranges (`last7` / `last30`) return an EMPTY `hourly` array** (`[]`), because an averaged/collapsed curve would mislead (the chart hides). **Never fabricated;** an empty single day is an honest all-zero series.
- **`shift_cash` v2:** the CLOSED shifts (`status in ('closed','reconciled')`) whose **branch-local `closed_at` day** falls in the **current** window (tz-less **excluded**); aggregates + `last_closed_shift` + `recent_closed_shifts` (newest-first, **cap 8**). It **READS the RF-055-stored** `expected_total_minor` / `counted_total_minor` / signed `variance_minor` (expected = opening float + completed **cash** payments; card/online tenders NOT in expected — an RF-055 invariant) — it **NEVER recomputes cash**. **Per-shift rollups** — `order_count`, `collected_minor`, `cash_sales_minor` — come from the **FK-enforced, server-stamped `payments.shift_id`** (RF-055/RF-117, real shift-linked payments); plus `opening_float_minor` (from `cash_drawer_sessions`), `opened_by_name` / `closed_by_name` (`employee_profiles.display_name`, same-org), and `duration_minutes`. `open_shift_count` is a **live** in-scope count (point-in-time). `opened_at` / `closed_at` are branch-local `YYYY-MM-DD HH24:MI` display strings. **Per-STAFF sales (who sold how much) are NOT part of this slice** (derivable from `payments.taken_by_employee_profile_id`; DEFERRED).
- **Returns:** `jsonb` — `{ok, entity:'owner_report_range', currency_code, range, range_start, range_end, current:{…above}, comparison:{order_count, gross_minor, net_minor, cash_minor, collected_minor}, hourly:[{hour, net_minor} × 24 | []], shift_cash:{closed_shift_count, open_shift_count, expected_cash_minor, counted_cash_minor, cash_variance_minor, last_closed_shift:{shift_id, branch_id, branch_name, opened_at, closed_at, opened_by_name, closed_by_name, opening_float_minor, duration_minutes, order_count, collected_minor, cash_sales_minor, expected_cash_minor, counted_cash_minor, cash_variance_minor}|null, recent_closed_shifts:[…same, newest-first, cap 8]}}`. `range_start` / `range_end` are branch-local `YYYY-MM-DD` display bounds (representative over the scoped branches; exact for the single-timezone pilot). Empty scope/window → honest zeros + empty `tenders` / `hourly` / `recent_closed_shifts` + `last_closed_shift: null` (never fabricated).
- **Timezone requirements:** range windows + hourly buckets use the **branch (then restaurant) IANA timezone** (`COALESCE(branch.timezone, restaurant.timezone)`); branches with **no timezone** are excluded (configure one to include them). The value must be a **DB-validated IANA zone** (`create_organization` validates `p_timezone` against `pg_timezone_names`). The production **pilot branch was onboarded with `UTC`** (the old client default), which shifted the sales-by-hour chart by the Israel offset; the **new onboarding default is `Asia/Jerusalem`**, and **existing branches can be corrected from Settings → Branch timezone** (the already-deployed `update_branch_settings(p_timezone)`) — **no DB migration is needed** to correct a branch setting.
- **Client fallback (fail-closed) — now a compatibility SAFETY NET, not the normal path:** since `owner_report_range` is **deployed to production** (§ Rollout), the Dashboard's normal path for every range is the RPC itself. The fallback remains only for compatibility / degraded environments: the Dashboard calls `owner_report_range` first, and on a **missing-function** signature (`PGRST202` / 404 — e.g. a pre-deploy environment or a brief schema-cache window) ONLY, **`today` degrades** to the deployed `owner_daily_report` path (§4.19a → then `sales_summary`), while **`yesterday` / `last7` / `last30` show an honest "range not available yet" state** (never today's data mislabelled). An **auth / permission / tenant error** (`42501` / `{ok:false}`) is **NEVER** treated as missing — it **FAILS CLOSED** (throws), so a denied caller never sees fallback data. The `sales_summary` fallback stays **safe + limited** (no hourly, no shift, `last_7_days`-only comparison). **No fake hourly / shift / comparison data** anywhere.
- **Side effects / Audit:** none — a scoped **read** writes no `audit_events`.
- **Rollout — LIVE:** the RF-REPORT-004 migration (`20260706110000_rf_report_004_owner_report_range.sql`, a forward-only `CREATE OR REPLACE`) was **applied to hosted production (2026-07-06)** — Dashboard **range reporting v2** (Today / Yesterday / Last 7 days / Last 30 days + prior-period comparisons + deeper Shift & cash) is **live in production**, and `owner_report_range` is now the **current real range-reporting path** (the fallback above is only a safety net). The **Free-plan / no-backup risk was accepted** for this pilot apply (no automated Supabase backups; the migration is additive / non-destructive — `CREATE OR REPLACE` + `GRANT` only). Future reporting migrations still require the **SAME strict R-003-style preflight** (exact single pending migration, no reset/seed/include-all/destructive flags, confirm target ref, backup posture, schema-reload only if needed — see DEPLOYMENT §13). Validated by pgTAP (`supabase/tests/rf_report_004_owner_report_range_test.sql`).
- *Status: **LIVE** — RF-REPORT-001/002/003/004 are all applied to hosted (see DEPLOYMENT §13); `owner_report_range` serves real range reporting in production. Browser smoke passed (ranges + reports work). The **RISK R-003** RLS/security sign-off (shared with `sales_summary` / §4.19a) was completed before apply.*

### 4.20 Basic billing — plans, subscriptions, entitlements (RF-093)
Internal, per-organization subscription state only — **no payment provider, no checkout, no payment links, no webhooks, no invoices, no tax/legal accounting, no secrets** (the billing model **Q-016** stays deferred). Money is integer `_minor` (**D-007**); RF-093 placeholder prices are `0`. Billing attaches to the **Organization** (**D-003**).
- **`plans`** (table) — shared (non-tenant) plan catalog: `code` PK, `display_name`, `price_minor` (integer minor), `currency_code`, `max_branches` (null = unlimited), `is_active`. Seeded `free` (max_branches 1) and `basic` (unlimited), both `price_minor 0`. Readable by `authenticated`; **no tenant writes**.
- **`organization_subscriptions`** (table) — one row per org: `organization_id` PK, `plan_code`, `status` (`trialing`/`active`/`past_due`/`canceled`), `current_period_start`/`current_period_end`. RLS: SELECT only to `org_owner`/`accountant` in the org; managers/cashiers/kitchen/KDS and cross-tenant get **zero rows**; all direct tenant writes **denied** (only the RPC below mutates).
- **`organization_entitlements`** (view, `security_invoker`) — tenant read surface: `organization_id`, `plan_code`, `plan_display_name`, `subscription_status`, `price_minor`, `currency_code`, `max_branches`, period dates. Inherits the subscription RLS (org_owner reads own; others/cross-tenant see nothing). Read-only.
- **`app.org_plan_limit(p_organization_id, p_key)`** — entitlement/limit primitive (`max_branches` today). SECURITY INVOKER: returns the org's own limit under the caller's RLS, `null` when unauthorized for the org / unlimited / unknown key — **cannot leak another org's limit**. RF-093 does **not** wire call-site blocking (deferred).
- **`app.set_organization_plan(p_organization_id, p_plan_code, p_status, p_reason, p_current_period_start?, p_current_period_end?)`** — **platform-admin** manual assignment. SECURITY DEFINER, locked `search_path`; gated via `app.platform_admin_guard` (active platform grant + MFA `aal2` + non-empty reason — **D-026**, never a tenant role; **org_owner cannot call it**). Validates org/plan/status/period, upserts the subscription, and writes a `platform_admin_audit_events` row (`platform.org.plan_set`, target org, reason, old/new). Granted to `authenticated` (self-gated). **No self-serve plan change.**

### 4.21 `public.start_pin_session` (public wrapper over `app.start_pin_session`, RF-122/RF-123)
Public Data API wrapper that exposes the PIN-session RPC of §4.13 (implemented as `app.start_pin_session`) on the **public** schema so clients can reach it (only `public`/`graphql_public` are exposed; `app.*` is **not** — `supabase/config.toml`). Same fast **human PIN session** on a paired+authorized device (**DECISION D-006**, **DECISION D-005**). **RF-122 authorizes the contract** (**DECISION D-029**); the wrapper is implemented under **RF-123**.
- **Purpose:** public-schema, client-callable wrapper over the internal `app.start_pin_session`; no new logic.
- **Inputs:** faithful pass-through — **same four parameters, same types and order** as the internal function: `p_device_session_id uuid`, `p_employee_profile_id uuid`, `p_pin_verifier text`, `p_local_operation_id text default null`. The PIN verifier is never logged and never stored plaintext (per [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).
- **Authorization:** `authenticated` only; **no `anon`**, **no service-role key in any client** (**DECISION D-011**). The wrapper is **`SECURITY INVOKER`** with `search_path=''`, delegating verbatim to `app.start_pin_session`, so the caller's existing `EXECUTE` on the `app` function is reused and **no new privilege is granted on `app.*`** (the RF-064 `public.sync_pull` pattern). All inner authorization (active device session on a paired device; branch/scope match; PIN verification) is unchanged.
- **Returns:** bare `uuid` (the PIN session id) — **identical to `app.start_pin_session`; no richer/composite return is introduced by RF-122/RF-123**. **Wrong PIN returns `NULL`** (no row, no error); **structural / precondition / lockout failures raise SQLSTATE `42501`** (device session not found/not active, employee not found/not in org/not active, membership empty/ambiguous/inactive/out-of-scope, PIN locked). The two failure modes are distinct: wrong verifier = `NULL`; everything else = `42501`.
- **Idempotency:** unchanged — keyed on `(organization, device session, employee profile, resolved membership, p_local_operation_id)`; a repeated validated call returns the **same** session id; replay never bypasses validation/lockout.
- **Audit:** unchanged from §4.13 — `pin_session.started` on success and rate-limited failed-attempt events (**DECISION D-013**).
- **Offline:** capable only within the cached offline validity window (**OPEN QUESTION Q-009**); a revoked employee/device is rejected (**RISK R-007**).

### 4.22 `public.get_my_context` (self-context membership resolver, RF-122/RF-124)
Authenticated, read-only **self-context / membership resolver**: lets a client read **its own** identity and the **list of its own memberships** so it can choose a tenant scope for routing, without trusting any client-supplied identity. **RF-122 authorizes the contract** (**DECISION D-029**); the resolver is implemented under **RF-124**. Read-only; no mutation.
- **Purpose:** server-resolved self-context for routing / membership selection in RF-108.
- **Inputs:** **none.** The caller is derived from `auth.uid()` via `app.current_app_user_id()` (fails closed when the principal is unlinked) and **never** from an input argument (**DECISION D-004 / D-005**).
- **Authorization:** `authenticated` only; **no `anon`**, **no service-role** (rejected with `42501`). The `app` schema is **not** exposed; only this `public.*` surface is reachable (`supabase/config.toml`). Locked `search_path=''`, granted `EXECUTE` to `authenticated` only.
- **Returns:** `jsonb`:
  - `ok` — boolean.
  - `app_user` — `{ id, email, display_name, is_active }` for the **calling principal only**.
  - `is_platform_admin` — a **separate boolean** (via `app.is_platform_admin()`), **never** a tenant membership entry; the platform-admin grant carries **no `organization_id`** and no org/restaurant/branch context is derivable from it (**DECISION D-026**).
  - `memberships` — a **LIST** (a user may hold many memberships across scopes); each entry: `id`, `organization_id`, `organization_name`, `restaurant_id` (nullable), `restaurant_name` (nullable), `branch_id` (nullable), `branch_name` (nullable), `role` (one of the six keys `org_owner`/`restaurant_owner`/`manager`/`cashier`/`kitchen_staff`/`accountant`), `status`. There is **no single global top-level `role`** — role is per-membership (**DECISION D-004 / D-005**).
  - The only PII returned is the **caller's own** `email`/`display_name`; no other user's data and no cross-org data.
- **Authorization model:** returns **only** rows for the calling principal — the caller's own `app_users` row and only memberships whose `app_user_id` is the caller; tenant RLS plus the explicit self-filter. No cross-user, no cross-org exposure (**DECISION D-001**, **RISK R-003**).
- **Side effects / Audit:** none — a self-scoped **read** writes **no `audit_events` row** (audit is reserved for sensitive mutations — [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) §7).
- **Idempotency:** N/A (read-only, no state change).
- **Offline:** online-only resolver (context selection is not an offline/outbox operation); the client caches the result for the offline window (**OPEN QUESTION Q-009**).

### 4.23 Menu management RPCs (RF-109, DECISION D-031)
Owner/manager menu CRUD for the six menu reference tables (`menu_categories`, `menu_items`, `item_sizes`, `item_variants`, `modifiers`, `modifier_options`; entities/fields owned by [DOMAIN_MODEL](DOMAIN_MODEL.md) §4). Tenant-scoped menu config writes go through audited `SECURITY DEFINER` RPCs (**DECISION D-011/D-012**) because direct table INSERT/UPDATE/DELETE is **denied by RLS policy and REVOKED** ([SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) §14 T-013). Menu **reads** are RLS-scoped table SELECT (to **price-capable roles only** — `org_owner`/`restaurant_owner`/`manager`/`cashier`/`accountant`; **`kitchen_staff` is excluded from menu reads on every path** because menu prices are money, [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) §14 T-003/T-013) + `sync_pull` (§4.15), not these RPCs.
- **Implementation / exposure:** each is `app.menu_*` (`SECURITY DEFINER`, locked `search_path=''`, granted to `authenticated` only) with a thin **`public.menu_*` `SECURITY INVOKER` wrapper** — the `app` schema is **not** Data-API-exposed (only `public`/`graphql_public` per `supabase/config.toml`); the wrapper adds **no new privilege** (the RF-064 `public.sync_pull` / RF-122 `public.start_pin_session` pattern).
- **Authorization:** `org_owner`, `restaurant_owner`, `manager` scoped to the target org/restaurant/branch. `cashier`, `kitchen_staff`, and the read-only `accountant` (**DECISION D-028**) are **denied** (`permission_denied` / `42501`). `platform_admin` is never a tenant write path (**DECISION D-026**). **No service-role key in any client** (**DECISION D-011**).
- **Money:** all prices are integer **minor units** (**DECISION D-007**) — `menu_items.base_price_minor` (absolute, `>= 0`) with `currency_code` (ISO 4217, [DOMAIN_MODEL](DOMAIN_MODEL.md) §4.2), and a **uniform signed** child `price_delta_minor` `bigint` on `item_sizes`/`item_variants`/`modifier_options` (**DECISION D-031** standardizes this, amending DOMAIN_MODEL §4.3/§4.6); non-integer / out-of-range money is rejected (`validation`).
- **Snapshots (D-008):** these RPCs mutate the **live** menu only; they never rewrite order snapshots — `order_items.menu_item_id` / `order_item_modifiers.modifier_option_id` remain non-FK snapshot references and orders never recompute from the live menu.
- **Idempotency:** **upsert-by-id** — re-running the same upsert is naturally idempotent (no `device_id`+`local_operation_id` outbox key; menu writes are online-direct, not the §4.14 outbox).
- **Audit (D-013):** every successful mutation **and** every denied write emits an `audit_events` row (`menu.<entity>.<action>` / `menu.<entity>.<action>_denied`) with actor, device, org/restaurant/branch, and old/new values.
- **Soft delete:** `menu_soft_delete(p_org, p_entity, p_id)` sets `deleted_at = now()` (tombstone, **DECISION D-020**); the row then propagates once via `sync_pull` (§4.15).
- **RPCs:** `menu_upsert_category`, `menu_upsert_item`, `menu_upsert_size`, `menu_upsert_variant`, `menu_upsert_modifier`, `menu_upsert_modifier_option`, and `menu_soft_delete`. Exact parameter lists are finalized with the RF-109 migration; the **semantics** (role gate, integer-minor money, audit, idempotent upsert-by-id, soft-delete) are frozen by **DECISION D-031**.
- **Errors:** `permission_denied` / `42501` (role/scope or non-member), `tenant_isolation` (target row resolves to another organization, **DECISION D-001**), `validation` (non-integer/negative absolute price, bad input). Error `message`/`details` never leak cross-tenant existence (§2).
- **Offline:** online-only (menu editing is not an offline/outbox operation); devices observe edits on the next `sync_pull`.

### 4.24 Menu image storage (RF-110, DECISION D-032)
Menu **item** images are stored in a **private** Supabase Storage bucket **`menu-images`** governed by tenant-scoped `storage.objects` RLS — **not** via any RPC and **not** as a `menu_items` column (the object key encodes the `menu_item_id`; UI / "current image" metadata is owned by RF-111). The `app` schema is unaffected; **no Data-API RPC is added** in RF-110.
- **Bucket:** `menu-images`, **private** (no public/anon read; no durable public URLs). Allowed MIME `image/png` / `image/jpeg` / `image/webp`; `file_size_limit` ≈ `5MiB`. Created by a SQL migration upserting `storage.buckets` (**not** a committed `config.toml` block).
- **Object key (path):** `{organization_id}/{restaurant_id}/{branch_id_or_global}/menu_item/{menu_item_id}/{image_id}.{ext}` — UUID segments; `branch_id_or_global` is a UUID or the literal `global` (restaurant-scoped, `branch_id NULL`); the literal `menu_item` segment is required; `ext` must be an allowed image type. **Menu item images only** (category/modifier images deferred). Malformed paths are denied.
- **Access model:** direct storage-api (S3 proxy) authenticated by the user's JWT (`auth.uid()`); **no service-role key in any client** (**DECISION D-011**). Because the storage-api does **not** set the app's org GUC, policies use **path-derived helpers** (`app.menu_image_scope`, `app.can_read_menu_image`, `app.can_write_menu_image`; `SECURITY DEFINER`, `search_path=''`) that identify the caller via `app.current_app_user_id()` (auth.uid) and derive scope from the path — **not** `app.has_scope` / `app.has_role_in_scope`. Four explicit `storage.objects` policies (SELECT/INSERT/UPDATE/DELETE), each pinned to `bucket_id='menu-images'`.
- **Read:** price-capable tenant roles in scope — `org_owner` / `restaurant_owner` / `manager` / `cashier` / `accountant`. **`kitchen_staff` is excluded** (live-menu surface; the path reveals menu structure — consistent with **DECISION D-031** / [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) §14 T-013/T-003; KDS uses order snapshots, §4.1). Reads are served by client-side signed URLs over the private objects the SELECT policy permits.
- **Write (INSERT/UPDATE/DELETE):** `org_owner` / `restaurant_owner` / `manager` in scope only; `cashier` / `kitchen_staff` / `accountant` / platform-admin-only / non-member / wrong-scope denied. A write **requires the referenced `menu_items` row to exist** in the parsed org/restaurant/branch scope (verified by the `SECURITY DEFINER` helper, which reads `menu_items` bypassing menu RLS). Physical delete; orphan cleanup deferred.
- **Audit:** RF-110 writes **no `audit_events`** for blob mutations (direct storage-api RLS, no `SECURITY DEFINER` RPC) — an accepted MVP gap; an audited RPC-mediated delete is a possible follow-up.
- **Errors / denial:** malformed paths, wrong scope (cross-org / cross-restaurant / sibling-branch), and unauthorized roles are denied by `storage.objects` RLS (no row returned / write rejected); no `anon`; `platform_admin` is never a tenant storage bypass (**DECISION D-026**).
- **RF-111** wires the owner upload UI and the "current image" metadata linkage later.

### 4.25 Tenant settings RPCs (RF-112, DECISION D-033)
Owner edits of **existing** hierarchy settings columns — **no new tables, no settings blob**: `update_organization_settings` (`default_currency`, `country_code`, `status`), `update_restaurant_settings` (`name`, `currency_override`, `timezone`, `status`), `update_branch_settings` (`name`, `address`, `timezone`, `receipt_prefix`, `status`); columns owned by [DOMAIN_MODEL](DOMAIN_MODEL.md) §2.1–§2.3. **Excluded** (each its own ticket): tax, rounding, locale, business hours, receipt template/logo/header/footer.
- **Implementation / exposure:** each is `app.update_*_settings` (`SECURITY DEFINER`, locked `search_path=''`, granted to `authenticated` only) with a thin **`public.*` `SECURITY INVOKER` wrapper** — the `app` schema is not Data-API-exposed (the RF-064 / RF-122 pattern); the wrapper adds **no new privilege**.
- **Authorization (GUC-free, DECISION D-033):** caller identified via `auth.uid()` → `app.current_app_user_id()`; tenant scope validated **directly from `memberships`** against the **passed** org/restaurant/branch — **not** `app.current_org_id` / `app.has_scope` / `app.has_role_in_scope`. `org_owner` / `restaurant_owner` in scope (a `manager` may edit branch settings only); `cashier` / `kitchen_staff` / `accountant` (read-only, **DECISION D-028**) are denied. `platform_admin` is never a tenant path (**DECISION D-026**); no `service_role`/`anon` (**DECISION D-011**).
- **Idempotency:** `client_request_id` (online management op; no `device_id`/`local_operation_id` outbox key).
- **Audit (D-013):** every successful settings change **and** every denied attempt emits an `audit_events` row (`settings.<entity>.updated` / `*_denied`) with actor/org/restaurant/branch/old/new.
- **Errors:** role-denied → `{ok:false, error:'permission_denied'}` (so the denial audit persists); structural validation / bad scope / not-found / cross-tenant → `42501`. Messages never leak cross-tenant existence (§2).

### 4.26 Membership management RPCs (RF-112, DECISION D-033)
`grant_membership` and `update_role` manage tenant memberships (entities [DOMAIN_MODEL](DOMAIN_MODEL.md) §3.2 / §3.3). Deactivate/revoke **reuses** RF-061 `revoke_employee` (§4.12). RF-112 adds **no** invite/pending flow and **no** new `memberships.status` enum value (the interim `active`/`revoked` set stands, **DECISION D-004/D-005**).
- **Implementation / exposure:** `app.grant_membership` / `app.update_role` (`SECURITY DEFINER`, `search_path=''`, `authenticated` only) + thin `public.*` `SECURITY INVOKER` wrappers.
- **`grant_membership`:** add a membership for an **existing `app_user`** at a target org/restaurant/branch + role; honors the `employee_profiles.membership_id` same-org authoritative link (§3.3). **`update_role`:** change an existing membership's role/scope.
- **Authorization (GUC-free + role-rank guard, DECISION D-033):** caller via `app.current_app_user_id()`; scope from `memberships` against the passed ids (not the org-GUC helpers). Rank `org_owner > restaurant_owner > manager > {cashier, kitchen_staff, accountant}` — the actor's rank must be **strictly higher** than the assigned/new role **and** the membership's existing role; a `manager` **cannot** assign `manager` / `restaurant_owner` / `org_owner`; **no self-grant / no self-escalation**; **downward-scope only**; cross-org / cross-restaurant / cross-branch targets denied (IDOR). `cashier` / `kitchen_staff` / `accountant` cannot manage (accountant read-only, **DECISION D-028**); `platform_admin` is **never** an assignable role (**DECISION D-026**).
- **Idempotency:** `client_request_id` (the RF-090 device-less model).
- **Audit (D-013):** `membership.granted` / `membership.role_updated` on success, and `*_denied` on every denied attempt, each with actor/org/restaurant/branch/old/new.
- **Errors:** role/rank/scope-denied → `{ok:false, error:'permission_denied'}` (denial audited); structural / cross-tenant / not-found → `42501`.

### 4.27 Device provisioning RPCs (RF-112, DECISION D-033)
The device **forward path** over the existing device schema (`devices` [DOMAIN_MODEL](DOMAIN_MODEL.md) §2.5, `device_pairings` §3.4 with the `code_issued → pending → paired → active → suspended → revoked` lifecycle, `device_sessions` §3.5). Revoke/suspend **reuses** RF-061 `revoke_device` (§4.11); the issue/redeem pairing surface complements §4.10.
- **RPCs:** `create_device` (register a scoped `devices` row); `issue_device_enrollment_code` (→ `device_pairings` `code_issued`; server-generated code; store **only** the `enrollment_code` hash/reference + `code_expires_at`; return the plaintext code **once**); `redeem`/`pair_device` (the device submits the code — **`code_issued → pending`**, **consume-once**; an expired code is rejected by the existing expiry guard); `approve_device` (the manager-approval edge **`pending → paired`** — **Approval REQUIRED**, device credentials issued and `paired_at` set; the subsequent activation **`paired → active`** permits opening a device session — transitions owned by [STATE_MACHINES](STATE_MACHINES.md) §9, which marks `pending → active` skipping `paired` **FORBIDDEN**); `start_device_session` (mint a `device_sessions` row on an `active` pairing; return the `session_token_ref` secret **once** — `start_pin_session` §4.13 only *consumes* a device session, it never creates one).
- **Implementation / exposure:** `app.*` (`SECURITY DEFINER`, `search_path=''`, `authenticated` only) + thin `public.*` `SECURITY INVOKER` wrappers.
- **Authorization (GUC-free, DECISION D-033):** caller via `app.current_app_user_id()`; scope from `memberships` against the passed ids. `org_owner` / `restaurant_owner` / `manager` in scope may provision; `cashier` / `kitchen_staff` / `accountant` denied. `platform_admin` is never a tenant path (**DECISION D-026**); no `service_role`/`anon` (**DECISION D-011**).
- **Secrets (SECURITY REQUIREMENT):** generated enrollment codes and session tokens are returned to the caller **once** and stored **only as hashes/references** — **never plaintext** in the DB or in `audit_events` (consistent with §2.5/§3.4/§3.5). The enrollment-code **TTL is conservative and the code is consume-once** (**OPEN QUESTION Q-009**-aware; not hard-coded permissively).
- **Fail-closed:** `revoked` / `suspended` / `code_expired` devices cannot pair or start a session (RF-061 revoke removes future access incl. the offline window — §14 T-004, **RISK R-007**).
- **Idempotency:** device-originated ops carry `device_id` + `local_operation_id` (**DECISION D-022**); management-initiated ops (e.g. create/issue) use `client_request_id`.
- **Audit (D-013):** every provisioning mutation **and** denial emits an `audit_events` row (`device.<action>` / `*_denied`).
- **Errors:** role/scope-denied → `{ok:false, error:'permission_denied'}` (audited); structural / cross-tenant / not-found / expired-code / already-consumed → `42501`.
- **Activation + session start (DECISION D-034):** the `paired → active` activation and `start_device_session` are defined in **§4.28** / **§4.29** — `approve_device` here **stops at `paired`** and never activates, and **no session starts on a non-`active` pairing**.

### 4.28 `activate_device` (RF-112, DECISION D-034)
The **`paired → active`** lifecycle edge ([STATE_MACHINES](STATE_MACHINES.md) §9), as a **separate explicit** RPC — activation is **never** folded into `approve_device` (which stops at `paired`) and **never** done inside `start_device_session`. An `active` pairing is the precondition for opening a device session (§4.29).
- **Implementation / exposure:** `app.activate_device` (`SECURITY DEFINER`, `search_path=''`, `authenticated` only) + a thin `public.activate_device` `SECURITY INVOKER` wrapper.
- **Params:** `p_client_request_id uuid`, `p_device_pairing_id uuid`.
- **Precondition (fail-closed):** the pairing must be **`paired`**; every other state (`code_issued`/`pending`/`active`/`suspended`/`revoked`/`code_expired`/`rejected`) is **rejected `42501`** (no re-activation, no skip); the device + branch/restaurant must be live (not soft-deleted) and the device `is_active`.
- **Authorization (GUC-free, D-034):** caller via `app.current_app_user_id()`; scope **derived from the pairing row** and validated against `memberships` (`app.actor_rank_in_scope`). `org_owner` / `restaurant_owner` / `manager` covering the device's scope may activate; `cashier` / `kitchen_staff` / `accountant` → `permission_denied`; non-member / cross-org / out-of-scope → `42501`. `platform_admin` is never a tenant path (**DECISION D-026**); no `service_role` / `anon` (**DECISION D-011**).
- **Idempotency:** `client_request_id` (the RF-112 management ledger). **Audit (D-013):** `device.activated` on success; `device.activate_denied` on role-denial. **No secret is minted** (the device credential `device_credential_ref` is provisioned separately — RF-021).
- **Response / errors:** `{ok:true, device_pairing_id, status:'active', idempotent_replay}`; role-denied → `{ok:false, error:'permission_denied'}` (audited); structural / state / scope / not-found → `42501`.

### 4.29 `start_device_session` (RF-112, DECISION D-034)
Mints a `device_sessions` row **only on an `active` pairing** ([DOMAIN_MODEL](DOMAIN_MODEL.md) §3.5); `start_pin_session` (§4.13) only *consumes* a device session — it never creates one.
- **Implementation / exposure:** `app.start_device_session` (`SECURITY DEFINER`, `search_path=''`, `authenticated` only) + a thin `public.start_device_session` `SECURITY INVOKER` wrapper.
- **Precondition (fail-closed):** the pairing must be **`active`**; a `paired` / `pending` / `suspended` / `revoked` / `code_expired` / non-active pairing is **rejected `42501`** (**§14 T-004** / **RISK R-007**); the device + branch/restaurant must be live and the device `is_active`.
- **Authorization (GUC-free, D-034):** **RF-112 management-initiated** — `org_owner` / `restaurant_owner` / `manager` covering the device's scope start the session (and securely hand the one-time token to the device); `cashier` / `kitchen_staff` / `accountant` → `permission_denied`; non-member / cross-org / out-of-scope / `anon` / platform-admin-only → `42501`. The fully **device-originated** form (the device authenticates with its own credential; idempotency `device_id` + `local_operation_id`, **DECISION D-022**) is a **follow-up** gated on the deferred device-auth bridge; the precondition, token handling, fail-closed states, and audit are identical.
- **Token (SECURITY REQUIREMENT):** the session token is **generated server-side**, stored **only as `session_token_ref` = its hash** (sha-256), and the **plaintext token is returned exactly ONCE** (first/claiming call). A **replay never re-returns the token** — the idempotency ledger stores a **no-token** result. **No plaintext token** in the DB or in `audit_events`.
- **Idempotency:** `client_request_id` (RF-112 management ledger); the device-originated follow-up uses `device_id` + `local_operation_id`. **Audit (D-013):** `device.session_started` on success (no token in the row); `device.session_start_denied` on role-denial.
- **Response / errors:** first call → `{ok:true, device_session_id, device_pairing_id, session_token (once), idempotent_replay:false}`; replay → the same envelope **without** `session_token` and `idempotent_replay:true`; role-denied → `{ok:false, error:'permission_denied'}` (audited); structural / state / scope / not-found → `42501`.

### 4.30 Cashier capability provisioning — `create_staff_member` (extended) + `set_staff_capabilities` (STAFF-CASHIER-PERMISSIONS-001)
Three routine `cashier` capabilities (`apply_discount`, `void_order` — UNPAID only, `close_shift` — own shift) are **enabled by default** and disableable per-cashier by an **explicit deny override** stored on `memberships.permissions` as the canonical JSON string `"false"` (key **absent** ⇒ role default ON). The effective gate is the fail-closed resolver `app.cashier_capability_allowed` (owned by [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) §5). Enforced server-side in `app.apply_discount` / `app.void_order` / `app.close_shift`; UI visibility is never relied upon.
- **`app.create_staff_member` (extended signature):** `(p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_display_name text, p_role text, p_capabilities jsonb DEFAULT NULL)`; thin `public.create_staff_member` `SECURITY INVOKER` wrapper with the same 7-arg signature. `SECURITY DEFINER`, `search_path=''`, `REVOKE`d from `PUBLIC`, granted to `authenticated`.
  - **`p_capabilities` behavior:** SQL `NULL` or `{}` ⇒ no initial denies (membership `permissions = '{}'`, all default ON). A non-empty value is **strict + fail-closed** (validated with `jsonb_each`, no coercion): only when `p_role='cashier'`, only keys `apply_discount`/`void_order`/`close_shift`, only the exact JSON **string** `"false"`. Any malformed shape/value (JSON null, boolean, number, array, nested object, non-object root, unknown key, mixed) ⇒ `42501` and **nothing is created** (atomic — the deny overrides persist in the **same transaction** as the membership; there is no fail-open create-then-set).
  - **Backward compatibility:** a **6-argument call** resolves to the 7-arg function via the `NULL` default and behaves exactly as before. **Idempotency:** `client_request_id`; the request fingerprint for a **no-deny** create equals the exact **pre-migration (6-arg) fingerprint** (capabilities are **not** appended for the `{}`/default case), so a request created before the migration **replays** after it; when real denies exist they extend the fingerprint via one canonical (key-order-independent) `jsonb` representation. **Audit:** `staff.created` carries the initial canonical denies + effective capability values (no PIN/secret material).
- **`app.set_staff_capabilities`:** `(p_client_request_id uuid, p_employee_profile_id uuid, p_apply_discount boolean, p_void_order boolean, p_close_shift boolean)` + thin `public.set_staff_capabilities` `SECURITY INVOKER` wrapper. `SECURITY DEFINER`, `search_path=''`, `REVOKE`d from `PUBLIC`, granted to `authenticated`.
  - **Target scope + authorization:** the employee-profile and the **membership that will be mutated** are resolved in one coherent lookup (`ep.membership_id=m.id` AND same `organization_id` AND same `app_user_id`); authorization **and** the scope-predicated `UPDATE` both derive from that **membership's own scope** (downward-only coverage via `app.actor_rank_in_scope`) — a profile in one branch can never authorize mutating a membership in another. Rank ≥ `manager` **and** strictly-outrank; non-cashier targets refused. Deny-only storage (`"false"` to deny; key removed to re-enable; unrelated keys preserved). **Idempotency:** `client_request_id`, checked **before** any target lookup. **Audit:** `staff.capabilities_updated` (old + new raw permissions + effective values) on success; `staff.capabilities_denied` on an in-scope insufficient-rank refusal (returned + durably audited).
  - **Errors / no-oracle:** in-scope insufficient-rank ⇒ `{ok:false, error:'permission_denied'}` (audited). Nonexistent / cross-tenant / sibling-branch-without-coverage / profile↔membership-mismatch / forged target all ⇒ **one identical `42501` (same SQLSTATE + message)** — no existence/role/branch leak (**RISK R-003**). Genuine same-scope `client_request_id` reuse with different input ⇒ conflict.
- **Rollout order (DB-first):** (1) apply the migration to hosted; (2) verify schema / PostgREST availability of the new signatures; (3) deploy the Dashboard; (4) rebuild/redeploy apps/APKs only when separately approved.

---

## 5. Cross-References
- Decisions: [DECISIONS](DECISIONS.md) (D-001, D-003, D-004, D-005, D-006, D-007, D-008, D-010, D-011, D-012, D-013, D-015, D-016, D-018, D-020, D-021, D-022, D-023, D-024, D-025, D-026, D-028, D-029, D-031, D-032, D-033, D-034).
- Open questions: [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (subset of the Q-001..Q-024 range: Q-004, Q-007, Q-008, Q-009, Q-010, Q-011, Q-012, Q-014, Q-017).
- State transitions: [STATE_MACHINES](STATE_MACHINES.md).
- Authorization, RLS, isolation tests, audit: [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).
- Money/tax/receipt arithmetic: [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md).
- Sync mechanics: [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
- Entities/fields: [DOMAIN_MODEL](DOMAIN_MODEL.md).
- System structure: [ARCHITECTURE](ARCHITECTURE.md).
- Scope: [MVP_SCOPE](MVP_SCOPE.md). Plan/workflow: [PROJECT_PLAN](PROJECT_PLAN.md).
