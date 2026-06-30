# RF-150 — Real Production Backend Integration & End-to-End Restaurant Flow

> **Working implementation note for ticket RF-150.** This is NOT a frozen baseline document. It cites the frozen sources of truth — [DECISIONS.md](DECISIONS.md), [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md), [DOMAIN_MODEL.md](DOMAIN_MODEL.md), [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md), [API_CONTRACT.md](API_CONTRACT.md), [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md), [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md) — and never overrides them. Where it proposes new surface area it marks it **PROPOSED** and routes it through the change-control procedure (own ticket + pgTAP + independent review + human approval), exactly as RF-125/RF-126 did.

## 0. Executive summary — where RestoFlow actually is

RF-150 is framed as "move from polished demo toward a real multi-tenant SaaS backend." The **Phase 0 audit (RF-150) found the production backend is already ~90 % built** across migrations **RF-014 → RF-139** (34 forward-only migrations, **2208 pgTAP assertions across 151 files, all green** at baseline). The real, multi-tenant, RLS-enforced, RPC-mediated data plane already exists:

- Tenant hierarchy + structural isolation, full per-command RLS, kitchen money-redaction.
- Per-person identity, memberships/roles, device pairing/activation, PIN sessions, MFA gate.
- Order submit / discount / void / payment+receipt / shift+cash-reconciliation RPCs.
- Offline `sync_push` / `sync_pull` with idempotency ledger, plus **public** Data-API wrappers (`public.sync_push`, `public.sync_pull`, `public.start_pin_session`, `public.get_my_context`, `public.platform_admin_*`, `public.menu_*`).
- Self-serve onboarding RPC (`app.create_organization`), device provisioning, membership management, menu schema/CRUD, dashboard rollup views, platform-admin panel, basic billing.

**The genuine gaps RF-150 should close are therefore narrower than the brief assumes:**

| Gap | Status | RF-150 disposition |
|---|---|---|
| **Printer configuration model** (tables/RLS/routing) | **Missing entirely** — no `printer_*` tables; `devices.device_type` is only `pos`/`kds` | **Implemented this branch** (Phase 8) |
| **Onboarding reachable by clients** | `app.create_organization` exists but `app` schema is not exposed to the Data API → clients cannot call it | **Implemented this branch** — `public.create_organization` wrapper (Phase 3) |
| **Client real-mode login/provisioning UI** + flipping app defaults to real-first | Real* repositories exist but are dormant/fail-closed; apps default to demo | **Deferred** — large, and partly human-gated (Q-008, Q-009, R-003). Documented below. |
| **Demo removal (real-first startup)** | Unsafe today: without a client login flow, real-first startup yields fail-closed empty/error screens with no way in | **Deferred with rationale** (Phase 9) |
| **Hardware printing transport** (USB/network/BT bytes, drawer kick) | Deferred behind the replaceable adapter; browser preview only | **Deferred** (Q-006/Q-015; native bridge) |
| **Card/online payments, tips, refunds, inventory** | Out of MVP / deferred decisions | **Out of scope** |

This branch (`feature/RF-150-real-backend-integration`) delivers the two genuinely-missing, additive, locally-testable backend foundations (**printer configuration** and **public onboarding wrapper**) plus this plan, and reports the rest honestly rather than shipping half-wired or fake real-mode code.

> **Doc-drift note:** [TASK_TRACKER.md](TASK_TRACKER.md) still reads "M0A complete, no app code/migrations yet." That is stale — M0B…M7 have all shipped. Not fixed here (out of RF-150 scope); flagged for a docs ticket.

---

## 1. How restaurants are separated (tenant isolation)

**The tenant is the Organization, not the restaurant** (**DECISION D-003**). Hierarchy is `Platform → Organization → Restaurant → Branch → Device/Station` (**D-002**). `organization_id` is the primary isolation boundary (**D-001**) and is present on every tenant-scoped row; operational rows additionally carry `restaurant_id` / `branch_id` / `device_id` / `station_id`.

Separation is enforced by **four defence layers** (**D-012**), all already implemented:

1. **PostgreSQL RLS** — every tenant table is `ENABLE` + `FORCE` row-level security with explicit per-command policies (RF-059). Read predicate: `organization_id = app.current_org_id() AND app.has_scope(org, restaurant, branch)`; money-bearing tables additionally require `app.can_read_financials(...)` (excludes `kitchen_staff`, T-003). Direct writes are denied (`with check (false)`) — writes are RPC-only.
2. **Membership/role + branch/device scoping** — `app.has_scope` / `app.has_role_in_scope` resolve the caller's active membership and role within the active org.
3. **SECURITY DEFINER RPCs** (**D-011**) — all sensitive mutations.
4. **DB constraints** — composite same-org foreign keys (e.g. `(organization_id, restaurant_id, branch_id) → branches(organization_id, restaurant_id, id)`) make a cross-organization parent reference **structurally impossible**.

The RF-019 harness auto-detects any `public` table carrying `organization_id` and **fails CI** unless it has RLS enabled + forced + ≥1 policy — so every new tenant table (including this branch's printer tables) is held to the isolation baseline automatically.

**RISK R-003 (CRITICAL):** an RLS resolver/policy bug would leak cross-tenant data. A **human RLS/security sign-off** is mandated before real tenant data is served; this branch's new tables ship with cross-tenant pgTAP isolation tests but still require that sign-off.

## 2. One app per restaurant, or one shared SaaS? — **One shared multi-tenant SaaS**

**One shared backend + one app codebase per role** (POS, KDS, owner dashboard, platform admin). **Never** one database or one app per restaurant. Each restaurant's organization is a tenant inside the same backend, isolated as in §1. This matches **D-002/D-003** and the existing schema, and is the architecture RF-150 mandates. The pilot may run a single org/branch, but no schema, query, RLS policy, or app assumes a single tenant.

## 3. How owner signup creates an organization

Already implemented as **`app.create_organization`** (RF-090, [API_CONTRACT.md](API_CONTRACT.md) §4):

- Caller is derived **only** from `auth.uid()` (a Supabase Auth principal); never from input.
- Bootstraps the caller's `app_users` row (from the verified `email` JWT claim) if absent.
- Atomically creates **organization → first restaurant → first branch (+ optional default station) → the first `org_owner` membership → an `organization.created` audit event**.
- Idempotent per `(created_by_app_user_id, creation_request_id)`; a retried signup returns the same org; conflicting reuse fails clearly.
- Never accepts `role` / `app_user_id` / `organization_id` / platform input; **never** grants `platform_admin` (**D-026**); no shared accounts (**D-004**).

**The only missing piece for clients: reachability.** The `app` schema is not exposed to the Data API (`config.toml [api].schemas = ["public","graphql_public"]`), so PostgREST builds no endpoint for `app.create_organization`. **This branch adds `public.create_organization`** — a thin `SECURITY INVOKER` pass-through (the proven RF-064/123/124/125/126 pattern) granting no new privilege. After this, a Supabase-authenticated client can self-serve an organization. (The onboarding **screen** in the dashboard app is still deferred — see §9.)

## 4. How users / memberships / roles work

Six **identity concepts** are kept distinct (**D-005**): user identity (`app_users`, global, no `organization_id`), membership (`memberships`), employee profile (`employee_profiles`), device identity (`devices`), device session (`device_sessions`), human PIN session (`pin_sessions`). **No shared accounts** (**D-004**).

Roles are **membership-scoped** (never a global role on the user). Role keys (exact): `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant` (read-only, **D-028**). **`platform_admin` is NOT a membership role** — it is a separate, audited grant in `platform_admin_grants` carrying no `organization_id` (**D-026**), checked only by `app.is_platform_admin()` and never referenced by any tenant RLS policy.

Cashiers/kitchen authenticate on a **paired, authorized device** via a personal employee identity + PIN-based fast session (`app.start_pin_session`, RF-051) — never a shared restaurant password (**D-006**). Owners/managers/accountants authenticate via Supabase Auth (JWT) and act through membership-gated RPCs (e.g. menu CRUD, and the new printer-config RPCs). MFA is gated for privileged roles (`app.require_mfa_for_privileged`, RF-050); the concrete MFA method is **OPEN QUESTION Q-008**.

## 5. How branch / station / device pairing works

- **Branches/stations** are created at onboarding (first branch) and via management RPCs thereafter. `stations` are KDS/prep stations within a branch.
- **Device pairing/provisioning** is implemented (RF-112): `devices`, `device_pairings` (short-lived expiring enrollment codes), `device_activation_sessions`, `device_sessions`. A POS/KDS device gets a **device identity** with limited permissions; **no service-role credentials live in clients** (**D-011**). Device lifecycle (`code_issued → pending → paired → active → suspended → revoked`) is owned by [STATE_MACHINES.md](STATE_MACHINES.md); revocation propagation is RF-061.
- A human then layers a **PIN session** on the active device session (RF-051), resolving the membership/role used for all subsequent operations.
- **SECURITY (R-007):** a revoked/suspended device must lose future access, including across the offline window (**Q-009**, ASSUMPTION ≤ 8 h cached PIN session).

## 6. POS → KDS → Dashboard / Admin data flow

```
POS (offline outbox)
  → public.sync_push(pin_session, device, operations[])   ── RF-126 wrapper → app.sync_push (RF-056)
        per op dispatch: shift.open / order.submit / order.discount / payment.create / shift.close
        → app.open_shift / submit_order / apply_discount / record_payment / close_shift (RF-052/53/54/55)
        money + receipt numbers stay SERVER-AUTHORITATIVE (integer minor units, D-007/D-008; per-branch monotonic receipt, D-021)
        idempotency ledger: (organization_id, device_id, local_operation_id)  (D-022)

KDS
  → public.sync_pull(pin_session, device, entities[], cursors)  ── RF-064 wrapper → app.sync_pull (RF-057/059)
        kitchen_staff: only orders / order_items / order_item_modifiers, EVERY *_minor + receipt field redacted (T-003)
        per-entity (updated_at, id) cursors; tombstones inline via deleted_at (D-020)

Dashboard (owner)
  → RLS-scoped rollup views (RF-075/092): daily_branch_sales_report, dashboard_org/restaurant_daily_sales
        integer-minor aggregates, organization-scoped by RLS

Platform admin
  → public.platform_admin_* (RF-091/125) → app.platform_admin_* (self-gated by is_platform_admin, reason-tagged, audited on the SEPARATE platform plane)
```

Kitchen "tickets" are a **projection of orders/order_items** delivered via `sync_pull` (money-redacted), not a separate persisted table. Supabase Realtime is an **enhancement only** (RF-058 hints), never the source of truth (**D-010**).

## 7. How printer configuration works (this branch — Phase 8)

The frozen [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md) defines the direction: every hardware entity is tenant-scoped (`organization_id` + `restaurant_id`/`branch_id`/`station_id`); printing sits behind a **replaceable adapter**; the local **print spool (`print_jobs`) stays on-device** (Drift/SQLite) and is *not* cloud-synced. What is genuinely a **backend** concern — and was entirely missing — is the **configuration**: which printers exist, how they connect, and which station routes to which printer.

This branch adds (additive, forward-only migration + RLS + RPCs + pgTAP):

- **`printer_devices`** — per branch: `display_name`, `connection_type ∈ {network, usb, bluetooth}`, `role ∈ {receipt, kitchen}` (roles, not SKUs — spec §2), `paper_width ∈ {58mm, 80mm}` (spec §4, default 80mm), `connection_config jsonb` (e.g. `{host,port}` for network; LAN-only, no tenant data — spec §3 SECURITY), `is_enabled`, `revision`, timestamps + `deleted_at`. Composite same-org FK to `branches`.
- **`printer_routes`** — maps a `station_id` → a kitchen `printer_devices` row (per-branch routing, spec §6), `is_enabled`, timestamps + `deleted_at`. Composite same-org FKs to both `stations` and `printer_devices` (same-branch enforced structurally).
- **RLS** — enable + force; SELECT scoped by `org + has_scope`; direct writes denied; **writes are owner/manager-only via SECURITY DEFINER RPCs** (`app.upsert_printer_device`, `app.set_printer_route`, soft-delete), mirroring the RF-109 menu-management pattern (`*_guard` raises 42501 on structural failure, returns a committed `*_denied` audit + `{ok:false}` on role-denial). Thin `public.*` `SECURITY INVOKER` wrappers make them Data-API-reachable.
- **Audit** — every printer-config mutation appends an `audit_events` row (**D-013**).

**Honest boundary:** this is **configuration only**. No native print transport, no drawer kick, no "printing succeeded" claim — those remain deferred behind the adapter (**Q-006/Q-015**). A future native local print bridge consumes this config.

## 8. What demo code remains (dev/test only)

Demo data/repositories remain for **local development, tests, and seeded preview**, never as the implied production path:

- POS/KDS demo fixtures (demo menu, demo tickets) and the `Demo*` repositories.
- Dashboard `DemoOwnerReportsRepository`, admin demo source — used by widget tests and the offline preview.
- The mode seam is `runtimeConfigProvider` (`isDemoMode`); `Real*` repositories already exist for the real path and fail closed without a session.

RF-150 keeps these as **explicit fake/seed implementations** behind the mode seam. It does **not** delete them (they back the test suites and the offline demo). Flipping the *default* to real-first is gated on the client login flow (§9) and is **not** done in this branch.

## 9. Implemented in this branch vs deferred

**Implemented (this branch):**
1. This plan (Phase 1).
2. `public.create_organization` onboarding wrapper + pgTAP (Phase 3 backend enabler).
3. Printer configuration foundation — tables, RLS, owner/manager RPCs, public wrappers, pgTAP isolation/authorization tests (Phase 8).

**Deferred (with rationale), to be their own tickets:**
- **Client real-mode login + device-pairing + PIN UI** and flipping app defaults to real-first (Phases 3 frontend, 4, 5, 6, 7 client wiring). The backend + `Real*` repositories exist; the missing work is the Supabase-Auth login screen, device enrollment UX, PIN entry, org/branch selection, and the AAL2/MFA UX. Large; partly human-gated by **Q-008** (MFA method) and **Q-009** (offline window); and blocked on the **R-003 human RLS sign-off** before real tenant data is served.
- **Demo removal / real-first startup (Phase 9).** *Unsafe today:* without the login flow, real-first startup shows fail-closed empty/error screens with no way to authenticate — a regression. Must follow the client login wiring.
- **App-level end-to-end tests (Phase 10).** The DB-level isolation chain is already proven by the pgTAP suite (incl. cross-tenant denial, kitchen redaction, idempotency). A full app-driven E2E needs the client real-mode wiring first; the existing [M6_FINAL_QA_ISOLATION_RUN_GUIDE.md](M6_FINAL_QA_ISOLATION_RUN_GUIDE.md) is the manual analog.
- **Hardware printing transport + drawer kick** (Q-006/Q-015), card/online payments, refunds, inventory — out of scope.

## 10. Security assumptions & RLS rules

- **Deny-by-default everywhere.** No tenant context (`app.current_org_id()` NULL) ⇒ zero rows. New printer tables follow the RF-059 per-command policy shape and are caught by the RF-019 default-deny detector.
- **Writes are RPC-only.** Direct `authenticated` INSERT/UPDATE/DELETE on tenant/management tables is revoked + policy-denied; all mutations go through SECURITY DEFINER RPCs that authorize (membership/role/scope) and audit. New printer-config writes are owner/manager-only (`org_owner`/`restaurant_owner`/`manager`); `cashier`/`kitchen_staff`/`accountant` are denied (committed `_denied` audit).
- **No service-role credentials in clients** (**D-011**); clients use the anon key + an authenticated JWT and reach the backend only through `public.*` wrappers. New public surface is `SECURITY INVOKER` (no privilege escalation) and granted to `authenticated` only (never `anon`).
- **Money is integer minor units only** (**D-007/D-008**); printer config touches no money. Kitchen sees no money (**T-003**) — unchanged.
- **Platform admin is separate + audited** (**D-026**) — never a tenant membership, never in tenant RLS.
- **Structural cross-tenant prevention** via composite same-org FKs (**D-012** layer 4) — extended to the new printer tables/routes.
- **Mandatory human RLS/security sign-off (R-003)** before serving real tenant data; **PROPOSED** new public surfaces (onboarding wrapper) are change-controlled (own ticket + pgTAP + independent review + human approval), consistent with RF-125/126.

## 11. Validation

All DB work is validated locally with `supabase test db` (baseline at branch start: **151 files / 2208 assertions / PASS**). New pgTAP suites added for the onboarding wrapper and the printer configuration (schema, constraints, cross-tenant isolation, role authorization). Flutter suites (`apps/*`, `packages/*`) remain green; this branch adds no app-layer behavior change. No production database, secrets, or destructive action is involved.
