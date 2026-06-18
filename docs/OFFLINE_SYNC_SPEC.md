# OFFLINE_SYNC_SPEC.md — Offline-First Synchronization (Authoritative)

> **Status — DRAFT (candidate), not yet frozen.** Drafted by Claude Code (RF-001) · pending ChatGPT review · pending independent Codex review · pending human approval (Saleh). Only the explicit RF-001 invariants (below/where cited) are binding requirements; every other architectural choice is a **PROPOSED DECISION** pending review and human approval. Architecture freeze happens only after independent review, required fixes, and Saleh's approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> **Document ownership.** This document OWNS the offline-first synchronization model for RestoFlow: the local store, outbox, server inbox/ledger, idempotency, ordering, retry, conflict resolution, revocation-while-offline behavior, tombstones, and reconciliation. It defines **concrete** rules — never "sync later."
>
> Topics owned elsewhere are referenced, not redefined:
> - Entities, fields, relationships: [DOMAIN_MODEL.md](DOMAIN_MODEL.md)
> - State enumerations and transitions: [STATE_MACHINES.md](STATE_MACHINES.md)
> - Money/rounding/receipt rules: [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md)
> - Security, RLS, isolation tests, audit: [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)
> - RPC/endpoint contracts: [API_CONTRACT.md](API_CONTRACT.md)
> - System structure: [ARCHITECTURE.md](ARCHITECTURE.md)
> - Decision log: [DECISIONS.md](DECISIONS.md). Open questions: [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).
>
> Decision IDs (**D-xxx**), open-question IDs (**Q-xxx**), and risk IDs (**R-xxx**) are owned by those registers; this document cites them and never invents parallel IDs. Where this document proposes a concrete numeric default not yet frozen, it is labeled **DECISION-candidate** and surfaced as an **OPEN QUESTION** at the end.

---

## 1. Scope and Principles

RestoFlow is a **multi-tenant** Restaurant Operating System. Synchronization is multi-tenant at every layer: every synced row and every sync operation carries `organization_id` (the primary isolation boundary, **DECISION D-001**) plus `restaurant_id`, `branch_id`, `device_id`, `station_id` where relevant (**DECISION D-002**, naming per **DECISION D-017**). No part of this design assumes a single organization, restaurant, or branch.

Core principles:

1. **Local-first (DECISION D-010).** SQLite via Drift is the immediate operational store. The POS and KDS fully function with no internet. The network is treated as eventually-available, not required.
2. **Durable outbox / inbox (DECISION D-010).** Every mutation is recorded locally in an outbox and shipped to a server inbox + processed-operation ledger. There is no path where a mutation is "lost" because the network was down.
3. **Idempotency everywhere (DECISION D-022).** Every mutating client operation carries a stable idempotency key `(device_id, local_operation_id)`. Re-delivery never double-applies.
4. **Server-authoritative on money and sequences (DECISION D-007, D-008, D-021).** Totals, receipt numbers, and monetary outcomes are reconciled to authoritative server values. Money is integer **minor units**; no floating point appears in any sync payload, ever.
5. **Realtime is an enhancement only (DECISION D-010).** Supabase Realtime may accelerate propagation but is NEVER the source of truth and NEVER the only sync mechanism. Pull-based reconciliation must work with Realtime fully disabled.
6. **Security is preserved offline (DECISION D-011, D-012; R-007).** Offline does not bypass authorization. The server re-authorizes every operation on ingest; operations that violate policy are rejected and audited.

**SECURITY REQUIREMENT.** No service-role credential is ever embedded in a Flutter client (**DECISION D-011**). All sync writes go through the authenticated device/PIN session and authorized RPC paths; the sync transport cannot escalate privilege.

---

## 2. Local Store (Drift / SQLite)

**DECISION D-010** establishes Drift/SQLite as the immediate local operational store. All reads served to the UI come from the local store, so the UI never blocks on the network.

### 2.1 Sync columns on every syncable entity
Per **DECISION D-017**, every sync-relevant table (local and server) carries:

| Column | Purpose |
| --- | --- |
| `id` (UUID) | Primary key; **client-generated UUIDv4** so rows exist before any server round-trip. |
| `organization_id` (+ `restaurant_id` / `branch_id` / `device_id` / `station_id` as relevant) | Tenant + operational scoping. |
| `revision` (integer) | Per-entity monotonic version, incremented on each accepted mutation (optimistic concurrency token). |
| `client_updated_at` (timestamptz) | Wall-clock time the change was made on the device. Used for display/diagnostics and as a tie-break input, NOT as a trust anchor. |
| `server_updated_at` (timestamptz) | Authoritative time set by the server on accept. Used for ordered pulls. |
| `created_at` / `updated_at` | Standard audit timestamps. |
| `deleted_at` (timestamptz, nullable) | Tombstone marker (**DECISION D-020**); see §13. |

**ASSUMPTION.** UUID primary keys are client-generatable without collision risk (UUIDv4). This removes the need for server-assigned surrogate keys for ordinary entities; the only server-assigned identifier is the per-branch receipt sequence (**DECISION D-021**, §11).

### 2.2 Local-only sync bookkeeping tables (not business data)
These exist only on the device:

- **`outbox`** — the durable queue of pending mutating operations (§3).
- **`sync_cursor`** — per-entity-class high-water marks (`last_server_updated_at`, `last_revision_seen`) used to request incremental pulls (§14).
- **`processed_pull_log`** — dedup guard for inbound changes (so a pulled change already applied locally is not re-applied destructively).

---

## 3. Local Outbox

Every mutating action the cashier/KDS performs creates exactly one **outbox entry** in the same local SQLite transaction that writes the business change. This guarantees the local store and the outbox never diverge (no "applied locally but not enqueued" gap), which is essential for crash recovery (§7).

Each outbox entry contains:

| Field | Meaning |
| --- | --- |
| `local_operation_id` (UUID) | Monotonic-per-device local op id. With `device_id` forms the idempotency key (**DECISION D-022**). |
| `device_id` | Authenticated device identity (**DECISION D-005/D-006**). |
| `organization_id` / `restaurant_id` / `branch_id` / `station_id` | Scoping carried with the op. |
| `operation_type` | e.g. `order.create`, `order_item.add`, `order.void`, `payment.create`, `kitchen_ticket.bump`. Maps to a server RPC (**API_CONTRACT.md**). |
| `target_entity` / `target_id` | The entity and its client UUID. |
| `payload` | Operation arguments (money fields integer `_minor` only; price/modifier **snapshots** included per **DECISION D-008**). |
| `depends_on` | Zero or more `local_operation_id`s that must be applied first (§5). |
| `base_revision` | The entity revision the change was computed against (optimistic concurrency, §9). |
| `client_created_at` / `client_updated_at` | Client timestamps. |
| `sync_state` | Sync operation state (§4): `created → pending → in_flight → applied`; plus `rejected`, `dead`, `conflict → resolved`. |
| `attempt_count` / `next_attempt_at` | Retry bookkeeping (§6). |
| `last_error_code` / `last_error_class` | Diagnostics; classifies transient vs permanent (§8). |

The outbox is processed **in dependency-respecting FIFO order per branch/device** (§5). Entries are never deleted on success; they transition to `applied` and may be pruned by a retention job after server acknowledgement (retention window is a **DECISION-candidate**, see **OPEN QUESTION Q-019** (was O-S2)).

---

## 4. Sync Operation State Machine (reference)

The sync operation lifecycle enumeration is a **PROPOSED state enumeration (DECISION D-018; pending review and approval — RF-001 §8 directs us to evaluate, not assume final)** and its transitions are owned by [STATE_MACHINES.md](STATE_MACHINES.md). This document references it; it does not redefine it.

```
created → pending → in_flight → applied
                 ↘ rejected (permanent)
                 ↘ dead (poison, after max retries)
   in_flight → conflict → resolved
```

- **Terminal:** `applied`, `rejected`, `dead`.
- `rejected` = permanent rejection (auth/validation), never retried automatically (§8, §12).
- `dead` = poison operation: exceeded max retries on a transient-looking error (§6, §8).
- `conflict` = server detected a concurrent change; resolution (§10) produces `resolved`, which re-routes to either `applied` (after rebase) or `rejected` (if resolution forbids the change).

This is the **same machine** referenced by the local `outbox.sync_state` and the server `sync_operations` ledger row, so client and server share one vocabulary.

---

## 5. Ordering of Dependent Operations

Operations frequently depend on earlier ones (an order must exist before its items; items before the order's payment; a kitchen ticket before its bump). Misordered delivery would cause spurious validation failures.

Rules:

1. **Per-device FIFO baseline.** Within a single device, outbox entries are shipped in creation order.
2. **Explicit `depends_on` edges.** An operation declares its prerequisites by `local_operation_id`. The client will not advance a dependent operation to `in_flight` until all `depends_on` operations are `applied`.
3. **Server-side dependency guard.** The server inbox also enforces dependencies: if `payment.create` references an `order` whose creating operation has not yet been applied, the server returns a **transient** "dependency-not-ready" result (retryable, §8), NOT a permanent rejection — protecting against out-of-order delivery across retries.
4. **Stable canonical examples** (transitions per **DECISION D-018**, owned by STATE_MACHINES.md):
   - `order.create` (draft) → `order_item.add`(s) → `order.submit` → `payment.create`.
   - `kitchen_ticket` lifecycle (`new → acknowledged → in_preparation → ready → bumped`) operations preserve order; a `recalled` (bumped → in_preparation) must arrive after the `bumped` it recalls.
5. **No cross-device ordering assumption.** Two devices may produce conflicting concurrent changes; ordering is only guaranteed *within* a device. Cross-device contention is resolved by §10, not by ordering.

**RISK R-002.** Out-of-order or duplicated operations are a primary sync hazard. Mitigation: dependency edges + idempotency + the transient dependency guard, all exercised by sync tests in M2 ([TESTING_STRATEGY.md](TESTING_STRATEGY.md)).

---

## 6. Retry Policy and Exponential Backoff

Transient failures (network loss, 5xx, timeout, "dependency-not-ready", rate-limit) are retried with capped exponential backoff and jitter. Concrete defaults (each a **DECISION-candidate**, surfaced as **OPEN QUESTION Q-018** (was O-S1)):

| Parameter | Proposed default | Notes |
| --- | --- | --- |
| `base_delay` | 2 s | First retry delay. |
| `multiplier` | 2.0 | Exponential factor. |
| `max_delay` | 5 min | Cap on a single inter-attempt delay. |
| `jitter` | full jitter (`random(0, computed_delay)`) | Avoids thundering herd when many devices reconnect at once. |
| `max_attempts` | 12 | After this, a still-transient operation becomes `dead` (poison, §8). |
| `dependency_retry` | same backoff | "dependency-not-ready" uses the same schedule but does NOT count toward poison until a separate, larger cap (see Q-018, was O-S1). |

Backoff is per-operation; the sync engine continues processing other independent (non-dependent) operations during a backoff window. A successful reconnect (connectivity transition offline→online) resets `next_attempt_at` to "now" for `pending` ops to re-attempt promptly.

**ASSUMPTION.** The offline authorization validity window (**OPEN QUESTION Q-009**) bounds how long a device may keep producing operations before it must successfully re-authenticate; that window interacts with `max_delay`/`max_attempts` and is resolved in [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).

---

## 7. Crash Recovery

Because the business write and the outbox entry are committed in **one local SQLite transaction** (§3), the device can crash at any point without divergence:

1. **On restart**, the sync engine scans the outbox for entries in `created`, `pending`, `in_flight`, or `conflict`.
2. **`in_flight` is treated as "unknown outcome."** The engine re-sends it; idempotency `(device_id, local_operation_id)` (**DECISION D-022**) guarantees the server applies it at most once. If the server already applied it, it returns the prior result (the processed-operation ledger, §10), and the client marks it `applied`.
3. **Partial UI writes are impossible** because there are no UI-only writes — the local store change and outbox entry are atomic.
4. **Pull cursors** (`sync_cursor`) are persisted, so a crash mid-pull resumes from the last durably-applied high-water mark; `processed_pull_log` prevents re-applying an inbound change.

---

## 8. Permanent Rejection vs Transient Failure

The server classifies every inbox outcome:

- **Transient (retryable):** network/5xx/timeout, "dependency-not-ready", optimistic lock contention pending rebase, lock timeouts. → operation stays `pending`, retries per §6.
- **Permanent (`rejected`, NOT retried):** authorization failure (revoked device/employee — §12, R-007), tenant-isolation violation, schema/validation failure, business-rule violation (e.g. voiding a paid order without the `void` permission — see SECURITY canonical isolation tests), or a conflict whose resolution forbids the change (§10).

A `rejected` operation is **never silently dropped**:
- It is recorded with `last_error_code`/`last_error_class` and surfaced to the cashier (§9) as **"needs attention."**
- The server writes an **append-only audit event** (**DECISION D-013**) capturing actor, device, organization/restaurant/branch, action, reason, old/new values.
- A `dead` (poison) operation — transient-looking but exceeding `max_attempts` (§6) — is quarantined identically: audited, surfaced, and excluded from automatic retry. Manual operator action or a support path (DEFERRED tooling, see Q-020, was O-S3) is required to retry or discard.

---

## 9. Sync Status Visible to the Cashier

Sync state is a first-class UI concern. The cashier always knows whether work is safely captured.

**Connectivity indicator (always visible):**
- **Online — synced:** outbox empty (or only `applied`).
- **Online — syncing:** operations `pending`/`in_flight`; show count.
- **Offline — working locally:** no connectivity; operations queued durably. Explicit reassurance that orders are saved.
- **Attention required:** one or more `rejected` or `dead` operations; non-dismissable badge with a drill-down list.

**Per-order/per-operation affordance:**
- Each order shows a small sync badge derived from the sync operation states of its operations: *saved locally*, *syncing*, *synced*, or *needs attention*.
- Receipt numbers display as **provisional** until reconciled to the authoritative per-branch sequence (§11), then update in place.

**SECURITY REQUIREMENT.** The "attention required" surface must not expose another tenant's data or internal error detail; it shows operator-safe messages only (cross-tenant isolation, **DECISION D-012**; see SECURITY doc).

---

## 10. Multi-Device Conflicts and Per-Entity Resolution Policy

Two devices in the same branch may mutate the same entity concurrently. The full per-entity conflict-resolution policy is **OPEN QUESTION Q-010**; this document defines the **default framework** and concrete examples, to be ratified there.

**Mechanism.** Optimistic concurrency via `revision` + `base_revision` (§3). On ingest the server compares the operation's `base_revision` to the current entity `revision`:
- Equal → apply, increment `revision`, return new revision.
- Different → **conflict**; resolve per the entity's class below, then either rebase-and-apply (`resolved → applied`) or forbid (`resolved → rejected`).

**Default per-entity-class policy (DECISION-candidate, pending Q-010):**

| Entity class | Default policy | Rationale / example |
| --- | --- | --- |
| **Money / sequence-bearing** (`payments`, order totals, receipt numbers) | **Server-authoritative.** The server recomputes from snapshots (**DECISION D-008**) and owns the per-branch receipt sequence (**DECISION D-021**). Client values are advisory. | Two devices must never both "win" a payment total; the server is the single arbiter. |
| **Order lifecycle state** (`orders.status`, `order_items.status`) | **Domain-rule merge**, governed by the PROPOSED state machine (**DECISION D-018**, STATE_MACHINES.md; pending review and approval). Only legal transitions apply; an illegal concurrent transition is `rejected`. | If device A submits and device B tries to add an item to a now-`submitted` order, B's add is evaluated against the new state, not blindly overwritten. |
| **Benign descriptive fields** (e.g. table assignment, customer note, non-monetary order metadata) | **Last-writer-wins** by `server_updated_at`, tie-broken by `device_id`. | Low-stakes; convergence matters more than which device wins. |
| **Kitchen ticket / station item state** | **Domain-rule merge** per the PROPOSED state machine (pending review and approval). A `bump` already applied makes a second concurrent `bump` a no-op (idempotent), not a conflict. | KDS bumps must be idempotent and ordered (§5). |
| **Voids / cancellations** | **Online-only by default** (per the STATE_MACHINES Order/Payment void ASSUMPTION); offline-provisional voids are a deferred/open consideration, not the default. When applied, voids are **server-authoritative + authorization-gated**: requires permission + reason; concurrent void wins once, second is idempotent no-op or `rejected` if unauthorized. Payment void is allowed **only pre-completion** (`pending → voided`, `tendered → voided`); a **`completed` payment is TERMINAL and can never be voided/reversed** (`completed → voided` is **FORBIDDEN**) — refunds / post-completion reversal are **DEFERRED** (**DECISION D-023**). An order void/cancel is likewise **`rejected`** once a `completed` payment exists (**DECISION D-024**). | A void is irreversible and audited (**DECISION D-013**); requiring connectivity ensures authorization and auditing at the moment of void. |

**Processed-operation ledger (server inbox).** The server keeps an append-only ledger keyed by `(device_id, local_operation_id)` (**DECISION D-022**). Re-delivery returns the stored prior result rather than re-applying — this is the substrate for idempotency, crash recovery (§7), and conflict bookkeeping. The ledger and audit trail are append-only and not app-mutable (**DECISION D-013**).

---

## 11. Receipt Numbering Reconciliation

Receipt numbering is owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) per **DECISION D-021**; the sync-relevant behavior:

- Offline, the device assigns a **provisional** identifier (clearly marked as provisional in UI and on any reprint).
- On sync, the server assigns the authoritative **per-branch monotonic** receipt number and returns it; the client reconciles the provisional id to the authoritative one in place.
- The per-branch sequence is **server-authoritative** (never client-assigned), preventing duplicate/forked sequences across devices in a branch. Legal numbering rules (resets, format) remain **OPEN QUESTION Q-004**.

---

## 12. Employee / Device Revocation While Offline (R-007)

**RISK R-007.** A device or employee revoked centrally may continue operating during the offline window before learning it is revoked.

Concrete behavior:

1. **Local operations still queue.** The device, unaware of revocation, may create operations offline (it cannot consult the server).
2. **Server re-authorizes on reconnect.** On ingest, the server re-checks the membership/role/scoping and device pairing status (**DECISION D-005/D-006/D-012**) **as of ingest time**, not as of operation-creation time.
3. **Operations from a revoked device/employee are `rejected`** (permanent, §8) — this is one of the canonical isolation tests: *"a revoked device cannot sync new operations"* and *"a removed employee cannot create new valid operations"* (SECURITY doc).
4. **Every rejection is audited** (**DECISION D-013**): actor, device, organization/restaurant/branch, action, reason = revocation, with old/new values.
5. **The offline validity window is bounded** by **OPEN QUESTION Q-009** (how long cached permissions / a PIN session remain valid offline). Shortening this window limits how many operations a revoked actor can stage. The window itself is decided in [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).
6. **Device pairing lifecycle** (`code_issued → pending → paired → active → suspended → revoked`, PROPOSED by **DECISION D-018**; pending review and approval) governs device state; a `suspended`/`revoked` device's operations are rejected on ingest.

**SECURITY REQUIREMENT.** Revocation must remove **future** access including within the offline window's eventual reconciliation; no operation created under revoked credentials may be accepted as valid.

---

## 13. Menu Changes While Offline + Price Snapshots

- Menu data (`menu_categories`, `menu_items`, `item_sizes`, `item_variants`, `modifiers`, `modifier_options`) is **pulled** to the device and read locally; the POS uses the last-pulled menu while offline.
- **Price integrity is protected by snapshots (DECISION D-008).** When an order item is created, the device captures the **item price snapshot** and **modifier price snapshots** (integer `_minor`) into the operation payload. Orders **never recompute from live menu prices** on sync. If a price changed centrally while the device was offline, the already-placed order keeps its snapshot price; the change applies only to future orders.
- Menu edits made centrally are propagated by pull (§14) / optionally Realtime (enhancement only); stale menus do not corrupt historical totals because of snapshots.
- Menu rows deleted centrally use tombstones (§13.1 / D-020); a tombstoned menu item disappears from new-order selection on next pull but remains referenceable by historical orders (which hold snapshots, not live FKs to a now-deleted price).

---

## 13.1 Tombstones / Soft-Delete Semantics (DECISION D-020)

- Sync-relevant deletions are **soft deletes**: set `deleted_at` rather than physically removing the row. This lets deletions propagate to every device (a hard delete would be invisible to a device that never saw the row vanish).
- Tombstones carry `organization_id` and the standard sync columns so they replicate within tenant scope only.
- The client treats a row with non-null `deleted_at` as removed for UI/selection but retains it for referential integrity of historical operations and for sync convergence.
- Physical purge of tombstones (retention) is a later operational concern (see [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md)) and ties to data-retention obligations (**OPEN QUESTION Q-005**).

---

## 14. Reconciliation After Reconnect — Pull-Then-Push

**DECISION-candidate (surfaced as OPEN QUESTION Q-021 (was O-S4)): RestoFlow reconciles PULL-THEN-PUSH.**

On connectivity restore, the device:

1. **PULL first.** Fetch authoritative changes since the per-entity `sync_cursor` high-water mark (`server_updated_at` / `revision`), apply them locally (dedup via `processed_pull_log`). This includes revocations (§12), menu changes (§13), and tombstones (§13.1).
2. **THEN PUSH** the outbox (§3–§6), computing conflicts against the now-current local revisions.

**Justification for pull-then-push:**
- The client learns about **revocations and price/menu changes before** pushing, reducing avoidable `rejected` operations and surprising conflicts (e.g. it discovers its device is `suspended` before wasting attempts).
- Optimistic-concurrency `base_revision` checks (§10) are computed against fresh state, lowering conflict rate.
- It is consistent with **server-authoritative money/sequence** (§10, §11): the client converges to authoritative state, then submits intent.
- **Money safety is independent of order:** snapshots (**DECISION D-008**) and idempotency (**DECISION D-022**) mean push correctness does not depend on having pulled first; pull-first is chosen for *fewer conflicts and earlier revocation awareness*, not for correctness of totals.

Pulls are **incremental and tenant-scoped** (RLS-enforced, **DECISION D-012**), never a full-table dump, and never cross-tenant.

---

## 15. Realtime as Enhancement Only (DECISION D-010)

- Supabase Realtime MAY push change notifications to reduce pull latency (e.g. KDS sees a new ticket faster).
- Realtime is **never** the source of truth and **never** the only mechanism: every entity class is fully reconcilable by the pull path (§14) with Realtime disabled.
- A Realtime notification is treated as a **hint to pull**, not as authoritative data to apply directly (it could be missed, reordered, or delivered to a reconnecting client out of band).
- Provider limits and the fallback **polling interval** are **OPEN QUESTION Q-014**; the polling fallback must exist regardless.

**RISK R-003 (CRITICAL).** A subscription/RLS bug must not leak cross-tenant data via Realtime. Realtime channels are tenant-scoped and covered by the mandatory isolation tests (SECURITY doc).

---

## 16. Duplicate-Mutation Prevention (Orders & Payments)

- **General duplicate prevention.** The idempotency key `(device_id, local_operation_id)` (**DECISION D-022**) + the append-only processed-operation ledger (§10) guarantee at-most-once application across retries, crashes (§7), and Realtime/pull races.
- **Order duplication.** A double-tap or retried `order.create` reuses the same `local_operation_id`; the server returns the existing order rather than creating a second one. The order `id` is a client UUID, so re-creation is naturally idempotent on the primary key as well.
- **Payment duplication.** Each `payment.create` carries its own idempotency key and references the order by UUID. A retried or duplicated payment operation is deduplicated by the ledger; the server returns the existing payment. Money is integer `_minor` (**DECISION D-007**) and reconciled server-authoritatively (§10), so no double-charge total can form. Payment state follows the PROPOSED machine `pending → tendered → completed` (+ `voided`/`failed`; `refunded` DEFERRED) — **DECISION D-018** (pending review and approval). `completed` is **TERMINAL**: void is permitted **only pre-completion** (`pending → voided`, `tendered → voided`) and `completed → voided` is **FORBIDDEN** (no post-completion reversal; refunds DEFERRED) (**DECISION D-023**). Payment and fulfillment are **independent**, so a completed payment may precede order completion (**pay-first supported**, **DECISION D-025**); a duplicate-prevented re-`completed` is an idempotent no-op, never a second charge.

---

## 17. Concrete Defaults Summary (DECISION-candidates)

The following numeric/policy defaults are proposed for freezing; each appears as an OPEN QUESTION below until ratified in [DECISIONS.md](DECISIONS.md):

| Item | Proposed default | OQ |
| --- | --- | --- |
| Backoff base / multiplier / max / jitter / max_attempts | 2 s / 2.0 / 5 min / full / 12 | Q-018 (was O-S1) |
| Applied-outbox retention before prune | 7 days or after server-ack confirmation | Q-019 (was O-S2) |
| Poison/`dead` operation handling tooling | manual operator retry/discard (tooling DEFERRED) | Q-020 (was O-S3) |
| Reconciliation order | pull-then-push | Q-021 (was O-S4) |
| Offline outbox storage ceiling behavior | warn at soft threshold; never drop captured orders; block new non-critical local writes at hard ceiling | Q-023 (was O-S6) |
| Per-entity conflict policy ratification | framework in §10 | Q-010 |
| Offline authorization validity window | (owned by SECURITY) | Q-009 |

---

## 18. UNRESOLVED SYNC DECISIONS (OPEN QUESTIONS)

These are sync-specific open items, now promoted into the canonical [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) register as `Q-018..Q-024` (their former local `O-Sx` ids are kept only as parentheticals). Cross-cutting items already registered are cited by their canonical IDs.

- **OPEN QUESTION Q-018** (was O-S1) — Final retry/backoff constants (`base_delay`, `multiplier`, `max_delay`, `jitter`, `max_attempts`) and whether "dependency-not-ready" gets a separate larger cap before poisoning. (Default proposed §6.)
- **OPEN QUESTION Q-019** (was O-S2) — Retention/prune policy for `applied` outbox entries and `processed_pull_log` on the device (storage vs auditability trade-off; interacts with **Q-005** data retention).
- **OPEN QUESTION Q-020** (was O-S3) — Operator tooling for `dead`/poison and `rejected` operations: manual retry, discard, escalate. (Tooling is DEFERRED for MVP; behavior of quarantine + audit is defined, the UI/tooling is not.)
- **OPEN QUESTION Q-021** (was O-S4) — Ratify **pull-then-push** as the reconciliation order (proposed §14) and confirm no entity class needs push-first.
- **OPEN QUESTION Q-022** (was O-S5) — Whether the device must enforce a hard "no new operations past the offline validity window" stop (depends on **Q-009**) versus allowing queueing that the server later rejects (R-007). Default: allow queueing, reject + audit on ingest.
- **OPEN QUESTION Q-023** (was O-S6) — Maximum offline outbox depth / local-storage ceiling and behavior when reached. **PROPOSED default (pending Q-023):** warn at a soft threshold; **never silently drop captured orders**; at the hard ceiling, block new non-critical local writes (e.g. new draft orders / non-essential edits) while preserving all already-captured operations until sync drains the outbox. The system must surface an explicit "storage near full — connect to sync" warning rather than degrade silently.
- **OPEN QUESTION Q-024** (was O-S7) — Clock-skew handling: bound on acceptable `client_updated_at` skew and whether the server clamps/annotates skewed client timestamps used in LWW tie-breaks (§10).
- **Q-009** — Offline authorization validity window (owned by SECURITY; gates §6, §12, Q-022).
- **Q-010** — Per-entity conflict-resolution policy ratification (this spec proposes the default framework in §10).
- **Q-014** — Realtime provider limits & fallback polling interval (§15).
- **Q-005** — Data-retention obligations affecting tombstone purge (§13.1) and outbox retention (Q-019).
- **Q-004** — Receipt numbering legal rules affecting reconciliation display (§11).

---

*End of OFFLINE_SYNC_SPEC.md. This document is intended to be frozen at M0A and implemented against in M2 (real backend + synchronization), per **DECISION D-019**.*
