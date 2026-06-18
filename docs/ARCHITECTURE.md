# RestoFlow — System Architecture

> **Status — DRAFT (candidate), not yet frozen.** Drafted by Claude Code (RF-001) · pending ChatGPT review · pending independent Codex review · pending human approval (Saleh). Only the explicit RF-001 invariants (below/where cited) are binding requirements; every other architectural choice is a **PROPOSED DECISION** pending review and human approval. Architecture freeze happens only after independent review, required fixes, and Saleh's approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

> **Scope:** M0A produces the candidate document set proposed for the architecture freeze. Design only — no code, packages, migrations, or CI are produced in this milestone (**DECISION D-019**).
>
> **Ownership:** This document owns *system structure* and how the pieces fit together. It **references** the detailed specs and never redefines their topics. For decision rationale see [DECISIONS](DECISIONS.md); for unresolved items see [OPEN_QUESTIONS](OPEN_QUESTIONS.md).

RestoFlow is a **multi-tenant Restaurant Operating System** (not merely a POS) serving many independent restaurant customers on one platform. No part of this architecture may assume a single restaurant or organization exists, even though the first pilot uses one restaurant and one branch.

---

## 1. Architectural Principles

These principles are binding constraints on every layer described below. They derive directly from the RF-001 invariants (binding requirements) and the proposed decisions pending review.

1. **Multi-tenant first (DECISION D-001, D-002, D-003).** The tenant is the **Organization**. The primary isolation boundary is `organization_id`, present on every tenant-scoped row. The hierarchy is `Platform -> Organization -> Restaurant -> Branch -> Device/Station`. The simplest customer is an Organization with one Restaurant and one Branch; no schema, query, policy, or app screen may hard-code that simplest case. See [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) for the isolation model and [DOMAIN_MODEL](DOMAIN_MODEL.md) for the entity graph.

2. **Offline-first (DECISION D-010).** The POS keeps working with no internet. The local Drift/SQLite store is the immediate operational store on each device; the server is the eventual source of truth reconciled via a local outbox + server inbox/processed-operation ledger. Supabase Realtime is an **enhancement only**, never the source of truth or the only sync mechanism. See [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).

3. **Defence in depth (DECISION D-011, D-012, D-013).** Four security layers: (1) PostgreSQL RLS; (2) membership/role + branch/device scoping checks; (3) sensitive mutations via PostgreSQL RPC (`SECURITY DEFINER`) that authorize + audit; (4) database constraints as the final safety boundary. Append-only audit events capture full actor/tenant/device context. **SECURITY REQUIREMENT:** no service-role credentials in Flutter clients; no shared restaurant password. See [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).

4. **Contracts-first.** APIs, RPC signatures, state transitions, and sync payloads are settled as contracts before implementation (proposed for freeze; pending review and approval). Clients and server agree on the same contract. See [API_CONTRACT](API_CONTRACT.md) and [STATE_MACHINES](STATE_MACHINES.md). Shared-package and API-contract changes require dedicated tickets (**DECISION D-016**).

5. **No floating-point money (DECISION D-007).** Money is stored and transported as integer **minor units** in columns suffixed `_minor`, everywhere — DB, RPC, Dart domain, and sync payloads. Currency is per organization (overridable per restaurant), single currency per order, ISO 4217. Orders never recompute from live menu prices; they use price/modifier snapshots taken at order time (**DECISION D-008**). See [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md).

6. **Membership-scoped identity (DECISION D-004, D-005, D-006).** No shared accounts. Every human has an individual identity; roles are membership-scoped, never a permanent global role on the user. The six identity concepts (User identity, Membership, Employee profile, Device identity, Device session, Human PIN session) are kept distinct everywhere. See [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).

7. **Replaceable hardware adapters (DECISION D-009, RISK R-001).** Printing and other hardware sit behind a replaceable adapter interface so a single pilot printer model can be standardized without leaking device specifics into business logic. See [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md).

8. **Localized, bidirectional UI (DECISION D-014).** Arabic, Hebrew, English with full RTL (ar, he) and LTR (en) across all surfaces, including receipts/tickets.

---

## 2. High-Level Topology

Four Flutter client surfaces (each a distinct app target) talk to one Supabase backend. Every device keeps a **local Drift/SQLite store** with a per-device **outbox** (pending local mutations) and consumes a server **inbox / processed-operation ledger** during sync.

- **POS app** — cashier stations; offline-first; full local store + outbox.
- **KDS app** — Kitchen Display System; consumes kitchen tickets/station items; bumping; mostly read + bounded status mutations; offline-first.
- **Dashboard app** — owner/manager reporting and configuration; primarily online; lighter local cache.
- **Platform admin app** — platform-level administration across organizations; isolated, explicitly audited path (**DECISION D-013**); never co-mingled with tenant flows.

> **ASSUMPTION:** The four surfaces are separate buildable app targets sharing common packages (Section 3). Whether KDS and POS could be combined into one installable shell with role-gated routes is an implementation detail deferred to M0B/M1; it does not change the architecture here. The local-store footprint per surface (full vs. lighter cache) is indicative and finalized in M0B.

```
                         +--------------------------------------------------+
                         |                  SUPABASE (cloud)                |
                         |                                                  |
                         |  Auth (users, sessions, MFA Q-008)               |
                         |  PostgreSQL  --  RLS policies (layer 1, D-012)   |
                         |              --  tables (organization_id scoped) |
                         |  RPC (SECURITY DEFINER) sensitive mutations  ----+--> append-only
                         |       authorize + audit (layer 3, D-011/D-013)   |    audit_events
                         |  DB constraints (layer 4, D-012)                 |
                         |  Realtime (ENHANCEMENT ONLY, D-010, Q-014)       |
                         |  Edge Functions (webhooks / server-only tasks)   |
                         +-------------------------▲------------------------+
                                                   |
                  HTTPS / authenticated sessions   |   Realtime (best-effort push)
        (anon/publishable key + user/device JWT;   |   sync = outbox/inbox, NOT realtime
         NO service-role key in clients, D-011)    |
                                                   |
   +-------------------+-------------------+--------+----------+--------------------+
   |                   |                   |                   |                    |
+--v-----+        +----v----+        +-----v-----+       +-----v------+             |
| POS app|        | KDS app |        | Dashboard |       |  Platform  |             |
|(Flutter)|       |(Flutter)|        |  (Flutter)|       | admin app  |             |
+--+-----+        +----+----+        +-----+-----+       +-----+------+             |
   |                   |                   |                   |                    |
   | local Drift/SQLite store per device + outbox(pending) + inbox/applied ledger   |
   v                   v                   v                   v                    |
+-----------------------------------------------------------------------------------+
|  Local store: orders, order_items, payments, kitchen_tickets, sync_operations ... |
|  Outbox  -> pending mutations w/ idempotency key (device_id + local_operation_id) |
|  Inbox   -> server-applied/rejected ledger; conflict/poison handling (D-020/D-022)|
+-----------------------------------------------------------------------------------+
   |
   | ESC/POS via replaceable printing adapter (D-009, R-001) -> network/USB/BT (Q-015)
   v
+--------------------------+
| Receipt / Kitchen printer|  (Arabic/Hebrew encoding + raster fallback, Q-015, R-006)
+--------------------------+
```

Key topology rules:

- **Source of truth direction.** Local store is authoritative for *in-flight, not-yet-synced* operations; the server is authoritative once an operation is applied. Receipt numbers are per-branch monotonic server-assigned sequences; offline a provisional id is used and reconciled to the authoritative value on sync (**DECISION D-021**). Details: [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md).
- **Realtime is additive.** Loss of Realtime degrades latency, never correctness; the outbox/inbox loop still converges (**DECISION D-010**, **OPEN QUESTION Q-014** for provider limits and fallback polling interval).
- **Platform admin is a separate, audited path** and must not be reachable through tenant client flows (**DECISION D-013**, **RISK R-003**).

---

## 3. Proposed Melos Monorepo Layout — **PROPOSED**

> **PROPOSED (DECISION D-009).** The following structure is a design proposal for M0B. Names and boundaries may be refined when the monorepo is actually bootstrapped. **Nothing here is created in M0A.** This section does not install dependencies or initialize packages.

```
restoflow/
  apps/
    pos/                # POS cashier app target
    kds/                # Kitchen Display System app target
    dashboard/          # Owner/manager dashboard app target
    admin/              # Platform admin app target (isolated, audited)
  packages/
    core/               # cross-cutting utils, Result/error types, env, logging hooks
    domain/             # entities, value objects, state enums (D-018), domain rules
      (a.k.a. models)   #   pure Dart, no Flutter, no IO
    data_local/         # Drift/SQLite schema + DAOs (offline store, outbox/inbox tables)
    data_remote/        # Supabase client wrappers, RPC call sites, query builders
    sync/               # outbox/inbox engine: idempotency, retry/backoff, conflict,
                        #   tombstones, poison handling (D-010, D-020, D-022)
    auth_identity/      # the six identity concepts (D-005): user/membership/employee/
                        #   device identity/device session/PIN session; role keys
    money/              # integer minor-unit money type, currency, rounding helpers (D-007)
    printing/           # ESC/POS adapter interface + implementations (D-009, R-001)
    design_system/      # themed widgets, RTL/LTR-aware layout primitives (D-014)
    l10n/               # ar/he/en localization assets + bidi helpers (D-014)
    feature_orders/     # feature_* packages compose domain+data+ui per capability
    feature_kitchen/    #   (orders, kitchen, payments, shifts, menu, reporting, ...)
    feature_payments/
    feature_shifts/
    feature_menu/
    feature_reporting/
  docs/                 # this documentation set (the only artifacts produced in M0A)
```

Layering intent (enforced as dependency rules in M0B):

- `domain` depends on nothing app-specific; it holds the **PROPOSED state enumerations** (**DECISION D-018**; pending review and approval — RF-001 §8 directs us to evaluate, not assume final) and money-typed fields backed by `money`.
- `data_local` and `data_remote` depend on `domain`; `sync` orchestrates both.
- `auth_identity` owns the **six identity concepts** and exposes the membership-scoped tenant context consumed by queries (Section 5).
- `feature_*` packages compose lower packages and are consumed by `apps/*`. Apps contain wiring (routing via GoRouter, Riverpod providers) and surface-specific UI only.
- `admin` may depend on a dedicated platform-admin path; it must **not** import tenant feature packages in a way that would bypass the audited admin boundary (**DECISION D-013**).

---

## 4. Tech Stack (DECISION D-009) — choices, risks, alternatives

Each major choice records the **RISK** carried and the **alternative considered**. None of this is installed in M0A.

| Concern | Chosen (D-009) | RISK | Alternative considered |
|---|---|---|---|
| Backend platform | Supabase (PostgreSQL + Auth + RLS + RPC + Realtime + Edge) | Vendor lock-in; Realtime quotas/limits (**Q-014**); RLS correctness is critical (**RISK R-003**). | Custom backend (Node/Go + self-managed Postgres). Rejected for M0–M3: far more ops burden against a 1-human + 3-AI team (**RISK R-005**); Supabase gives RLS, Auth, and RPC out of the box. Postgres remains portable if we ever leave Supabase. |
| Local store | Drift over SQLite | Drift codegen/build complexity; schema migration discipline required offline. | `sqflite` (lower-level, more boilerplate, weaker type-safety) and Isar (fast, but NoSQL model fits our relational sync/tombstone needs less cleanly, **DECISION D-020**). Drift chosen for typed relational queries that mirror the server schema. |
| State management | Riverpod | Learning curve; provider graph can sprawl without discipline. | Bloc (more ceremony, explicit but verbose). Riverpod chosen for compile-safe DI and testability of the offline/sync providers. |
| Routing | GoRouter | Deep-link/role-guard config complexity across four surfaces. | `auto_route` (codegen-heavy). GoRouter chosen as the first-party, declarative option. |
| Monorepo tooling | Melos | Multi-package orchestration overhead. | Single-package app (rejected: four surfaces + shared packages need real package boundaries). |
| Realtime | Supabase Realtime, **enhancement only** (**DECISION D-010**) | If treated as source of truth, offline correctness breaks (forbidden). Provider limits/fallback unresolved (**Q-014**). | Realtime-as-primary-sync (explicitly rejected by D-010). Fallback is bounded polling on top of the outbox/inbox loop. |
| Sensitive mutations | PostgreSQL RPC (`SECURITY DEFINER`) (**DECISION D-011**) | Logic-in-DB is harder to test than Dart; must be covered by isolation tests (**RISK R-003**). | Direct table writes guarded only by RLS (insufficient for authorize + audit of voids/refunds/etc.). |
| Printing | ESC/POS behind replaceable adapter (**DECISION D-009**) | Hardware variation (**RISK R-001**); Arabic/Hebrew encoding (**RISK R-006**, **Q-015**). | Vendor-specific SDK lock-in (rejected: not replaceable). |
| Auth/MFA | Supabase Auth; MFA for privileged roles | MFA method undecided (**Q-008**); offline authorization staleness (**RISK R-007**, **Q-009**). | Third-party IdP (deferred; adds integration surface without M0–M3 benefit). |
| CI | GitHub Actions | None blocking at M0A. | Other CI providers; not material now. |

---

## 5. Data Layering & Tenant Context Flow

Tenant context is **`organization_id`** (**DECISION D-001**), augmented by `restaurant_id`, `branch_id`, `device_id`, `station_id` where the operation is scoped more narrowly. The flow from auth to a query:

1. **Authenticate.** A human authenticates to Supabase Auth (owners/managers: personal account + MFA where required, **Q-008**; cashiers/kitchen: personal employee identity via a **PIN session** layered on an authorized **device session**, **DECISION D-006**). A device has its own **device identity** and **device session**, distinct from any human (**DECISION D-005**).
2. **Resolve memberships.** The authenticated principal is mapped to its **memberships** — scoped relationships to organizations (and optionally restaurant/branch) carrying role(s) from the canonical **tenant** role keys: `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant` (read-only, ships-or-not per **Q-017**). Roles are never a permanent global field on the user (**DECISION D-004**). **DECISION D-026** — `platform_admin` is **NOT** a membership role; platform administration resolves via a separate `platform_admin_grants` path (owned by [DOMAIN_MODEL](DOMAIN_MODEL.md) §3.7) that carries **no** `organization_id`, is separately audited and MFA-gated, and is never a tenant membership.
3. **Establish active tenant context.** The client selects (or is pinned to) an active organization/restaurant/branch/device for the session. The server independently derives the authoritative tenant context from the verified session + membership — the client claim is never trusted on its own.
4. **RLS enforces (layer 1).** Every tenant-scoped table carries `organization_id`; RLS policies restrict rows to those the principal's membership permits, with branch/device scoping applied on operational tables (layer 2). See [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (owns the policy definitions).
5. **Queries.** Reads go through `data_remote` query builders that always filter within the resolved tenant context; locally, `data_local` mirrors the same scoping so offline reads cannot surface another tenant's rows. The same `organization_id` (+ narrower ids) is written on every locally created row so it remains correctly scoped after sync.

**SECURITY REQUIREMENT:** clients use only the anon/publishable key plus the user/device session token; no service-role key ever ships in a Flutter client (**DECISION D-011**). IDOR and cross-tenant access are prevented at layers 1–2 and validated by the mandatory isolation tests (Org A cannot read Org B orders; cashier A cannot modify Restaurant B; KDS cannot read financial reports; revoked device/removed employee cannot create valid new operations) defined in [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) and [TESTING_STRATEGY](TESTING_STRATEGY.md) (**RISK R-003**).

---

## 6. Sensitive-Mutation Path (RPC)

Sensitive mutations — voids, refunds (**DEFERRED**, see [STATE_MACHINES](STATE_MACHINES.md)), discounts beyond policy, shift/drawer reconciliation, device pairing/revocation, role/membership changes — do **not** go through direct table writes. They flow through PostgreSQL **RPC (`SECURITY DEFINER`)** functions (**DECISION D-011**, layer 3 of **D-012**) that:

1. Re-derive tenant context and verify the actor's membership/role/scope (a cashier cannot void an order without permission — canonical test).
2. Validate the requested state transition against the proposed state machines (**DECISION D-018**, pending review and approval; [STATE_MACHINES](STATE_MACHINES.md)). Payment and fulfillment are **independent** transition tracks (**DECISION D-025**): a payment may complete from any of `submitted`/`accepted`/`preparing`/`ready`/`served` (quick-service **pay-first**), and completing payment does not advance fulfillment. A `completed` payment and a `completed` order are **terminal** (**DECISION D-023/D-024**): a void is accepted only before completion, an order void/cancel is rejected once a completed payment exists, and there is no refund in MVP (refunds **DEFERRED**).
3. Apply the change within DB constraints (layer 4).
4. Write an **append-only audit event** with actor, device, organization, restaurant, branch, timestamp, action, reason, old values, new values (**DECISION D-013**), never updatable/deletable by app roles.
5. Carry the caller's **idempotency key** (`device_id` + `local_operation_id`) so a retried/duplicated call is applied at most once (**DECISION D-022**).

The exact function signatures, parameters, and error contracts are owned by [API_CONTRACT](API_CONTRACT.md); the authorization and audit semantics are owned by [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md). This document only fixes that the path exists and is the sole route for sensitive mutations.

---

## 7. Offline / Sync Architecture (summary)

> Full rules are owned by [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md). This is the architectural summary only.

- **Local-first writes.** Mutations are written to the local Drift store and enqueued in a local **outbox** with an idempotency key (`device_id` + `local_operation_id`, **DECISION D-022**), client + server timestamps, and an entity revision/version.
- **Server inbox / processed-operation ledger.** On reconnect, the `sync` engine pushes outbox operations; the server records each in a processed-operation ledger so duplicates are rejected idempotently. Sync operation lifecycle uses the proposed enumeration (pending review and approval) `created -> pending -> in_flight -> applied`, plus `rejected` (permanent), `dead` (poison after max retries), and `conflict -> resolved` (**DECISION D-018**).
- **Retry, ordering, recovery.** Retry with backoff; dependent-operation ordering; crash recovery; poison/permanent-rejection handling; sync status visible to the cashier.
- **Conflicts & deletions.** Multi-device conflict rules per entity (**OPEN QUESTION Q-010** — LWW vs. domain rules); soft-delete **tombstones** for sync-relevant deletions (**DECISION D-020**).
- **Revocation while offline.** Removing an employee or revoking a device must remove FUTURE access; the server rejects operations from a revoked device/removed employee on reconnect within the offline validity window (**OPEN QUESTION Q-009**, **RISK R-007**).
- **Menu/price changes offline.** Orders use price/modifier snapshots taken at order time (**DECISION D-008**) so menu changes during the offline window never retro-alter open orders.
- **Realtime.** Used only to reduce latency of inbound updates; never required for convergence (**DECISION D-010**, **RISK R-002**).

---

## 8. Printing Architecture (summary)

> Full rules are owned by [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md). This is the architectural summary only.

- ESC/POS printing sits behind a **replaceable adapter** in `packages/printing` (**DECISION D-009**) so business logic depends on an interface, not a printer model (**RISK R-001** mitigation: standardize one pilot model).
- Print jobs follow the proposed lifecycle (pending review and approval) `created -> queued -> printing -> printed`, plus `failed -> retrying`, `cancelled`, and `abandoned` after max retries (**DECISION D-018**). Terminal: `printed`, `cancelled`, `abandoned`.
- Receipts/tickets are localized (ar/he/en) with an encoding / **raster fallback** strategy for Arabic/Hebrew (**DECISION D-014**, **RISK R-006**, **OPEN QUESTION Q-015** for connectivity network/USB/BT and encoding).

---

## 9. Cross-Cutting Concerns

### 9.1 Localization & RTL/LTR (DECISION D-014)
Arabic, Hebrew (RTL) and English (LTR) are first-class across all four surfaces and on printed output. The `l10n` and `design_system` packages provide bidi-aware layout primitives so direction is data-driven, not hard-coded. Receipt/ticket localization shares the same encoding/raster fallback path as printing (Section 8, **Q-015**).

### 9.2 Error Handling
Domain operations return explicit result/error types (in `core`/`domain`) rather than throwing across layer boundaries. Sync surfaces distinguish *transient* (retry with backoff) from *permanent* (`rejected`) and *poison* (`dead`) failures (**DECISION D-018**), all visible to the cashier as sync status. RPC calls return structured error contracts owned by [API_CONTRACT](API_CONTRACT.md). No silent assumptions: anything unknown is tracked as an **OPEN QUESTION**, not papered over.

### 9.3 Observability
> Operational concerns (backup RPO/RTO **Q-013**, DR region, incident response, monitoring/alerting) are owned by [OPERATIONS_AND_RECOVERY](OPERATIONS_AND_RECOVERY.md).

Architecturally: the append-only `audit_events` ledger (**DECISION D-013**) is the authoritative record of sensitive actions; structured logging hooks live in `core`; client-side sync status and print-job status give operators visibility into the offline pipeline. Platform-admin access is itself audited on its isolated path (**DECISION D-013**, **RISK R-003**).

---

## 10. References

- [DECISIONS](DECISIONS.md) — decision log (D-xxx).
- [OPEN_QUESTIONS](OPEN_QUESTIONS.md) — open-questions register (Q-xxx).
- [DOMAIN_MODEL](DOMAIN_MODEL.md) — entities, fields, relationships.
- [STATE_MACHINES](STATE_MACHINES.md) — transitions for the proposed enumerations.
- [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) — security layers, RLS, threats, isolation tests.
- [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md) — offline/sync rules.
- [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) — money/tax/receipt rules.
- [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md) — printing/hardware.
- [API_CONTRACT](API_CONTRACT.md) — RPC/endpoint contracts.
- [TESTING_STRATEGY](TESTING_STRATEGY.md) — test strategy and mandatory isolation tests.
- [OPERATIONS_AND_RECOVERY](OPERATIONS_AND_RECOVERY.md) — ops/backup/incident.
- [PRODUCT_SPEC](PRODUCT_SPEC.md) · [MVP_SCOPE](MVP_SCOPE.md) · [PROJECT_PLAN](PROJECT_PLAN.md) — product, scope, milestones.
