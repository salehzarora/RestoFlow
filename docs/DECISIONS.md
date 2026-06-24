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
  - **Order:** `draft -> submitted -> accepted -> preparing -> ready -> served -> completed`; plus `cancelled` (pre-production, terminal) and `voided` (post-submission, requires authorization+reason, terminal). Takeaway skips `served` (`ready -> completed`). Terminal: `completed`, `cancelled`, `voided`.
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
