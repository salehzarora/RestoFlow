# RestoFlow — DECISIONS.md (Decision Log)

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

**Status:** FROZEN — M0A architecture baseline, approved at RF-004 (authored RF-001; independently reviewed RF-002; corrected RF-003).
**Owner of this document:** This file is the single authoritative source for decision IDs (`D-xxx`). Every other document **cites** these IDs and must never invent a conflicting decision. Open questions are owned by [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) (`Q-xxx`); risks are surfaced from the canon risk register (`R-xxx`).

**Decision-status taxonomy used below:**
- **RF-001 INVARIANT (binding requirement)** — taken directly from the RF-001 task; recorded as binding, while the surrounding document set is still a draft pending review.
- **RF-001 requirement; specific approach PROPOSED pending review** — the requirement comes from RF-001, but the specific approach/framing is Claude's proposal.
- **PROPOSED DECISION — pending ChatGPT + Codex review + Saleh approval; not frozen** — introduced by Claude Code.
- **INTENDED DIRECTION, pending confirmation** — RF-001 names these as intended (not final) decisions.

## How to read this log

Each entry is an ADR-style block:

- **ID + Title** — the decision, part of the frozen M0A baseline approved at RF-004 (RF-001 invariants flagged as binding).
- **Status** — one of the taxonomy values above, optionally annotated `Provisional (pending Q-xxx)` where a decision also depends on an unresolved open question.
- **Context** — why the decision matters.
- **Decision** — the precise choice.
- **Alternatives considered** — at least one real alternative and why it was rejected.
- **Consequences** — positive outcomes and negative/risk trade-offs (linking `R-xxx`).
- **Related** — documents that depend on or expand the decision.

**Conventions:** Multi-tenant by construction (no single-organization assumptions); no shared accounts; money is integer minor units only (no floating point). These are RF-001 invariants reinforced by individual decisions below; the rest of the log is the frozen M0A baseline, approved at RF-004.

**Adding decisions:** Do not invent decisions beyond D-001..D-028 elsewhere. If a new decision is genuinely required, add it here as the next free ID (D-029+) with a full ADR block and a note in the changelog, then cite it from the consuming document.

---

## D-001 — organization_id is the primary tenant-isolation boundary

- **Status:** RF-001 INVARIANT (binding requirement). (Recorded as binding; the surrounding set is still a draft pending review.)
- **Context:** RestoFlow is a multi-tenant Restaurant Operating System serving many independent customers on one platform. Tenant isolation must be enforced uniformly and verifiably, not improvised per table or per query.
- **Decision:** **DECISION D-001** — `organization_id` is the PRIMARY tenant-isolation boundary. Every tenant-scoped row carries `organization_id`. Operational rows additionally carry `restaurant_id`, `branch_id`, `device_id`, `station_id` where relevant (see [DOMAIN_MODEL](DOMAIN_MODEL.md) for the per-entity field set). Isolation is enforced in depth via the four security layers of **DECISION D-012**.
- **Alternatives considered:**
  - *Restaurant as the isolation boundary* — rejected because a restaurant group is one customer owning multiple restaurants/branches; restaurant-level isolation would fragment a single tenant and break cross-restaurant reporting and billing. Superseded explicitly by **DECISION D-003**.
  - *Row-level tenant tags without a hard column* (e.g., a JSON attribute) — rejected: not indexable/constrainable, incompatible with PostgreSQL RLS predicates and with database constraints as a final safety boundary.
- **Consequences:**
  - (+) Single, consistent predicate (`organization_id = current tenant`) for RLS and scoping checks; clear billing/ownership unit.
  - (+) Database constraints can enforce that scoped foreign keys belong to the same `organization_id`.
  - (-) **RISK R-003 (CRITICAL):** a single RLS/scoping bug can leak cross-tenant data; mitigated by mandatory isolation tests and human sign-off (see [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).
- **Related:** [DOMAIN_MODEL](DOMAIN_MODEL.md), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md), [ARCHITECTURE](ARCHITECTURE.md), depends on D-002, D-012.

---

## D-002 — Tenant hierarchy: Platform -> Organization -> Restaurant -> Branch -> Device/Station

- **Status:** RF-001 INVARIANT (binding requirement). (Recorded as binding; the surrounding set is still a draft pending review.)
- **Context:** The platform must model both a single small restaurant and a multi-restaurant group without schema changes. A stable hierarchy is required before any table, RLS policy, or API contract is designed.
- **Decision:** **DECISION D-002** — the canonical hierarchy is **Platform -> Organization -> Restaurant -> Branch -> Device/Station**, and must never be silently changed.
  - Small restaurant: Organization -> one Restaurant -> one Branch.
  - Restaurant group: one Organization owns Restaurant A (many branches) + Restaurant B (many branches).
- **Alternatives considered:**
  - *Flat Organization -> Branch* (drop the Restaurant level) — rejected: a group cannot express per-brand menus, pricing, and reporting without a Restaurant tier.
  - *Add a Region/Area tier between Restaurant and Branch* — **DEFERRED**: not needed for MVP; would add complexity to RLS and the domain model with no pilot value. Can be revisited as a future decision (D-023+).
- **Consequences:**
  - (+) One schema serves single-site and group customers; pilot with one restaurant/branch never bakes in a single-tenant assumption.
  - (-) Every operational entity must reason about which tiers apply (`restaurant_id`/`branch_id`/`device_id`/`station_id`), increasing modelling discipline (owned by [DOMAIN_MODEL](DOMAIN_MODEL.md)).
- **Related:** [DOMAIN_MODEL](DOMAIN_MODEL.md), [ARCHITECTURE](ARCHITECTURE.md), [PRODUCT_SPEC](PRODUCT_SPEC.md), underpins D-001, D-003.

---

## D-003 — Organization is the tenant (supersedes "Restaurant = Tenant" from v1.0 plan)

- **Status:** RF-001 requirement; specific approach PROPOSED pending review. (The Organization-as-tenant reconciliation follows from the D-001 invariant; the reconciliation itself is proposed for human confirmation.)
- **Context:** The earlier v1.0 plan framed "Restaurant = Tenant." That framing breaks for restaurant groups and contradicts the isolation boundary in **DECISION D-001**. A reconciliation is required so older planning material is not implemented as written.
- **Decision:** **DECISION D-003** — the TENANT is the **Organization**. In the simplest case an Organization contains exactly one Restaurant and one Branch. This **supersedes** the v1.0 "Restaurant = Tenant" framing. Do **not** regress to restaurant-as-tenant in any schema, RLS policy, API contract, or client architecture.
  - **Reconciliation:** Where v1.0 text says "restaurant" in the sense of "the customer/account/tenant," read it as "**organization**." Where it means an actual dining brand/establishment, it maps to the **Restaurant** tier under an Organization (**DECISION D-002**). Per-restaurant currency overrides and per-restaurant menus remain valid because Restaurant is a real tier — but isolation, ownership, identity, and billing attach to the Organization.
- **Alternatives considered:**
  - *Keep "Restaurant = Tenant" for pilot speed and migrate later* — rejected: a later tenant-boundary migration would touch every table, RLS policy, RPC, and the offline store; the cost and the **RISK R-003** exposure of re-pointing isolation are unacceptable. Proposing the correct boundary now (for freeze after approval) is cheaper.
- **Consequences:**
  - (+) Groups and single sites share one model; no future tenant re-keying.
  - (+) Removes an ambiguity that could otherwise produce contradictory schemas.
  - (-) Requires diligence when reading any v1.0-era artifact; mitigated by this explicit reconciliation note (**RISK R-005** — single-builder/legacy-doc drift).
- **Related:** [DOMAIN_MODEL](DOMAIN_MODEL.md), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md), [PROJECT_PLAN](PROJECT_PLAN.md), depends on D-001, D-002.

---

## D-004 — Per-person identity; membership-scoped roles; no shared accounts

- **Status:** RF-001 INVARIANT (binding requirement). (No shared employee accounts; per-person identities and membership-scoped roles. Recorded as binding; the surrounding set is still a draft pending review.)
- **Context:** Restaurants commonly share a single login. That destroys auditability and makes revocation impossible. RestoFlow must attribute every action to an individual and support a user belonging to multiple tenants.
- **Decision:** **DECISION D-004** — every human has an individual identity. Roles are **membership-scoped**, never a single permanent global role on the user. A user may hold multiple memberships across organizations/restaurants/branches, each carrying role(s) and permissions. **SECURITY REQUIREMENT:** no shared accounts and no shared restaurant password anywhere. **Membership (tenant) role keys are exactly six**: `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant` (read-only; whether `accountant` ships in MVP is **OPEN QUESTION Q-017**). `platform_admin` is **NOT** a membership/tenant role — platform administration is modelled via the separate `platform_admin_grants` entity, not as a membership role (see **DECISION D-026**).
- **Alternatives considered:**
  - *Single global role column on the user* — rejected: cannot represent a person who is a manager at Branch 1 and cashier at Branch 2, nor a consultant serving multiple organizations.
  - *Shared per-station login* — rejected: violates the no-shared-accounts SECURITY REQUIREMENT and breaks audit attribution (**DECISION D-013**).
- **Consequences:**
  - (+) Every action is attributable; revocation is per-membership and precise.
  - (-) More join complexity (user -> membership -> scope) in authorization and queries.
  - (-) **RISK R-007:** revocation must also propagate to offline windows (see **DECISION D-006**, **Q-009**).
- **Related:** [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md), [DOMAIN_MODEL](DOMAIN_MODEL.md), depends on D-005, related D-013, [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-017).

---

## D-005 — Six distinct identity concepts

- **Status:** RF-001 INVARIANT (binding requirement). (The six distinct identity concepts must be documented. Recorded as binding; the surrounding set is still a draft pending review.)
- **Context:** Conflating "user," "role," "employee," and "device" produces insecure shortcuts (e.g., a device acting as a person, or an employee record doubling as a login). The model must keep these orthogonal.
- **Decision:** **DECISION D-005** — keep SIX distinct concepts everywhere:
  1. **User identity** — the global person/auth principal.
  2. **Membership** — a user's scoped relationship to an Organization (optionally restaurant/branch) carrying role(s)/permissions.
  3. **Employee profile** — employment record within an organization (display name, employee number, PIN credential reference, employment status). Distinct from User and Membership.
  4. **Device identity** — a registered POS/KDS device with its own credentials and limited permissions (not a human).
  5. **Device session** — an authenticated session bound to a device identity.
  6. **Human PIN session** — a short, fast staff session established by PIN on an already paired+authorized device, layered on top of the device session.
  Corresponding tables follow [DOMAIN_MODEL](DOMAIN_MODEL.md) naming (e.g., `app_users`, `memberships`, `employee_profiles`, `devices`, `device_sessions`, `pin_sessions`).
- **Alternatives considered:**
  - *Merge Employee profile into User* — rejected: an organization manages employment data (employee number, status) independently of whether the person has a platform login; a single person can be an employee in one org and a User without an employee profile in another.
  - *Treat a device as a special user* — rejected: devices need limited, non-human permissions and a separate revocation path; modelling them as users invites privilege confusion.
- **Consequences:**
  - (+) Clean separation enables PIN-on-device sessions, device revocation, and per-employment lifecycle without touching auth principals.
  - (-) More entities to design and test; offset by sharper security boundaries.
- **Related:** [DOMAIN_MODEL](DOMAIN_MODEL.md), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md), depends on D-004, feeds D-006.

---

## D-006 — Authentication model (personal + MFA for privileged; PIN session on paired device; device identity)

- **Status:** RF-001 requirement; specific approach PROPOSED pending review. (Auth directions are given by RF-001; MFA method is **OPEN QUESTION Q-008**, PIN attempt limits and pairing-code TTL are proposed/open. Provisional on **Q-008** and offline validity window **Q-009**.)
- **Context:** Different actors need different authentication ergonomics and assurance: owners/managers need strong personal auth; floor staff need fast PIN entry; devices need their own controlled enrollment.
- **Decision:** **DECISION D-006** — authentication direction:
  - Owners/managers authenticate with personal accounts and secure auth; **MFA is mandatory for privileged/sensitive roles** (method TBD — **OPEN QUESTION Q-008**).
  - Cashiers/kitchen staff use their **personal employee identity** with a **PIN-based fast session** that is valid **only on a paired+authorized device** (PIN session per **DECISION D-005**).
  - POS/KDS **devices** hold a **separate device identity** with limited permissions; device pairing uses **short-lived enrollment codes / controlled enrollment** that expire (pairing lifecycle in [STATE_MACHINES](STATE_MACHINES.md): `code_issued -> pending -> paired -> active -> suspended -> revoked`, plus `code_expired`/`rejected`).
  - Removing an employee or revoking a device must remove **FUTURE** access, including within the offline window (validity TBD — **OPEN QUESTION Q-009**; **RISK R-007**).
  - **SECURITY REQUIREMENT:** no service-role credentials in Flutter clients (see **DECISION D-011**).
- **Alternatives considered:**
  - *PIN as the sole credential, independent of device* — rejected: a leaked PIN would grant access from any device; binding PIN sessions to a paired+authorized device contains the blast radius.
  - *Optional MFA for owners* — rejected for privileged roles: the cost of a compromised org_owner is total tenant compromise; MFA is required (pending only the method, **Q-008**).
- **Consequences:**
  - (+) Fast floor workflow without sacrificing per-person attribution; devices are independently revocable.
  - (-) Offline revocation staleness remains a real exposure until **Q-009** sets the window (**RISK R-007**); server must reject revoked actors on reconnect and audit it.
- **Related:** [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md), [STATE_MACHINES](STATE_MACHINES.md), [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-008, Q-009), depends on D-004, D-005, D-011.

---

## D-007 — Money in integer minor units; no floating point; currency per organization

- **Status:** RF-001 INVARIANT (binding requirement) for the no-floating-point / integer-minor-units rule. (Recorded as binding; the surrounding set is still a draft pending review. Default currency and single-vs-multi-currency support remain Provisional pending **Q-007**.)
- **Context:** Floating-point money causes rounding drift and is unacceptable in a financial system spanning POS, RPC, Dart domain, and sync payloads.
- **Decision:** **DECISION D-007** — money is stored as **integer MINOR units** (e.g., agorot/cents). **NO floating point for money anywhere** — not in DB, RPC, Dart domain, or sync payloads. Money columns are integers **suffixed `_minor`** (**DECISION D-017**). Currency is per **organization**, overridable per **restaurant**; a single currency per order; ISO 4217 code. Default currency and single-vs-multi-currency support are **OPEN QUESTION Q-007**.
- **Alternatives considered:**
  - *Decimal/`numeric` money columns* — rejected: still risks float coercion across the Dart and JSON sync boundary; integer minor units are unambiguous end to end.
  - *Currency fixed at restaurant tier only* — rejected: org-level default with restaurant override matches the **D-002** hierarchy and group use cases.
- **Consequences:**
  - (+) Exact arithmetic across all layers; trivially serializable.
  - (-) Every layer must format/parse minor units consistently; rounding rules live in [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md).
  - (-) **RISK R-008:** money/rounding/tax correctness is partly blocked on jurisdiction (**Q-001..Q-004**); keep tax open until resolved.
- **Related:** [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) (owns money/tax rules), [DOMAIN_MODEL](DOMAIN_MODEL.md), [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-007), related D-008, D-017.

---

## D-008 — Price and modifier snapshots at order time

- **Status:** RF-001 requirement; specific approach PROPOSED pending review. (Price/modifier snapshots are required by RF-001 §9; the modeling is proposed.)
- **Context:** Menu prices change. Orders, receipts, and reports must reflect the price charged at the moment of sale, including while a device is offline and the live menu later changes.
- **Decision:** **DECISION D-008** — capture **item price snapshots and modifier price snapshots at order time**; orders **never recompute** from live menu prices. Discounts (order-level and item-level; percentage and fixed), void vs cancellation vs refund distinctions, and rounding are owned by [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md). Tips are **DEFERRED** (**Q-011**); service-charge rules are **OPEN QUESTION Q-012**.
- **Alternatives considered:**
  - *Recompute order totals from current menu prices* — rejected: produces incorrect historical totals and breaks offline orders created before a price change; violates auditability.
- **Consequences:**
  - (+) Historically accurate, audit-safe orders; offline price changes (D-010) cannot corrupt past orders.
  - (-) Order rows carry snapshot amounts (in `_minor` units per D-007), increasing row size and requiring snapshot fields in [DOMAIN_MODEL](DOMAIN_MODEL.md).
- **Related:** [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md), [DOMAIN_MODEL](DOMAIN_MODEL.md), [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), depends on D-007, related D-010.

---

## D-009 — Technology stack

- **Status:** INTENDED DIRECTION, pending confirmation. (RF-001 calls these tech-stack specifics "intended decisions," not final; pending ChatGPT + Codex review + Saleh approval. **No installation/initialization in M0A.** Note: the sub-parts no-service-role-in-clients, Realtime-not-sole, and offline-first ARE RF-001 invariants — see D-011, D-010.)
- **Context:** A coherent, cross-platform, offline-capable stack with strong Postgres security primitives is required, plus a documentation-first agent workflow.
- **Decision:** **DECISION D-009** — Flutter; Melos monorepo; Riverpod; GoRouter; Supabase / PostgreSQL; PostgreSQL RLS; PostgreSQL RPC for sensitive mutations; Drift/SQLite offline-first; reliable outbox/inbox sync; Supabase Realtime **as enhancement only**; ESC/POS printing behind a replaceable adapter; Arabic + Hebrew + English with full RTL/LTR; GitHub Actions CI; Claude Code primary implementer; Codex independent reviewer; ChatGPT + human owner as planning/decision layer. **M0A constraint:** document the stack and its risks/alternatives; do **not** install or initialize anything.
- **Alternatives considered:**
  - *React Native / native apps* — rejected: Flutter offers stronger single-codebase RTL/LTR control for ar/he/en (D-014) and consistent rendering across POS/KDS.
  - *Firebase instead of Supabase/Postgres* — rejected: RLS + SQL constraints + SECURITY DEFINER RPC (D-011/D-012) give the relational, testable isolation model RestoFlow's security depends on.
- **Consequences:**
  - (+) One codebase across surfaces; Postgres-native security; replaceable printing adapter limits **RISK R-001**.
  - (-) Vendor coupling to Supabase; mitigated by treating Realtime as enhancement only (D-010) and keeping logic in portable SQL/RPC.
- **Related:** [ARCHITECTURE](ARCHITECTURE.md), [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md), [TESTING_STRATEGY](TESTING_STRATEGY.md), [PROJECT_PLAN](PROJECT_PLAN.md), related D-010, D-011, D-014.

---

## D-010 — Offline-first: SQLite + outbox/inbox + idempotency; Realtime is enhancement only

- **Status:** RF-001 INVARIANT (binding requirement). (Offline-first with idempotency, and Realtime is not the sole synchronization mechanism / not the source of truth. Recorded as binding; the surrounding set is still a draft pending review. Per-entity conflict policy remains Provisional pending **Q-010**; Realtime limits/fallback pending **Q-014**.)
- **Context:** A POS must keep operating with no internet. Sync must be deterministic, not "sync later" hand-waving.
- **Decision:** **DECISION D-010** — SQLite/Drift is the **immediate local operational store**; the POS works fully offline. A **local outbox + server inbox/processed-operation ledger** with **idempotency keys** (`device_id` + `local_operation_id`, per **DECISION D-022**), client + server timestamps, entity revision/version, retry with backoff, dependent-op ordering, duplicate-mutation handling, crash recovery, poison/permanent-rejection handling, visible sync status, multi-device conflict rules, offline employee/device revocation, offline menu changes with price snapshots (D-008), order/payment duplication prevention, **tombstones** for deletions (**DECISION D-020**), and reconciliation after reconnect are all in scope and defined by [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md). **Supabase Realtime is an ENHANCEMENT only**, never the source of truth or the only sync mechanism. Per-entity conflict resolution (LWW vs domain rules) is **OPEN QUESTION Q-010**; Realtime limits/fallback polling is **Q-014**.
- **Alternatives considered:**
  - *Realtime/websocket as the sync mechanism* — rejected: not durable, not offline-safe; cannot be the source of truth.
  - *Naive last-write-wins everywhere* — rejected as a blanket policy: some entities need domain rules (e.g., payments); resolved per entity under **Q-010**.
- **Consequences:**
  - (+) Reliable offline operation; deterministic reconciliation; **RISK R-002** (sync conflicts/duplicates) contained by idempotency + outbox/inbox tested in M2.
  - (-) Significant sync engineering; **RISK R-007** offline revocation staleness (see D-006, Q-009).
- **Related:** [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), [STATE_MACHINES](STATE_MACHINES.md) (sync operation states), [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-010, Q-014), depends on D-008, D-020, D-021, D-022.

---

## D-011 — Sensitive mutations via PostgreSQL RPC; no service-role key in clients

- **Status:** RF-001 INVARIANT (binding requirement) for the no-service-role-credentials-in-clients rule. (Recorded as binding; the surrounding set is still a draft pending review. The SECURITY DEFINER RPC layer framing is part of the proposed D-012 synthesis.)
- **Context:** Sensitive operations (voids, refunds, price overrides, device pairing) need server-side authorization and auditing that clients cannot bypass.
- **Decision:** **DECISION D-011** — sensitive mutations go through **PostgreSQL RPC (SECURITY DEFINER functions)** that **authorize + audit** before mutating. **SECURITY REQUIREMENT:** **no service-role credentials in Flutter clients**; clients use anon/authenticated keys only and operate under RLS. RPC contracts are owned by [API_CONTRACT](API_CONTRACT.md).
- **Alternatives considered:**
  - *Direct client-side table writes for everything* — rejected: cannot reliably enforce authorization + audit for privileged actions; widens IDOR/abuse surface.
  - *Service-role key embedded in the app for "trusted" writes* — rejected outright: a service-role key in a client bypasses RLS and is extractable; explicit SECURITY REQUIREMENT violation.
- **Consequences:**
  - (+) Authorization and audit (D-013) are centralized and tamper-resistant; layer 3 of D-012.
  - (-) More RPCs to design, version, and test (owned by [API_CONTRACT](API_CONTRACT.md) and [TESTING_STRATEGY](TESTING_STRATEGY.md)).
- **Related:** [API_CONTRACT](API_CONTRACT.md), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md), depends on D-012, D-013.

---

## D-012 — Four security layers (defence in depth)

- **Status:** RF-001 requirement; specific approach PROPOSED pending review. (Each layer — RLS / membership+scope / RPC / DB constraints — is an RF-001 requirement; the "four layers" framing is a proposed synthesis.)
- **Context:** No single control should be the sole barrier between tenants. Cross-tenant leakage is the platform's most severe risk (**RISK R-003**, CRITICAL).
- **Decision:** **DECISION D-012** — four layers of defence in depth:
  1. **PostgreSQL RLS** on every tenant-scoped table.
  2. **Membership/role + branch/device scoping checks**.
  3. **Sensitive mutations via SECURITY DEFINER RPC** that authorize + audit (**DECISION D-011**).
  4. **Database constraints** as the final safety boundary.
  Cross-tenant access prevention, IDOR protection, and platform-admin isolation (a separate, explicitly audited path) are required. The mandatory isolation/permission test set is owned by [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md): Org A cannot read Org B orders; Cashier A cannot modify Restaurant B; KDS cannot read financial reports; a revoked device cannot sync new operations; a removed employee cannot create new valid operations; a cashier cannot void a paid order without permission; platform-admin access is explicitly audited.
- **Alternatives considered:**
  - *RLS alone* — rejected: a single policy bug becomes total leakage; layered controls plus constraints provide backstops.
  - *Application-layer authorization only (no RLS)* — rejected: a compromised or buggy client could read across tenants; RLS enforces isolation at the database.
- **Consequences:**
  - (+) Multiple independent failures required for a breach; **RISK R-003** substantially mitigated.
  - (-) Higher implementation and test cost; partially redundant checks by design.
- **Related:** [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (owns RLS/threats/isolation tests), [API_CONTRACT](API_CONTRACT.md), [TESTING_STRATEGY](TESTING_STRATEGY.md), depends on D-001, D-011, D-013.

---

## D-013 — Append-only audit events with full context

- **Status:** RF-001 INVARIANT (binding requirement). (Append-only audit events with the mandated fields. Recorded as binding; the surrounding set is still a draft pending review.)
- **Context:** Accountability requires an immutable record of who did what, where, when, and why — especially for sensitive actions (voids, refunds, overrides, platform-admin access).
- **Decision:** **DECISION D-013** — append-only **`audit_events`** capturing **actor, device, organization, restaurant, branch, timestamp, action, reason, old values, new values**. Audit events are **never updatable or deletable by app roles**. Sensitive RPCs (**DECISION D-011**) write audit events as part of the mutation.
- **Alternatives considered:**
  - *Mutable audit log* — rejected: a mutable log is not evidence; append-only is mandatory.
  - *Logging only at the application layer* — rejected: bypassable and not co-transactional with the mutation; audit must be written server-side within the RPC transaction.
- **Consequences:**
  - (+) Tamper-evident accountability; supports the platform-admin explicit-audit requirement of D-012.
  - (-) Storage growth and retention obligations (**OPEN QUESTION Q-005**, owned operationally by [OPERATIONS_AND_RECOVERY](OPERATIONS_AND_RECOVERY.md)).
- **Related:** [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md), [DOMAIN_MODEL](DOMAIN_MODEL.md), [OPERATIONS_AND_RECOVERY](OPERATIONS_AND_RECOVERY.md), [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-005), depends on D-011, D-012.

---

## D-014 — Languages ar/he/en with full RTL/LTR

- **Status:** RF-001 INVARIANT (binding requirement). (Languages ar/he/en + full RTL/LTR. Recorded as binding; the surrounding set is still a draft pending review. Arabic/Hebrew printing encoding strategy remains Provisional pending **Q-015**.)
- **Context:** The target market requires Arabic and Hebrew (RTL) alongside English (LTR), including on printed receipts/tickets.
- **Decision:** **DECISION D-014** — supported languages are **Arabic, Hebrew, English**, with **full RTL (ar, he) and LTR (en)** across all surfaces, and **localized receipts/tickets**. Encoding/raster fallback for Arabic/Hebrew printing is **OPEN QUESTION Q-015** (owned by [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md)).
- **Alternatives considered:**
  - *English-first, localize later* — rejected: RTL is structural, not cosmetic; retrofitting layout/printing is costly and error-prone. Designing RTL/LTR from the start avoids rework.
- **Consequences:**
  - (+) Market fit from day one; consistent RTL handling in Flutter (D-009).
  - (-) **RISK R-006:** Arabic/Hebrew printing/encoding correctness is hardware-dependent; mitigated by raster fallback and pilot validation (Q-015).
- **Related:** [PRODUCT_SPEC](PRODUCT_SPEC.md), [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md), [ARCHITECTURE](ARCHITECTURE.md), [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-015), related D-009.

---

## D-015 — Sources of truth (Jira / Git / Docs / TASK_TRACKER)

- **Status:** RF-001 INVARIANT (binding requirement). (Sources of truth: Jira/Git/Docs/TASK_TRACKER. Recorded as binding; the surrounding set is still a draft pending review.)
- **Context:** With multiple agents and a human owner, ambiguity about "the truth" causes drift and duplicated backlogs.
- **Decision:** **DECISION D-015** — sources of truth:
  - **Jira (project key RF)** = official source of truth for **task status**.
  - **Git** = official source of truth for **code and change history**.
  - **Architecture documents (`docs/`)** = official source of truth for **technical decisions and contracts**.
  - **`docs/TASK_TRACKER.md`** (the single tracker) = ONLY a concise current-session resume file; **not** a duplicate backlog.
  The master task list lives in [IMPLEMENTATION_CHECKLIST](IMPLEMENTATION_CHECKLIST.md) (human-readable) and `JIRA_IMPORT.csv` (import), authored together; [PROJECT_PLAN](PROJECT_PLAN.md) describes milestones, not individual tickets. Avoid multiple manually maintained full task lists.
- **Alternatives considered:**
  - *Maintain the backlog in Markdown only* — rejected: Jira is the agreed status authority; duplicating it in Markdown guarantees divergence.
- **Consequences:**
  - (+) Each artifact has one owner; reduces contradiction (**RISK R-005**).
  - (-) Requires discipline to keep `docs/TASK_TRACKER.md` thin and not re-copy the Jira backlog.
- **Related:** [PROJECT_PLAN](PROJECT_PLAN.md), [IMPLEMENTATION_CHECKLIST](IMPLEMENTATION_CHECKLIST.md), `JIRA_IMPORT.csv`, related D-016, D-019.

---

## D-016 — Agent workflow pipeline + guardrails

- **Status:** RF-001 INVARIANT (binding requirement). (Agent workflow pipeline + guardrails. Recorded as binding; the surrounding set is still a draft pending review.)
- **Context:** Three AI agents plus one human must collaborate without clobbering each other's work or pushing unreviewed/unsafe changes.
- **Decision:** **DECISION D-016** — pipeline: **ChatGPT planning -> Human approval -> Claude Code implementation -> Tests -> Codex independent review -> Claude Code fixes -> Human approval -> Merge.** Guardrails: Claude Code and Codex must not edit the same working tree simultaneously; Codex reviews read-only by default; parallel implementation needs separate branches + worktrees; one active ticket per worktree; every task has a ticket ID; shared-package and API-contract changes need dedicated tickets; **only the human owner (Saleh) performs the merge**; **no agent may push without human approval**; **no force push; no `reset --hard`; no database reset; no deletion of real data; no production changes; no secret disclosure; no silent scope expansion.**
- **Alternatives considered:**
  - *Single agent, ad hoc commits* — rejected: no independent review, higher defect and bus-factor risk (**RISK R-005**).
- **Consequences:**
  - (+) Independent review and a human merge gate catch defects and scope creep (**RISK R-004**).
  - (-) Slower throughput per ticket; deliberate trade-off for safety.
- **Related:** [PROJECT_PLAN](PROJECT_PLAN.md), [TESTING_STRATEGY](TESTING_STRATEGY.md), related D-015, D-017 (branch/commit naming).

---

## D-017 — Naming conventions

- **Status:** PROPOSED DECISION — pending ChatGPT + Codex review + Saleh approval; not frozen.
- **Context:** Consistent naming across DB, sync columns, tickets, branches, and commits prevents ambiguity and supports automation.
- **Decision:** **DECISION D-017** —
  - **DB:** snake_case, **plural** table names (e.g., `organizations`, `restaurants`, `branches`, `stations`, `devices`, `app_users`, `memberships`, `employee_profiles`, `device_pairings`, `device_sessions`, `pin_sessions`, `menu_categories`, `menu_items`, `item_sizes`, `item_variants`, `modifiers`, `modifier_options`, `orders`, `order_items`, `order_item_modifiers`, `kitchen_tickets`, `kitchen_station_items`, `payments`, `shifts`, `cash_drawer_sessions`, `print_jobs`, `sync_operations`, `audit_events`, `tables`). UUID primary key named `id`. `organization_id` on every tenant-scoped table (+ `restaurant_id`/`branch_id`/`device_id`/`station_id` where relevant). Money integer columns **suffixed `_minor`** with a currency where needed (D-007). `created_at`/`updated_at`; `deleted_at` tombstones for sync-relevant deletions (D-020). Sync columns: `device_id`, `local_operation_id`, `revision`/`version`, client/server timestamps.
  - **Tickets:** `RF-<number>`.
  - **Branch:** `<type>/RF-<id>-<slug>`, `type` in `{feat, fix, chore, docs, refactor, test, infra}`.
  - **Commit:** Conventional Commits `"<type>(<scope>): <summary> [RF-<id>]"`.
- **Alternatives considered:**
  - *Singular table names / camelCase columns* — rejected: inconsistent with PostgreSQL conventions and harder to script; plural snake_case chosen for uniformity.
- **Consequences:**
  - (+) Predictable schema and history; enables tooling and review.
  - (-) Requires enforcement in review (Codex/human) to avoid drift.
- **Related:** [DOMAIN_MODEL](DOMAIN_MODEL.md), [API_CONTRACT](API_CONTRACT.md), [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), related D-007, D-016, D-020.

---

## D-018 — Proposed state enumerations

- **Status:** PROPOSED DECISION — pending ChatGPT + Codex review + Saleh approval; not frozen. (RF-001 §8 explicitly directs us to evaluate these and NOT assume the listed values are final.)
- **Context:** State values should be agreed before the domain model and transitions are designed, so every layer can align on legal statuses. RF-001 §8 directs us to evaluate, not assume, the final enumerations.
- **Decision:** **DECISION D-018 (PROPOSED)** — the following status enumerations are PROPOSED and were approved into the frozen M0A baseline at RF-004 (RF-001 §8 directed evaluation rather than assuming the values final). [STATE_MACHINES](STATE_MACHINES.md) defines the transitions; [DOMAIN_MODEL](DOMAIN_MODEL.md) uses these baseline values:
  - **Order:** `draft -> submitted -> accepted -> preparing -> ready -> served -> completed`; plus `cancelled` (pre-production, terminal) and `voided` (post-submission, requires authorization+reason, terminal). Terminal: `completed`, `cancelled`, `voided`. *(The original draft clause here read "Takeaway skips `served` (`ready -> completed`)" — **superseded by RESTAURANT-OPERATIONS-V1-001 (review B3)**: both order types share the one chain `ready -> served -> completed`; a takeaway `served` is the customer pickup, displayed "Picked up" with no persisted `picked_up` state, and direct `ready -> completed` is not legal for any type. See [STATE_MACHINES](STATE_MACHINES.md) §1.)*
  - **Order item:** `pending -> queued -> preparing -> ready -> served`; plus `voided`, `cancelled` (terminal).
  - **Kitchen ticket:** `new -> acknowledged -> in_preparation -> ready -> bumped`; plus `recalled` (`bumped -> in_preparation`, audited), `cancelled`. Terminal: `bumped`, `cancelled`.
  - **Kitchen station item:** `queued -> in_preparation -> ready -> bumped`; plus `voided`. Terminal: `bumped`, `voided`.
  - **Payment:** `pending -> tendered -> completed`; plus `voided`, `failed`; `refunded` (**DEFERRED**). Terminal: `completed`, `voided`, `failed`. **`completed` is TERMINAL in MVP; `completed -> voided` is FORBIDDEN. Void is allowed ONLY pre-completion** (`pending -> voided`, `tendered -> voided`), per **DECISION D-023**.
  - **Shift:** `opening -> open -> closing -> closed -> reconciled`. Terminal: `reconciled`.
  - **Cash drawer session:** `opened(opening float) -> active -> counting -> closed(counted+variance) -> reconciled`. Terminal: `reconciled`. Bound to a shift.
  - **Print job:** `created -> queued -> printing -> printed`; plus `failed -> retrying`, `cancelled`, `abandoned(after max retries)`. Terminal: `printed`, `cancelled`, `abandoned`.
  - **Device pairing:** `code_issued -> pending -> paired -> active -> suspended -> revoked`; plus `code_expired`, `rejected`. Terminal: `revoked`, `code_expired`, `rejected`.
  - **Sync operation:** `created -> pending -> in_flight -> applied`; plus `rejected(permanent)`, `dead(poison after max retries)`, `conflict -> resolved`. Terminal: `applied`, `rejected`, `dead`.
- **Alternatives considered:**
  - *Free-form/boolean flags per entity* — rejected: ambiguous, unenforceable, and incompatible with audited transitions; explicit enumerations are required.
- **Consequences:**
  - (+) Shared vocabulary across DB, RPC, Dart domain, KDS, and sync; transitions become testable.
  - (-) Changing an enumeration later is a contract change requiring a dedicated ticket (D-016).
- **Related:** [STATE_MACHINES](STATE_MACHINES.md) (owns transitions), [DOMAIN_MODEL](DOMAIN_MODEL.md), [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md), related D-020, D-021, D-022.

---

## D-019 — Milestone structure M0A..M4

- **Status:** RF-001 INVARIANT (binding requirement) for the milestone structure M0A..M4. (Recorded as binding; the surrounding set is still a draft pending review. Indicative dates are PROPOSED and may change.)
- **Context:** A staged plan separates documentation, foundation, prototype, real backend, hardware pilot, and sellable SaaS so that scope is gated and risk is sequenced.
- **Decision:** **DECISION D-019** — milestones:
  - **M0A** — Documentation & Architecture baseline, FROZEN at RF-004 (human-approved by Saleh); originated RF-001, independently reviewed RF-002, corrected RF-003.
  - **M0B** — Technical foundation (monorepo, CI, Supabase bootstrap, first multi-tenant migrations, RLS skeleton, Drift+outbox, l10n+RTL) — **no business features**.
  - **M1** — Local POS + KDS prototype (local data, no real backend).
  - **M2** — Real backend + synchronization (Auth, RLS, RPC, outbox/inbox, conflict handling).
  - **M3** — Hardware pilot (ESC/POS printing, cash drawer, one real restaurant/branch, daily reports).
  - **M4** — Sellable SaaS (self-serve signup, platform admin, dashboards, basic billing, production hardening).
  Indicative dates (M0 ~Jul 2026; M1 Jul-Aug; M2 Aug-Sep; M3 Sep-Oct; M4 Oct-Dec 2026) are **PROPOSED** and owned by [PROJECT_PLAN](PROJECT_PLAN.md).
- **Alternatives considered:**
  - *Build backend and prototype together* — rejected: a local-first prototype (M1) de-risks UX before backend/sync complexity (M2); separating them controls scope (**RISK R-004**).
- **Consequences:**
  - (+) Clear gates; M0A enforces docs-only (no code/migrations); pilot isolated to M3.
  - (-) Dates are estimates; **billing model for M4 is OPEN QUESTION Q-016 (deferred but flagged).**
- **Related:** [PROJECT_PLAN](PROJECT_PLAN.md) (owns milestones/timeline), [MVP_SCOPE](MVP_SCOPE.md), [PILOT_PLAN](PILOT_PLAN.md), [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-016), related D-015.

---

## D-020 — Tombstone / soft-delete semantics for sync

- **Status:** RF-001 requirement; specific approach PROPOSED pending review. (Tombstones are required by RF-001 §7; the specific semantics are proposed.)
- **Context:** Deletions must propagate across offline devices; a hard delete cannot be communicated to a device that never saw the row removed.
- **Decision:** **DECISION D-020** — sync-relevant deletions use **tombstones** (`deleted_at`, per **DECISION D-017**) rather than physical deletion, so deletions reconcile deterministically across devices. Tombstone propagation and reconciliation rules are owned by [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
- **Alternatives considered:**
  - *Hard deletes* — rejected: an offline device cannot learn of a row that simply vanished; reconciliation would be ambiguous and could resurrect deleted data.
- **Consequences:**
  - (+) Deterministic deletion propagation; supports duplicate/conflict handling (**RISK R-002**).
  - (-) Soft-deleted rows persist (retention implications, **Q-005**); queries and RLS must exclude tombstoned rows appropriately.
- **Related:** [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), [DOMAIN_MODEL](DOMAIN_MODEL.md), [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-005), depends on D-017, related D-010.

---

## D-021 — Receipt numbering = per-branch server-assigned monotonic sequence (offline provisional reconciled)

- **Status:** PROPOSED DECISION — pending ChatGPT + Codex review + Saleh approval; not frozen (and pending **Q-004**, jurisdiction **Q-001**). (The receipt-numbering approach is proposed.)
- **Context:** Receipts need stable, gap-controlled numbers per branch, but offline devices cannot know the authoritative next number at sale time.
- **Decision:** **DECISION D-021** — receipt numbering is a **per-branch monotonic server-assigned sequence**. Offline, a device assigns a **provisional id** that is **reconciled to the authoritative server number on sync**. Exact format, sequence-reset, and legal numbering rules are **OPEN QUESTION Q-004** (jurisdiction **Q-001**); detailed mechanics are owned by [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) and [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
- **Alternatives considered:**
  - *Client-generated final receipt numbers* — rejected: offline devices would collide and could not guarantee per-branch monotonicity or legal compliance.
  - *Global (cross-branch) sequence* — rejected: branches operate independently; per-branch sequencing matches operations and likely fiscal rules (pending Q-004).
- **Consequences:**
  - (+) Authoritative, monotonic per-branch numbering with offline continuity.
  - (-) Receipts show a provisional number until reconciled; UX must surface this (sync status, D-010). Legal correctness blocked on **Q-001/Q-004** (**RISK R-008**).
- **Related:** [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md), [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-001, Q-004), depends on D-022, related D-018.

---

## D-022 — Idempotency via device_id + local_operation_id on every mutating op

- **Status:** RF-001 INVARIANT (binding requirement). (Offline-first with idempotency. Recorded as binding; the surrounding set is still a draft pending review.)
- **Context:** Network retries, crashes, and reconnects can resend the same operation; the server must apply each exactly once.
- **Decision:** **DECISION D-022** — every mutating client operation carries an **idempotency key = `device_id` + `local_operation_id`**. The server inbox/processed-operation ledger uses this key to detect and reject duplicates so each operation is applied at most once. Mechanics are owned by [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md); RPC contracts that accept the key are owned by [API_CONTRACT](API_CONTRACT.md).
- **Alternatives considered:**
  - *Rely on server-side dedup by content hash* — rejected: legitimately identical operations (e.g., two identical items) would be wrongly merged; an explicit per-device operation id is unambiguous.
  - *Single global sequence per device only* — rejected: composing `device_id` with `local_operation_id` guarantees uniqueness across devices without coordination.
- **Consequences:**
  - (+) Exactly-once application; prevents order/payment duplication (**RISK R-002**); enables safe retries with backoff.
  - (-) Clients must persist `local_operation_id` durably (crash recovery) and never reuse it.
- **Related:** [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), [API_CONTRACT](API_CONTRACT.md), [DOMAIN_MODEL](DOMAIN_MODEL.md), depends on D-010, D-017, feeds D-021.

---

## D-023 — Completed payment is terminal in MVP

- **Status:** Accepted at the RF-004 architecture freeze (human-approved by Saleh, after RF-002 review and RF-003 corrections); part of the frozen M0A baseline.
- **Context:** The Payment enumeration (**DECISION D-018**) lists `completed` as terminal, but earlier draft text did not state unambiguously whether a completed payment could later be voided. Allowing `completed -> voided` would silently reintroduce a refund/reversal pathway that the MVP has deliberately deferred, corrupting financial history and audit integrity. The void semantics for pre-completion states (cash physically received vs. not) also need to be explicit.
- **Decision:** **DECISION D-023** —
  - `payment.completed` is **TERMINAL** in MVP.
  - A payment may be **voided ONLY before completion**: `pending -> voided` and `tendered -> voided`. Each void requires an **authorized actor + reason + audit event** (**DECISION D-013**). The `tendered -> voided` path must **account for cash physically received** before finalization (the drawer/shift accounting reflects the received-then-voided cash; it is not silently discarded).
  - `completed -> voided` is **FORBIDDEN**.
  - Refunds, reversals, and any post-completion corrections are **DEFERRED** (no hidden refund pathway exists in MVP).
- **Alternatives considered:**
  - *Allow `completed -> voided` as a "correction"* — rejected: it is an undocumented refund/reversal mechanism that rewrites finalized financial records and undermines audit integrity; post-completion correction is explicitly deferred.
  - *Forbid all voids, even pre-completion* — rejected: legitimate operational mistakes before finalization (wrong tender, mis-keyed payment) must be reversible while the payment is still in flight, with authorization and audit.
- **Consequences:**
  - (+) Finalized payments are immutable; audit and reporting stay trustworthy; **RISK R-008** exposure is contained by refusing silent post-completion money changes.
  - (-) Genuine post-completion corrections must wait for the deferred refund workflow; operators handle them out-of-band until then.
- **Related:** [STATE_MACHINES](STATE_MACHINES.md), [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md), [API_CONTRACT](API_CONTRACT.md), related D-018, D-024, D-025, D-013.

---

## D-024 — Completed order is terminal in MVP

- **Status:** Accepted at the RF-004 architecture freeze (human-approved by Saleh, after RF-002 review and RF-003 corrections); part of the frozen M0A baseline.
- **Context:** The Order enumeration (**DECISION D-018**) marks `completed` terminal, but the draft did not state clearly that a completed order cannot be cancelled or voided after the fact, nor how cancel/void interacts with an already-completed payment. Permitting post-completion order changes would rewrite historical records and could imply an undeferred refund.
- **Decision:** **DECISION D-024** —
  - `order.completed` is **TERMINAL** in MVP.
  - `completed -> voided` and `completed -> cancelled` are **FORBIDDEN**.
  - Pre-completion cancel/void is allowed **only** when the transition is otherwise valid (per [STATE_MACHINES](STATE_MACHINES.md)) **AND no completed payment exists** for the order.
  - If a **completed payment exists**, a cancel/void is **REJECTED** in MVP (honouring it would require the deferred refund workflow, **DECISION D-023**).
  - Historical completed records are **never rewritten**.
- **Alternatives considered:**
  - *Allow voiding a completed order and cascade-reverse its payment* — rejected: this is a refund pathway, explicitly deferred (D-023), and would mutate finalized financial history.
  - *Allow cancel/void with a completed payment, leaving the payment untouched* — rejected: produces an inconsistent record (cancelled order, captured money) with no reconciliation path in MVP.
- **Consequences:**
  - (+) Completed orders and their money are immutable; consistent with payment terminality (D-023); audit-safe.
  - (-) Mistakes discovered after completion cannot be corrected in-app until the deferred refund/correction workflow ships.
- **Related:** [STATE_MACHINES](STATE_MACHINES.md), [PRODUCT_SPEC](PRODUCT_SPEC.md), related D-018, D-023, D-025.

---

## D-025 — Payment and fulfillment are independent; quick-service pay-first

- **Status:** Accepted at the RF-004 architecture freeze (human-approved by Saleh, after RF-002 review and RF-003 corrections); part of the frozen M0A baseline.
- **Context:** Quick-service flows take payment before food is prepared, while table-service flows pay after. The order lifecycle (**DECISION D-018**) and the payment lifecycle must not be conflated: completing a payment must not auto-advance fulfillment, and reaching a fulfillment state must not imply payment. The set of order states from which a payment may start must be explicit.
- **Decision:** **DECISION D-025** —
  - Payment and fulfillment are **independent** lifecycles.
  - Eligible order states from which a payment may **START** are: `submitted`, `accepted`, `preparing`, `ready`, `served`. The states `draft`, `cancelled`, `voided`, and `completed` are **excluded** (no payment may start there).
  - **Payment completion does NOT imply** the order is prepared/ready/served/completed.
  - An order **completes only when** fulfillment is satisfied **AND** the (chargeable) payment is completed.
- **Alternatives considered:**
  - *Couple the two state machines (completing payment forces order to completed)* — rejected: breaks both quick-service (paid but not yet prepared) and table-service (served but not yet paid) realities.
  - *Allow payment from any order state including `draft`* — rejected: charging against an unsubmitted or terminal order is invalid and unauditable.
- **Consequences:**
  - (+) One model supports both pay-first and pay-later flows; clear completion gate; testable independently.
  - (-) Two lifecycles to coordinate; the completion rule must be enforced server-side (RPC, **DECISION D-011**) rather than inferred client-side.
- **Related:** [STATE_MACHINES](STATE_MACHINES.md), [PRODUCT_SPEC](PRODUCT_SPEC.md), [API_CONTRACT](API_CONTRACT.md), related D-018, D-023, D-024.

---

## D-026 — Platform admin is not a tenant membership role

- **Status:** Accepted at the RF-004 architecture freeze (human-approved by Saleh, after RF-002 review and RF-003 corrections); part of the frozen M0A baseline.
- **Context:** Earlier text (D-004/D-005) listed `platform_admin` among the membership role keys. Platform administration is cross-tenant by nature and has **no** `organization_id`; modelling it as a tenant membership role conflates platform operators with tenant staff, muddies RLS predicates, and risks a privileged role leaking into tenant authorization paths.
- **Decision:** **DECISION D-026** —
  - **Remove `platform_admin` from the membership role keys.** Tenant (membership) roles are exactly: `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant`.
  - Platform administration is modelled via the **separate PROPOSED entity `platform_admin_grants`** ([DOMAIN_MODEL](DOMAIN_MODEL.md) §3.7) with fields: `app_user_id`, **NO `organization_id`**, `status` (`active -> suspended -> revoked`), `granted_by` / `granted_at` / `revoked_by` / `revoked_at`.
  - Platform-admin access is a **separate, privileged, explicitly-audited path** (**DECISION D-013**) that **never silently bypasses tenant protections**; **MFA** applies per **OPEN QUESTION Q-008**.
  - Mandatory tests **T-008..T-011** ([SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)) cover platform-admin isolation and audit.
- **Alternatives considered:**
  - *Keep `platform_admin` as a membership role with a null/sentinel `organization_id`* — rejected: pollutes the tenant role model and RLS predicates; a null tenant boundary on a membership invites cross-tenant leakage (**RISK R-003**).
- **Consequences:**
  - (+) Clean separation between tenant authorization and platform operations; auditable, MFA-gated, explicitly tested isolation.
  - (-) A second authorization mechanism to build and test alongside memberships.
- **Related:** [DOMAIN_MODEL](DOMAIN_MODEL.md), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md), [API_CONTRACT](API_CONTRACT.md), [ARCHITECTURE](ARCHITECTURE.md), [TESTING_STRATEGY](TESTING_STRATEGY.md), [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-008), related D-004, D-005, D-012, D-013.

---

## D-027 — M0B blocker classification

- **Status:** Accepted at the RF-004 architecture freeze (human-approved by Saleh, after RF-002 review and RF-003 corrections); part of the frozen M0A baseline.
- **Context:** It was ambiguous whether every open question (Q-001..Q-024) must be resolved before M0B can begin. Treating all open questions as global blockers would stall foundation work that does not actually depend on them; treating none as blockers would risk baking in irreversible assumptions.
- **Decision:** **DECISION D-027** —
  - **RF-004 human approval blocks the START of M0B as a MILESTONE** (the freeze event gates the milestone).
  - An **individual open question blocks ONLY its dependent tickets**, not M0B as a whole.
  - A question may be classified **"Accepted Open"** when: an owner is assigned; the blocking ticket/milestone is identified; a **safe interim interface/config/placeholder/flag** exists; and **no irreversible schema/contract assumption** is made.
  - **RF-004 does NOT require all Q-001..Q-024 to be resolved.**
- **Alternatives considered:**
  - *Require every open question resolved before M0B* — rejected: blocks foundation work (monorepo, CI, RLS skeleton) on questions it does not depend on; no pilot value.
  - *Ignore open questions during M0B* — rejected: risks committing irreversible schema/contract decisions before the relevant question is answered.
- **Consequences:**
  - (+) M0B foundation work proceeds where safe; risk is localized to dependent tickets; "Accepted Open" gives a disciplined interim path.
  - (-) Requires per-question owner/blocker tracking and discipline to avoid an "Accepted Open" silently hardening into a real assumption.
- **Related:** [OPEN_QUESTIONS](OPEN_QUESTIONS.md), [PROJECT_PLAN](PROJECT_PLAN.md), [AGENT_WORKFLOW](AGENT_WORKFLOW.md), [IMPLEMENTATION_CHECKLIST](IMPLEMENTATION_CHECKLIST.md), related D-019.

---

## D-028 — Accountant read-only; shift close/count separated from reconciliation

- **Status:** Accepted at the RF-004 architecture freeze (human-approved by Saleh, after RF-002 review and RF-003 corrections); part of the frozen M0A baseline.
- **Context:** The `accountant` role (D-004, Q-017) must be genuinely read-only, and the shift/drawer lifecycle (**DECISION D-018**) must distinguish the operational close/count step from the managerial reconciliation step. Folding both into one action would let the counting party also approve the variance, removing separation of duties.
- **Decision:** **DECISION D-028** —
  - `accountant` performs **NO transition or mutation anywhere**; it is strictly read-only.
  - **Shift close / count** is performed by a **cashier or authorized manager**: `close_shift` advances the shift `open -> closing`, the cash drawer `open -> counting`, records the counted amount, computes **variance = counted − expected**, advances the drawer to `closed`, and writes an audit event.
  - **Reconciliation** is a **separate** step performed by a **manager / restaurant_owner / org_owner**: `reconcile_shift` reviews the close, captures a **reason when required**, advances the shift `closed -> reconciled`, and writes a **sensitive** audit event.
  - **One RPC must not do both** close/count and reconciliation (separation of duties).
- **Alternatives considered:**
  - *Single RPC that closes, counts, and reconciles* — rejected: collapses separation of duties; the party counting cash would also approve its own variance.
  - *Let `accountant` perform reconciliation* — rejected: `accountant` is read-only by definition; reconciliation is a privileged mutation.
- **Consequences:**
  - (+) Enforced separation of duties; clear, auditable money trail; matches the shift/drawer enumerations (D-018).
  - (-) Two RPCs and two role gates to implement and test instead of one.
- **Related:** [STATE_MACHINES](STATE_MACHINES.md), [API_CONTRACT](API_CONTRACT.md), [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md), [TESTING_STRATEGY](TESTING_STRATEGY.md), related D-004, D-018, [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-017).

---

## D-029 — Authorize two public auth precursor APIs (`public.start_pin_session` wrapper + `public.get_my_context` resolver) as change-controlled, client-facing surfaces

- **Status:** Accepted at the RF-122 architecture-change approval (human-approved by Saleh, after independent Codex review), under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9); **amends** the frozen M0A API-contract baseline. Satisfies candidate D-030 point 2 (each new backend surface is authorized by its own decision before code); candidate **D-030** itself remains unratified/reserved (the M6-track label).
- **Context:** RF-108 (the real client auth/session wiring) needs two client-callable backend surfaces that do **not** exist today. (1) The Data API exposes only the `public`/`graphql_public` schemas (`supabase/config.toml`), so the already-built `app.start_pin_session(uuid, uuid, text, text)` (RF-051) is **not** HTTP-reachable; a narrow **public wrapper** is needed so a paired+authorized device can establish a human PIN session (**DECISION D-006**). (2) The client must resolve **which** tenant scope/membership to act under for routing and scope selection without trusting client-supplied identity; a **self-context resolver** `public.get_my_context()` is needed because a raw client self-read returns membership **IDs only** (joined org/restaurant/branch names are not readable without a server-side GUC the client cannot set). Authorizing new client-facing auth surface touches the frozen API contract and is credential/tenant-isolation sensitive (**DECISION D-011**, **DECISION D-001**, **RISK R-003**), so it is ratified here before any SQL is written.
- **Decision:** **DECISION D-029** —
  - Authorize a **narrow `public.start_pin_session` wrapper** that is a **faithful pass-through** to `app.start_pin_session` — **same four parameters, same types and order** (`p_device_session_id uuid, p_employee_profile_id uuid, p_pin_verifier text, p_local_operation_id text default null`), **returns a bare `uuid`**, preserving the existing semantics: **wrong PIN → `NULL`** (no row, no error); **structural / precondition / lockout failures → SQLSTATE `42501`**; keyed idempotent replay unchanged.
  - The wrapper is **`SECURITY INVOKER`**, `search_path=''`, delegates verbatim to `app.start_pin_session`, and **adds no new privilege** (it reuses the caller's existing `EXECUTE` on the `app` function — the RF-064 `public.sync_pull` mirror pattern). **No richer return** is introduced by this authorization (RF-123).
  - Authorize **`public.get_my_context()`** — a **read-only self-context resolver** that returns the calling principal's identity (derived from `auth.uid()` via `app.current_app_user_id()`, **never** an input argument) and the **LIST of that user's own memberships** (membership id, `organization_id`, `restaurant_id`, `branch_id`, the six-key `role`, status), with `organization`/`restaurant`/`branch` **names** for display, plus `is_platform_admin` as a **separate boolean** (via `app.is_platform_admin()`).
  - `public.get_my_context()` returns a membership **LIST, never a single global role**; role is **per-membership** (**DECISION D-004 / D-005** multi-membership preserved). `is_platform_admin` is a **separate boolean / path, never a tenant membership**, carries **no `organization_id`**, and no org/restaurant/branch context may be derived from it (**DECISION D-026** platform-admin separation preserved). The only PII returned is the **caller's own** `email`/`display_name`; no other user's data and no cross-org data. As a self-scoped **read** it requires **no `audit_events` row** (audit is scoped to sensitive mutations — [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) §7).
  - Both are **change-controlled backend surfaces**: each is implemented under its **own** RF ticket (RF-123 wrapper, RF-124 resolver) per the architecture-change procedure — **not** folded into a UI/feature ticket; the **RF-060 tenant-isolation suite must be green before the backend wrapper/resolver merges** (**RISK R-003**).
  - **No service-role credential in any client** (**DECISION D-011**); both functions are granted `EXECUTE` to **`authenticated` only** — **never `anon` / public / `service_role`**. The `app` schema is **not** added to the Data API; only the `public.*` surfaces are reachable.
- **Alternatives considered:**
  - *Expose the `app` schema directly via the Data API instead of `public.*` wrappers* — rejected: widens the HTTP attack surface to every internal `app.*` function and breaks the established `public`-only exposure boundary (RF-064 pattern).
  - *Have `public.get_my_context()` return a single top-level `role`* — rejected: a user may hold **multiple memberships** across scopes (**DECISION D-004 / D-005**); a global role has no backing column and would misrepresent identity. It must return a membership **list**.
  - *Fold these RPCs into the RF-108 client ticket* — rejected: new client-facing backend surface must follow the architecture-change procedure with its own ticket + DECISIONS entry (candidate D-030 point 2).
  - *Audit every `get_my_context` self-read* — rejected: audit is reserved for sensitive mutations (§7); a self-scoped read creates audit noise with no security benefit.
- **Consequences:**
  - (+) RF-108 can wire real auth/session against a stable, explicitly-authorized public contract; isolation posture is fixed before code (**RISK R-003** addressed by the mandatory RF-060 gate).
  - (+) `app.*` stays unexposed; the wrapper adds no new grant; identity stays server-derived, never client-supplied.
  - (-) Two additional public RPCs to implement, grant-test, and isolation-test (their own RF-123 / RF-124 tickets).
  - (-) `public.get_my_context` surfaces the caller's own `email`/`display_name` (minimal PII); accepted as the narrowest self-scoped read of the caller's own row.
- **Related:** [API_CONTRACT](API_CONTRACT.md) (§4.21 `public.start_pin_session`, §4.22 `public.get_my_context`), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-012), [AGENT_WORKFLOW](AGENT_WORKFLOW.md) (§9 architecture-change procedure), related D-001, D-004, D-005, D-006, D-011, D-026, candidate D-030 (M6 track, unratified), **RISK R-003**, [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-009 offline PIN-session validity window).

---

## D-031 — RF-109 menu backend schema/RLS/RPC/sync contract

- **Status:** Accepted at the RF-109 architecture-change approval (human-approved by Saleh, after independent Codex review), under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9); **amends** the frozen M0A schema/RLS/API/sync baseline. Like **DECISION D-029**, this is a **per-ticket M6 backend-surface ADR** that **satisfies candidate D-030 point 2** (each new M6 backend surface is authorized by its own decision before code — [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) §11). The standalone **candidate D-030** (the M6-track umbrella) **remains unratified/reserved** and is **not** consumed by this entry; RF-109 takes the next free sequential ID **D-031**, exactly as RF-122 took D-029 and left D-030 reserved.
- **Context:** M6 introduces real menu data. **No menu tables exist server-side today** — the menu is referenced only as opaque non-FK uuids plus order-time snapshots in `submit_order`, while the client already carries a Drift menu mirror (RF-030: `menu_categories`, `menu_items`, `item_sizes`, `item_variants`, `modifiers`, `modifier_options`). RF-109 is the backend menu **data foundation**: schema, RLS/isolation, role-gated management RPCs, and `sync_pull` read exposure. Creating new tenant-scoped tables, new RLS policies, audited mutation RPCs, and extending the `sync_pull` allowlist all touch the frozen baseline and are credential/tenant-isolation/money sensitive (**DECISION D-001**, **D-007**, **D-008**, **D-011**, **D-012**, **RISK R-003**, **RISK R-008**), so the contract is ratified here **before any SQL is written**. Owning specs: entities/fields [DOMAIN_MODEL](DOMAIN_MODEL.md) §4, RPC shapes [API_CONTRACT](API_CONTRACT.md) (§4.23, §4.15), isolation/tests [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-013).
- **Decision:** **DECISION D-031** —
  - **Scope (in):** the backend menu **data foundation only** — (a) the six menu tables; (b) RLS/tenant isolation on all six; (c) role-gated `SECURITY DEFINER` management RPCs with audit; (d) menu **read** exposure via `sync_pull`; (e) pgTAP coverage. **Scope (out):** image storage bucket/policies (RF-110), owner menu UI (RF-111), real POS submit-order integration (RF-115), payments, printing, KDS write actions, dashboard reports, any app/UI integration, and production deployment — none are in RF-109.
  - **Schema.** Create six tables — `menu_categories`, `menu_items`, `item_sizes`, `item_variants`, `modifiers`, `modifier_options` — each carrying `id uuid`, `organization_id uuid not null`, `restaurant_id uuid not null`, `branch_id uuid` (nullable scope override), `display_order integer`, `is_active boolean`, `created_at`, `updated_at`, and `deleted_at` (tombstone, **DECISION D-020**), using the **composite same-org FK** pattern of RF-014 (`unique (organization_id, id)` on parents; children FK on `(organization_id, parent_id)`), consistent with **DECISION D-001/D-002/D-012** and the naming of **DECISION D-017**. This **amends** [DOMAIN_MODEL](DOMAIN_MODEL.md) §4: `branch_id` (nullable scope override) is **promoted from the §4.1 ASSUMPTION to a ratified column on all six tables** — added to `menu_items` (§4.2) and the four child tables (§4.3–§4.6), which §4 currently scopes to `organization_id` + `restaurant_id` only — and `default_station_id` (already in §4.2) is carried on `menu_items` (resolving RF-109-Q1). DOMAIN_MODEL §4 is **reconciled accordingly under RF-109 (Stage 0B)** — `branch_id` on items + children, the child money column standardized to `price_delta_minor`, and the §4.2 `currency` field named `currency_code`.
  - **Money (D-007).** All menu prices are **integer minor units only**: `menu_items.base_price_minor bigint` (absolute, `>= 0`) with `currency_code` (ISO 4217; [DOMAIN_MODEL](DOMAIN_MODEL.md) §4.2 `currency`, single currency per order enforced at order time — **OPEN QUESTION Q-007**), plus a **uniform signed** child `price_delta_minor bigint` on `item_sizes`, `item_variants`, and `modifier_options` (inheriting the item's currency). **No** float / numeric-money / decimal / double anywhere, and orders never recompute from the live menu. This **standardizes** the child money column on `price_delta_minor`, **amending** [DOMAIN_MODEL](DOMAIN_MODEL.md) §4.3 (`price_delta_minor` *or* `price_minor`) and §4.6 (`modifier_options` absolute `price_minor`) to match the RF-030 client Drift mirror, which already uses `price_delta_minor` for all three children (DOMAIN_MODEL §4 reconciled under RF-109 — see the Schema clause).
  - **Snapshots (D-008).** **No foreign key** is added from order snapshot rows to the live menu: `order_items.menu_item_id` and `order_item_modifiers.modifier_option_id` remain **non-FK snapshot references**; price/modifier snapshots captured at order time stay authoritative and orders never recompute from the live menu.
  - **Open-question resolutions (RF-109).**
    - **RF-109-Q1:** add `default_station_id` to `menu_items` now as a **nullable FK to stations** (KDS routing, [DOMAIN_MODEL](DOMAIN_MODEL.md) §4.2), avoiding a later migration.
    - **RF-109-Q2:** allow **signed** `price_delta_minor` (including negative deltas, e.g. a smaller size = −500), integer minor only.
    - **RF-109-Q3:** use `updated_at` for MVP sync cursor/paging; **no** separate server-side `revision` column.
    - **RF-109-Q4:** mirror client parity — children carry `organization_id` + `restaurant_id` + nullable `branch_id` (matches the RF-030 Drift mirror), enabling uniform restaurant/branch-depth RLS.
    - **RF-109-Q5:** thin `public.menu_*` wrappers are **required** because the `app` schema is not Data-API-exposed (only `public`/`graphql_public` per `supabase/config.toml`).
    - **RF-109-Q6:** the `sync_pull` pager uses uniform org/branch behaviour because all six tables carry `branch_id`.
  - **RLS / security.** RLS **enabled + forced** on all six tables with **explicit per-command policies** (deny-by-default). SELECT is allowed **only** to a scoped tenant membership holding a **non-kitchen** tenant role — `org_owner`, `restaurant_owner`, `manager`, `cashier`, `accountant` — i.e. the existing scope predicate (`organization_id = app.current_org_id() AND app.has_scope(organization_id, restaurant_id, branch_id)`, the RF-015 scope helpers) **plus a role gate that excludes `kitchen_staff`**. **`kitchen_staff` reads no menu row on any path:** menu rows carry money (`base_price_minor`/`price_delta_minor`) and a kitchen principal must not read **any** money figure (**T-003**, [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) §14) — so kitchen is excluded from the role-gated table SELECT (table path) **and** from the `sync_pull` entity allowlist (sync path), with `app.redact_money` as a defence-in-depth backstop. KDS gets item names from order snapshots (**DECISION D-008**), never the live menu. Direct INSERT/UPDATE/DELETE are **denied by policy and REVOKED**; all writes go through `SECURITY DEFINER` RPCs (**DECISION D-011/D-012**). Write roles are **`org_owner`, `restaurant_owner`, `manager`** only; `cashier`, `kitchen_staff`, and the read-only `accountant` cannot write (**DECISION D-028**). `platform_admin` is **never** on the tenant RLS path (**DECISION D-026**); **no service-role key in any client** (**DECISION D-011**).
  - **RPC / API.** Role-gated menu management RPCs — `menu_upsert_category`, `menu_upsert_item`, `menu_upsert_size`, `menu_upsert_variant`, `menu_upsert_modifier`, `menu_upsert_modifier_option`, and `menu_soft_delete` — implemented as `app.*` `SECURITY DEFINER` (locked `search_path`, granted to `authenticated` only) with thin `public.menu_*` `SECURITY INVOKER` wrappers (the RF-064 `public.sync_pull` / RF-122 `public.start_pin_session` pattern). Each gates owner/manager, validates integer-minor money, writes an `audit_events` row on **both** the mutation and any denied write (**DECISION D-013**), is **idempotent upsert-by-id**, and soft-deletes via `deleted_at`. Contract owned by [API_CONTRACT](API_CONTRACT.md) §4.23.
  - **Sync.** Menu **read** path is `sync_pull`: extend the inner `app.sync_pull_changes` entity allowlist and the outer `app.sync_pull` role/entity gates (forward migration **CREATE OR REPLACE**, never an in-place edit of RF-057/RF-059) so `cashier`/`manager`/`restaurant_owner`/`org_owner` (and `accountant` if shipped, **OPEN QUESTION Q-017**) can pull the menu and `kitchen_staff` **cannot**. The `public.sync_pull` wrapper signature is **unchanged** (RF-064). Menu writes are online-direct RPCs, **not** the outbox (§4.14).
  - **Governance.** Implemented under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9): own ticket (RF-109), this DECISIONS entry before code, independent Codex review, human approval, and the **RF-060 tenant-isolation suite green before merge** (**RISK R-003**). Test contract: pgTAP for schema/constraints, no-float money, RLS/isolation (incl. restaurant/branch-depth), role matrix, sync visibility (kitchen excluded), soft-delete/tombstones, and **D-008** snapshot independence, with the RF-060 regression suite kept green ([SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) §14 T-013; [TESTING_STRATEGY](TESTING_STRATEGY.md) §2/§4/§5/§6/§7).
- **Alternatives considered:**
  - *Add FKs from `order_items`/`order_item_modifiers` to the new menu tables* — rejected: it would couple historical orders to the live menu and break **DECISION D-008** snapshot independence (orders must never recompute from the live menu).
  - *Carry menu prices as `numeric`/decimal money* — rejected: violates **DECISION D-007** (integer minor units only; no floating-point money anywhere).
  - *Expose the `app` schema directly / let clients write menu tables* — rejected: widens the HTTP/RLS attack surface and bypasses audit; writes must go through audited `SECURITY DEFINER` RPCs with `public.*` wrappers (**DECISION D-011/D-012**, RF-064 pattern).
  - *Carry menu writes on the offline outbox (`sync_push`)* — rejected: the outbox dispatches a closed op-type set for operational mutations; menu is server-authoritative config edited online-direct (last-writer-wins by id).
  - *Let `kitchen_staff` read the live menu (table SELECT or sync pull)* — rejected: menu prices are money and a kitchen principal must not read **any** money figure (**T-003**); KDS needs only item names, which it gets from order snapshots (**DECISION D-008**) — so kitchen is excluded from **both** the role-gated table SELECT and the `sync_pull` allowlist, with `app.redact_money` as a defence-in-depth backstop.
  - *Consume the reserved `D-030` id for this ADR* — rejected: `D-030` is the reserved (unratified) M6-track umbrella label referenced across the M6 docs; per the D-029/RF-122 precedent this per-ticket ADR takes the next free id **D-031** and satisfies candidate D-030 point 2.
- **Consequences:**
  - (+) M6 gains a real, tenant-isolated, integer-minor menu backend with audited owner/manager writes and cashier/manager/owner sync — without weakening **D-007**/**D-008**/**D-026** or the kitchen money boundary.
  - (+) Snapshot independence is preserved (no order→menu FK); existing orders are never rewritten by menu edits.
  - (-) New RLS surface across six tables raises the **RISK R-003** review burden; mitigated by the stations-template per-command policies + the RF-060 green gate + the T-013 isolation tests.
  - (-) Menu prices are money (**RISK R-008**); mitigated by `bigint _minor` + check constraints + integer-parse validation in the write RPCs + no-float pgTAP assertions.
  - (-) Several `app.menu_*` RPCs + `public.*` wrappers to implement, grant-test, and isolation-test under the RF-109 ticket.
- **Related:** [API_CONTRACT](API_CONTRACT.md) (§4.23 menu management RPCs; §4.15 `sync_pull` menu read), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-013, T-003 kitchen money boundary), [DOMAIN_MODEL](DOMAIN_MODEL.md) (§4 menu entities — **amended** by this decision and **reconciled** under RF-109 Stage 0B: `branch_id` on all six tables, child money column → `price_delta_minor`, `currency` → `currency_code`), [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), [TESTING_STRATEGY](TESTING_STRATEGY.md), [AGENT_WORKFLOW](AGENT_WORKFLOW.md) (§9), [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) (§11 candidate D-030, unratified), related D-001, D-002, D-005, D-007, D-008, D-011, D-012, D-013, D-017, D-020, D-026, D-028, D-029, **RISK R-003**, **RISK R-008**, [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-007, Q-017).

---

## D-032 — RF-110 menu image storage bucket and policies contract

- **Status:** Accepted at the RF-110 architecture-change approval (human-approved by Saleh, after independent Codex review), under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9); **amends** the frozen M0A baseline by adding a new Supabase **Storage** backend surface. Like **DECISION D-029** / **D-031**, this is a **per-ticket M6 backend-surface ADR** that **satisfies candidate D-030 point 2** (each new M6 backend surface is authorized by its own decision before code — [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) §11); the standalone **candidate D-030** (the M6-track umbrella) **remains unratified/reserved** and is not consumed here. RF-110 takes the next free sequential ID **D-032** (D-031 is RF-109; D-030 stays reserved).
- **Context:** RF-110 adds menu **item** images. The repo uses no Supabase Storage today. Storage objects are written/read through the Supabase storage-api (S3 proxy), which authenticates by JWT (`auth.uid()`) but does **not** set the app's `app.current_organization_id` GUC. Consequently the existing tenant helpers `app.current_org_id()` / `app.has_scope()` / `app.has_role_in_scope()` — which all pin `m.organization_id = app.current_org_id()` — return NULL/false inside a `storage.objects` policy and would **lock everyone out**. A storage-plane tenant-isolation approach is therefore required, ratified here before any SQL (credential/tenant-isolation sensitive: **DECISION D-001**, **D-011**, **D-026**, **RISK R-003**). Owning specs: RPC/contract shape [API_CONTRACT](API_CONTRACT.md) (§4.24), isolation/control [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-014).
- **Decision:** **DECISION D-032** —
  - **Scope (in):** a Supabase Storage bucket for menu item images; `storage.objects` RLS policies; path-derived storage helper functions; storage-policy pgTAP tests (a later stage). **Scope (out):** owner menu UI (RF-111), app image-upload UI, **category images**, **modifier images**, a `menu_items` image column, a `menu_item_images` table, signed-URL RPCs, upload/delete RPCs, `audit_events` for blob mutations, POS submit-order (RF-115), KDS live actions, payments, printing, dashboard reports, production deployment.
  - **Storage helper plane (critical).** The existing GUC-based tenant helpers (`app.current_org_id`, `app.has_scope`, `app.has_role_in_scope`, `app.can_read_financials`) **must NOT** be used inside `storage.objects` policies — the storage-api request does not set `app.current_organization_id`, so they return NULL/false. RF-110 storage policies use **new path-derived helpers** that (a) identify the caller from `auth.uid()` via `app.current_app_user_id()` (which resolves from `app_users.auth_user_id` under a real JWT — RF-050-B1), and (b) derive the target `(organization_id, restaurant_id, branch_id, menu_item_id)` from the **object path**, checking membership **directly** (no org GUC). `app.is_platform_admin()` is **never** used as a tenant storage bypass (**DECISION D-026**).
  - **Bucket.** Name **`menu-images`**; **private** (not public); **no anon/public read**; **no durable public URLs** in RF-110 (signed-URL behaviour is handled by the client storage SDK / RF-111 UI, not RF-110 RPCs). Allowed MIME types `image/png`, `image/jpeg`, `image/webp`; target per-bucket `file_size_limit` ≈ `5MiB` (if supported by `storage.buckets`). The bucket is **created by a SQL migration** that inserts/upserts a `storage.buckets` row — **not** by committing a `config.toml` bucket block.
  - **Path convention.** Object key inside `menu-images`: `{organization_id}/{restaurant_id}/{branch_id_or_global}/menu_item/{menu_item_id}/{image_id}.{ext}` — `organization_id`/`restaurant_id`/`menu_item_id`/`image_id` are UUIDs; `branch_id_or_global` is a UUID or the literal `global` (= restaurant-scoped, `branch_id NULL`); the literal segment `menu_item` is required; `ext` must be an allowed image extension. **Menu item images only** in RF-110 (category/modifier images **deferred**). **Malformed paths are denied.** The path is **not trusted by itself** — it is verified against the caller's membership and against the referenced `menu_items` row.
  - **Read policy.** Private read for the **price-capable** tenant roles only — `org_owner`, `restaurant_owner`, `manager`, `cashier`, `accountant` — scoped to the path's org/restaurant/branch. **Denied:** `kitchen_staff`, platform-admin-only, non-member, wrong-scope, anon. **Kitchen/KDS does NOT read live menu images in RF-110**: images carry no money field directly, but they are live-menu surface and the object path reveals menu structure, so RF-110 keeps the **DECISION D-031 / T-013** boundary (KDS uses order snapshots, not the live menu).
  - **Write policy.** INSERT/UPDATE/DELETE on `storage.objects` (`menu-images`) for **`org_owner`, `restaurant_owner`, `manager`** only — gated by storage RLS. **Denied:** `cashier`, `kitchen_staff`, `accountant`, platform-admin-only, non-member, wrong-scope, anon. A write **requires the corresponding `menu_items` row to exist** in the same parsed org/restaurant/branch scope. **Physical delete** of blobs is acceptable (no soft-delete for storage objects); **orphan cleanup is deferred**.
  - **Audit.** RF-110 writes **no `audit_events` for storage blob mutations** — uploads/deletes go through direct storage-api RLS, not a `SECURITY DEFINER` RPC, so a co-transactional audit row is not feasible. This is an **accepted MVP gap** (images are non-financial assets; the menu_item *row* mutations remain audited under RF-109/D-031). If audited image mutation is later required, add a follow-up **RPC-mediated finalize/delete** flow.
  - **Policy/helper design.** Proposed `SECURITY DEFINER`, `search_path=''` helpers, granted only as needed: `app.menu_image_scope(name text)` (strict path parse → `(org, restaurant, branch, menu_item_id)`; malformed → no row), `app.can_read_menu_image(p_org, p_restaurant, p_branch)`, `app.can_write_menu_image(p_org, p_restaurant, p_branch, p_menu_item_id)`. Four explicit `storage.objects` policies — **SELECT / INSERT / UPDATE / DELETE** — each pinning `bucket_id = 'menu-images'`. **No anon; no platform-admin tenant bypass; no service-role client path** (**DECISION D-011 / D-026**).
- **Alternatives considered:**
  - *Reuse `app.has_scope` / `app.has_role_in_scope` in storage policies* — rejected: they depend on `app.current_org_id()` (the `app.current_organization_id` GUC), which the storage-api does not set → they return false and deny all access. Storage needs path-derived helpers keyed on `auth.uid()`.
  - *Public bucket with public URLs* — rejected: object paths reveal cross-tenant menu structure and yield durable shareable URLs; a private bucket + scoped SELECT + client signed URLs is the tenant-safe posture (**RISK R-003**).
  - *Let `kitchen_staff` read menu images* — rejected: images are live-menu surface and the path leaks menu structure; consistency with **DECISION D-031 / T-003** (kitchen off the live menu; KDS uses order snapshots) wins. A money-free KDS thumbnail is a possible **future** decision, not RF-110.
  - *Add an `image_object_path` column to `menu_items` / a `menu_item_images` table now* — rejected: that is UI-shaped "current image" metadata owned by **RF-111**; RF-110 is storage-only (the object key already encodes `menu_item_id`).
  - *Audit blob mutations in RF-110* — rejected as infeasible without an RPC in the write path; accepted as a documented MVP gap with an RPC-mediated follow-up if required.
  - *Consume the reserved `D-030` id* — rejected: `D-030` is the reserved (unratified) M6-track umbrella label; per the D-029/D-031 precedent this per-ticket ADR takes the next free id **D-032**.
- **Consequences:**
  - (+) Menu images are tenant-isolated on the storage plane via path-derived membership checks; no GUC dependency; no anon/public/service-role/platform bypass.
  - (+) Storage-only: no RF-109 schema/RPC change; RF-111 wires UI/current-image metadata later.
  - (-) A **new RLS surface** (`storage.objects`) — **RISK R-003** critical; mitigated by strict path parsing, path-derived helpers, and the T-014 isolation tests, with the RF-060 suite green before merge.
  - (-) **Audit gap** for blob mutations (accepted) and **deferred orphan cleanup** (a soft-deleted/deleted `menu_items` row leaves its images behind).
  - (-) **Local-test nuance:** storage policies authenticate by `auth.uid()`, so tests must simulate the JWT (`request.jwt.claims` `sub`), and the `storage` schema must be present under the local stack.
- **Related:** [API_CONTRACT](API_CONTRACT.md) (§4.24 menu image storage), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-014; T-013 menu boundary), [DOMAIN_MODEL](DOMAIN_MODEL.md) (§4 — menu item images are storage objects, not menu columns), [AGENT_WORKFLOW](AGENT_WORKFLOW.md) (§9), [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) (§6 images / §11 candidate D-030, unratified), related D-001, D-004, D-005, D-011, D-012, D-013, D-026, D-029, D-031, **RISK R-003**.

---

## D-033 — RF-112 settings, membership roles, and device provisioning backend contract

- **Status:** Accepted at the RF-112 architecture-change approval (human-approved by Saleh, after independent Codex review), under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9); **amends** the frozen M0A schema/RLS/API baseline by adding a new tenant-administration backend surface. Like **DECISION D-029** / **D-031** / **D-032**, this is a **per-ticket M6 backend-surface ADR** that **satisfies candidate D-030 point 2** (each new M6 backend surface is authorized by its own decision before code — [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) §11); the standalone **candidate D-030** (the M6-track umbrella) **remains unratified/reserved** and is not consumed here. RF-112 takes the next free sequential ID **D-033** (D-029 RF-122, D-031 RF-109, D-032 RF-110; **D-030** stays reserved).
- **Context:** RF-112 is the **tenant administration backend** — settings edits, membership grant/role management, and the **device provisioning forward path** — for the owner/manager dashboard (the RF-113 UI consumes it later). The identity/device/audit **schema already exists** (`memberships` [DOMAIN_MODEL](DOMAIN_MODEL.md) §3.2, `employee_profiles` §3.3, `devices` §2.5, `device_pairings` §3.4 with `enrollment_code`/`code_expires_at` + the `code_issued → … → revoked` lifecycle, `device_sessions` §3.5, `pin_sessions` §3.6, `audit_events` §10.2), and **RF-061 already ships the revoke teardown** (`app.revoke_device` / `app.revoke_employee`). **What is missing** is the entire forward management surface: no `grant_membership` / `update_role`, no `create_device` / enrollment-code issue / redeem / approve / `start_device_session`, no settings RPCs, **no role-rank escalation guard**, and **no GUC-free management-auth helper**. Authorizing this is privilege-escalation- and tenant-isolation-critical (**DECISION D-001**, **D-004/D-005**, **D-011/D-012**, **D-013**, **D-026/D-028**, **RISK R-003**, **R-007**), so the contract is ratified here **before any SQL is written**. Owning specs: RPC shapes [API_CONTRACT](API_CONTRACT.md) (§4.25–§4.27), isolation/control [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-015), entities [DOMAIN_MODEL](DOMAIN_MODEL.md) (§2.1–§2.3, §3.2–§3.6).
- **Decision:** **DECISION D-033** —
  - **Scope (in):** (a) **settings** update RPCs over **existing columns only** for `organizations` / `restaurants` / `branches`; (b) **membership management** RPCs `grant_membership` + `update_role` (reusing RF-061 `revoke_employee` for deactivate); (c) the **device provisioning forward path** RPCs `create_device`, `issue_device_enrollment_code`, `redeem`/`pair_device`, `approve_device`, `start_device_session` (reusing RF-061 `revoke_device`); (d) a **GUC-free** management-auth helper + a **role-rank** guard; (e) audit on every mutation **and** denial; (f) pgTAP isolation coverage. **Scope (out):** the RF-113 management UI; RF-090 self-serve org signup; billing/plan edits (platform-admin path, §4.20); **tax / rounding / locale / business-hours / receipt-template/logo/header/footer** settings (each is net-new schema needing its own ticket); the real client **auth/org-context bridge** (separate prerequisite — see below); POS submit-order (RF-115); KDS write actions; payments; printing; reports; production deployment.
  - **GUC-free auth plane (critical).** RF-112 RPCs **must be GUC-free**: they **must NOT** reuse `app.current_org_id()`, `app.has_scope()`, `app.has_role_in_scope()`, or the RF-109 menu guard. (These pin `m.organization_id = app.current_org_id()`, i.e. the `app.current_organization_id` GUC, which **no production caller sets** — only pgTAP sets it — so they fail closed for a real JWT; this is the RF-111 D1/D3 blocker.) Instead, mirror the **RF-110 path-derived pattern** (**DECISION D-032**): identify the caller from `auth.uid()` → `app.current_app_user_id()` (resolves `app_users.auth_user_id` under a real JWT; fail-closed NULL if unlinked — identity is **never** an RPC argument), and validate tenant scope **directly from `memberships`** against the **passed** `(organization_id, restaurant_id, branch_id)` (EXISTS on an `active`, non-`deleted_at` membership with the required role and a null-or-equal scope hierarchy). `app.is_platform_admin()` is **never** a tenant bypass (**DECISION D-026**); no `anon` / `service_role` client path (**DECISION D-011**).
  - **Role-rank guard (the missing control).** Define a total rank `org_owner > restaurant_owner > manager > {cashier, kitchen_staff, accountant}`. For `grant_membership` / `update_role`: the **actor's rank must be strictly higher** than both the **assigned/new** role and (on update) the membership's **existing** role; a **`manager` cannot assign `manager` / `restaurant_owner` / `org_owner`**; **no self-grant** and **no self-escalation**; the assigned scope must be **within the actor's scope** (downward-only, null-or-equal hierarchy); **cross-org / cross-restaurant / cross-branch targets are denied** as IDOR (scope is server-derived, never client-asserted); `cashier` / `kitchen_staff` / `accountant` **cannot manage** (accountant is read-only, **DECISION D-028**); **`platform_admin` is not a tenant role** and is never an assignable value (**DECISION D-026**). No precedent RPC supplies this rank ceiling — RF-112 introduces it.
  - **Settings slice (existing columns only).** Update RPCs expose **only** already-ratified columns: `organizations` → `default_currency`, `country_code`, `status` (§2.1); `restaurants` → `name`, `currency_override`, `timezone`, `status` (§2.2); `branches` → `name`, `address`, `timezone`, `receipt_prefix`, `status` (§2.3). **Excluded** (each needs its own ticket): tax, rounding, locale/language, business/opening hours, and receipt template/logo/header/footer. **No new tables, no settings JSON blob.** Authorization: `org_owner` / `restaurant_owner` in scope (a `manager` may edit branch-level settings only, if the §4.25 contract grants it); writes are audited.
  - **Membership RPC contract.** `grant_membership` adds a membership for an **existing `app_user`** (RF-112 introduces **no invite/pending flow** and **no new membership status enum value** — the interim `active`/`revoked` set stands, **DECISION D-004/D-005**; deactivate/revoke **reuses RF-061 `revoke_employee`** unless a thin `public.*` wrapper is required for Data-API reach). `update_role` changes an existing membership's role/scope under the rank guard. Both honor the `employee_profiles.membership_id` same-org authoritative link (§3.3), **audit success and denied attempts** (`membership.granted` / `membership.role_updated` / `*_denied`, **DECISION D-013**), and are **idempotent via a `client_request_id`** (the RF-090 device-less idempotency model — these are online management ops with no `device_id`/`local_operation_id`).
  - **Device provisioning contract.** Forward-path RPCs over the existing device schema: `create_device` (register a scoped `devices` row); `issue_device_enrollment_code` (server-generated code → `device_pairings` in `code_issued`, store **only** the `enrollment_code` hash/reference + `code_expires_at`, return the plaintext code **once**); `redeem`/`pair_device` (the device submits the code — **`code_issued → pending`**, **consume-once**; the existing expiry guard rejects an expired code); `approve_device` (the manager-approval edge **`pending → paired`** — **Approval REQUIRED**, device credentials issued and `paired_at` set; the subsequent activation **`paired → active`** permits opening a device session; transitions owned by [STATE_MACHINES](STATE_MACHINES.md) §9, which marks `pending → active` skipping `paired` **FORBIDDEN**); `start_device_session` (mint a `device_sessions` row on an `active` pairing, return the `session_token_ref` secret **once** — `start_pin_session` only *consumes* a device session, it never creates one). **Generated secrets are returned once only and stored only as hashes/references — never plaintext in the DB or in `audit_events`** (**SECURITY REQUIREMENT**, consistent with §2.5/§3.4/§3.5). The enrollment-code **TTL is conservative and the code is consume-once** (interim, **OPEN QUESTION Q-009**-aware; the exact window is not hard-coded permissively). **Revoked / suspended / expired devices fail closed** (RF-061 revoke removes future access incl. the offline window — **T-004**, **RISK R-007**); RF-112 must not weaken that. All provisioning mutations and denials are audited (**DECISION D-013**); device-originated ops carry the `device_id` + `local_operation_id` idempotency key (**DECISION D-022**), while management-initiated provisioning (e.g. issue/create) uses `client_request_id`.
  - **Auth/org-context bridge decision.** RF-112 **does NOT** implement the full GoTrue sign-in / app-client session + active-org-context bridge. Because RF-112 ships **GUC-free**, its backend RPCs are **fully buildable and pgTAP-testable now** (the caller is simulated via `request.jwt.claims`); they become **end-to-end client-usable** once the **separate prerequisite** — real GoTrue sign-in + `app_users.auth_user_id` linkage + active-membership selection (the surface RF-122/RF-123/RF-124 began, also needed by RF-111 for real persistence) — lands under its **own** ticket. That bridge is **not** folded into RF-112 (nor RF-111).
  - **Governance.** Implemented under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9): own ticket (RF-112), this DECISIONS entry before code, independent Codex review, human approval, and the **RF-060 tenant-isolation suite green before merge** (**RISK R-003**). Test contract owned by [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) §14 T-015 + [TESTING_STRATEGY](TESTING_STRATEGY.md).
- **Alternatives considered:**
  - *Reuse `app.has_role_in_scope` / the menu guard for RF-112 auth* — rejected: they depend on the `app.current_organization_id` GUC that no production caller sets, so they pass GUC-setting pgTAP but **fail closed for every real JWT** (a silent false-green); RF-112 uses the GUC-free RF-110 pattern.
  - *Reuse only the actor-role check (no rank ceiling)* — rejected: without an "assigned-role ≤ actor-role" ceiling a `manager` could grant `org_owner` (**TH-2**); the rank guard + self-grant/self-escalation denial is mandatory.
  - *Add an invite/pending membership flow + a new status enum value* — rejected for RF-112: it changes the unfrozen `active`/`revoked` membership status set and adds accept-before-active semantics; deferred to its own ticket. RF-112 grants memberships for existing `app_user`s only.
  - *Carry settings as a JSON blob / add tax/locale/hours columns now* — rejected: the slice is strictly existing columns; tax/rounding (**RISK R-008**, **Q-001/Q-002**), locale, hours, and receipt templates are net-new schema each needing its own ticket.
  - *Model `approve_device` as part of redeem* — rejected: keeping a distinct manager-approval edge (`pending → paired`, per [STATE_MACHINES](STATE_MACHINES.md) §9) preserves separation between the device redeeming a code (`code_issued → pending`) and a human authorizing it; the transitions are owned by [STATE_MACHINES](STATE_MACHINES.md).
  - *Fold the GoTrue/org-context bridge into RF-112* — rejected: new client-facing auth/session surface follows its own architecture-change ticket (the D-029/RF-122 precedent); RF-112 stays GUC-free and backend-only.
  - *Consume the reserved `D-030` id* — rejected: `D-030` is the reserved (unratified) M6-track umbrella label; per the D-029/D-031/D-032 precedent this per-ticket ADR takes the next free id **D-033**.
- **Consequences:**
  - (+) The owner/manager dashboard gains a real, tenant-isolated, audited backend for settings, membership roles, and device provisioning — without the GUC trap and without weakening **D-026** platform separation or **D-011** no-service-role.
  - (+) RF-112 is buildable + pgTAP-testable now; the orthogonal client auth/org-context bridge can land independently.
  - (+) The new role-rank ceiling closes the **TH-2** escalation gap that no prior RPC addressed.
  - (-) A **new privilege-bearing RPC surface** (membership grant + device provisioning) raises the **RISK R-003** review burden; mitigated by the GUC-free pattern, the rank guard, audited denials, and the T-015 isolation tests with the RF-060 suite green before merge.
  - (-) Several `app.*` RPCs + `public.*` wrappers to implement, grant-test, and isolation-test under the RF-112 ticket.
  - (-) Device-secret handling (enrollment code + session token) must be return-once / store-hash-only; mishandling would be **TH-6** secret leakage — covered by T-015.
- **Related:** [API_CONTRACT](API_CONTRACT.md) (§4.25 settings RPCs, §4.26 membership management RPCs, §4.27 device provisioning RPCs; §4.10–§4.12 reused pairing/revoke), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-015; §13 TH-2/TH-3/TH-5/TH-6), [DOMAIN_MODEL](DOMAIN_MODEL.md) (§2.1–§2.3 settings columns, §3.2 memberships, §3.3 employee_profiles, §3.4–§3.6 device/pin sessions), [STATE_MACHINES](STATE_MACHINES.md) (device pairing transitions incl. `approve_device`), [AGENT_WORKFLOW](AGENT_WORKFLOW.md) (§9), [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) (§11 candidate D-030, unratified), related D-001, D-004, D-005, D-006, D-011, D-012, D-013, D-020, D-022, D-026, D-028, D-029, D-031, D-032, **RISK R-003**, **RISK R-007**, [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-008 MFA, Q-009 offline window, Q-017 accountant-in-MVP).

---

## D-034 — RF-112 device activation and session-start contract

- **Status:** Accepted at the RF-112 (Stage 2 follow-up) architecture-change approval (human-approved by Saleh, after independent Codex review), under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9); **amends** the frozen baseline by defining the device **activation + session-start** surface left open by **DECISION D-033** / [API_CONTRACT](API_CONTRACT.md) §4.27. Like **DECISION D-029**/**D-031**/**D-032**/**D-033**, this is a **per-ticket M6 backend-surface ADR** that **satisfies candidate D-030 point 2**; **candidate D-030** stays reserved/unratified. RF-112 takes the next free sequential ID **D-034**.
- **Context:** RF-112 Stage 2 implemented the device forward path up to **`paired`** (`create_device` → `issue_device_enrollment_code` → redeem `code_issued → pending` → `approve_device` `pending → paired`). The Codex Stage 2 review **APPROVED** but confirmed a real **contract gap**: §4.27 says `start_device_session` mints a session **on an `active` pairing** and [STATE_MACHINES](STATE_MACHINES.md) §9 makes **`active`** the prerequisite for opening a device session (`paired → active … allowed to open device_session`), but **no RPC was defined for the `paired → active` activation** — `approve_device` correctly stops at `paired`, and **`pending → active` is FORBIDDEN** ([STATE_MACHINES](STATE_MACHINES.md) §9). Implementing `start_device_session` would have required inventing an undocumented activation edge or weakening the lifecycle, so Stage 2 **stopped and reported** the gap. D-034 closes it **before Stage 3** builds the activation/session RPCs (credential/state-sensitive: **DECISION D-006**, **D-011/D-012**, **D-013**, **RISK R-003**, **R-007**). Owning specs: RPC shapes [API_CONTRACT](API_CONTRACT.md) (§4.28 / §4.29), transitions [STATE_MACHINES](STATE_MACHINES.md) §9, control [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-015), entities [DOMAIN_MODEL](DOMAIN_MODEL.md) (§3.4 / §3.5).
- **Decision:** **DECISION D-034** —
  - **D-033 stands.** Everything ratified by D-033 remains valid. `approve_device` **remains `pending → paired`** (Approval REQUIRED); **`pending → active` remains FORBIDDEN**; approval **never** silently activates (no hidden `paired → active` inside `approve_device`); and **no device session may be started on a non-`active` pairing**.
  - **Activation is a SEPARATE explicit RPC — `activate_device`** (the chosen option; not a hidden step inside approve, not folded into session-start). It performs the **`paired → active`** lifecycle edge ([STATE_MACHINES](STATE_MACHINES.md) §9 — actor *manager/server*), which D-034 **assigns to `activate_device`** (owned by RF-112). **Required state:** **`paired`** only; every other state (`code_issued`/`pending`/`active`/`suspended`/`revoked`/`code_expired`/`rejected`) is **rejected `42501`** (fail-closed; no re-activation, no skip). **Authorization:** GUC-free (the RF-112 Stage 1 pattern — caller via `auth.uid()` → `app.current_app_user_id()`, scope **derived from the pairing's row**, validated against `memberships` via `app.actor_rank_in_scope`); **`org_owner`/`restaurant_owner`/`manager`** covering the device's scope may activate; **`cashier`/`kitchen_staff`/`accountant`** → `permission_denied` (audited); **non-member/cross-org/out-of-scope/`anon`/platform-admin-only** → `42501`; **never** the org-GUC helpers or `is_platform_admin`. **Idempotency:** `client_request_id` (the Stage 1 management ledger). **Audit:** `device.activated` on success, `device.activate_denied` on role-denial (**DECISION D-013**). Activation mints **no secret** (the device credential `device_credential_ref` is OS-secure-stored and provisioned separately — RF-021).
  - **`start_device_session`** mints a `device_sessions` row **only on an `active` pairing** (the `paired → active` activation above is the precondition; a `paired`/`pending`/`suspended`/`revoked`/`code_expired`/non-active pairing is **rejected `42501`**, fail-closed — consistent with **T-004**/**RISK R-007**); it also requires the backing **device + branch/restaurant be live** (not soft-deleted) and the device `is_active`. **Server-side token:** the session token is **generated server-side**, stored **only as `session_token_ref` = its hash** (the RF-112 `app.hash_provisioning_secret` sha-256 pattern), and the **plaintext token is returned exactly ONCE** (first/claiming call). **Replay never leaks the token:** the idempotency ledger stores a **no-token** result (the RF-112 enrollment-code precedent), so a replay returns `{…, idempotent_replay:true}` **without** the token. **No plaintext token** in the DB or in `audit_events`. **Audit:** `device.session_started` on success (no token in the row), `device.session_start_denied` on role-denial.
  - **Who starts a device session (RF-112 interim vs target).** The **target** model is **device-originated** — a paired+activated device authenticates with its own device credential and starts its session, keyed by **`device_id` + `local_operation_id`** (**DECISION D-022**). That model **requires the device-auth bridge** (a device principal / device-credential sign-in), which RF-112 **does not** implement (the same deferred bridge as D-033's GoTrue/org-context note). So in RF-112, `start_device_session` is **management-authorized** (an in-scope `org_owner`/`restaurant_owner`/`manager` provisions the device's session and securely hands the one-time token to the device — exactly as the enrollment code is hand-carried), keyed by **`client_request_id`**. D-034 ratifies the management-initiated contract for RF-112 and records the device-originated (`device_id`+`local_operation_id`) variant as the **follow-up** once the device-auth bridge lands; the **`active`-pairing precondition, hash-only/return-once token, fail-closed states, and audit are identical** in both.
  - **Governance.** Implemented under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9): this DECISIONS entry **before any SQL** (a docs gate, like D-033), then Stage 3 SQL + pgTAP under the RF-112 ticket, independent Codex review, human approval, and the **RF-060 isolation suite green before merge** (**RISK R-003**).
- **Alternatives considered:**
  - *Fold activation into `approve_device` (`pending → paired → active` in one call)* — rejected: it would make approval yield `active`, i.e. effectively `pending → active`, collapsing the **Approval REQUIRED** edge and the **FORBIDDEN** skip; the human-approval (`paired`) and provisioning-complete (`active`) states must stay distinct ([STATE_MACHINES](STATE_MACHINES.md) §9).
  - *Let `start_device_session` activate (accept a `paired` pairing and do `paired → active` itself)* — rejected: a session must never be opened on a non-`active` pairing; mixing activation into session-start hides the lifecycle edge and weakens the fail-closed `active` precondition. A separate `activate_device` keeps the edge explicit and auditable.
  - *Define `start_device_session` as device-originated now* — rejected for RF-112: it requires the deferred device-auth bridge; ratifying the management-initiated contract unblocks Stage 3 immediately while preserving the device-originated model as a documented follow-up (identical security envelope).
  - *Consume the reserved `D-030` id* — rejected: `D-030` is the reserved (unratified) M6-track umbrella label; per the D-029/D-031/D-032/D-033 precedent this per-ticket ADR takes the next free id **D-034**.
- **Consequences:**
  - (+) Stage 3 can build `activate_device` + `start_device_session` against a stable contract; the `paired → active` edge has an explicit, audited owner and `pending → active` stays forbidden.
  - (+) The one-time session token follows the proven RF-112 hash-only / return-once / no-replay-leak pattern; revoked/suspended/expired/non-active pairings fail closed.
  - (-) A **new privilege-bearing RPC surface** (activation + session-start over a device session) raises the **RISK R-003** review burden; mitigated by the GUC-free pattern, explicit state guards, audited denials, and T-015 coverage with the RF-060 suite green before merge.
  - (-) The fully **device-originated** session-start remains gated on the deferred device-auth bridge; RF-112 ships the management-initiated form, which still requires the one-time token to be securely transferred to the device (the same trust step as the enrollment code).
- **Related:** [API_CONTRACT](API_CONTRACT.md) (§4.28 `activate_device`, §4.29 `start_device_session`; §4.27 device provisioning), [STATE_MACHINES](STATE_MACHINES.md) (§9 — `paired → active` owned by `activate_device`; `pending → active` FORBIDDEN; session-start requires `active`), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-015; §13 TH-3/TH-6), [DOMAIN_MODEL](DOMAIN_MODEL.md) (§3.4 device_pairings, §3.5 device_sessions), [AGENT_WORKFLOW](AGENT_WORKFLOW.md) (§9), related D-005, D-006, D-011, D-012, D-013, D-022, D-026, D-033, **RISK R-003**, **RISK R-007**, [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-009 offline window).

---

## D-035 — RF-125 platform-admin read-only public wrapper (`public.platform_admin_*`)

- **Status:** **PROPOSED** under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9) — **drafted before the SQL** alongside the wrapper migration in the **M7 backend baseline** (proposed ticket **RF-125**). **NOT yet ratified:** pending independent Codex review and **human approval by Saleh at the merge gate** (§8), with the **RF-060 tenant-isolation suite green before merge** (**RISK R-003**); to be flipped to *Accepted* (with the approving RF id) on merge. Like **DECISION D-029**/**D-031**/**D-032**/**D-033**/**D-034**, this is a **per-ticket backend-surface ADR** that **satisfies candidate D-030 point 2**; **candidate D-030** stays reserved/unratified. RF-125 takes the next free sequential ID **D-035**.
- **Context:** RF-091 implemented three **read-only** platform-admin panel RPCs in the `app` schema — `app.platform_admin_organization_overview(p_reason)`, `app.platform_admin_get_organization(p_organization_id, p_reason)`, `app.platform_admin_recent_audit(p_reason, p_limit default 50)` ([API_CONTRACT](API_CONTRACT.md) §4.18) — each `SECURITY DEFINER`, granted to `authenticated`, self-gated by `app.platform_admin_guard` (authenticated principal + **ACTIVE `platform_admin_grant`** [**D-026**, never a tenant membership] + **MFA `aal2`** [RF-050] + non-empty `reason`), each writing a reason-tagged `platform_admin_audit_events` row (the read is itself audited). But the `app` schema is deliberately **not** exposed to the Data API (`supabase/config.toml` `[api].schemas = ["public","graphql_public"]`), so a Flutter client (anon key + authenticated JWT, PostgREST) has **no entry point** to call them — the grant is necessary but not sufficient without an exposed route. The M7 **platform-admin real-data wiring** (Agent B's `PlatformAdminRepository`) is therefore blocked. This is the same situation `app.sync_pull` was in before **RF-064**, `app.start_pin_session` before **RF-123**, and the `app.menu_*` RPCs before **RF-109** (**D-031**).
- **Decision:** **DECISION D-035** —
  - Authorize **three thin `public.*` `SECURITY INVOKER` wrappers** — `public.platform_admin_organization_overview(text)`, `public.platform_admin_get_organization(uuid, text)`, `public.platform_admin_recent_audit(text, integer)` — each a **faithful pass-through** that delegates verbatim to its `app.*` source of truth, with the **same parameters, types, order, and the `p_limit integer default 50` default**, returning the **same `jsonb`**. No richer/aggregated return, **no transformation, no authorization logic of its own**.
  - Each wrapper is **`SECURITY INVOKER`**, `search_path=''`, runs as the authenticated caller (who already holds `EXECUTE` on the `app.*` function per RF-091), so it needs **no new privilege and no new grant on `app.*`** (the RF-064 pattern). It is left **VOLATILE** (no `STABLE`/`IMMUTABLE` marker) so PostgREST routes it as **POST**, executing the delegate's audit `INSERT` in a writable context.
  - **Read-only (DECISION D-026) preserved.** Platform admin remains read-only: none of the three mutate tenant data, impersonate, run a generic cross-tenant `select *`, or grant/revoke. The **entire gate** (active grant + `aal2` + non-empty reason), the **audited reads**, the narrow cross-tenant scoping, and the read-only / no-impersonation posture all stay inside the **UNCHANGED** `app.*` bodies. The audit **actor** is `app.current_app_user_id()` (from `auth.uid()`), so the `SECURITY INVOKER` wrapper calling the `SECURITY DEFINER` app RPC **cannot shift or spoof** it.
  - **Grant posture mirrors the app RPC exactly:** `revoke all ... from public` + `grant execute ... to authenticated` — never `anon`/`service_role` (**D-011**); anon is doubly blocked (revoked from public, and `SECURITY INVOKER` requires the caller's own `EXECUTE` on the inner `app.*`, which is `authenticated`-only).
  - **Scope is exactly the three read-only RF-091 panel RPCs.** The `app` schema is **NOT** added to `[api].schemas`, so no other `app.*` RPC becomes reachable. The pre-existing `app.platform_admin_list_organizations` (§4.16) is **not** wrapped (it is not yet `aal2`-gated — a tracked **Q-008** hardening follow-up), and the mutating `app.set_organization_plan` (§4.20, a platform-admin write) is **not** wrapped (a mutation would need its own decision; D-035 is read-only only).
  - **Governance.** Implemented under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9): own ticket (RF-125), this DECISIONS entry **before any SQL**, pgTAP coverage (`rf125_public_platform_admin_wrapper_test`: introspection/grants/INVOKER + delegation parity + the full `42501` guard preserved through the wrapper for non-admin / org_owner / blank-reason / missing-`aal2`), independent Codex review, human approval, and the **RF-060 isolation suite green before merge** (**RISK R-003**).
- **Alternatives considered:**
  - *Expose the `app` schema directly via the Data API* — rejected: it would make **every** internal `app.*` function HTTP-reachable (every mutating RPC), widening the attack surface and breaking the established `public`-only exposure boundary (**RISK R-003**). A single narrow `public.*` wrapper per capability keeps `app` unexposed.
  - *Add aggregation / a richer composite return / extra auth in the wrapper* — rejected: the wrapper must be a faithful pass-through that adds no privilege and no logic (the D-029/RF-064 pattern); any transformation belongs in the audited `app.*` body under its own change.
  - *Wrap all platform-admin RPCs (incl. `platform_admin_list_organizations` and `set_organization_plan`)* — rejected: `platform_admin_list_organizations` is not yet `aal2`-gated (**Q-008** follow-up) and `set_organization_plan` is a **mutation** that would breach the read-only scope and needs its own decision; D-035 is strictly the three read-only panel RPCs.
  - *Consume the reserved `D-030` id* — rejected: `D-030` is the reserved (unratified) M6/M7-track umbrella label; per the D-029/D-031/D-032/D-033/D-034 precedent this per-ticket ADR takes the next free id **D-035**.
- **Consequences:**
  - (+) The platform-admin panel gains a **real, audited, MFA-gated, read-only** client surface without exposing the `app` schema or weakening **D-026** platform separation / **D-011** no-service-role.
  - (+) Agent B can wire a real `PlatformAdminRepository` over `public.platform_admin_*` once the auth foundation (authenticated JWT + the `aal2` MFA + active-grant flow) lands; demo mode is unaffected.
  - (-) A **new public surface** over the frozen contract raises the **RISK R-003** review burden; mitigated by the faithful-pass-through pattern, the pgTAP parity/guard tests, and the RF-060 isolation suite green before merge.
  - (-) End-to-end use still depends on the **platform-admin MFA (`aal2`) + active-grant sign-in flow**, which is not yet wired in any client (a separate prerequisite); until then the wrapper is callable but every call fails closed without the credentials.
- **Related:** [API_CONTRACT](API_CONTRACT.md) (§4.16 / §4.18 — the three RF-091 panel RPCs + this wrapper note), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-007/T-008/T-009/T-010 platform-admin isolation + audit, T-012 public-wrapper pattern), [AGENT_WORKFLOW](AGENT_WORKFLOW.md) (§9), [M7_REAL_BACKEND_WIRING_HANDOFF.md](M7_REAL_BACKEND_WIRING_HANDOFF.md), [M7_BACKEND_CONTRACT_NOTES.md](M7_BACKEND_CONTRACT_NOTES.md), related D-011, D-012, D-013, D-026, D-029, D-031, **RISK R-003**, [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-008 MFA).

---

## D-036 — RF-126 platform POS write contract: `public.sync_push` public wrapper

- **Status:** **PROPOSED** under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9) — **drafted before the SQL** alongside the wrapper migration in the **M7 backend baseline** (proposed ticket **RF-126**). **NOT yet ratified:** pending independent Codex review and **human approval by Saleh at the merge gate** (§8), with the **RF-060 tenant-isolation suite green before merge** (**RISK R-003**); to be flipped to *Accepted* (with the approving RF id) on merge. Like **DECISION D-029**/**D-031**/**D-032**/**D-033**/**D-034**/**D-035**, this is a **per-ticket backend-surface ADR** that **satisfies candidate D-030 point 2**; **candidate D-030** stays reserved/unratified. RF-126 takes the next free sequential ID **D-036**.
- **Context:** RF-056 implemented the server-side PUSH half of offline sync (**DECISION D-010**) as a single `SECURITY DEFINER` RPC `app.sync_push(p_pin_session_id uuid, p_device_id uuid, p_operations jsonb)` ([API_CONTRACT](API_CONTRACT.md) §4.14): it validates the PIN session + active device/pairing, derives org/restaurant/branch **server-side** (never from the payload), dedups/replays via the `sync_operations` inbox/ledger (transport identity `device_id`+`local_operation_id`, **D-022**), checks dependency edges, and **dispatches** each ordered op to the matching business RPC (`shift.open→open_shift`, `order.submit→submit_order`, `order.discount→apply_discount`, `payment.create→record_payment`, `shift.close→close_shift`) inside per-operation `EXCEPTION` subtransactions; money/sequences/receipt numbers stay server-authoritative inside the dispatched RPCs (**D-007**/**D-021**). But the `app` schema is deliberately **not** exposed to the Data API (`supabase/config.toml` `[api].schemas = ["public","graphql_public"]`), so a Flutter client (anon key + authenticated JWT, PostgREST) has **no entry point** to call `app.sync_push` — the grant to `authenticated` is necessary but not sufficient without an exposed route. The POS **real submit/order/payment/outbox** path (the M7 client wiring, Agent B handoff ticket #4) is therefore **closed**; the gap was surfaced (no silent scope expansion) in [M7_BACKEND_CONTRACT_NOTES.md](M7_BACKEND_CONTRACT_NOTES.md) §2.2/§5 and drift register D1. This is the same situation `app.sync_pull` was in before **RF-064**, `app.start_pin_session` before **RF-123**, `app.get_my_context` before **RF-124**, `app.menu_*` before **RF-109** (**D-031**), and `app.platform_admin_*` before **RF-125** (**D-035**).
- **Decision:** **DECISION D-036** —
  - Authorize **one thin `public.sync_push(uuid, uuid, jsonb)` `SECURITY INVOKER` wrapper** — a **faithful pass-through** that delegates verbatim to `app.sync_push` (the source of truth, RF-056), with the **same parameters, types, and order**, returning the **same `jsonb`** envelope (`{ ok, results:[ per-op {local_operation_id, operation_type, ok, status, error?, idempotency_replay} ], server_ts }`). No richer/aggregated return, **no transformation, no authorization logic of its own**.
  - The wrapper is **`SECURITY INVOKER`**, `search_path=''`, runs as the authenticated caller (who already holds `EXECUTE` on `app.sync_push` per RF-056), so it needs **no new privilege and no new grant on `app.*`** (the RF-064 pattern). It is left **VOLATILE** (no `STABLE`/`IMMUTABLE` marker) so PostgREST routes it as **POST** and the delegate's ledger/audit/business writes execute in a writable context. **No new `SECURITY DEFINER` is introduced:** `app.sync_push`'s `SECURITY DEFINER` posture is existing, justified architecture (**D-011** — sensitive mutations via `SECURITY DEFINER` RPC); the wrapper itself is `INVOKER` and grants no new authority.
  - **The entire batch gate stays inside the UNCHANGED `app.sync_push` body:** PIN-session validity + active device/pairing + **device match** + **server-side org/branch derivation** (never trusting payload org/branch/role; a revoked/expired device fails the whole batch — **RISK R-007**), the idempotency ledger (exactly-once via `sync_operations`, **D-022**), the per-operation dispatch + `EXCEPTION` isolation (one failed op never rolls back applied ops), the **money authority** (integer minor only; server-recomputed totals from snapshots, **D-007**/**D-008**; server-allocated per-branch monotonic `receipt_number`, **D-021**), and the sync/business audit writes (**D-013**). The wrapper adds none of these and can weaken none of them.
  - **Grant posture mirrors the app RPC exactly:** `revoke all ... from public` + `grant execute ... to authenticated` — never `anon`/`service_role` (**D-011**); **anon cannot write** (doubly blocked: revoked from public, and `SECURITY INVOKER` requires the caller's own `EXECUTE` on the inner `app.sync_push`, which is `authenticated`-only).
  - **Scope is exactly `sync_push`.** The `app` schema is **NOT** added to `[api].schemas`, so no other `app.*` RPC becomes reachable. In particular the dispatched mutators (`submit_order`/`record_payment`/`apply_discount`/`open_shift`/`close_shift`) are **not** individually wrapped — they remain reachable **only** through the dispatcher, behind its full validation. `public.sync_push` is the single, narrow POS write entry point; it is not a generic write proxy.
  - **Governance.** Implemented under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9): own ticket (RF-126), this DECISIONS entry **before any SQL**, pgTAP coverage (`rf126_public_sync_push_wrapper_test`: introspection/grants/`INVOKER`/`VOLATILE` + the narrowness guard + the whole-batch `42501` gate preserved through the wrapper for a bogus PIN session / device mismatch / malformed batch + a **real** `shift.open→order.submit→payment.create` flow applied through the wrapper with integer-minor money, a server-authoritative receipt number, idempotent replay, per-op reject of malformed/unknown/unauthorized ops, and a shared-ledger cross-delegation proof), independent Codex review, human approval, and the **RF-060 isolation suite green before merge** (**RISK R-003**).
- **Alternatives considered:**
  - *Expose the `app` schema directly via the Data API* — rejected: it would make **every** internal `app.*` function HTTP-reachable (every mutating RPC), widening the attack surface and breaking the established `public`-only exposure boundary (**RISK R-003**). A single narrow `public.*` wrapper per capability keeps `app` unexposed.
  - *Wrap each business RPC directly (`public.submit_order` / `public.record_payment` / …) instead of the dispatcher* — rejected: it would multiply the public write surface, bypass the `sync_operations` idempotency/dependency transport (**D-010**/**D-022**), and duplicate the offline-reconciliation entry point. `sync_push` is the documented single outbox push contract (§4.14); wrapping it keeps the mutators dispatcher-only behind one gate.
  - *Add validation / a non-batch convenience path / extra auth in the wrapper* — rejected: the wrapper must be a faithful pass-through that adds no privilege and no logic (the D-029/RF-064 pattern); any change to batch shape or authorization belongs in the audited `app.sync_push` body under its own change.
  - *Consume the reserved `D-030` id* — rejected: `D-030` is the reserved (unratified) M6/M7-track umbrella label; per the D-029/D-031/D-032/D-033/D-034/D-035 precedent this per-ticket ADR takes the next free id **D-036**.
- **Consequences:**
  - (+) The POS gains a **real, idempotent, audited, integer-minor** client write surface (submit/discount/payment/shift via the outbox) without exposing the `app` schema or weakening **D-010** offline-first, **D-011** no-service-role, **D-022** idempotency, or **D-007/D-021** money authority. Agent B can wire the real `OutboxRepository`/`PaymentRepository` over `public.sync_push` once the auth foundation (authenticated JWT + PIN session) lands; demo mode is unaffected.
  - (+) The single dispatcher entry point keeps the mutators dispatcher-only; the wrapper is provably narrow (the `rf126` narrowness guard asserts no `submit_order`/`record_payment`/`apply_discount`/`open_shift`/`close_shift` public sibling).
  - (-) A **new public WRITE surface** over the frozen contract raises the **RISK R-003**/**R-002** review burden (it is the first client-reachable mutation path); mitigated by the faithful-pass-through pattern, the full whole-batch-gate-preserved pgTAP coverage, and the RF-060 isolation suite green before merge.
  - (-) End-to-end use still depends on the **client auth foundation** (authenticated JWT + an established PIN session on a paired+active device), which is wired by Agent B; until then the wrapper is callable but every push fails closed without a valid session.
- **Related:** [API_CONTRACT](API_CONTRACT.md) (§4.14 `sync_push` + this wrapper note), [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) (§14 T-012 public-wrapper pattern; R-007 offline authorization staleness), [STATE_MACHINES](STATE_MACHINES.md) (Sync operation), [AGENT_WORKFLOW](AGENT_WORKFLOW.md) (§9), [M7_REAL_BACKEND_WIRING_HANDOFF.md](M7_REAL_BACKEND_WIRING_HANDOFF.md), [M7_BACKEND_CONTRACT_NOTES.md](M7_BACKEND_CONTRACT_NOTES.md), related D-007, D-008, D-010, D-011, D-012, D-013, D-021, D-022, D-026, D-029, D-035, **RISK R-002**, **RISK R-003**, **RISK R-007**, [OPEN_QUESTIONS](OPEN_QUESTIONS.md) (Q-010 conflict policy, Q-014 Realtime).

---

## Provisional decisions awaiting open questions (quick index)

| Decision | Blocked/conditioned by | Nature of dependency |
|---|---|---|
| D-006 | Q-008, Q-009 | MFA method; offline auth validity window |
| D-007 | Q-007 | Default currency; single-vs-multi-currency |
| D-010 | Q-010, Q-014 | Per-entity conflict policy; Realtime limits/fallback |
| D-014 | Q-015 | Arabic/Hebrew printing encoding strategy |
| D-021 | Q-001, Q-004 | Jurisdiction; legal receipt-numbering rules |

See [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) for owners, blocking milestones, and status. Money/tax correctness more broadly remains exposed to **RISK R-008** until **Q-001..Q-004** are resolved (tax rules owned by [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md)).

## Changelog

- M0A (RF-001): Initial decision log **drafted** (candidate set proposed for the architecture freeze) covering D-001..D-022 — pending ChatGPT review, independent Codex review, and human approval (Saleh); not yet frozen. No decisions beyond D-022 introduced. Future additions must use the next free ID (D-023+) with a full ADR block and a changelog entry.
- M0A (RF-003): Added **D-023..D-028** as human-approved proposed corrections (originating from RF-002/RF-003) for the **RF-004 freeze CANDIDATE** — D-023 (completed payment terminal in MVP), D-024 (completed order terminal in MVP), D-025 (payment/fulfillment independence; quick-service pay-first), D-026 (platform admin is not a tenant membership role; `platform_admin_grants` entity), D-027 (M0B blocker classification; "Accepted Open"), D-028 (accountant read-only; shift close/count separated from reconciliation). Also corrected: Payment enumeration (completed terminal; void only pre-completion, D-023); D-004/D-005 membership role keys reduced to six with `platform_admin` removed (D-026); D-019 M0A relabelled as a Freeze Candidate (freeze event is RF-004). These corrections were **approved at the RF-004 architecture freeze (human-approved by Saleh)**. The decision range is now **D-001..D-028**; the next free ID is **D-029+**.
- **M0A (RF-004): ARCHITECTURE FREEZE APPROVED by the human owner, Saleh.** The full M0A documentation/architecture baseline — decisions **D-001..D-028** and the candidate document set — is hereby **FROZEN as v1**, following RF-001 drafting, RF-002 independent Codex review, RF-003 corrections, and final Codex verification. **RF-003 is complete; RF-004 is done (approved).** Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — none resolved, none guessed); the freeze does not require them resolved. No application code, migrations, package manifests, dependencies, or CI were created during M0A. Any future change to a frozen decision or contract requires the **architecture-change procedure** (a new ticket, independent review, and human approval — see [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9) and the next free decision ID (**D-029+**). Next milestone: **M0B** (technical foundation), beginning with **RF-010** and **RF-013** once project/Jira tracking is ready.
- **M6-track (RF-122): Added D-029** (authorize two public auth precursor APIs — a `public.start_pin_session` faithful wrapper over `app.start_pin_session`, and a `public.get_my_context` self-context membership resolver — as change-controlled, `authenticated`-only client surfaces; no service-role in clients; the `app` schema stays unexposed; **D-004** multi-membership and **D-026** platform-admin separation preserved; the RF-060 isolation suite must be green before the backend wrappers merge), via the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9; independently Codex-reviewed, human-approved by Saleh). Amends the frozen API-contract baseline ([API_CONTRACT.md](API_CONTRACT.md) §4.21 / §4.22, [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) §14 T-012). The decision range is now **D-001..D-029**; the next free ID is **D-030+** (candidate **D-030** remains the reserved, unratified M6-track label per [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) §11).
- **M6-track (RF-109): Added D-031** (ratify the RF-109 menu backend contract — six menu tables `menu_categories`/`menu_items`/`item_sizes`/`item_variants`/`modifiers`/`modifier_options`, each org+restaurant+branch scoped with composite same-org FKs and `deleted_at` tombstones; integer-minor money only (`base_price_minor`/`price_delta_minor` `bigint`, **D-007**); no order→menu FK so snapshot independence holds (**D-008**); RLS enabled+forced with explicit per-command policies; owner/manager-only audited `SECURITY DEFINER` write RPCs + thin `public.menu_*` wrappers; `kitchen_staff` excluded from menu reads on **every** path — role-gated SELECT + `sync_pull` allowlist (menu prices are money, **T-003**); **D-026** platform-admin separation and **D-011** no-service-role preserved; RF-060 isolation suite green before merge), via the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9; independently Codex-reviewed, human-approved by Saleh). Amends the frozen baseline ([API_CONTRACT.md](API_CONTRACT.md) §4.23 / §4.15, [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) §14 T-013) and [DOMAIN_MODEL.md](DOMAIN_MODEL.md) §4 (promotes `branch_id` to a ratified nullable column on all six menu tables; standardizes the child money column on signed `price_delta_minor`; DOMAIN_MODEL §4 reconciled under RF-109 Stage 0B). Like **D-029**, this per-ticket M6 backend-surface ADR **satisfies candidate D-030 point 2** and takes the next free sequential ID, leaving **candidate D-030** the reserved, unratified M6-track umbrella label ([M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) §11). The ratified decision range is now **D-001..D-029 and D-031** (**D-030** reserved/unratified); the next free ID is **D-032+**.
- **M6-track (RF-110): Added D-032** (ratify the RF-110 menu image storage contract — a **private** `menu-images` Supabase Storage bucket (no public/anon read, no durable public URLs; MIME `image/png|jpeg|webp`, ~5MiB; created via a SQL `storage.buckets` insert, not committed `config.toml`); `storage.objects` RLS with four explicit per-command policies pinned to `bucket_id='menu-images'`; **path-derived** helpers (`app.menu_image_scope` / `app.can_read_menu_image` / `app.can_write_menu_image`) because the org-GUC helpers `has_scope`/`has_role_in_scope` are unusable in the storage-api context — the caller is identified via `auth.uid()` → `app.current_app_user_id()` and scope is parsed from the object key `{org}/{restaurant}/{branch|global}/menu_item/{menu_item_id}/{image_id}.{ext}`; read = price-capable roles, **`kitchen_staff` excluded** (live-menu surface, **D-031/T-013**); write = `org_owner`/`restaurant_owner`/`manager`, requiring the `menu_items` row to exist in scope; menu-item images only (category/modifier deferred); no `menu_items` column / no `menu_item_images` table / no RPCs; **no `audit_events` for blob mutations** (accepted MVP gap) and orphan cleanup deferred; **D-026** platform-admin separation and **D-011** no-service-role/no-anon preserved; RF-060 isolation suite green before merge), via the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9; independently Codex-reviewed, human-approved by Saleh). Amends the frozen baseline ([API_CONTRACT.md](API_CONTRACT.md) §4.24, [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) §14 T-014, [DOMAIN_MODEL.md](DOMAIN_MODEL.md) §4 storage-image note). Like **D-029**/**D-031**, this per-ticket M6 backend-surface ADR **satisfies candidate D-030 point 2** and takes the next free sequential ID, leaving **candidate D-030** the reserved, unratified M6-track umbrella label ([M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) §11). The ratified decision range is now **D-001..D-029, D-031, D-032** (**D-030** reserved/unratified); the next free ID is **D-033+**.
- **M6-track (RF-112): Added D-033** (ratify the RF-112 settings / membership-roles / device-provisioning backend contract — **GUC-free** management auth on the RF-110 path-derived pattern (`auth.uid()` → `app.current_app_user_id()` + scope validated directly from `memberships` against passed org/restaurant/branch; **never** `app.current_org_id`/`has_scope`/`has_role_in_scope`/menu guard, which fail closed for a real JWT — the RF-111 D1/D3 trap); a **role-rank guard** `org_owner > restaurant_owner > manager > cashier/kitchen_staff/accountant` (actor strictly outranks the assigned **and** existing role, manager cannot assign manager/restaurant_owner/org_owner, no self-grant/self-escalation, downward-scope only, cross-org/restaurant/branch IDOR denied, accountant/cashier/kitchen_staff cannot manage, `platform_admin` is not a tenant role); a **settings slice over existing columns only** (org `default_currency`/`country_code`/`status`, restaurant `name`/`currency_override`/`timezone`/`status`, branch `name`/`address`/`timezone`/`receipt_prefix`/`status`; tax/rounding/locale/business-hours/receipt-template excluded; no new tables / no blob); **membership RPCs** `grant_membership`/`update_role` (existing `app_user` only, no invite/pending flow, no new membership-status enum value, reuse RF-061 `revoke_employee`, audit success + denial, `client_request_id` idempotency); a **device-provisioning forward path** `create_device`/`issue_device_enrollment_code`/redeem-pair/`approve_device` (the `pending → paired` manager-approval edge per [STATE_MACHINES](STATE_MACHINES.md) §9)/`start_device_session` (secrets returned once, stored as hashes/refs only, conservative consume-once enrollment-code TTL, revoked/suspended/expired devices fail closed, reuse RF-061 `revoke_device`); and the decision that RF-112 **does not** implement the GoTrue/app-client auth-org-context bridge — that stays a **separate prerequisite** while RF-112 ships GUC-free and pgTAP-testable now; **D-026** platform separation and **D-011** no-service-role/no-anon preserved; RF-060 isolation suite green before merge), via the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9; independently Codex-reviewed, human-approved by Saleh). Amends the frozen baseline ([API_CONTRACT.md](API_CONTRACT.md) §4.25–§4.27, [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) §14 T-015, [DOMAIN_MODEL.md](DOMAIN_MODEL.md) §2–§3 notes). Like **D-029**/**D-031**/**D-032**, this per-ticket M6 backend-surface ADR **satisfies candidate D-030 point 2** and takes the next free sequential ID, leaving **candidate D-030** the reserved, unratified M6-track umbrella label ([M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) §11). The ratified decision range is now **D-001..D-029, D-031, D-032, D-033** (**D-030** reserved/unratified); the next free ID is **D-034+**.
- **M6-track (RF-112): Added D-034** (define the device **activation + session-start** contract left open by D-033/§4.27, resolving the Codex Stage 2 gap — **D-033 stands**, `approve_device` **remains `pending → paired`**, `pending → active` **remains FORBIDDEN**, approval never hidden-activates, and no session starts on a non-`active` pairing; activation is a **separate explicit `activate_device` RPC** (the **`paired → active`** edge, owned by RF-112, [STATE_MACHINES.md](STATE_MACHINES.md) §9) — GUC-free management auth (`org_owner`/`restaurant_owner`/`manager` in the pairing's scope; cashier/kitchen_staff/accountant/anon/platform-admin-only/wrong-scope denied), requires `paired`, audits `device.activated`/`*_denied`, `client_request_id` idempotency, mints no secret (device credential = RF-021); **`start_device_session`** requires an **`active`** pairing only, generates the session token server-side, stores **only `session_token_ref` = hash**, returns the plaintext token **once** (a replay never leaks it — no-token ledger result, the enrollment-code precedent), audits `device.session_started`, fails closed on revoked/suspended/expired/non-active; **management-initiated via `client_request_id` in RF-112** (the fully **device-originated** `device_id`+`local_operation_id` variant is the follow-up once the deferred device-auth bridge lands; identical `active`-precondition / hash-only / return-once / fail-closed envelope); **D-026** platform separation and **D-011** no-service-role/no-anon preserved; docs gate before Stage 3 SQL, RF-060 suite green before merge), via the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9; independently Codex-reviewed, human-approved by Saleh). Amends the frozen baseline ([API_CONTRACT.md](API_CONTRACT.md) §4.28 / §4.29, [STATE_MACHINES.md](STATE_MACHINES.md) §9 note, [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) §14 T-015 note, [DOMAIN_MODEL.md](DOMAIN_MODEL.md) §3 note). Like **D-029**/**D-031**/**D-032**/**D-033**, this per-ticket M6 backend-surface ADR **satisfies candidate D-030 point 2** and takes the next free sequential ID, leaving **candidate D-030** the reserved, unratified M6-track umbrella label ([M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md) §11). The ratified decision range is now **D-001..D-029, D-031, D-032, D-033, D-034** (**D-030** reserved/unratified); the next free ID is **D-035+**.
- **M7-track (RF-125): PROPOSED D-035** (authorize three thin read-only platform-admin **public wrappers** — `public.platform_admin_organization_overview(text)` / `public.platform_admin_get_organization(uuid, text)` / `public.platform_admin_recent_audit(text, integer)` — as faithful `SECURITY INVOKER` pass-throughs over the RF-091 `app.platform_admin_*` panel RPCs so the Data API client gains an entry point, with the **entire** `app.platform_admin_guard` gate (active `platform_admin_grant` + `aal2` MFA + non-empty reason — **D-026**/T-008) and the reason-tagged `platform_admin_audit_events` writes preserved inside the **unchanged** `app.*` bodies; same params/types/order incl. `p_limit default 50`; grants mirror the app RPC (`revoke all from public` + `grant execute to authenticated`, never `anon`/`service_role` — **D-011**); wrappers left **VOLATILE** so PostgREST POST-routes the audited read; **read-only (D-026)** — no mutation/impersonation/`select *`/grant-revoke; the `app` schema stays **unexposed** and **only** these three read-only panel RPCs are wrapped — `platform_admin_list_organizations` (not yet `aal2`-gated, **Q-008**) and the mutating `set_organization_plan` are deliberately **not** wrapped). **DRAFTED before the SQL** under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9) in the M7 backend baseline; covered by `rf125_public_platform_admin_wrapper_test`. **NOT yet ratified** — pending independent Codex review and **human approval by Saleh** at the merge gate, with the **RF-060 isolation suite green before merge** (**RISK R-003**); to be flipped to *Accepted* on merge. Amends the frozen baseline ([API_CONTRACT.md](API_CONTRACT.md) §4.16 / §4.18, [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) §14 T-007/T-008/T-012). Like **D-029**/**D-031**/**D-032**/**D-033**/**D-034**, this per-ticket backend-surface ADR **satisfies candidate D-030 point 2** and takes the next free sequential ID, leaving **candidate D-030** the reserved, unratified umbrella label. On ratification the range becomes **D-001..D-029, D-031..D-035** (**D-030** reserved/unratified); the next free ID is **D-036+**.
- **M7-track (RF-126): PROPOSED D-036** (authorize one thin POS write wrapper — `public.sync_push(uuid, uuid, jsonb)` — as a faithful `SECURITY INVOKER` pass-through over the RF-056 `app.sync_push` outbox-push RPC so the Data API client gains the **single, narrow** POS write/outbox entry point, with the **entire** whole-batch gate (valid PIN session + active device/pairing + device match + **server-side** org/branch derivation), the `sync_operations` idempotency ledger (exactly-once, transport identity `device_id`+`local_operation_id` — **D-022**), the per-operation dispatch to the business RPCs inside per-op `EXCEPTION` subtransactions, the **money authority** (integer minor only, server-recomputed totals, server-allocated per-branch `receipt_number` — **D-007/D-008/D-021**), and the sync/business audit writes (**D-013**) all preserved inside the **unchanged** `app.sync_push` body; grants mirror the app RPC (`revoke all from public` + `grant execute to authenticated`, never `anon`/`service_role` — **D-011**; **no anon writes**); wrapper left **VOLATILE** so PostgREST POST-routes the write; the `app` schema stays **unexposed** and **only** `sync_push` is wrapped — the dispatched mutators `submit_order`/`record_payment`/`apply_discount`/`open_shift`/`close_shift` remain **dispatcher-only**, not individually wrapped). **DRAFTED before the SQL** under the architecture-change procedure ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9) in the M7 backend baseline; covered by `rf126_public_sync_push_wrapper_test` (introspection/grants/`INVOKER`/`VOLATILE` + narrowness guard + whole-batch gate preserved through the wrapper + a **real** `shift.open→order.submit→payment.create` applied flow with integer-minor money, server-authoritative receipt number, idempotent replay, per-op reject of malformed/unknown/unauthorized ops, and a shared-ledger cross-delegation proof). **NOT yet ratified** — pending independent Codex review and **human approval by Saleh** at the merge gate, with the **RF-060 isolation suite green before merge** (**RISK R-002/R-003**); to be flipped to *Accepted* on merge. Amends the frozen baseline ([API_CONTRACT.md](API_CONTRACT.md) §4.14, [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) §14 T-012, [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md)). Like **D-029**/**D-031**/**D-032**/**D-033**/**D-034**/**D-035**, this per-ticket backend-surface ADR **satisfies candidate D-030 point 2** and takes the next free sequential ID, leaving **candidate D-030** the reserved, unratified umbrella label. On ratification the range becomes **D-001..D-029, D-031..D-036** (**D-030** reserved/unratified); the next free ID is **D-037+**.
