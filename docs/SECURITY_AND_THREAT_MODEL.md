# SECURITY_AND_THREAT_MODEL

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

**Status:** M0A baseline, frozen as the M0A architecture baseline at RF-004 (approved into the frozen M0A baseline (RF-004)) (RF-001).
**Owns:** the security model, RLS strategy, tenant-isolation rules, the four defence layers, the threat model, and the canonical mandatory isolation/permission **test assertions** that [TESTING_STRATEGY](TESTING_STRATEGY.md) references as its source.
**Does not own / references only:** entities and fields ([DOMAIN_MODEL](DOMAIN_MODEL.md)), RPC/endpoint bodies ([API_CONTRACT](API_CONTRACT.md)), money/tax/receipt rules ([MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md)), sync mechanics ([OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md)), state transitions ([STATE_MACHINES](STATE_MACHINES.md)), backup/incident operations ([OPERATIONS_AND_RECOVERY](OPERATIONS_AND_RECOVERY.md)), and the decision/question registers ([DECISIONS](DECISIONS.md), [OPEN_QUESTIONS](OPEN_QUESTIONS.md)).

This document defines mandatory controls. Where a topic is owned elsewhere, this document states the *security requirement* and links out; it does not duplicate schemas, RPC signatures, or transition tables.

---

## 1. Scope and security objectives

RestoFlow is a multi-tenant Restaurant Operating System serving many independent restaurant customers on one platform (**DECISION D-003**: the tenant is the Organization). The security model must hold from the first single-branch pilot through full multi-organization SaaS without redesign. No control in this document may assume a single organization, restaurant, or branch exists, and no shared accounts are permitted (**DECISION D-004**).

Primary objectives:

1. **Tenant confidentiality and integrity** — no organization can read, infer, or mutate another organization's data.
2. **Least privilege** — every actor (human or device) acts only within its membership-, restaurant-, branch-, and device-scoped grants.
3. **Non-repudiation** — every sensitive mutation is attributable to an actor and device via an append-only audit trail (**DECISION D-013**).
4. **Resilience under offline operation** — offline capability (**DECISION D-010**) never becomes an authorization bypass.
5. **Defence in depth** — a single failed control must not cause cross-tenant exposure (**DECISION D-012**).

> **RISK R-003** (CRITICAL): an RLS or scoping bug leaks cross-tenant data. Mitigated by the mandatory isolation tests in Section 14 plus required human sign-off before any merge that touches RLS, RPC authorization, or membership logic.

---

## 2. Tenant-isolation boundary

**SECURITY REQUIREMENT** — The primary tenant-isolation boundary is `organization_id` (**DECISION D-001**). Every tenant-scoped row carries `organization_id`, and operational rows additionally carry `restaurant_id`, `branch_id`, `device_id`, and `station_id` where relevant (**DECISION D-017**; column inventory owned by [DOMAIN_MODEL](DOMAIN_MODEL.md)).

**SECURITY REQUIREMENT** — Tenant scope is derived **server-side** from the authenticated principal's membership(s), never from a client-supplied `organization_id`. A request may *select among* the organizations the caller is a member of; it may never *assert* membership in one it does not hold.

**SECURITY REQUIREMENT** — The tenant hierarchy is fixed at Platform -> Organization -> Restaurant -> Branch -> Device/Station (**DECISION D-002**). Authorization decisions walk this hierarchy downward only; a grant at a lower scope never widens to a higher one (a branch manager is not an org owner).

> **ASSUMPTION** — A single physical Supabase/PostgreSQL database holds all tenants, isolated logically by `organization_id` + RLS rather than per-tenant databases. This is the documented pilot/MVP posture; per-tenant or sharded isolation is **DEFERRED** and would be revisited at M4 scale (see [PROJECT_PLAN](PROJECT_PLAN.md)).

---

## 3. The four defence layers (DECISION D-012)

Authorization is enforced redundantly. A mutation must pass **all** applicable layers; isolation must survive the failure of any one.

### Layer 1 — PostgreSQL Row-Level Security (RLS)
**SECURITY REQUIREMENT** — Every tenant-scoped table has RLS **enabled and forced**, with policies that constrain rows to organizations in which the current principal holds an active membership, further narrowed by `restaurant_id` / `branch_id` / `device_id` for scoped roles. RLS is the backstop that holds even if application code is wrong.

- Policies read the principal's organization/role/scope set from the authenticated JWT claims and/or a membership lookup; they never trust client-supplied tenant identifiers.
- A table with no explicit policy denies all access by default (deny-by-default).
- Platform-admin access does **not** flow through normal tenant RLS (see Section 6).
- Concrete policy predicates, the membership-resolution helper functions, and per-table policy matrices live in [DOMAIN_MODEL](DOMAIN_MODEL.md) / migrations authored in **M0B**; this document fixes the *requirement*, not the SQL.

### Layer 2 — Membership / role + branch + device scoping checks
**SECURITY REQUIREMENT** — Application and RPC code re-evaluate the caller's membership-scoped role(s) and branch/device scope before acting, rather than relying on RLS alone. Roles are membership-scoped, never a permanent global attribute on the user (**DECISION D-004**, **D-005**). The **tenant membership role keys** are exactly: `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant` (**DECISION D-026**). `platform_admin` is **not** a tenant membership role and does not appear in this list; platform administration is a separate platform-scoped grant (Section 6, **DECISION D-026**).

- A user may hold different roles in different organizations/restaurants/branches simultaneously; each request is evaluated against the membership matching the targeted scope.
- `accountant` is **strictly read-only** — it performs no mutation anywhere; any mutating RPC invoked by an `accountant` is denied (**DECISION D-028**). Its MVP inclusion is **OPEN QUESTION Q-017**.

### Layer 3 — Sensitive mutations via PostgreSQL RPC (SECURITY DEFINER)
**SECURITY REQUIREMENT** — Sensitive mutations execute only through PostgreSQL RPC functions (`SECURITY DEFINER`) that (a) authorize the actor, (b) enforce state-transition legality, (c) write an audit event, and (d) run inside a single transaction (**DECISION D-011**, **D-012**). Clients never perform sensitive writes by direct table DML.

Sensitive operations include (non-exhaustive; signatures owned by [API_CONTRACT](API_CONTRACT.md)): voiding a submitted/paid order, applying discounts, refunds (**DEFERRED** pending the payment-model freeze — see [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) §12.3 and Q-002/Q-003/Q-004), opening/closing/reconciling shifts and cash-drawer sessions, device pairing/suspension/revocation, membership/employee grant changes, and platform-admin actions.

- `SECURITY DEFINER` functions must set a safe `search_path` and re-derive tenant scope internally; they must never accept an authorization decision (e.g. "is_authorized=true") from the client.

### Layer 4 — Database constraints as the final safety boundary
**SECURITY REQUIREMENT** — Schema constraints are the last line that holds even if Layers 1-3 are bypassed: `NOT NULL` on every `organization_id`; foreign keys that keep `restaurant_id`/`branch_id`/`device_id` within the same `organization_id`; `CHECK` constraints on enum/status values matching the PROPOSED state enumerations (**DECISION D-018** — PROPOSED, approved into the frozen M0A baseline (RF-004); RF-001 §8 directs us to evaluate, not assume final); unique constraints enforcing per-branch receipt sequence and idempotency keys (**DECISION D-021**, **D-022**); and money columns typed as integer minor units suffixed `_minor` (**DECISION D-007** — no floating-point money in DB, RPC, Dart, or sync payloads).

---

## 4. Cross-tenant access prevention

**SECURITY REQUIREMENT** — Every read and write is filtered to the caller's organization(s) at Layer 1 and re-checked at Layer 2. Aggregate/reporting queries are likewise tenant-filtered; no endpoint returns cross-organization aggregates to a non-platform principal.

**SECURITY REQUIREMENT** — Cross-tenant references are structurally impossible: a foreign key may only point to a row in the same `organization_id` (enforced at Layer 4). An order may not reference a menu item, table, or branch belonging to another organization.

**SECURITY REQUIREMENT** — Error responses must not leak existence of other tenants' data. A request for a non-owned `id` returns the same "not found / not authorized" result as a non-existent `id` (no distinguishable 403-vs-404 oracle).

---

## 5. Membership-, branch-, and device-scoped permissions (IDOR protection)

**SECURITY REQUIREMENT** — Object access is authorized by *ownership relationship*, never by mere knowledge of an `id` (**DECISION D-005**). Possessing a UUID grants nothing; the server verifies the object's `organization_id` (and `restaurant_id`/`branch_id`/`device_id` where the role is scoped) against the caller's membership on every access. This is the IDOR control and is exercised by the Section 14 tests.

**SECURITY REQUIREMENT** — UUID primary keys (`id`, **DECISION D-017**) are used to avoid enumerable sequential identifiers, but UUID unguessability is treated as *defence in depth only* — authorization never depends on an identifier being secret.

Scope rules:

- `org_owner` — full access within one organization (all its restaurants/branches).
- `restaurant_owner` — limited to restaurants in their membership.
- `manager` — limited to assigned restaurant/branch scope; may perform authorized sensitive mutations (e.g. void with reason) per role grant.
- `cashier` — limited to assigned branch. **STAFF-CASHIER-PERMISSIONS-001** (human-approved, 2026-07): a cashier applies discounts, cancels/voids **UNPAID** orders, and performs cash-drawer/shift **close and count of their OWN/current shift** (`close_shift`) — these three are **enabled by default**, each disableable per-cashier via an **explicit deny override** (`memberships.permissions ->> key = 'false'`) set by an owner/manager, enforced server-side. A cashier still **may not void a PAID order** (the completed-payment block, Section 14 T-006; paid void/refund is deferred, **DECISION D-023**), and **cannot close another person's/branch's shift**. Does **not** reconcile.
- `kitchen_staff` — limited to kitchen/KDS surfaces of assigned branch/station; no access to financial reports, payments, or money figures (Section 14, T-003).
- `accountant` — **strictly read-only** financial/reporting access within scope; performs **no** mutation anywhere, and any mutating RPC it invokes is denied (**DECISION D-028**). MVP inclusion is **OPEN QUESTION Q-017**.

> Shift **reconciliation** (closed -> reconciled) is a **privileged mutation** performed by `manager` / `restaurant_owner` / `org_owner` via the `reconcile_shift` RPC — it is **separate** from the cashier's close/count (`close_shift`), and is **never** performed by the read-only `accountant` (**DECISION D-028**; transitions owned by [STATE_MACHINES](STATE_MACHINES.md), RPC signatures by [API_CONTRACT](API_CONTRACT.md)).

### Cashier default-on capabilities with explicit deny overrides (STAFF-CASHIER-PERMISSIONS-001)

**SECURITY REQUIREMENT** — Three routine `cashier` capabilities are **enabled by default** and disableable per-cashier by an **explicit deny override**. Human-approved (2026-07); consistent with [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) §4.5 (a cashier may apply discounts) and **DECISION D-028** (a cashier closes their own shift). The three capabilities and their canonical `memberships.permissions` keys are:

| Capability | Key | Enforcing RPC | Default | Notes |
|---|---|---|---|---|
| Apply order/item discount | `apply_discount` | `app.apply_discount` | ON | existing discount limits/rounding/reason/audit unchanged |
| Cancel/void an **UNPAID** order | `void_order` | `app.void_order` | ON | **paid orders stay blocked** (completed-payment guard; paid void/refund deferred, D-023) |
| Close the cashier's **OWN/current** shift | `close_shift` | `app.close_shift` | ON | ownership preserved — a cashier still cannot close another person's/branch's shift; reconciliation stays separate (D-028) |

- **Effective-permission rule (single source of truth):** the **pure `SECURITY INVOKER`** (immutable, no table access) resolver `app.cashier_capability_allowed(role, permissions, capability)` is **fail-closed**. It returns TRUE iff `role = 'cashier'` **AND** the capability is one of the three named **AND** `permissions` is a well-formed JSON **object** **AND** the deny key is **ABSENT**. Deny-only storage removes the key to allow and writes the canonical `{"key":"false"}` to deny, so a **present** key **always denies** — the canonical `"false"` and every malformed present value (boolean / JSON null / number / array / object / the non-canonical string `"true"`) all **DENY**. Non-object / JSON-null / SQL-NULL `permissions`, every non-cashier role, and any capability outside the three named ones all **DENY**. Missing permission data is **NOT** a universal allow — absence allows **only** a named cashier capability. The three RPCs `OR` this resolver with their existing `manager`/`restaurant_owner`/`org_owner` role grants; those roles are unaffected.
- **Backend is authoritative.** Enforcement is in the three `SECURITY DEFINER` RPCs; Dashboard button visibility is never relied upon. A disabled capability is rejected server-side even if a stale client still shows the control.
- **Live, not snapshotted.** Each RPC reads `memberships.role`/`.permissions` **live** from the membership row at action time (the PIN session stores only `resolved_membership_id`). A Dashboard capability change therefore takes effect on the cashier's **next action / next PIN session**; there is no stale grant baked into an existing session, and the offline-window authorization rules (§11, **RISK R-007**, **Q-009**) are unchanged.
- **Full-comp discount manager gate (MONEY_AND_TAX_SPEC §4.4/§4.5).** Making `apply_discount` default-on for cashiers does **not** grant full compensation. `app.apply_discount` computes the discount amount in integer minor units and, **before** the clamp, rejects any discount that would reduce a **positive** order/item target **to zero** (a 100% percentage, a percentage that rounds to the full base, or a fixed amount ≥ base) unless the actor is `manager`/`restaurant_owner`/`org_owner`. A cashier full-comp attempt is **rejected** (`order.discount_denied` audit + `permission_denied`, no state change) — it is **never silently clamped** into a 100% comp. Partial cashier discounts that leave a positive remainder are allowed; an explicit `apply_discount='false'` cashier is denied every discount. No configured sub-100% threshold exists, so the frozen 100%/zero-out gate is the enforced rule.
- **Strict, fail-closed capability input.** `create_staff_member`'s optional `p_capabilities` is validated with `jsonb_each` (no text coercion): only `role='cashier'`, only the three canonical keys, and only the exact JSON **string** `"false"` are accepted; JSON null / boolean / number / array / nested-object / non-object-root / unknown-key / mixed payloads are **rejected** (`42501`) and — because validation and all inserts share one transaction — **nothing is created** (atomic rollback, no fail-open).
- **Owner/manager write path + target scope.** `app.set_staff_capabilities` (public wrapper `public.set_staff_capabilities`) sets a target cashier's deny overrides. The target employee-profile and the **membership that will be mutated** are resolved in **one coherent lookup** (`ep.membership_id = m.id` **and** same `organization_id` **and** same `app_user_id`); **authorization and the scope-predicated `UPDATE` both derive from that membership's own scope** (downward-only coverage via `app.actor_rank_in_scope`), so a profile in one branch can never authorize a mutation of a membership in another branch. Rank ≥ `manager` **and** strictly-outrank are enforced; non-cashier targets are refused. **No oracle:** the actor-scoped idempotency replay check runs **before** any target lookup, and every not-found / cross-tenant / sibling-branch-without-coverage / profile↔membership-mismatch / forged target collapses to **one identical `42501`** (same SQLSTATE and message; **RISK R-003**). Storage is **deny-only** (canonical `"false"` to deny; key removed to re-enable; unrelated permission keys preserved). Audits carry **old and new** raw permissions + effective values. `SECURITY DEFINER`, `search_path=''`, `REVOKE`d from `PUBLIC`, granted only to `authenticated`.
  - *Durable denial-audit limitation:* an **in-scope but insufficient-rank** refusal returns `permission_denied` and **durably** writes `staff.capabilities_denied` (the function returns, so the audit commits). A **not-found / cross-tenant** refusal `RAISE`s `42501`; PostgreSQL rolls back an in-transaction audit on a raised exception, and the project has no supported durable-denial mechanism (no autonomous transaction / dblink / service-role), so those refusals are **fail-closed but not audited** — an accepted, documented limitation rather than an unsafe workaround.
- **DB-first rollout.** These RPC signatures are a schema change: apply the migration to hosted and verify PostgREST availability **before** deploying the Dashboard, and rebuild/redeploy the apps/APKs only when separately approved.

---

## 6. Platform administration (separate privileged, audited path)

**SECURITY REQUIREMENT** — Platform administration is **not** a tenant membership and `platform_admin` is **not** one of the tenant membership role keys (**DECISION D-026**; see Layer 2 in Section 3 and the scope rules in Section 5). It is modelled by a **separate PROPOSED entity, `platform_admin_grants`** (owned by [DOMAIN_MODEL](DOMAIN_MODEL.md) §3.7): a grant references the `app_user_id`, carries **no `organization_id`**, and has its own lifecycle `active -> suspended -> revoked` with `granted_by` / `granted_at` / `revoked_by` / `revoked_at`. A platform-admin grant therefore never becomes an organization membership and never appears in normal tenant RLS predicates.

**SECURITY REQUIREMENT** — A platform-admin grant is exercised **only** through a **separate, privileged, explicitly-audited authorization path** with its own policies — distinct from the tenant application surface. It **never silently bypasses tenant RLS or other tenant protections**: any platform-level access to or mutation of tenant data (e.g. support, incident response) is an explicit, time-bounded, reason-tagged operation, and **every** platform-level access and mutation is recorded as a platform-scoped `audit_events` record (Section 7, **DECISION D-013**) and is independently testable (Section 14, T-007, T-008, T-009, T-010). **OPEN QUESTION Q-005** (data retention/privacy obligations) may further constrain what platform admins may view; pending its resolution, broad tenant-data reads by platform admins are treated as restricted.

**SECURITY REQUIREMENT** — Platform-admin authentication **requires MFA** (Section 8; method and mapping are **OPEN QUESTION Q-008**) and originates from accounts that hold no tenant membership, keeping the platform plane and tenant plane separate. An organization membership can never grant platform-admin access, and a platform-admin grant never confers a tenant membership (Section 14, T-008, T-009).

---

## 7. Append-only audit events (DECISION D-013)

**SECURITY REQUIREMENT** — Sensitive mutations write an append-only `audit_events` record (table named per **DECISION D-017**) capturing: actor (user identity), device (device identity), `organization_id`, `restaurant_id`, `branch_id`, timestamp (server-authoritative), action, reason, old values, and new values.

**SECURITY REQUIREMENT** — `audit_events` is **append-only**: no application role may `UPDATE` or `DELETE` audit rows. This is enforced by RLS/grants (no update/delete privilege) and by the absence of any RPC that mutates audit rows. Audit writes occur inside the same transaction as the mutation they describe (Layer 3), so an unaudited sensitive mutation cannot be committed.

- Audit entries record both successful and denied sensitive attempts where feasible (e.g. an attempted unauthorized void), to support detection of privilege-escalation probing.
- Money values in audit old/new payloads are integer minor units (**DECISION D-007**); no floating point.
- Retention of audit data is governed by **OPEN QUESTION Q-005**; operational backup/retention is owned by [OPERATIONS_AND_RECOVERY](OPERATIONS_AND_RECOVERY.md).

**SECURITY REQUIREMENT — read-only tenant audit viewer (AUDIT-LOG-DASHBOARD-001).** Owners/managers may READ their own organization's audit trail through the Dashboard "Activity log", served **exclusively** by the read-only `app.owner_audit_events` RPC (contract in [API_CONTRACT](API_CONTRACT.md) §4.31). This viewer:
- **Never mutates.** It performs no `UPDATE`/`DELETE`/`INSERT` on `audit_events` and introduces no new audit action — the append-only guarantee above is untouched. There is no "clear log", edit, retry, or raw-JSON surface.
- **Is management-only.** Authorization mirrors the owner-report reads (`app.actor_rank_in_scope` over the passed scope, downward-only, 0 ⇒ `42501`) but with a **stricter** role allowlist: `manager` / `restaurant_owner` / `org_owner` only; `cashier`, `kitchen_staff`, and `accountant` are denied. It is a GUC-free `SECURITY DEFINER` function whose explicit `organization_id` + scope predicates ARE the tenant-isolation boundary (**RISK R-003**); an out-of-scope branch is refused identically to a nonexistent one (no cross-tenant existence oracle). No anon / service_role (**DECISION D-011**).
- **Enforces a SERVER-SIDE allowlist privacy boundary (never raw payload JSON).** The RPC does not return raw `old_values`/`new_values` — not even secret-key-redacted raw JSON. `app.audit_safe_detail(action, values)` returns `{}` for any unsupported action (no payload detail) and, for a supported action, emits ONLY a fixed allowlist of safe scalar fields (status/scope/discount type/value/roles/integer-minor money/item & attempt counts/locked) plus the nested `capabilities` booleans; **every un-listed key — secret OR merely unknown — and every other nested structure is dropped**, so a direct authenticated caller cannot retrieve the original payload. The Dashboard presentation mapper independently allowlists again (a second layer that also protects the demo path). The actor is shown as a staff display name only (never email/phone, and no actor/auth ids); PINs, hashes, tokens, enrollment/device-session secrets, and publishable/service-role keys are structurally impossible to render. This is a tenant-scoped read of the org's own data and does **not** relax the platform-admin restrictions of Section 6 or **OPEN QUESTION Q-005**.

---

## 8. Human authentication and MFA

**SECURITY REQUIREMENT** — Owners and managers authenticate with personal accounts and secure auth; MFA is required for the privileged **tenant membership roles** (`org_owner`, `restaurant_owner`, and `manager` for sensitive actions) and is **mandatory** for the platform-admin grant (Section 6, **DECISION D-026** — platform-admin is a platform-scoped grant, not a tenant membership role). The specific MFA method (TOTP/SMS/email) and the exact role-to-MFA mapping are **OPEN QUESTION Q-008**; until frozen, the design must keep MFA enforcement role-driven and configurable.

**SECURITY REQUIREMENT** — Cashiers and kitchen staff use a personal employee identity with a **PIN-based fast session**, established only on a device that is already paired and authorized (**DECISION D-005**, **D-006**). The PIN is a fast re-auth on top of an authenticated device session — never a standalone credential and never a shared/restaurant-wide secret.

---

## 9. PIN sessions, attempt limits, and session expiration

**SECURITY REQUIREMENT** — A human PIN session is layered on top of a valid device session; a PIN never authenticates against the platform directly. PIN credential material is stored as a salted hash referenced by the employee profile, never in plaintext (**DECISION D-005**; the employee profile carries a PIN credential *reference*, not the PIN).

**SECURITY REQUIREMENT** — PIN entry is **rate-limited with lockout**: after a bounded number of consecutive failures the PIN is temporarily locked on that device and the lockout is auditable. (Exact threshold/backoff to be fixed in [API_CONTRACT](API_CONTRACT.md)/M0B; the *requirement* for an attempt cap is an RF-001 invariant, frozen as the M0A baseline at RF-004.)

**SECURITY REQUIREMENT** — Sessions expire. Human PIN sessions are short-lived and re-prompt after inactivity; privileged web sessions have shorter lifetimes than cashier sessions; device sessions are renewable but revocable (Section 10). The offline validity of a cached PIN/permission is bounded by **OPEN QUESTION Q-009** (see Section 11).

---

## 10. Device identity, pairing expiration, and revocation

**SECURITY REQUIREMENT** — POS/KDS devices have their own device identity and credentials with limited permissions (a device is not a human, **DECISION D-005**). A device session (**concept 5**) is required before any human PIN session (**concept 6**) can exist on that device.

**SECURITY REQUIREMENT** — Device pairing uses short-lived enrollment codes / controlled enrollment that **expire** (**DECISION D-006**). The pairing lifecycle follows the PROPOSED state enumeration (**DECISION D-018** — PROPOSED, approved into the frozen M0A baseline (RF-004); RF-001 §8 directs us to evaluate, not assume final): `code_issued -> pending -> paired -> active -> suspended -> revoked`, plus `code_expired` and `rejected`; terminal states `revoked`, `code_expired`, `rejected`. An expired or unredeemed code cannot be used to pair.

**SECURITY REQUIREMENT** — Device revocation removes **future** access. A `revoked` device cannot establish new sessions, and operations it submits after revocation are rejected server-side on sync (Section 14, T-004), even if the device was offline at revocation time. Revocation is an audited RPC (Layer 3).

---

## 11. Employee revocation and offline authorization expiration

**SECURITY REQUIREMENT** — Removing an employee or revoking a device removes future access (**DECISION D-006**). A removed employee cannot create new valid operations; any operation created under a revoked identity is rejected on sync (Section 14, T-005).

**SECURITY REQUIREMENT** — Offline operation never bypasses authorization. Cached permissions and PIN sessions are valid offline only for a bounded window; on reconnect the server re-validates the actor/device and **rejects** operations from a now-revoked actor/device created after revocation took effect.

> **RISK R-007** — An employee/device revoked during an offline window keeps acting on a disconnected device. Mitigation: a short offline-validity window (**OPEN QUESTION Q-009**, currently unfrozen), server-side rejection on reconnect with audit, and visible sync status to the cashier. Until Q-009 is frozen, the design assumes a conservative (short) default and must not hard-code a permissive window.

The mechanics of outbox/inbox, idempotency, and rejection handling are owned by [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md); this document fixes the *authorization* requirements that sync must honour.

---

## 12. Client, secret, storage, transport, and logging controls

**SECURITY REQUIREMENT** — No service-role key or other privileged backend credential is ever embedded in or shipped to Flutter clients (**DECISION D-011**). Clients use only public/anon-class keys plus the authenticated principal's session; all privileged operations go through RPC (Layer 3).

**SECURITY REQUIREMENT** — No production secrets in the repository. Secrets (service-role keys, signing keys, provider tokens) live in environment/secret stores, never in source, fixtures, or committed config. CI secret-scanning is required from M0B onward.

**SECURITY REQUIREMENT** — All client-server transport is TLS; no plaintext sync or auth traffic.

**SECURITY REQUIREMENT — local DB protection & secure storage.** The local SQLite/Drift operational store (**DECISION D-010**) holds tenant data on devices and must be protected: encryption at rest on the device, OS-level secure storage (Keychain/Keystore) for device credentials, session tokens, and PIN credential references — never plaintext files or shared preferences. A lost/stolen device must not yield long-lived usable credentials beyond the bounded offline window (Section 11) and is mitigated by device revocation (Section 10).

> **OPEN QUESTION Q-009** also bounds how much usable authority a stolen, still-paired device retains before its cached window expires.

**SECURITY REQUIREMENT — log redaction.** Logs (client, server, sync, print) must redact secrets, full PINs, tokens, and personal data. Money may be logged only as integer minor units. Audit events (Section 7) are the authoritative record of sensitive actions; general application logs are not a substitute and must not capture credentials.

**SECURITY REQUIREMENT — rate limits.** Authentication endpoints, PIN entry (Section 9), device pairing, and sync ingestion are rate-limited to resist brute force, enumeration, and replay floods. Idempotency keys (`device_id` + `local_operation_id`, **DECISION D-022**) prevent duplicate-mutation acceptance independent of rate limiting.

Backup/recovery (RPO/RTO, **OPEN QUESTION Q-013**) and incident handling are owned by [OPERATIONS_AND_RECOVERY](OPERATIONS_AND_RECOVERY.md); security incidents (suspected breach, leaked secret, anomalous platform-admin access) are routed through that runbook, with audit-event review as the primary forensic source.

---

## 13. STRIDE threat table (top threats)

| # | Threat (STRIDE) | Description | Primary controls | Refs |
|---|-----------------|-------------|------------------|------|
| TH-1 | **I**nformation Disclosure — cross-tenant read | Org B principal reads Org A orders/reports | Layer 1 RLS on `organization_id`; Layer 2 membership check; identical not-found/not-authorized responses (no oracle); FK same-org constraint | D-001, D-012, R-003; Tests T-001, T-003 |
| TH-2 | **E**levation of Privilege — privilege escalation | Cashier/kitchen acts beyond scope, self-grants role, a manager assigns a role at/above its own rank, accountant attempts a mutation, or a tenant membership reaches for platform-admin | Membership-scoped roles (no global role); RPC re-authorizes; **role-rank ceiling** on `grant_membership`/`update_role` (actor strictly outranks assigned+existing role; no self-grant/self-escalation; downward-scope only — D-033); accountant strictly read-only; platform-admin is a separate platform-scoped grant (not a membership); denied attempts audited; DB constraints | D-004, D-005, D-012, D-013, D-026, D-028, D-033; Tests T-002, T-006, T-008, T-011, T-015 |
| TH-2b | **E**levation of Privilege — platform-plane crossover | Platform-admin grant treated as tenant membership, or used to bypass tenant RLS | `platform_admin_grants` carries no `organization_id` and is not a tenant membership; separate privileged, audited path; tenant RLS never bypassed; MFA required | D-026, D-013, Q-008; Tests T-007, T-008, T-009, T-010 |
| TH-3 | **S**poofing / Tampering — stolen device | Lost/stolen paired device used to act or exfiltrate local DB | Device identity + revocation; provisioning secrets return-once/hash-only + consume-once enrollment code (D-033); encrypted local store + secure storage; bounded offline window; PIN re-auth + lockout | D-006, D-033, Q-009, R-007; Tests T-004, T-015 |
| TH-4 | **T**ampering / **R**epudiation — replayed/duplicated mutation | Same mutation replayed to double-charge/double-apply | Idempotency key (`device_id`+`local_operation_id`); server inbox/processed ledger; per-branch unique receipt sequence; transactional RPC | D-021, D-022, R-002; (sync owned by OFFLINE_SYNC_SPEC; idempotency/replay coverage in [TESTING_STRATEGY](TESTING_STRATEGY.md) §5 and contract idempotency in §7) |
| TH-5 | **E**levation / Spoofing — offline-revoked actor | Revoked employee/device keeps acting offline | Future-access removal; revoked/suspended/expired devices fail closed in provisioning (D-033); server rejection on reconnect with audit; short offline validity | D-006, D-033, Q-009, R-007; Tests T-004, T-005, T-015 |
| TH-6 | **I**nformation Disclosure — secret leakage | Service-role key/secret in client or repo; device enrollment code / session token leaked or stored in plaintext | No service-role key in clients; no secrets in repo; provisioning secrets returned once and stored as hashes/references only — never plaintext in DB or `audit_events` (D-033); CI secret scanning; log redaction; TLS | D-011, D-033; Section 12; Test T-015 |

Cross-tenant RLS correctness (TH-1) is the **CRITICAL** risk **R-003** and gates merges via human sign-off.

---

## 14. MANDATORY TEST CASES (canonical isolation/permission assertions)

These assertions are the **source of truth** that [TESTING_STRATEGY](TESTING_STRATEGY.md) references and implements (test placement, fixtures, and harness are owned there). Each is phrased as a testable assertion and must pass before any release touching auth/RLS/RPC. All must be evaluated with at least two distinct organizations present (no single-tenant assumption).

- **T-001 — Cross-organization read isolation.** Given Org A and Org B each with orders, a principal whose only active membership is in Org B **cannot** read, list, or aggregate Org A's `orders` (or any tenant-scoped row); the attempt returns no Org A rows and is indistinguishable from non-existent data. *(TH-1, D-001)*

- **T-002 — Cross-restaurant write isolation.** A `cashier` (or any scoped role) whose membership is in Restaurant A **cannot** create, modify, void, or otherwise mutate any row belonging to Restaurant B; the attempt is denied at RLS and/or RPC and, where applicable, audited as a denied action. *(TH-2, D-004/D-005)*

- **T-003 — KDS / kitchen_staff cannot read financials.** A `kitchen_staff` principal (and a KDS device session) **cannot** read financial reports, payments, totals, or any money figure; only kitchen-relevant order/ticket data within scope is returned. *(TH-1/TH-2, D-005)*

- **T-004 — Revoked device cannot sync new operations.** A device transitioned to `suspended`/`revoked` **cannot** establish a new session, and operations it submits dated after revocation are **rejected** on sync (including operations created while it was offline), with the rejection audited. *(TH-3/TH-5, D-006, R-007, Q-009)*

- **T-005 — Removed employee cannot create valid operations.** After an employee is removed/revoked, operations created under that identity (online or queued offline) are **rejected** server-side and produce no valid committed mutation; the rejection is audited. *(TH-5, D-006, R-007)*

- **T-006 — Cashier void authorization; PAID orders are never voided.** *(Updated by **STAFF-CASHIER-PERMISSIONS-001**, human-approved 2026-07 — the invariant this test protects is preserved and strengthened.)* A **PAID** order (one with a live `completed` payment) **cannot be voided by anyone** — the void RPC denies the request (`permission_denied` + `detail=order_has_completed_payment`), no payment/order state changes, and the denied attempt is audited; paid void/refund is **deferred** (**DECISION D-023**). For an **UNPAID** order, voiding is a **default-ON cashier capability** (effective permission = role default unless an explicit deny override `memberships.permissions ->> 'void_order' = 'false'` is present): a cashier **carrying that explicit deny cannot void** — the RPC denies, no state changes, the denied attempt is audited — while a **default cashier may void an eligible unpaid order**. A void by an authorized actor requires a reason and is audited. *(TH-2, D-012/D-013, state model D-018; effective-permission resolver `app.cashier_capability_allowed`)*

- **T-007 — Platform-admin access is explicitly audited.** Any platform-admin access to tenant data flows through the separate platform path and **must** produce a platform-scoped, reason-tagged `audit_events` record; there is no normal-tenant code path by which a platform admin can read tenant operational data without an audit entry. *(TH-1, D-013, D-026, Section 6)*

- **T-008 — Organization membership cannot grant platform-admin access.** No tenant membership (any of `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant`), at any scope and in any combination, confers platform-admin authority; a principal holding only organization memberships **cannot** invoke the platform-admin path or any platform-scoped operation. *(TH-2, D-026, Section 6)*

- **T-009 — Platform-admin grant is not an organization membership.** A `platform_admin_grants` row ([DOMAIN_MODEL](DOMAIN_MODEL.md) §3.7) does **not** appear as, or behave as, a tenant membership: it carries **no `organization_id`**, never satisfies tenant RLS membership predicates, and a principal whose only grant is a platform-admin grant has **no** tenant-scoped read/write rights through the normal application surface. *(TH-1/TH-2, D-026, Section 6)*

- **T-010 — Platform-admin operations enforce the privileged path and cannot bypass tenant RLS.** A platform-admin actor **cannot** read or mutate tenant data through the normal tenant code path; tenant RLS and the four defence layers are not bypassed. Any legitimate platform-level access occurs only via the separate privileged path, which is time-bounded and reason-tagged. *(TH-1, D-012, D-026, Section 6)*

- **T-011 — Accountant is strictly read-only; reconciliation is privileged.** An `accountant` principal invoking **any** mutating RPC (including `reconcile_shift`, `close_shift`, void, discount, grant changes) is **denied** and no state changes; shift reconciliation (closed -> reconciled) succeeds only for `manager` / `restaurant_owner` / `org_owner` via `reconcile_shift`, separately from the cashier's `close_shift` close/count, and denied attempts are audited. *(TH-2, D-028, D-012/D-013)*

- **T-012 — Public auth precursor RPCs are caller-scoped, self-only, and not over-privileged.** `public.start_pin_session` and `public.get_my_context` (**DECISION D-029**) are `EXECUTE`-granted **only** to `authenticated` — **never** `anon`, and **no service-role key is ever used in a client** (Section 12) — and the `app` schema is **not** exposed via the Data API. `public.start_pin_session` is a faithful **pass-through** that **adds no privilege** beyond `app.start_pin_session` (wrong PIN still returns `NULL`; structural / precondition / lockout failures still raise `42501`; a **revoked device / employee / session is still rejected**, extending T-004/T-005). `public.get_my_context` returns **only the calling principal's own** identity and memberships: it **cannot** return another user's `app_users` row or memberships (**cross-user isolation**), **cannot** return any other organization's data (**cross-org isolation**, extending T-001), and surfaces `is_platform_admin` as a **separate boolean** that is **never** a tenant membership and from which **no `organization_id`** is derivable (extending T-008/T-009/T-010). A `kitchen_staff` caller still sees **no** money figure through any context it returns (T-003). Evaluated with **at least two distinct organizations and two distinct users**. *(TH-1/TH-2/TH-5, D-001, D-004/D-005, D-006, D-011, D-026, Section 12; extends T-001, T-003, T-004/T-005, T-008/T-009/T-010)*

- **T-013 — Menu backend is tenant-isolated, money-safe, and kitchen-excluded from the live menu.** The six menu tables (`menu_categories`, `menu_items`, `item_sizes`, `item_variants`, `modifiers`, `modifier_options`; **DECISION D-031**, RF-109) have RLS **enabled + forced** with explicit per-command policies (deny-by-default). **Tenant isolation (extends T-001/T-002):** a principal whose only membership is in Org B reads **zero** Org A menu rows and cannot mutate them; a restaurant/branch-scoped member does **not** see sibling-restaurant/branch child rows (SELECT predicate `app.has_scope(org, restaurant_id, branch_id)`); IDOR-by-id returns nothing. **Denied direct DML (Layer 3; D-011/D-012):** direct INSERT/UPDATE/DELETE on every menu table is **denied by policy and REVOKED**; all writes flow through the role-gated `SECURITY DEFINER` `menu_*` RPCs ([API_CONTRACT](API_CONTRACT.md) §4.23), restricted to `org_owner`/`restaurant_owner`/`manager` — `cashier`/`kitchen_staff`/`accountant` writes are denied (`permission_denied` / `42501`) and **audited** as `menu.*_denied`. **Audited mutations (D-013):** each successful menu mutation writes an append-only `audit_events` row (actor/device/org/restaurant/branch/old/new). **Money safety (D-007):** every menu price is integer `_minor` (`base_price_minor`/`price_delta_minor` `bigint`); no float reaches any menu money path. **Kitchen live-menu restriction (extends T-003):** `kitchen_staff` (and KDS device sessions) read **zero** menu rows on **every** path — they are excluded from the **role-gated menu table SELECT** (a direct `select` returns **no rows**, not a money-redacted row) **and** from the `sync_pull` menu entity allowlist (the request raises `42501`); **no `*_minor` value reaches a kitchen principal on any path**. Menu prices are money, so only the five price-capable roles (`org_owner`/`restaurant_owner`/`manager`/`cashier`/`accountant`) read the menu; KDS derives item names from order snapshots (written by `submit_order`, §4.1), never the live menu. **Snapshot independence (D-008):** editing or soft-deleting a menu row never rewrites an existing `order_items`/`order_item_modifiers` snapshot, and no FK links order rows to the live menu. **No service-role client path (D-011):** menu RPCs/wrappers are `EXECUTE`-granted to `authenticated` only — never `anon` / `service_role` — and the `app` schema is not Data-API-exposed; `platform_admin` is never on the menu tenant path (**DECISION D-026**). Evaluated with **at least two distinct organizations** plus restaurant/branch-scoped members. *(TH-1/TH-2, D-001, D-007, D-008, D-011, D-012, D-013, D-026, D-028, D-031, RISK R-003, RISK R-008; extends T-001, T-002, T-003)*

- **T-014 — Menu image storage is path-derived, tenant-isolated, and kitchen-excluded.** The private `menu-images` Supabase Storage bucket (**DECISION D-032**, RF-110) is governed by four explicit `storage.objects` per-command policies pinned to `bucket_id = 'menu-images'`. **Path-derived authorization (NOT the org-GUC helpers):** because the storage-api request sets `auth.uid()` but **not** `app.current_organization_id`, policies use `SECURITY DEFINER` helpers (`app.menu_image_scope` / `app.can_read_menu_image` / `app.can_write_menu_image`) that identify the caller via `app.current_app_user_id()` (auth.uid → `app_users`) and derive the target org/restaurant/branch/menu_item from the **object key**; `app.has_scope` / `app.has_role_in_scope` are **not** used (they would deny all access without the GUC). **Path-spoofing denied:** a malformed key (wrong segment count, missing `menu_item` label, non-UUID segment, bad extension) yields no parsed scope → policy denies. **Cross-tenant isolation (extends T-001/T-002):** a caller cannot read or write an object whose path org/restaurant/branch is not covered by an active membership of the caller; cross-org, cross-restaurant, and sibling-branch paths are denied; a write additionally requires the referenced `menu_items` row to exist in the parsed scope. **Read role gate:** only `org_owner`/`restaurant_owner`/`manager`/`cashier`/`accountant` may read; **`kitchen_staff` reads no menu image** (live-menu surface; the path reveals menu structure — consistent with T-013/T-003; KDS uses order snapshots). **Write role gate:** only `org_owner`/`restaurant_owner`/`manager` may INSERT/UPDATE/DELETE; `cashier`/`kitchen_staff`/`accountant` denied. **No public exposure:** the bucket is private (no `anon`, no public URLs); reads are signed URLs over permitted objects. **No platform / service-role bypass:** `app.is_platform_admin()` is never referenced in storage policies (**DECISION D-026**); no `anon` or `service_role` client path (**DECISION D-011**). **Accepted gaps (documented, not controls):** blob mutations are **not** written to `audit_events` (no `SECURITY DEFINER` RPC in the storage write path), and **orphan cleanup is deferred** (deleting/soft-deleting a `menu_items` row does not remove its stored images). Evaluated with **at least two distinct organizations** and a JWT principal simulated via `request.jwt.claims`. *(TH-1/TH-2, D-001, D-011, D-012, D-026, D-031, D-032, RISK R-003; extends T-001, T-002, T-003, T-013)*

- **T-015 — Tenant administration backend (settings / membership roles / device provisioning) is GUC-free, escalation-proof, tenant-isolated, and secret-safe.** The RF-112 management RPCs (**DECISION D-033**) — settings updates ([API_CONTRACT](API_CONTRACT.md) §4.25), `grant_membership` / `update_role` (§4.26), and the device forward path `create_device` / `issue_device_enrollment_code` / redeem-pair / `approve_device` / `start_device_session` (§4.27) — authorize **GUC-free**: the caller is identified via `auth.uid()` → `app.current_app_user_id()` and scope is validated **directly from `memberships`** against the **passed** org/restaurant/branch; `app.current_org_id` / `app.has_scope` / `app.has_role_in_scope` / the menu guard are **never** used (they would deny all access without the unset `app.current_organization_id` GUC — the RF-111 D1/D3 trap). **Role-rank escalation denied (extends T-002, TH-2):** with the rank `org_owner > restaurant_owner > manager > {cashier, kitchen_staff, accountant}`, an actor **cannot** grant or update to a role at or above its own rank — a `manager` **cannot** assign `manager` / `restaurant_owner` / `org_owner`; **self-grant and self-escalation are denied**; the assigned scope must be within the actor's scope (**downward-only**); `cashier` / `kitchen_staff` / `accountant` **cannot manage** (accountant strictly read-only, **DECISION D-028**, extends T-011); and **`platform_admin` is never an assignable role** (**DECISION D-026**, extends T-008/T-009). **Cross-tenant membership IDOR denied (extends T-001/T-002):** a `grant_membership` / `update_role` / settings / provisioning call targeting an org/restaurant/branch the actor does not actively belong to is denied — cross-org, cross-restaurant, and sibling-branch targets resolve to no authority (scope is server-derived, never client-asserted). **Settings slice is bounded:** only the existing columns in [DOMAIN_MODEL](DOMAIN_MODEL.md) §2.1–§2.3 are writable; no tax / locale / hours / receipt-template surface is exposed. **Device secrets are return-once / hash-only (TH-6):** enrollment codes and session tokens are returned to the caller exactly once and stored **only as hashes/references** — **no plaintext secret in the DB or in `audit_events`**; the enrollment code is **consume-once** (a second redeem fails) and an **expired code is rejected** by the existing expiry guard. **Revoked/suspended/expired devices fail closed (extends T-004, RISK R-007):** they cannot pair or start a session, and RF-061 revoke removes future access incl. the offline window; RF-112 does not weaken this. **Audited mutations and denials (D-013):** every successful settings/membership/device mutation **and** every denied attempt writes an append-only `audit_events` row (actor/org/restaurant/branch/old/new). **No service-role / anon client path (D-011):** all RPCs/wrappers are `EXECUTE`-granted to `authenticated` only — never `anon` / `service_role` — and the `app` schema is not Data-API-exposed; a role-denied call returns `{ok:false, error:'permission_denied'}` (denial audited) while structural / scope / not-found / cross-tenant raise `42501`. Evaluated with **at least two distinct organizations** (and ≥2 restaurants/branches and ≥2 users), with the JWT principal simulated via `request.jwt.claims`. *(TH-2/TH-2b/TH-3/TH-5/TH-6, D-001, D-004/D-005, D-006, D-011, D-012, D-013, D-022, D-026, D-028, D-033, RISK R-003, RISK R-007; extends T-001, T-002, T-004, T-005, T-008/T-009, T-011)*

- **T-015 (DECISION D-034 extension) — device activation + session start.** The RF-112 `activate_device` (`paired → active`) and `start_device_session` (**DECISION D-034**, [API_CONTRACT](API_CONTRACT.md) §4.28 / §4.29) carry the same GUC-free management authorization and fail-closed envelope as T-015: **activation cannot skip approval** — only a **`paired`** pairing activates, `pending → active` is **FORBIDDEN** ([STATE_MACHINES](STATE_MACHINES.md) §9), and activation **never** happens inside `approve_device`; **a device session starts only on an `active` pairing** (`revoked`/`suspended`/`code_expired`/`paired`/non-active fail closed — extends **T-004**/**RISK R-007**); the **session token is server-generated, stored hash-only (`session_token_ref`), returned exactly once, and a replay never re-returns it** (no-token idempotency-ledger result — **TH-6**); every activation/session mutation **and** role-denial is audited (`device.activated` / `device.session_started` / `*_denied`, **D-013**); and there is **no `anon` / `service_role` path** (**D-011**) and **no `platform_admin` bypass** (**D-026**). *(TH-3/TH-6, D-006, D-011, D-013, D-022, D-026, D-034; extends T-004, T-015)*

Additional security tests (e.g. IDOR by guessed UUID, PIN lockout after N failures, expired pairing code rejection, idempotency-key replay rejection, secret-scanning in CI) are enumerated and owned by [TESTING_STRATEGY](TESTING_STRATEGY.md), derived from the requirements in Sections 5, 9, 10, and 12 above.

---

## 15. Open questions and deferrals affecting security

- **OPEN QUESTION Q-005** — data retention & privacy obligations (constrains audit retention and platform-admin data access).
- **OPEN QUESTION Q-008** — MFA method and mandatory-role mapping.
- **OPEN QUESTION Q-009** — offline authorization validity window (bounds R-007 exposure).
- **OPEN QUESTION Q-013** — backup RPO/RTO & DR region (owned by [OPERATIONS_AND_RECOVERY](OPERATIONS_AND_RECOVERY.md)).
- **OPEN QUESTION Q-017** — whether the read-only `accountant` role ships in MVP.
- **DEFERRED** — payment refunds are out of MVP and deferred pending the payment-model freeze (see [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) §12.3 and Q-002/Q-003/Q-004); their authorization requirements will be added when scoped. Tips remain tracked under **OPEN QUESTION Q-011**.

Full context for every D-xxx and Q-xxx lives in [DECISIONS](DECISIONS.md) and [OPEN_QUESTIONS](OPEN_QUESTIONS.md); this document cites them and must not invent parallel IDs.
