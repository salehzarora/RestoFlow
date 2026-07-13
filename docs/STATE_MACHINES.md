# STATE_MACHINES.md — RestoFlow State Machines (Authoritative for Transitions)

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

**Status:** M0A architecture-baseline document, frozen as the M0A architecture baseline at RF-004 (approved into the frozen M0A baseline (RF-004)) (RF-001).
**Owner of this topic:** This document is the single source of truth for **state transitions** of every stateful entity in RestoFlow. It owns the *allowed transition tables*, *forbidden transitions*, *terminal states*, *who/condition/reason/audit/offline/reversibility* per transition.

**This document does NOT own:**
- Entity fields/relationships → see [DOMAIN_MODEL.md](DOMAIN_MODEL.md).
- Money/discount/void-vs-refund accounting rules and receipt numbering → see [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md).
- RLS, role permissions, isolation tests, audit-event storage → see [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).
- Outbox/inbox, idempotency, conflict resolution mechanics → see [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md).
- RPC contracts that *execute* sensitive transitions → see [API_CONTRACT.md](API_CONTRACT.md).
- Print/hardware adapter behaviour → see [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md).
- The decision log → see [DECISIONS.md](DECISIONS.md); the open-question register → see [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

The **state value enumerations** below are **PROPOSED** by **DECISION D-018** (pending ChatGPT + Codex review + Saleh approval; not frozen — RF-001 §8 explicitly directs us to evaluate, not assume the listed values are final). While this draft stands, this document MUST NOT add, rename, or remove a state value independently; it only defines transitions over those proposed values. The proposed enumerations in [DECISIONS.md](DECISIONS.md) (D-018) and this document MUST agree verbatim.

---

## 0. Conventions used in every transition table

Each transition row carries these columns. The legend applies to all 10 machines.

> **Convention — `(create)`:** A `(create) → <state>` row denotes the row insertion that brings an entity into its initial state; `(create)` is **not** a stored status value but the act of inserting the row directly into the named initial state.

| Column | Meaning |
| --- | --- |
| **From → To** | The state change, over the PROPOSED state values only. |
| **Actor** | Who may perform it: a membership role key (`org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant`), a *device identity* (POS/KDS), the *server* (system/RPC), or a *PIN session* human on a paired device. Roles are membership-scoped per **DECISION D-004**; `platform_admin` is **not** a membership role (**DECISION D-026**) — platform administration is a separate explicitly-audited grant, not a tenant membership, and its actions follow the separate admin path (**D-012**). `accountant` is **strictly read-only** (**DECISION D-028**; **OPEN QUESTION Q-017** — may not ship in MVP) and therefore performs **no** state transition or mutation in any machine. |
| **Conditions** | Preconditions that must hold (scope checks, prior state, related-entity state). Scope/permission enforcement is owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md); this column states the *domain* precondition. |
| **Reason/Approval** | Whether a free-text reason and/or an explicit authorizing role is REQUIRED. |
| **Audit** | Whether an append-only `audit_events` row is REQUIRED (**DECISION D-013**). "Always" means every occurrence; "Yes(sensitive)" means it is a sensitive mutation that MUST flow through an RPC SECURITY DEFINER path (**DECISION D-011/D-012**). |
| **Offline** | `Yes-provisional` = may occur offline on the device, applied locally, server-authoritative on sync (**DECISION D-010/D-020**); `No-online-only` = requires server; `Server-only` = only the server may originate it. |
| **Reversible** | Whether the transition can be undone, and by which counter-transition (e.g. void vs cancel vs kitchen recall). Terminal-state entries are irreversible by definition. |

**Global rules (apply to all machines):**

- **SECURITY REQUIREMENT:** every transition marked `Yes(sensitive)` MUST execute through a PostgreSQL RPC SECURITY DEFINER function that authorizes the actor and writes the audit row atomically (**DECISION D-011, D-012**). No Flutter client may mutate these directly; no service-role key ships in clients.
- **SECURITY REQUIREMENT:** a transition performed offline is **provisional**. On reconnect the server re-validates actor authority, device validity, employee validity, and current entity revision (**DECISION D-022** idempotency via `device_id` + `local_operation_id`). A revoked device or removed employee acting during the offline window has its provisional transitions **rejected** on sync (**RISK R-007**, **OPEN QUESTION Q-009** offline validity window).
- Any transition NOT listed in a machine's allowed table is **FORBIDDEN**. The "Forbidden / invalid" subsection lists the high-value illegal moves explicitly to make tests concrete, but the *allowed table is exhaustive*.
- All money implications use integer minor units (**DECISION D-007**); no floating point appears in any payload accompanying a transition.
- Sync-relevant deletions are tombstones (`deleted_at`), never hard deletes (**DECISION D-020**); deletion is modelled as a state transition where the machine has one (e.g. `cancelled`/`voided`), not as row removal.

---

## 1. Order

**Proposed states (D-018, approved into the frozen M0A baseline (RF-004)):** `draft → submitted → accepted → preparing → ready → served → completed`; plus `cancelled` (pre-production, terminal) and `voided` (post-submission, requires authorization+reason, terminal).
**Terminal:** `completed`, `cancelled`, `voided`.
**Takeaway rule:** takeaway/pickup orders skip `served` (`ready → completed`).

### 1.1 Allowed transitions

| From → To | Actor | Conditions | Reason/Approval | Audit | Offline | Reversible |
| --- | --- | --- | --- | --- | --- | --- |
| draft → submitted | cashier / manager / restaurant_owner / org_owner (PIN session on paired device) | order has ≥1 non-voided order_item; branch_id + restaurant_id + organization_id set; receipt sequence provisional id reserved (**D-021**) | No | Always | Yes-provisional | Yes → via void/cancel only (no "unsubmit"); see Forbidden |
| submitted → accepted | server (on POS/KDS confirmation) / manager / cashier | order valid; price/modifier snapshots captured (**D-008**) | No | Always | Yes-provisional | No direct reverse (forward only; terminate via void) |
| submitted → cancelled | cashier / manager / restaurant_owner / org_owner | no production started (no order_item past `queued`/`preparing`) | Reason REQUIRED | Yes(sensitive) | Yes-provisional | Terminal |
| accepted → preparing | server / kitchen_staff / KDS device | ≥1 kitchen_ticket exists and is `acknowledged`/`in_preparation` | No | Always | Yes-provisional | No |
| accepted → cancelled | manager / restaurant_owner / org_owner | no production started | Reason REQUIRED | Yes(sensitive) | Yes-provisional | Terminal |
| preparing → ready | server / kitchen_staff / KDS device | all non-voided order_items `ready` (or kitchen tickets bumped) | No | Always | Yes-provisional | Reversible by kitchen recall at *ticket* level (see §3); order may return preparing if a recalled ticket reopens |
| ready → served | cashier / manager / server | dine-in order (NOT takeaway) | No | Always | Yes-provisional | No |
| ready → completed | cashier / manager / server | **takeaway order only** (skips served); payment in `completed` or settlement rules met (see [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md)) | No | Always | Yes-provisional | No |
| served → completed | cashier / manager / server | dine-in; payment settled per money spec | No | Always | Yes-provisional | No |
| submitted → voided | manager / restaurant_owner / org_owner, **and a cashier by default** (STAFF-CASHIER-PERMISSIONS-001; UNPAID orders only; disableable per-cashier via `permissions.void_order='false'`) | post-submission termination; **no `completed` payment** (paid-order void is REJECTED, D-023/D-024) | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only by default (see ASSUMPTION below) | Terminal |
| accepted → voided | manager / restaurant_owner / org_owner | post-submission termination | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| preparing → voided | manager / restaurant_owner / org_owner | post-submission termination; kitchen tickets cancelled as side-effect | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| ready → voided | manager / restaurant_owner / org_owner | post-submission termination | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| served → voided | manager / restaurant_owner / org_owner | allowed only when **no `completed` payment exists**; if any `payment` is `completed`, the void is **REJECTED in MVP** (would require the deferred refund flow, **D-024**) | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |

> **SECURITY REQUIREMENT (paid-order void):** In MVP a **paid** order (any associated `payments` row in `completed`) MUST NOT be voided at all — the void is **REJECTED** because reversing the completed payment would require the deferred refund flow (**D-024**; `completed → voided` is FORBIDDEN on the payment, **D-023**). Under **STAFF-CASHIER-PERMISSIONS-001** a cashier voids an **UNPAID** order **by default** (disableable per-cashier via `permissions.void_order='false'`); a cashier carrying that explicit deny CANNOT void. The canonical test's protected invariant (**T-006**) is preserved and strengthened: **no role — not even a privileged one — may void a PAID order in MVP** (`completed` payment ⇒ REJECTED). (Where no completed payment exists, the standard authorized-actor + reason + audit void path of §1.1 applies.) See [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).

> **DECISION D-024 (order terminal + pre-completion cancel/void):** `completed` is **TERMINAL**: `completed → voided` and `completed → cancelled` are **FORBIDDEN**. Pre-completion `cancel`/`void` is allowed **only** when it is valid for the current state (per §1.1) **AND no `completed` payment exists** for the order. If a `completed` payment exists, any pre-completion `cancel`/`void` MUST be **REJECTED in MVP** — undoing it would require the deferred refund flow (refunds **DEFERRED**, see [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md)). Historical completed records are never rewritten to simulate a refund.

> **DECISION D-025 (pay-first / independence of payment and fulfillment):** Payment lifecycle (§5) and order fulfillment (§1) are **INDEPENDENT axes**; quick-service **PAY-FIRST** is supported. Eligible order states in which a payment may be **started** are `submitted`, `accepted`, `preparing`, `ready`, `served`; **excluded**: `draft`, `cancelled`, `voided`, `completed`. Cash payment does **not** require `ready`/`served` first. Payment completion does **not** auto-advance fulfillment (it does not imply food prepared/ready/served or order completed). An order reaches `completed` only when fulfillment is satisfied **AND** (for a chargeable order) payment is `completed`.

> **IMPLEMENTATION NOTE (ORDER-COMPLETION-001) — D-025 is now ENFORCED IN CODE, and `served → completed` is reachable.** Two long-standing gaps between this frozen document and the shipped backend are closed; **no decision changed**:
> 1. **The payment gate was never enforced.** D-025 above requires that an order reach `completed` only when payment is `completed`, but `app.update_order_status` contained **no payment check** — an UNPAID order could be completed. The state machine now enforces it: completing an order with no `completed` payment is refused with the stable domain error **`order_not_paid`**, and nothing is written. This affects **only** the `→ completed` transition, which no client previously performed, so no shipped behaviour regressed. **Caveat, since RESOLVED:** D-025 says *"for a **chargeable** order"*, and when this note was written **no chargeable flag existed in the schema** (the word appeared only in prose), so the gate applied to **every** order. **ORDER-AUTO-COMPLETION-001 gave it a definition — `grand_total_minor > 0` IS "chargeable"** — and a **zero-total** order is therefore NON-CHARGEABLE: it owes nothing, settles with no payment row, and `app.record_payment` now refuses to charge it at all (`order_not_chargeable`). See the note below and [API_CONTRACT §4.32d/§4.34](API_CONTRACT.md). Completion still creates **no** payment and changes **no** payments row — payment and fulfillment remain independent axes; the gate only makes fulfillment *wait*.
> 2. **No client could reach the transition.** The KDS is the only status writer and its highest value is `served`, so orders accumulated. `served → completed` is now reachable from the owner/manager **Dashboard** via `app.owner_complete_order` (see [API_CONTRACT §4.32c](API_CONTRACT.md)), a JWT front that delegates to the **same** single state machine (`app.apply_order_status_transition`) the PIN/device front uses. Authorized actors are `cashier` / `manager` / `restaurant_owner` / `org_owner` (the RPC's allowlist; `kitchen_staff` and `accountant` are denied). **NOTE:** the actor column in the §1.1 table above names *"cashier / manager / server"*, but **`server` is not one of the six frozen membership role keys** (D-017) — the RPC's allowlist is authoritative.
>
> **STILL UNRESOLVED (unchanged by this ticket):** the **takeaway** fork. This document says a takeaway order skips `served` (`ready → completed`) and that `ready → served` is FORBIDDEN for takeaway, but the shipped RPC has **no order-type fork**: the only route to `completed` is `served → completed`, and `ready → served` is permitted for every order type. A takeaway order therefore reaches `completed` only via a hop this doc forbids. Flagged, not silently reconciled — it needs its own ticket.

> **IMPLEMENTATION NOTE (ORDER-AUTO-COMPLETION-001) — `served → completed` now fires AUTOMATICALLY when the order is fully paid. No decision changed; no transition was added.** D-025 above already says an order reaches `completed` when fulfillment is satisfied **AND** payment is `completed`. Until now that conjunction had to be applied by a human clicking a button. It is now applied **by the system, in the same transaction as the operation that made it true**:
> - **Direction A** — a transition lands on `served` and the order is **already** fully paid (the KDS bump).
> - **Direction B** — an **already-`served`** order becomes fully paid (a POS payment / "pay later").
>
> Both chain the one internal helper `app.try_auto_complete_order` at the tail of the operation, under the order row lock the operation **already holds** (`orders FOR UPDATE` is the first lock both `app.apply_order_status_transition` and `app.record_payment` take) — so there is **no new lock, no new lock order and no deadlock**, and no polling job or scheduled worker exists. **The transition table above is UNCHANGED:** direction A chains a **second, already-legal single-step** transition (`served → completed`); it does not widen the machine, and an order still in the kitchen is never completed early.
>
> - **"Fully paid" is a SETTLEMENT test, not a marker test** (`app.order_is_fully_settled`): a live completed payment whose **`amount_minor >= orders.grand_total_minor`** (integer minor units, D-007). This matters because `app.apply_discount` recomputes `grand_total_minor` and is guarded only by *terminal* status — and since a paid order is deliberately still non-terminal (D-025), a later, smaller discount can raise the total back above the frozen payment amount. The payment is never falsified; **the target moves under it**. The same predicate now also hardens the **manual** D-025 gate, so "fully paid" has exactly one definition in the system. See [API_CONTRACT §4.32d](API_CONTRACT.md). (**The discount hole itself is now closed** by `MONEY-SETTLEMENT-CONSISTENCY-001` — see the note below — but the amount-aware test remains necessary regardless: it is what keeps an **under-covered** order visibly unsettled instead of falsely paid.)
> - **A served UNPAID order stays ACTIVE.** That is the point: it is a real exception and must stay visible in *Awaiting close*. The rule never fabricates a payment to force a closure.
> - **The automatic step does not re-run the role gate** — authorization already passed on the *triggering* operation, and the completion is a system-rule consequence of it, not a second human decision. (Concretely: direction A's actor is `kitchen_staff`, who **is** denied the *manual* `→ completed`; re-entering the role-gated core would emit a spurious denial on every KDS bump of a paid order.) The **manual** fronts keep the role gate exactly as frozen.
> - **The manual `owner_complete_order` (§4.32c) is now a RECOVERY action**, not the normal way an order closes — it remains for an order the rule did not close (served and paid before this shipped, or a fail-soft miss). Its audit is stamped `completion_mode='manual'`; the automatic one carries `completion_mode='automatic'` + `completion_trigger`, on the same canonical `order.status_updated` action key (still **money-free**, T-003).
> - **ZERO-TOTAL = NON-CHARGEABLE = SETTLED (human decision).** D-025 says an order completes when fulfillment is satisfied **AND** *(for a **chargeable** order)* payment is `completed` — and the ORDER-COMPLETION-001 note above recorded honestly that **no chargeable flag existed in the schema**. It now has a definition: **`grand_total_minor > 0` IS "chargeable".** A **zero-total** order (comped, 100%-discounted) **owes nothing**, so it is **settled with no payment row — and none is ever created for it.** It therefore auto-completes on `served` like any other settled order. A **positive-total** order is unchanged: it settles only when a live completed payment **covers** the current total. A **negative** total (unreachable under the `orders` CHECK) **fails closed**. All of this lives in the **one** predicate `app.order_is_fully_settled`, which the automatic paths and the manual recovery RPC both consult — there is no second zero-total exception anywhere.
>   - **The audit does not lie about it:** a zero-total completion records `payment_status = 'not_chargeable'`, never `paid` — `audit_events` is append-only (**D-013**) and must never assert a payment that was not taken.
>   - **Consequence — DECIDED, not left open (MONEY-SETTLEMENT-CONSISTENCY-001):** a comped order that auto-completes becomes **terminal and therefore NON-VOIDABLE**, where before it was voidable (it carries no completed payment, so the RF-062 void guard never fired). The human decision is that **`completed` stays TERMINAL, exactly like any other completed order — there is NO special `completed → void` path for a zero-total order** (that would be the first crack in D-024, and post-completion correction is a policy question of its own). What changed instead is the **surface**: the POS no longer offers a Cancel button on an order it knows is terminal, and no longer gates that button on the payment marker. See [API_CONTRACT §4.34](API_CONTRACT.md).
>   - **Post-completion correction (refund / reversal / re-open) remains DEFERRED** and needs its own policy ticket. It is deliberately NOT solved by widening the state machine.

> **IMPLEMENTATION NOTE (MONEY-SETTLEMENT-CONSISTENCY-001) — the DISCOUNT axis is now frozen at payment.** **DECISION D-025** keeps payment and fulfillment independent, which means a fully-PAID order is still `submitted`/`served` — **not terminal** — and `app.apply_discount` was guarded **only** by terminal status. It could therefore re-base `grand_total_minor` **underneath a settled payment**. Now: an order carrying a **live completed payment** refuses **any** discount mutation, in **either** direction (raising *or* lowering the total — after the guest is charged, a price change is a **refund**, and **D-023** makes a completed payment TERMINAL). The order row is locked `FOR UPDATE` first, so a payment cannot race the guard. A **non-chargeable** zero-total order carries no payment and stays discountable. No lifecycle state or transition changed. See [API_CONTRACT §4.5 and §4.34](API_CONTRACT.md).

> **ASSUMPTION (void offline):** `void` is treated as `No-online-only` because it is a privileged, audited financial reversal and offline authorization staleness is a live risk (**R-007**, **Q-009**). If the pilot requires offline voids, this becomes a provisional transition gated by a cached privileged PIN session within the offline window; flagged here rather than silently allowed.

> **ASSUMPTION (`accepted` is retained, not redundant):** The model distinguishes `submitted` (order captured by POS, idempotency id assigned) from `accepted` (kitchen/business acknowledgement that the order is admitted for production). One might argue `submitted` and `accepted` collapse for a single-station setup, but they are kept distinct because: (a) cancellation policy differs (cancel is permitted in both pre-production states but production may begin only after `accepted`); (b) multi-station/KDS acknowledgement (**§3** kitchen_ticket `acknowledged`) maps cleanly onto `accepted`; (c) future auto-accept vs manual-accept configuration. We therefore PROPOSE retaining both states rather than dropping one (approved into the frozen M0A baseline (RF-004)). No order state is considered redundant in this draft.

### 1.2 Forbidden / invalid transitions (non-exhaustive, illustrative)

- `completed → *`, `cancelled → *`, `voided → *` — all terminal; **FORBIDDEN**.
- `draft → cancelled` is **FORBIDDEN** as a distinct path: a `draft` order that is abandoned is discarded locally before submission (no receipt sequence consumed); `cancelled` applies only to *submitted/accepted* pre-production orders. (A draft never entered the server-authoritative lifecycle.)
- `draft → accepted` / `draft → preparing` — **FORBIDDEN** (must pass `submitted`).
- `submitted → served` / `submitted → completed` — **FORBIDDEN** (must pass production states).
- `served → preparing` (dine-in "back to kitchen") — **FORBIDDEN at order level**; achieved only via kitchen recall of a ticket (**§3**), which may pull the order back to `preparing` through the ticket machine.
- `ready → served` for a **takeaway** order — **FORBIDDEN** (takeaway skips served).
- `completed → voided` / `completed → cancelled` — **FORBIDDEN** (`completed` is TERMINAL, **DECISION D-024**); post-completion correction is a refund, which is **DEFERRED** (payment `refunded`, **Q-011** tips aside) — see [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md). Historical completed order records are never rewritten to simulate a refund.
- A cashier-initiated `* → voided` when the cashier carries an explicit `permissions.void_order='false'` deny — **FORBIDDEN**; and **any** `* → voided` of a **PAID** order (regardless of role) — **FORBIDDEN** (SECURITY REQUIREMENT above). A default cashier voiding an UNPAID order is **permitted** (STAFF-CASHIER-PERMISSIONS-001).
- `cancelled` after any order_item reached `preparing` — **FORBIDDEN**; once production has started the only termination is `voided`. This is the canonical **cancelled (pre-production) vs voided (post-submission/post-production)** boundary.

---

## 2. Order item

**Proposed states (D-018, approved into the frozen M0A baseline (RF-004)):** `pending → queued → preparing → ready → served`; plus `voided`, `cancelled` (terminal).
**Terminal:** `voided`, `cancelled`. (`served` is the normal end-of-life but is non-terminal in the enumeration because an item may still be voided post-service alongside an order void; see Forbidden.)
> Note: `served` is the normal **resting end-of-life on the happy path** — parent order completion closes the line rather than moving the item to a separate "completed" status; `voided` is reserved for post-service reversal.

### 2.1 Allowed transitions

| From → To | Actor | Conditions | Reason/Approval | Audit | Offline | Reversible |
| --- | --- | --- | --- | --- | --- | --- |
| pending → queued | server / cashier / POS device | parent order in `submitted`/`accepted`; routed to a kitchen station | No | Always | Yes-provisional | No (forward) |
| queued → preparing | kitchen_staff / KDS device / server | parent order `accepted`/`preparing`; kitchen_station_item `in_preparation` | No | Always | Yes-provisional | Reversible only via kitchen recall (§4) |
| preparing → ready | kitchen_staff / KDS device | station finished item | No | Always | Yes-provisional | Reversible via recall (§4) |
| ready → served | cashier / server | dine-in delivery to guest | No | Always | Yes-provisional | No |
| pending → cancelled | cashier / manager | parent order pre-production; item never produced | Reason REQUIRED | Yes(sensitive) | Yes-provisional | Terminal |
| queued → cancelled | cashier / manager | item not yet `preparing` | Reason REQUIRED | Yes(sensitive) | Yes-provisional | Terminal |
| pending → voided | manager / restaurant_owner / org_owner | item correction post-submission | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| queued → voided | manager / restaurant_owner / org_owner | post-submission correction | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| preparing → voided | manager / restaurant_owner / org_owner | post-production correction; cancels linked kitchen_station_item | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| ready → voided | manager / restaurant_owner / org_owner | post-production correction | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| served → voided | manager / restaurant_owner / org_owner | comp/error after service; allowed only when **no `completed` payment exists** on the parent order — if the order has a `completed` payment the item void is **REJECTED in MVP** (would require the deferred refund flow, **D-024**) | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |

### 2.2 Forbidden / invalid transitions

- `voided → *`, `cancelled → *` — terminal; **FORBIDDEN**.
- `preparing → cancelled` / `ready → cancelled` / `served → cancelled` — **FORBIDDEN**; once an item entered production the only removal is `voided` (mirrors order-level cancel-vs-void boundary).
- `served → ready`, `ready → preparing`, `preparing → queued` without a recall event — **FORBIDDEN**; backward movement is exclusively a kitchen recall (§4) that the order_item follows.
- `pending → preparing` (skipping `queued`) — **FORBIDDEN**.
- Cashier-initiated `* → voided` when the cashier carries an explicit `void_order='false'` deny, or **any** void of a PAID order — **FORBIDDEN** (SECURITY REQUIREMENT, §1). A default cashier voiding an UNPAID order is permitted (STAFF-CASHIER-PERMISSIONS-001).

---

## 3. Kitchen ticket

**Proposed states (D-018, approved into the frozen M0A baseline (RF-004)):** `new → acknowledged → in_preparation → ready → bumped`; plus `recalled` (`bumped → in_preparation`, audited), `cancelled`.
**Terminal:** `bumped`, `cancelled`.
> Note on `recalled`: per D-018 a recall is the audited transition `bumped → in_preparation`. `recalled` is a **transition / audit marker**, not a persistent stored status value: it is the *named action/audit reason* for that transition, and the ticket's resting state after recall is `in_preparation`. (See ASSUMPTION below.)

### 3.1 Allowed transitions

| From → To | Actor | Conditions | Reason/Approval | Audit | Offline | Reversible |
| --- | --- | --- | --- | --- | --- | --- |
| new → acknowledged | kitchen_staff / KDS device | ticket displayed at station; corresponds to order `accepted` | No | Always | Yes-provisional | No |
| acknowledged → in_preparation | kitchen_staff / KDS device | station begins; order moves toward `preparing` | No | Always | Yes-provisional | No |
| in_preparation → ready | kitchen_staff / KDS device | all station items ready | No | Always | Yes-provisional | Reversible via recall |
| ready → bumped | kitchen_staff / KDS device | expo/bump confirms completion | No | Always | Yes-provisional | Reversible via recall (`bumped → in_preparation`) |
| bumped → in_preparation (**recalled**) | kitchen_staff / manager / KDS device | ticket bumped in error or remake needed | **Reason REQUIRED** (recall reason) | Always (audited recall, D-018) | Yes-provisional | This *is* the reverse; re-bump returns to `bumped` |
| new → cancelled | server / manager | parent order/item cancelled or voided pre/post production | Reason REQUIRED (propagated) | Yes(sensitive) | Yes-provisional | Terminal |
| acknowledged → cancelled | server / manager | parent order cancelled/voided | Reason REQUIRED | Yes(sensitive) | Yes-provisional | Terminal |
| in_preparation → cancelled | server / manager | parent order voided | Reason REQUIRED | Yes(sensitive) | No-online-only (follows order void) | Terminal |
| ready → cancelled | server / manager | parent order voided | Reason REQUIRED | Yes(sensitive) | No-online-only | Terminal |

### 3.2 Forbidden / invalid transitions

- `bumped → *` except the audited recall `bumped → in_preparation` — **FORBIDDEN**.
- `cancelled → *` — terminal; **FORBIDDEN**.
- `new → in_preparation` (skipping `acknowledged`) — **FORBIDDEN**.
- `ready → acknowledged`, `in_preparation → acknowledged`, `in_preparation → new` — **FORBIDDEN**; the only backward path is the explicit `bumped → in_preparation` recall.
- Recall without a reason — **FORBIDDEN** (recall is always audited, D-018).
- `bumped → cancelled` — **FORBIDDEN**; a bumped ticket whose order is later voided is handled by the order/payment void at the order level, not by cancelling a terminal ticket.

> **ASSUMPTION (`recalled`):** D-018 lists `recalled` as the transition `bumped → in_preparation`. We model it as a transition + audit reason, with `in_preparation` as the resting state, rather than introducing a separate persistent `recalled` resting state. This avoids an ambiguous state with no defined exits while honouring the proposed enumeration. Flagged for reviewer (Codex) confirmation rather than silently dropped.

---

## 4. Kitchen station item

**Proposed states (D-018, approved into the frozen M0A baseline (RF-004)):** `queued → in_preparation → ready → bumped`; plus `voided`.
**Terminal:** `bumped`, `voided`.

### 4.1 Allowed transitions

| From → To | Actor | Conditions | Reason/Approval | Audit | Offline | Reversible |
| --- | --- | --- | --- | --- | --- | --- |
| queued → in_preparation | kitchen_staff / KDS device | parent kitchen_ticket `in_preparation` | No | Always | Yes-provisional | Reversible via ticket recall |
| in_preparation → ready | kitchen_staff / KDS device | item finished at station | No | Always | Yes-provisional | Reversible via ticket recall |
| ready → bumped | kitchen_staff / KDS device | item bumped | No | Always | Yes-provisional | Reversible if parent ticket recalled (`bumped → in_preparation`) |
| queued → voided | manager / restaurant_owner / org_owner | linked order_item voided | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| in_preparation → voided | manager / restaurant_owner / org_owner | linked order_item voided | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| ready → voided | manager / restaurant_owner / org_owner | linked order_item voided | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |

### 4.2 Forbidden / invalid transitions

- `bumped → *` except return via parent ticket recall (`bumped → in_preparation`) — **FORBIDDEN** as a standalone item move; recall is driven by the kitchen_ticket machine (§3).
- `voided → *` — terminal; **FORBIDDEN**.
- `queued → ready` (skipping `in_preparation`) — **FORBIDDEN**.
- `bumped → voided` — **FORBIDDEN** (terminal; handled via order/item void at higher level).
- Backward `ready → in_preparation`/`in_preparation → queued` without a recall — **FORBIDDEN**.

---

## 5. Payment

**Proposed states (D-018, approved into the frozen M0A baseline (RF-004)):** `pending → tendered → completed`; plus `voided`, `failed`; `refunded` (**DEFERRED**).
**Terminal:** `completed`, `voided`, `failed`.
> **Independence note (D-025):** payment and order fulfillment are independent axes; **PAY-FIRST** is supported. A payment may start while the order is in `submitted`/`accepted`/`preparing`/`ready`/`served` (excludes `draft`/`cancelled`/`voided`/`completed`). Completing a payment does **not** auto-advance fulfillment.

### 5.1 Allowed transitions

| From → To | Actor | Conditions | Reason/Approval | Audit | Offline | Reversible |
| --- | --- | --- | --- | --- | --- | --- |
| pending → tendered | cashier / manager (PIN session) | order in an eligible pay-first state — `submitted`/`accepted`/`preparing`/`ready`/`served` (**D-025**); amount in integer `_minor` units (**D-007**); single currency per order (**Q-007**) | No | Always | Yes-provisional | Reversible by `tendered → voided` before completion |
| tendered → completed | server (settlement) / cashier | tender confirmed; receipt sequence reconciled to authoritative (**D-021**) | No | Always | Yes-provisional (provisional completion reconciled on sync) | **TERMINAL** — no post-completion reversal in MVP; refunds **DEFERRED** (**D-023**) |
| pending → failed | server / cashier | tender declined / aborted | Reason RECOMMENDED | Always | Yes-provisional | Terminal (a new payment row is created to retry) |
| tendered → failed | server | settlement failed (e.g. gateway) | Reason RECOMMENDED | Always | No-online-only | Terminal |
| pending → voided | manager / cashier(with permission) | payment captured in error before tender; authorized actor + reason + audit (**D-023**) | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| tendered → voided | manager / restaurant_owner / org_owner | mis-tender correction **before completion**; authorized actor + reason + audit; **must account for any cash physically received before finalization** (**D-023**) | **Reason + authorization REQUIRED** | Yes(sensitive) | No-online-only | Terminal |

> **DECISION D-023 (payment terminal + void only before completion):** `payment.completed` is **TERMINAL** in MVP. A payment void is allowed **ONLY before completion**: `pending → voided` and `tendered → voided`, each requiring an authorized actor + reason + audit (**D-013**); `tendered → voided` must additionally account for any cash physically received before finalization. `completed → voided` is **FORBIDDEN**. There is **NO post-completion payment reversal in MVP** — refunds/reversals/post-completion corrections are **DEFERRED** (no hidden refund). Plain `cashier` without permission CANNOT perform a void (canonical isolation test, [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)).

### 5.2 Forbidden / invalid transitions

- `* → refunded` — **DEFERRED**: refunds are explicitly out of MVP scope (**D-018**, **D-023**, [MVP_SCOPE.md](MVP_SCOPE.md)); no transition into `refunded` exists in MVP. There is **NO post-completion payment reversal in MVP** — refunds are DEFERRED (no hidden refund mechanism).
- `completed → voided` — **FORBIDDEN** (`completed` is TERMINAL, **D-023**); payment voids are allowed only **before** completion (`pending → voided`, `tendered → voided`). Refunds/reversals are **DEFERRED**.
- `completed → tendered`, `completed → pending`, `completed → failed` — **FORBIDDEN** (no backward; `completed` is terminal, **D-023**).
- `voided → *`, `failed → *` — terminal; **FORBIDDEN**.
- `pending → completed` (skipping `tendered`) — **FORBIDDEN**.
- Duplicate payment creation on retry — prevented by idempotency `device_id` + `local_operation_id` (**D-022**); not a state transition but enforced at insert (see [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md)).

---

## 6. Shift

**Proposed states (D-018, approved into the frozen M0A baseline (RF-004)):** `opening → open → closing → closed → reconciled`.
**Terminal:** `reconciled`.

### 6.1 Allowed transitions

| From → To | Actor | Conditions | Reason/Approval | Audit | Offline | Reversible |
| --- | --- | --- | --- | --- | --- | --- |
| (create) → opening | cashier / manager (PIN session) | no open shift for same device/station; org/restaurant/branch scoped | No | Always | Yes-provisional | n/a |
| opening → open | cashier / manager | cash_drawer_session `opened`/`active` bound (**§7**); opening float recorded | No | Always | Yes-provisional | No |
| open → closing | cashier / manager | end of shift initiated | No | Always | Yes-provisional | Reversible to `open` only by manager (reopen) — see `closing → open` row |
| closing → open | manager / restaurant_owner / org_owner | shift not yet closed (reopen as audited correction) | **Reason REQUIRED** | Yes(sensitive) | No-online-only | This *is* the reverse of `open → closing` |
| closing → closed | cashier / authorized manager | **close/count step** (`close_shift`): drawer counted, counted amount recorded, `variance = counted − expected`; cash_drawer_session moves `counting → closed` (**§7**) | No | Always | Yes-provisional | No (corrections happen in the separate reconciliation step) |
| closed → reconciled | manager / restaurant_owner / org_owner | **reconciliation step** (`reconcile_shift`, performed later): expected/counted/variance reviewed/approved; reports finalized | **Reason/note REQUIRED if variance exceeds threshold** | Yes(sensitive) | No-online-only | Terminal |

> **DECISION D-028 (shift split + accountant read-only):** close/count and reconciliation are **SEPARATE operations / separate RPCs** — proposed `close_shift` and `reconcile_shift`; **one RPC must NOT do both**. *Close/count* (`close_shift`, by **cashier or authorized manager**): shift `open → closing`, drawer `open → counting`, record counted amount, compute `variance = counted − expected`, then `→ closed`, audited. *Reconciliation* (`reconcile_shift`, **later**, by **manager / restaurant_owner / org_owner**): review expected/counted/variance, reason/note when required, shift + drawer `closed → reconciled`, sensitive audit. `accountant` is **strictly read-only** (**D-028**, **Q-017**) and performs **NO** transition anywhere — including `closed → reconciled`; it may only view.

### 6.2 Forbidden / invalid transitions

- `reconciled → *` — terminal; **FORBIDDEN**.
- `closed → open` / `closed → opening` — **FORBIDDEN**; a closed shift cannot reopen. Re-opening before close is the explicit `closing → open` allowed row (manager/restaurant_owner/org_owner only, audited), permitted only as a correction.
- `open → closed` (skipping `closing`) — **FORBIDDEN**.
- `opening → closing` (skipping `open`) — **FORBIDDEN**.
- Opening a second shift on a device/station that already has a non-terminal shift — **FORBIDDEN** (one active shift per station).

> **ASSUMPTION:** `closing → open` (manager reopen) is permitted as an audited correction and is now an explicit allowed-transition row in §6.1; this does not add a state, only a reverse edge within the proposed values. If the pilot forbids reopening, remove this edge — flagged, not silently assumed.

---

## 7. Cash drawer session

**Proposed states (D-018, approved into the frozen M0A baseline (RF-004)):** `opened(opening float) → active → counting → closed(counted+variance) → reconciled`.
**Terminal:** `reconciled`. Bound to a shift (**§6**).

### 7.1 Allowed transitions

| From → To | Actor | Conditions | Reason/Approval | Audit | Offline | Reversible |
| --- | --- | --- | --- | --- | --- | --- |
| (create) → opened | cashier / manager | bound to a shift in `opening`/`open`; opening float in `_minor` units | No | Always | Yes-provisional | n/a |
| opened → active | cashier | first cash movement / shift `open` | No | Always | Yes-provisional | No |
| active → counting | cashier / authorized manager | drawer count initiated at shift close (part of the `close_shift` close/count step, **D-028**) | No | Always | Yes-provisional | Reversible to `active` (recount) by manager |
| counting → closed | cashier / authorized manager | **close/count step** (`close_shift`, **D-028**): counted total + variance computed as `variance_minor = counted − expected` (signed minor units); arithmetic owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) | **Reason REQUIRED if variance ≠ 0** | Yes(sensitive) | Yes-provisional (variance reconciled on sync) | No |
| closed → reconciled | manager / restaurant_owner / org_owner | **reconciliation step** (`reconcile_shift`, later, **D-028**): variance reviewed/approved; bound shift moving to `reconciled` | **Reason/approval REQUIRED for over-threshold variance** | Yes(sensitive) | No-online-only | Terminal |

> **DECISION D-028 (cash drawer follows the shift split):** the drawer count (`counting → closed`) is part of the close/count step (`close_shift`, cashier or authorized manager); the drawer `closed → reconciled` is part of the separate, later reconciliation step (`reconcile_shift`, manager / restaurant_owner / org_owner). One RPC must not do both. `accountant` is strictly read-only and performs no drawer transition.

### 7.2 Forbidden / invalid transitions

- `reconciled → *` — terminal; **FORBIDDEN**.
- `closed → active` / `closed → counting` — **FORBIDDEN** (no reopen after close; recount only `counting → active`).
- `opened → counting` / `opened → closed` (skipping `active`) — **FORBIDDEN**.
- A cash_drawer_session not bound to a shift — **FORBIDDEN** (must be bound, D-018).
- `active → reconciled` (skipping counting/closed) — **FORBIDDEN**.

---

## 8. Print job

**Proposed states (D-018, approved into the frozen M0A baseline (RF-004)):** `created → queued → printing → printed`; plus `failed → retrying`, `cancelled`, `abandoned` (after max retries).
**Terminal:** `printed`, `cancelled`, `abandoned`.
> Print job behaviour and the ESC/POS adapter are owned by [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md); this section owns only the state transitions.
> **Cash-drawer jobs (`drawer_kick` job_type — RF-58 / RF-074) are a special one-shot variant.** To keep the physical drawer **at-most-once**, the RF-074 trigger layer creates them with `max_retries = 0` — a single dispatch, and any failure goes straight to `failed → abandoned`, **never** `retrying`. They are **never reprinted**: the spool refuses `reprint()` of a `drawer_kick` job because a re-issue would open the drawer again. A crash-interrupted kick (`printing → possiblyPrinted`) is left for manual review and **never auto-replayed**.

### 8.1 Allowed transitions

| From → To | Actor | Conditions | Reason/Approval | Audit | Offline | Reversible |
| --- | --- | --- | --- | --- | --- | --- |
| (create) → created | server / POS device / KDS device | render payload prepared (localized ar/he/en, **D-014**; raster fallback **Q-015**) | No | Optional | Yes-provisional | n/a |
| created → queued | device | adapter queue accepts job | No | Optional | Yes-provisional | No |
| queued → printing | device (printer adapter) | printer reachable | No | Optional | Yes-provisional | No |
| printing → printed | device | adapter confirms success | No | Optional | Yes-provisional | Terminal |
| printing → failed | device | adapter error / printer offline | Reason auto-captured (error code) | Yes (error logged) | Yes-provisional | n/a |
| queued → failed | device | dispatch error before printing | Reason auto-captured | Yes (error logged) | Yes-provisional | n/a |
| failed → retrying | device / server | retry attempt remaining (< max retries; backoff) | No | Optional | Yes-provisional | n/a |
| retrying → printing | device | retry dispatch | No | Optional | Yes-provisional | No |
| failed → abandoned | server / device | **max retries exceeded** | Reason auto-captured (final error) | Yes | Yes-provisional | Terminal |
| created → cancelled | cashier / manager / device | job no longer needed (e.g. order voided before print) | Reason RECOMMENDED | Optional | Yes-provisional | Terminal |
| queued → cancelled | cashier / manager / device | job superseded | Reason RECOMMENDED | Optional | Yes-provisional | Terminal |

### 8.2 Forbidden / invalid transitions

- `printed → *`, `cancelled → *`, `abandoned → *` — terminal; **FORBIDDEN**.
- `printing → cancelled` — **FORBIDDEN** (cannot cancel mid-print; let it succeed or fail). Reprint is a *new* print_job, never a reverse transition.
- `failed → printed` directly (without `retrying → printing`) — **FORBIDDEN**.
- `abandoned → retrying` — **FORBIDDEN**; once abandoned, a new job must be created.
- `created → printing` (skipping `queued`) — **FORBIDDEN**.

> Print jobs carry no money state and are not financially sensitive, so most transitions are `Optional` audit; failures/abandonment ARE recorded for operational diagnostics (see [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md)). **RISK R-001/R-006** (hardware variation, Arabic/Hebrew encoding) are mitigated by the failed/retry/abandoned path plus raster fallback.

---

## 9. Device pairing

**Proposed states (D-018, approved into the frozen M0A baseline (RF-004)):** `code_issued → pending → paired → active → suspended → revoked`; plus `code_expired`, `rejected`.
**Terminal:** `revoked`, `code_expired`, `rejected`.
> Identity/credential semantics owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) (device identity = distinct from human, **D-005/D-006**). This section owns the pairing lifecycle transitions.

### 9.1 Allowed transitions

| From → To | Actor | Conditions | Reason/Approval | Audit | Offline | Reversible |
| --- | --- | --- | --- | --- | --- | --- |
| (create) → code_issued | manager / restaurant_owner / org_owner | short-lived enrollment code generated, scoped to org/restaurant/branch | No | Yes(sensitive) | No-online-only | n/a |
| code_issued → pending | device | device submits code before expiry | No | Yes(sensitive) | No-online-only | No |
| code_issued → code_expired | server | enrollment code TTL elapsed | No | Yes | Server-only | Terminal |
| pending → paired | manager / restaurant_owner / org_owner | enrollment approved; device credentials issued | **Approval REQUIRED** | Yes(sensitive) | No-online-only | Reversible by revoke |
| pending → rejected | manager / restaurant_owner / org_owner | enrollment denied | Reason RECOMMENDED | Yes(sensitive) | No-online-only | Terminal |
| paired → active | manager / server | device fully provisioned; allowed to open device_session | No | Yes(sensitive) | No-online-only | Reversible via suspend/revoke |
| active → suspended | manager / restaurant_owner / org_owner | temporary disable (lost/maintenance) | Reason REQUIRED | Yes(sensitive) | No-online-only | Reversible (`suspended → active`) |
| suspended → active | manager / restaurant_owner / org_owner | re-enable | Reason RECOMMENDED | Yes(sensitive) | No-online-only | n/a |
| active → revoked | manager / restaurant_owner / org_owner; or platform administration via the separate audited grant path (**D-026**) | permanent removal | **Reason REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| suspended → revoked | manager / restaurant_owner / org_owner; or platform administration via the separate audited grant path (**D-026**) | permanent removal | **Reason REQUIRED** | Yes(sensitive) | No-online-only | Terminal |
| paired → revoked | manager / restaurant_owner / org_owner | remove before activation | Reason REQUIRED | Yes(sensitive) | No-online-only | Terminal |

> **SECURITY REQUIREMENT:** pairing-state mutations are sensitive and server-authoritative (online-only). A device transitioned to `suspended`/`revoked` MUST lose **future** access; provisional operations it created during an offline window are re-validated and **rejected** on sync if the device was revoked (**RISK R-007**, **Q-009**). This realizes the canonical test "a revoked device cannot sync new operations" ([SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)). `platform_admin` actions on pairing follow the separate explicitly-audited admin path (**D-012**).

### 9.2 Forbidden / invalid transitions

- `revoked → *`, `code_expired → *`, `rejected → *` — terminal; **FORBIDDEN** (a revoked device must re-enroll from `code_issued`).
- `code_issued → paired` (skipping `pending`/approval) — **FORBIDDEN**.
- `pending → active` (skipping `paired`) — **FORBIDDEN**.
- `suspended → paired`, `active → paired`, `active → pending` — **FORBIDDEN** (no backward to enrollment).
- Any device-initiated transition to `paired`/`active`/`suspended`/`revoked` — **FORBIDDEN**; only privileged human roles (or server for expiry) drive these. A device may only move `code_issued → pending`.

> **Activation + session start (DECISION D-034, RF-112).** The `paired → active` edge is owned by the RF-112 **`activate_device`** RPC ([API_CONTRACT](API_CONTRACT.md) §4.28) — a **separate** management-authorized step, **never** folded into `approve_device` (which stops at `paired`, the `pending → paired` approval edge) and **never** performed inside session-start. **`pending → active` remains FORBIDDEN** (above) — activation can never skip approval. A **device session** (`start_device_session`, [API_CONTRACT](API_CONTRACT.md) §4.29) may be opened **only on an `active` pairing**; `paired`/`pending`/`suspended`/`revoked`/`code_expired` are rejected (fail-closed). See [DECISIONS](DECISIONS.md) D-034.

---

## 10. Sync operation

**Proposed states (D-018, approved into the frozen M0A baseline (RF-004)):** `created → pending → in_flight → applied`; plus `rejected` (permanent), `dead` (poison after max retries), `conflict → resolved`.
**Terminal:** `applied`, `rejected`, `dead`.
> Mechanics (outbox/inbox, idempotency, backoff, conflict policy) owned by [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md); this section owns the operation lifecycle states.

### 10.1 Allowed transitions

| From → To | Actor | Conditions | Reason/Approval | Audit | Offline | Reversible |
| --- | --- | --- | --- | --- | --- | --- |
| (create) → created | device (local outbox) | local op enqueued with `device_id` + `local_operation_id` (**D-022**), client timestamp, revision | No | Local log | Yes-provisional (created offline by design) | n/a |
| created → pending | device | op ready to ship; ordering of dependent ops resolved | No | Local log | Yes-provisional | No |
| pending → in_flight | device / server | transmission started; server inbox receives | No | Server log | No-online-only | No |
| in_flight → applied | server | op validated, idempotency-deduped, committed to authoritative store | No | Server log + domain audit if op is sensitive | Server-only | **Terminal** (the applied domain effect may itself be reversible, e.g. void; the *sync op* is not re-run) |
| in_flight → conflict | server | server revision ≠ client base revision (multi-device conflict) | No | Server log | Server-only | Resolvable |
| conflict → resolved | server (per conflict policy, **Q-010**) / manager (manual) | conflict policy applied (LWW or domain rule) | Reason if manual override | Yes(sensitive) if manual | No-online-only | n/a (resolution then yields applied effect) |
| conflict → rejected | server / manager | conflict cannot be auto-resolved and is permanently rejected | Reason REQUIRED | Yes | No-online-only | Terminal |
| in_flight → rejected | server | permanent validation failure (e.g. revoked device/removed employee; **R-007**) | Reason auto-captured | Yes | Server-only | Terminal |
| in_flight → pending | device | transient network failure; retry with backoff (< max retries) | No | Local log | No-online-only | n/a (re-attempt) |
| pending → dead | server / device | **poison operation: max retries exceeded** (permanent-rejection / poison handling) | Reason auto-captured | Yes | Server-only / local | Terminal |
| in_flight → dead | server | repeated failures exhaust retry budget | Reason auto-captured | Yes | Server-only | Terminal |

> **`dead` = poison-operation after max retries.** A `dead` op is parked for human inspection (sync status visible to cashier per **D-010**), never silently dropped. `rejected` = permanent business/authorization rejection (distinct from `dead` which is exhausted-retry). `resolved` is the successful exit of a `conflict`, after which the op proceeds to `applied`. Retry/backoff constants (**Q-018**), poison/dead operation tooling & handling (**Q-020**), reconciliation order (**Q-021**), and clock-skew handling for last-writer-wins tie-breaks (**Q-024**) are open questions owned by [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) / [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

### 10.2 Forbidden / invalid transitions

- `applied → *`, `rejected → *`, `dead → *` — terminal; **FORBIDDEN**. A correction is a *new* sync operation with a new `local_operation_id`, never re-running a terminal op (idempotency, **D-022**).
- `created → in_flight` (skipping `pending`) — **FORBIDDEN**.
- `created → applied` (client self-applying authoritatively) — **FORBIDDEN**; only the server moves an op to `applied`.
- `conflict → applied` directly (skipping `resolved`) — **FORBIDDEN**.
- Re-using a terminal op's `local_operation_id` to resurrect it — **FORBIDDEN** (would break idempotency / duplicate-prevention).
- Device transitioning an op to `applied`/`rejected`/`dead`(server-side) — **FORBIDDEN**; those are server-authoritative (**D-010**).

---

## 11. Cross-machine coupling (summary of side-effects)

These are the load-bearing couplings tests must cover (full conflict/sync rules in [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md); transition legality above):

- Order `submitted` reserves a **provisional** per-branch receipt sequence; `payment completed` / order `completed` reconciles it to the authoritative server sequence (**D-021**).
- Order `* → voided` cascades: linked `order_item → voided`, `kitchen_station_item → voided`, and non-terminal `kitchen_ticket → cancelled`. Per **D-024**, a pre-completion order void/cancel is **REJECTED in MVP** if any associated `payment` is `completed` (it would require the deferred refund flow); a completed `payment` cannot be reversed (`completed → voided` FORBIDDEN, **D-023**). The legacy "void-paid permission" path applies only where no completed payment exists; the historical completed records are never rewritten.
- Order `cancelled` is only legal while ALL items are pre-production (no item past `queued`); otherwise termination is `voided`.
- Kitchen ticket recall (`bumped → in_preparation`) can pull dependent `order_item`s back to `preparing` and the parent order back to `preparing` from `ready` (the only sanctioned backward order movement).
- Shift `closed → reconciled` requires its bound cash_drawer_session at `closed`/`reconciled`; cash variance reason/approval gates flow from §7.
- A `device_pairing` reaching `suspended`/`revoked`, or an `employee_profile` set inactive, causes the server to **reject** that actor's in-flight/queued `sync_operation`s on validation (`in_flight → rejected`), enforcing **R-007** and the canonical revocation tests.

## 12. Open questions affecting transitions

- **Q-009** offline authorization validity window — bounds how long PIN/device authority is honoured for provisional transitions before server rejection. Until frozen, privileged voids are kept online-only (ASSUMPTION, §1).
- **Q-010** per-entity conflict-resolution policy — governs `sync_operation` `conflict → resolved` vs `conflict → rejected` (§10); clock-skew handling for last-writer-wins tie-breaks is tracked as **Q-024** ([OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md)).
- **Q-008** MFA scope — affects which privileged transitions (voids, reconciliation, pairing approval) demand step-up auth.
- **Q-015** Arabic/Hebrew print encoding & connectivity — affects print_job `failed/retrying/abandoned` frequency (§8).
- **Q-017** accountant role in MVP — if shipped, remains read-only and performs no transition in any machine.
- **Q-007** currency model — single currency per order is assumed for payment transitions (§5).

---

*End of STATE_MACHINES.md. State values are PROPOSED by D-018 (approved into the frozen M0A baseline (RF-004), not frozen); transitions defined here are the M0A candidate frozen as the M0A architecture baseline at RF-004 for RF-001 and are subject to ChatGPT and independent Codex review per D-016 before any freeze.*
