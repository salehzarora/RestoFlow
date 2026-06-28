# M7 Backend Contract Notes — ratified contracts + Agent B integration spec

> **STATUS — RATIFIED BACKEND BASELINE (Agent A, M7 backend worktree).** This
> document is the committed hand-off Agent B (client worktree
> `RestoFlow-m7-client`) codes against. It **ratifies** the existing backend
> contracts against the real SQL (with `file:line` evidence), records the two new
> backend changes (the **RF-125 platform-admin public wrapper**, PROPOSED
> **DECISION D-035**; and the **RF-126 `public.sync_push` POS write wrapper**,
> PROPOSED **DECISION D-036** — which **unblocks the POS write path**), registers
> **contract drift**, and gives Agent B a precise
> **DI / config-switch + mock-test spec**. It **references** the canon; it never
> overrides it: contracts are owned by [API_CONTRACT.md](API_CONTRACT.md),
> decisions by [DECISIONS.md](DECISIONS.md), isolation by
> [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md), and the seam map
> by [M7_REAL_BACKEND_WIRING_HANDOFF.md](M7_REAL_BACKEND_WIRING_HANDOFF.md) (§A).
>
> Binding rules carried from the handoff §3: **demo mode stays default + working;
> no false live-data claims; money is integer minor units (D-007); platform admin
> is read-only (D-026); no service-role key in any client (D-011); no RLS bypass.**

---

## 1. Exposure model (read this first)

Clients reach the database **only** through PostgREST (the Supabase Data API)
with the **anon key + an authenticated JWT** — never a service-role key
(**D-011**). PostgREST exposes **only** the schemas in
`supabase/config.toml` → `[api].schemas = ["public","graphql_public"]`
(`supabase/config.toml:13`). The **`app` schema is deliberately NOT exposed**, so
a client can call an `app.*` RPC **only** if a thin **`public.*` `SECURITY
INVOKER` wrapper** exists. Three states a contract can be in:

| State | Meaning for Agent B |
|---|---|
| **callable-today** | A `public.*` function/view exists and is granted to `authenticated`. Wire it. |
| **needs-public-wrapper** | The capability exists only as `app.*` (unexposed). Agent A must add a `public.*` wrapper **before** Agent B can wire it — **do not** attempt to call `app.*` directly; it has no HTTP route. |
| **new-wrapper-added (PROPOSED)** | Agent A added the wrapper on a backend branch (RF-125 platform-admin; **RF-126 `public.sync_push`**). Agent B may wire it **only after** it is **committed and merged** (handoff §7, dependency rule). |

---

## 2. Per-capability CONTRACT notes

Format per capability: **name · schema · input params · output shape · auth ·
RLS · demo vs real · callable by app client · tests · Agent B: use now / wait.**

### 2.1 AUTH / SESSION (DECISION D-029) — **callable-today**

**CONTRACT: `public.get_my_context()`**
- **schema:** `public` (`SECURITY INVOKER`) → `app.get_my_context` (`SECURITY DEFINER`, source of truth).
- **input params:** **none.** Identity is always `auth.uid()` via `app.current_app_user_id()` — **never** an argument (D-004/D-005).
- **output shape:** `jsonb { ok, app_user:{id,email,display_name,is_active}, is_platform_admin:bool, memberships:[{id, organization_id, organization_name, restaurant_id?, restaurant_name?, branch_id?, branch_name?, role(one of six keys), status}] }`. `memberships` is a **LIST** (multi-membership), `[]` when none; no top-level global role; `is_platform_admin` is a **separate boolean** carrying no `organization_id` (D-026). No money fields.
- **auth:** `authenticated` JWT only. Fails closed `42501` for unauthenticated / unlinked / inactive principal.
- **RLS:** returns **only** the caller's own `app_users` row + only the caller's `active`, non-tombstoned memberships; a membership whose org/restaurant/branch parent is soft-deleted is **excluded** (RF124-B1). `SECURITY DEFINER` only to bypass per-org name-RLS for the name joins; strict self-filter preserves isolation (D-001/R-003).
- **demo vs real:** *Real:* call with no args to resolve identity + membership list for tenant-scope routing; cache for the offline window. *Demo:* synthesize context locally (no network). No SQL auth bypass — anon/unlinked is rejected.
- **callable by app client:** `authenticated` = **yes**; `anon` = no; `app.*` source = not client-reachable.
- **tests:** `rf124_get_my_context_resolver_test.sql` (pre-existing, green at last reset).
- **Agent B:** **use now.** Evidence: `…rf124…sql:134-147`, `:33-119`; `API_CONTRACT.md` §4.22.

**CONTRACT: `public.start_pin_session(p_device_session_id uuid, p_employee_profile_id uuid, p_pin_verifier text, p_local_operation_id text default null)`**
- **schema:** `public` (`SECURITY INVOKER`) → `app.start_pin_session` (`SECURITY DEFINER`).
- **input params:** the four above (same types/order as the app source).
- **output shape:** bare **`uuid`** = the PIN session id. **NOT jsonb.** **Wrong PIN ⇒ `NULL`** (no row, no error); structural / precondition / lockout failures ⇒ **`42501`**. Two distinct failure modes.
- **auth:** `authenticated` JWT only; inner RPC validates active device session + active pairing + device match + active in-org employee/membership + lockout. Idempotent replay keyed on `(org, device_session, employee, resolved_membership, local_operation_id)`.
- **RLS:** identity/scope derived server-side; resolved membership must cover the device-session scope; cross-org/branch ⇒ `42501`. Direct `INSERT` on `pin_sessions` is revoked — a session is establishable **only** via this RPC.
- **demo vs real:** *Real:* establish a PIN session against a real `device_session_id` + employee + PIN verifier. **Caveat:** the verifier check is an **interim dev seam** (plaintext-equality against `employee_profiles.pin_credential_ref`), **not production crypto** — salted-hash is deferred; do not present it as production-grade. *Demo:* simulate a local PIN session.
- **callable by app client:** `authenticated` = **yes**; `anon` = no.
- **tests:** `rf123_public_start_pin_session_wrapper_test.sql` (pre-existing, green).
- **Agent B:** **use now.** Evidence: `…rf123…sql:37-64`; `…rf051…sql:290-474`; `API_CONTRACT.md` §4.21.

### 2.2 POS WRITE PATH (submit / payment / outbox) — **new-wrapper-added (RF-126, PROPOSED D-036)**

> **RESOLVED (was the critical blocker).** The POS write path was entirely closed
> to clients — `app.submit_order`, `app.record_payment`, and `app.sync_push` all
> live in the **unexposed `app` schema**, and the handoff §2/§6 had wrongly assumed
> `sync_push` was reachable. **RF-126 (this backend track) adds the missing
> `public.sync_push` wrapper** (PROPOSED **DECISION D-036**), giving the POS its
> single, narrow write/outbox entry point. The dispatched mutators
> (`submit_order`/`record_payment`/`apply_discount`/`open_shift`/`close_shift`) are
> **deliberately NOT individually wrapped** — they stay reachable **only** through
> the `sync_push` dispatcher, behind its full validation. Agent B may wire POS real
> submit/payment (handoff ticket #4) **once RF-126 is committed AND merged**.

**CONTRACT (NEW): `public.sync_push(p_pin_session_id uuid, p_device_id uuid, p_operations jsonb)`** — *the offline reconciliation / POS write entry point*
- **schema:** `public` (`SECURITY INVOKER`, **VOLATILE** → POST-routed) → `app.sync_push` (`SECURITY DEFINER`, source of truth, RF-056). Faithful pass-through — same params/types/order, same `jsonb` return; no transformation, no added privilege.
- **input params:** `p_pin_session_id`, `p_device_id`, `p_operations jsonb` (ordered envelope array; each op: `local_operation_id` (required), `operation_type ∈ {shift.open, order.submit, order.discount, payment.create, shift.close}`, `payload` (object, required), optional `depends_on[]`, `target_entity`, `target_id`, `client_created_at`). Batch cap **100 ops** (interim). Per-op `payload` keys by type — e.g. `order.submit`: `{order_id, order_type, table_id?, shift_id?, currency_code, notes?, order_items:[{menu_item_id, quantity, unit_price_minor_snapshot, menu_item_name_snapshot, modifiers?:[…]}], subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor}`; `payment.create`: `{order_id, tender_type:'cash', amount_tendered_minor, provisional_receipt_number?, expected_revision?}`; `shift.open`: `{shift_id, cash_drawer_session_id, opening_float_minor}`.
- **output shape:** `jsonb { ok:true, results:[ per-op {local_operation_id, operation_type, ok, status ∈ created/pending/in_flight/applied/rejected/dead/conflict/resolved, error?, idempotency_replay, …dispatched-RPC fields on applied} ], server_ts }`. **Per-operation, not all-or-nothing:** one failed op never rolls back applied ops; a malformed/unknown/unauthorized op comes back `status:'rejected'` while the batch envelope stays `ok:true`.
- **auth:** `authenticated` JWT only; `anon`/public **revoked** (no anon writes). Inside the unchanged `app.sync_push`: valid PIN session + active device/pairing + **device match** validated once for the whole batch (revoked/expired device fails the **whole** batch, R-007); org/restaurant/branch derived **server-side** (never from payload); each op re-authorized by its dispatched `SECURITY DEFINER` RPC with the **same** session+device.
- **RLS / idempotency:** `sync_operations` enable+force, org+scope policy; direct writes revoked (written only by the definer). **Exactly-once** transport identity `unique(organization_id, device_id, local_operation_id)` (D-022) — a replay returns the stored result (`idempotency_replay:true`) without re-dispatching, no duplicate payment, no receipt-counter advance. Money authority (integer minor, server-recomputed totals, server-allocated per-branch `receipt_number`) stays in the dispatched RPCs (D-007/D-008/D-021).
- **expected errors:** whole-batch `42501` for a bad/expired/absent PIN session, a device mismatch, a revoked device/pairing, or a non-array `p_operations`. Per-op (batch still `ok:true`): `invalid_envelope`/`invalid_payload`/`unknown_operation_type`/`invalid_depends_on` (rejected, no ledger row), `dependency_not_ready` (pending, retryable), business-rule failures → `rejected`, optimistic-concurrency `40001` → `conflict`.
- **demo vs real:** *Real:* the outbox drainer batches queued envelopes and `public.sync_push`es them; server dedups/replays via the ledger, checks `depends_on`, dispatches. *Demo:* keep ops in a local outbox; never push.
- **callable by app client:** `authenticated` = **yes** (once merged); `anon` = no; `app.*` source = not client-reachable. The mutators are dispatcher-only — there is no `public.submit_order`/`record_payment`/etc.
- **tests:** `rf126_public_sync_push_wrapper_test.sql` — **36/36 pass** (introspection/grants/`INVOKER`/`VOLATILE` + narrowness guard + whole-batch `42501` gate preserved through the wrapper + a **real** `shift.open→order.submit→payment.create` applied flow with integer-minor money, server-authoritative receipt number, idempotent replay, per-op reject of malformed/unknown/unauthorized ops, and a shared-ledger cross-delegation proof). Plus pre-existing `rf056_*` app-level coverage.
- **Agent B:** **WAIT until RF-126 is committed AND merged** to `main` (handoff §7 + the dependency rule). On this branch the wrapper exists and is green. Meanwhile build the real `OutboxRepository`/`PaymentRepository` **interfaces + mocks** against the envelope shape above; flip to the live `public.sync_push` call after merge. End-to-end also needs the client auth foundation (authenticated JWT + an established PIN session on a paired+active device).

**Dispatched-RPC contracts (reached only via `sync_push`; NOT individually wrapped):**
- **`app.submit_order(p_pin_session_id, p_order_id, p_device_id, p_local_operation_id, p_order_type, p_table_id, p_shift_id, p_currency_code, p_notes, p_order_items jsonb, p_client_subtotal_minor bigint, p_client_discount_total_minor bigint, p_client_tax_total_minor bigint, p_client_grand_total_minor bigint, p_client_created_at timestamptz default null)`** → `jsonb {ok, order_id, revision, server_ts, idempotency_replay}`. Integer-minor money only (`app.order_parse_minor` rejects float/negative); server **recomputes** totals from submitted snapshots (anti-tamper, D-008); idempotency on `device_id+local_operation_id` (D-022); `receipt_number` stays NULL until payment (RF-054). Reached via the `order.submit` op. Evidence `…rf052…sql:268-289,426-452`.
- **`app.record_payment(p_pin_session_id, p_order_id, p_device_id, p_local_operation_id, p_tender_type('cash'), p_amount_tendered_minor bigint, p_provisional_receipt_number text default null, p_expected_revision integer default null)`** → `jsonb {ok, payment_id, order_id, receipt_number, change_due_minor, shift_id, cash_drawer_session_id, payment_revision(=1), order_revision, server_ts, idempotency_replay}`. **Server allocates the authoritative per-branch monotonic `receipt_number`** under a row lock (D-021); integer change `= tendered − payable ≥ 0` (D-007). Non-authorized role ⇒ `{ok:false, error:'permission_denied'}` + audited (no raise). Requires an open shift + active drawer (RF-062). Reached via the `payment.create` op. Evidence `…rf054…sql:238-251,391-427`.

### 2.3 KDS POLLING (sync_pull) — **callable-today** (⚠️ shape correction)

**CONTRACT: `public.sync_pull(p_pin_session_id uuid, p_device_id uuid, p_entities text[] default null, p_cursors jsonb default '{}'::jsonb, p_limit integer default 500)`**
- **schema:** `public` (`SECURITY INVOKER`) → `app.sync_pull` (`SECURITY DEFINER`).
- **input params:** the five above. `p_entities` null ⇒ all role-permitted entities. `p_limit` rejected if `≤0` or `>1000` (`42501`); `p_cursors` must be a JSON object.
- **output shape — ⚠️ NOT `{entities, tombstones, cursors}`:** `jsonb { ok, server_ts, changes:{ <entity>:{ rows:[…], next_cursor:{updated_at,id}|null, has_more:bool } }, operation_statuses:{ rows, next_cursor, has_more } }`. **Tombstones are inline rows with `deleted_at` set** (D-020); the **cursor is per-entity `next_cursor {updated_at,id}`** (no global revision/`change_seq`); `server_ts` is top-level; `operation_statuses` is an extra current-device outbox-reconciliation feed. The handoff's `{entities, tombstones, cursors}` description is **wrong** — code against the shape here.
- **auth:** `authenticated` JWT only; inner RPC requires valid PIN session + active device/pairing + device match + active membership; `42501` on revoked-device / expired-PIN / device mismatch.
- **RLS:** scope (org/branch) + actor + role derived server-side from the `pin_sessions` row, never from payload. Operational pager filters `organization_id = session org AND branch_id = session branch`; `operation_statuses` filters current-org + current-device.
- **Kitchen money redaction (T-003 / D-007):** for `kitchen_staff`, only non-financial operational entities `orders` / `order_items` / `order_item_modifiers` are permitted (a kitchen request for any financial or menu entity ⇒ `42501`), and every returned row is passed through `app.redact_money` which strips any key matching `(^|_)minor($|_)` (catches `amount_minor`, `unit_price_minor_snapshot`, etc.) plus `receipt_number`/`receipt_provisional_id`. **A KDS client therefore pulls money-free `orders`/`order_items`/`order_item_modifiers` only**, and derives item names from non-money `*_snapshot` keys.
- **demo vs real:** *Real:* call `public.sync_pull` over PostgREST, apply `changes`/tombstones to local Drift, advance per-entity cursors. *Demo:* serve a fixture/seeded feed. Polling-first (D-010); Realtime (RF-058) is **enhancement-only** money-free invalidation hints on `kds:branch:{branch_id}` — never the source of truth, and a hint grants no data (the KDS must still `sync_pull`).
- **callable by app client:** `authenticated` = **yes**; `anon` = no.
- **tests:** `rf064_public_sync_pull_wrapper_test.sql` (incl. redaction-through-wrapper, green).
- **Agent B:** **use now.** Evidence: `…rf064…sql:34-62`; `…rf109_menu_sync_pull…sql:173-315`; `…rf059…sql:142-165` (redaction).

### 2.4 OWNER DASHBOARD REPORT VIEWS (RF-075 / RF-092) — **callable-today**

All five are `security_invoker = true` views → base-table RF-059 SELECT applies
**as the caller** via `app.can_read_financials(org,restaurant,branch)` (roles
`cashier/manager/restaurant_owner/org_owner/accountant`; **`kitchen_staff`/KDS/
cross-tenant get ZERO rows**). All money columns are integer `_minor` SUMs of
persisted columns — never recomputed (D-007/D-008). `grant select to
authenticated`; `anon` revoked. Writes are impossible (aggregating views). **Use
now.**

| View | Grain | Money columns (all `_minor`) |
|---|---|---|
| `public.daily_branch_sales_report` | `(org, restaurant, branch, business_day, currency)` | gross, discount_total, net_sales, tax_total, void_total, collected_total, collected_cash |
| `public.daily_branch_shift_lines` | per shift | expected_total, counted_total, variance, opening_float |
| `public.daily_branch_void_discount_reasons` | per void/discount audit row | discount_value (explicit `can_read_financials` guard in-view) |
| `public.dashboard_org_daily_sales` | `(org, business_day, currency)` | summed buckets above (+ restaurant_count, branch_count) |
| `public.dashboard_restaurant_daily_sales` | `(org, restaurant, business_day, currency)` | summed buckets (+ branch_count) |

- **demo vs real:** *Real:* `SELECT` the RLS-scoped view (filter by `business_day`/`branch_id` in `WHERE`). *Demo:* `DemoOwnerReportsRepository` computes a synthetic dataset client-side; the view SQL is real-only.
- **tests:** `rf075_*`, `rf092_*` (green). Evidence: `…rf075…sql:42-247`, `…rf092…sql:21-71`; `API_CONTRACT.md` §4.19.

### 2.5 PLATFORM ADMIN (RF-091 panel) — **new-wrapper-added (RF-125, PROPOSED D-035)**

**Underlying app RPCs (read-only, MFA+grant+reason gated, audited):**
`app.platform_admin_organization_overview(p_reason text)`,
`app.platform_admin_get_organization(p_organization_id uuid, p_reason text)`,
`app.platform_admin_recent_audit(p_reason text, p_limit integer default 50)`.
Each: gate = authenticated principal + **ACTIVE `platform_admin_grant`** (D-026,
never a tenant membership — even `org_owner` is denied) + **MFA `aal2`** +
non-empty `reason`; each writes a `platform_admin_audit_events` row (the read is
audited); read-only (no mutation/impersonation/`select *`). Previously
**needs-public-wrapper** (app-schema only, no client entry point).

**CONTRACT (NEW): `public.platform_admin_organization_overview(text)` / `public.platform_admin_get_organization(uuid, text)` / `public.platform_admin_recent_audit(text, integer)`**
- **schema:** `public` (`SECURITY INVOKER`, VOLATILE) → the `app.*` source. Faithful pass-throughs — same params/types/order incl. `p_limit default 50`, same `jsonb` return; no transformation, no added privilege.
- **output shape:**
  - overview → `{ ok, organizations:[{id,name,status,created_by_app_user_id,creation_request_id,restaurants_count,branches_count,active_memberships_count}], server_ts }`
  - get_organization → `{ ok, organization:{id,name,status,default_currency,created_by_app_user_id,creation_request_id,created_at}, restaurants:[{id,name,status,branches_count}], restaurants_count, branches_count, active_memberships_count, server_ts }` (non-existent org ⇒ `42501`)
  - recent_audit → `{ ok, events:[{id,actor_app_user_id,target_organization_id,action,reason,occurred_at}], limit, server_ts }` (newest first, `p_limit` capped `[1,200]`)
- **auth:** `authenticated` JWT **with an `aal2` MFA claim** **and** an active `platform_admin_grant` **and** a non-empty reason — all preserved inside the unchanged `app.*` body. Any miss ⇒ `42501`.
- **RLS:** not tenant-RLS-scoped (the separate platform plane, D-026); cross-tenant reads only after the gate passes; `platform_admin_audit_events` is unreadable by the tenant `authenticated` path.
- **demo vs real:** *Real:* call the `public.platform_admin_*` wrapper with a reason, from a platform-admin session holding `aal2` + an active grant. *Demo:* `DemoPlatformAdminRepository` renders a computed dataset; **read-only** — never wire a mutation (D-026).
- **callable by app client:** `authenticated` (with the credentials above) = **yes**; `anon` = no; a non-admin authenticated caller may *call* but is denied `42501`.
- **tests:** `rf125_public_platform_admin_wrapper_test.sql` — **34/34 pass** (introspection/grants/INVOKER + delegation parity + the full `42501` guard preserved through the wrapper for non-admin / org_owner / blank-reason / missing-`aal2`). Plus pre-existing `rf091_*` app-level tests.
- **Agent B:** **WAIT until RF-125 is committed AND merged** (handoff §7 + the dependency rule). On this branch the wrapper exists and is green, but B must not wire the real `PlatformAdminRepository` until the wrapper lands in `main`. Also note: end-to-end use needs the **platform-admin `aal2` MFA + active-grant sign-in flow**, which no client wires yet.

---

## 3. Contract-drift register (API_CONTRACT.md §4 vs real SQL)

| # | Drift | Where | Action |
|---|---|---|---|
| D1 | **POS write path had no public surface.** §4.14 calls `sync_push` "the offline reconciliation entry point" and §4.1/§4.7 push orders/payments via it, but there was **no `public.sync_push`** (and no `public.submit_order`/`record_payment`); the client write path was closed. | `API_CONTRACT.md` §4.1/§4.7/§4.14; `config.toml:13` | **Fixed on the RF-126 branch** — `public.sync_push` added (PROPOSED **D-036**, §2.2), §4.14 now carries the Data-API-exposure note. Unblocks handoff ticket #4 once RF-126 merges. |
| D2 | **`sync_pull` return shape.** §4.15 prose ("changed entities, tombstones, and a new cursor/revision watermark") implies `{entities, tombstones, cursors}`; real shape is `{ok, server_ts, changes:{<entity>:{rows,next_cursor,has_more}}, operation_statuses}` with inline `deleted_at` tombstones and per-entity cursors (no global revision). | `API_CONTRACT.md:316` | Code against §2.3 here. Optional doc-polish note on §4.15. |
| D3 | **PIN-session audit not emitted.** §4.13/§4.21 promise `pin_session.started` + rate-limited failed-attempt audit events; `app.start_pin_session` writes **no `audit_events`** row. | `API_CONTRACT.md:293,364`; `…rf051…sql:290-474` | Follow-up ticket to wire the audit, or mark forward-looking. Not blocking M7 client wiring. |
| D4 | **Platform-admin RPCs had no documented wrapper.** §4.16/§4.18 documented only the `app.*` RPCs. | `API_CONTRACT.md` §4.18 | **Fixed on this branch** — added the RF-125 Data-API-exposure note (§4.18). |
| D5 | **Interim PIN verifier.** §4.13/§4.21 don't foreground that PIN matching is plaintext-equality (dev seam), not salted-hash. | `…rf051…sql:157-175` | Transparency note; salted-hash deferred. Don't claim production-grade PIN. |
| D6 | **"service-role rejected with 42501" wording.** Deny is by absence-of-grant (insufficient_privilege), not an in-body check. | `API_CONTRACT.md:361,371` | Cosmetic; behavior is fail-closed and correct. |

Reports (§4.19) and the auth wrappers (§4.21/§4.22) ratify **as-is** — signatures,
columns, scoping, money-`_minor`, and platform separation all match the SQL.

---

## 4. Agent B — DI / config-switch + mock-test SPEC (blueprint, no `apps/**` edits here)

> This is a **specification** for Agent B to implement in the client worktree.
> It describes the intended structure in prose + illustrative snippets only;
> Agent A does **not** create any `apps/**` file. Every `Demo*` repo stays; a
> `Real*` is added beside it and selected by mode. Seam locations are from the
> handoff §A.

### 4.1 Mode gate + config (one source of truth)

A single `RestoFlowConfig` resolved from `--dart-define`s, default **demo**:

```dart
// packages/<core>/lib/src/config/restoflow_config.dart  (Agent B)
class RestoFlowConfig {
  final bool demoMode;          // RESTOFLOW_DEMO_MODE, default TRUE
  final String? supabaseUrl;    // RESTOFLOW_SUPABASE_URL   (real mode only)
  final String? supabaseAnonKey;// RESTOFLOW_SUPABASE_ANON_KEY (anon/publishable ONLY)

  static RestoFlowConfig fromEnv() {
    const demo = bool.fromEnvironment('RESTOFLOW_DEMO_MODE', defaultValue: true);
    const url  = String.fromEnvironment('RESTOFLOW_SUPABASE_URL');
    const key  = String.fromEnvironment('RESTOFLOW_SUPABASE_ANON_KEY');
    // Honesty + safety: real mode requires BOTH url and anon key, else fall back
    // to demo and surface a clear "demo (real backend not configured)" label.
    final realReady = !demo && url.isNotEmpty && key.isNotEmpty;
    return RestoFlowConfig(demoMode: !realReady, supabaseUrl: ..., supabaseAnonKey: ...);
  }
}
```

Rules: **never** read or accept a `service_role` key (D-011) — assert/strip any
key whose JWT `role` claim is `service_role`. Real mode is opt-in:
`--dart-define=RESTOFLOW_DEMO_MODE=false --dart-define=RESTOFLOW_SUPABASE_URL=… --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=…`.

### 4.2 Supabase client + transport seam

```dart
final restoFlowConfigProvider = Provider<RestoFlowConfig>((_) => RestoFlowConfig.fromEnv());

// Real mode only: anon key + the signed-in user's JWT. No service-role.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  final c = ref.watch(restoFlowConfigProvider);
  if (c.demoMode) return null;          // demo never constructs a network client
  return SupabaseClient(c.supabaseUrl!, c.supabaseAnonKey!);
});
```

Wrap all PostgREST/RPC calls behind a thin `BackendApi` (testable seam): methods
like `rpc(name, params)` and `selectView(view, filters)` so `Real*` repos depend
on `BackendApi`, and tests inject a **mock `BackendApi`** (no live network).

### 4.3 Per-seam wiring map (override the existing providers by mode)

For each provider below: `if (config.demoMode) return Demo…(); else return Real…(backendApi, …);`

| App | Provider (swap point) | Demo (unchanged) | Real (new) → backend contract | Wire when |
|---|---|---|---|---|
| POS | `paymentRepositoryProvider` (`apps/pos/lib/src/state/payment_controller.dart`) | `DemoPaymentStore` | `RealPaymentRepository` → `public.sync_push` (`payment.create`→`app.record_payment`) | **WAIT for RF-126 merged** (then ready) |
| POS | `outboxRepositoryProvider` (`apps/pos/lib/src/state/outbox_controller.dart`) | `DemoOutboxStore` | `RealOutboxRepository` → `public.sync_push` (`order.submit`→`app.submit_order`) | **WAIT for RF-126 merged** (then ready) |
| POS | `tablesRepositoryProvider` (`apps/pos/lib/src/state/order_setup_controller.dart`) | `DemoTablesStore` | `RealTablesRepository` → RLS-scoped `public` table/`sync_pull` | after auth foundation |
| KDS | `kitchenOrdersRepositoryProvider` (`apps/kds/lib/src/state/kitchen_orders_controller.dart`) | `DemoKitchenOrdersStore` | `RealKitchenOrdersRepository` → `public.sync_pull` (orders/order_items, money-free) | **after auth foundation — ready now** |
| KDS | `kdsSyncSourceProvider` (`packages/feature_kitchen/lib/src/kds_providers.dart`; override in `apps/kds/lib/main.dart`) | board fallback | real `KdsSyncCoordinator` polling `public.sync_pull` | **ready now** |
| Dashboard | `ownerReportsRepositoryProvider` (`apps/dashboard/lib/src/state/dashboard_providers.dart`) | `DemoOwnerReportsRepository` | `RealOwnerReportsRepository` → SELECT the 5 RLS views (§2.4) | **ready now** |
| Admin | `platformAdminRepositoryProvider` (`apps/admin/lib/src/state/platform_admin_providers.dart`) | `DemoPlatformAdminRepository` | `RealPlatformAdminRepository` → `public.platform_admin_*` (read-only) | **WAIT for RF-125 merged** |
| All | `AuthGatedHome` + `authDemoModeEnabled()` (`packages/feature_auth`) | demo bypass | Supabase Auth JWT + `public.get_my_context` routing; `public.start_pin_session` | **ready now (start here)** |

### 4.4 UI loading / error / empty states

The seams are already async. For real-mode failures add states: a `42501` →
"not permitted / session expired" (re-auth), a network error → retry, an empty
result → honest empty state. **Honesty rule:** show a "demo data" label whenever
`config.demoMode` is true (incl. the real-not-configured fallback); show real
data only when truly wired + verified.

### 4.5 Mock-test plan (no live network)

- **Auth:** mock `BackendApi.rpc('get_my_context')` to return the documented jsonb; assert routing chooses the right membership scope; assert unlinked/`42501` → re-auth. PIN: assert wrong-PIN `NULL` vs `42501` are handled distinctly.
- **KDS:** mock `sync_pull` returning the **§2.3 shape** (`changes.orders.rows` + per-entity `next_cursor` + inline `deleted_at` tombstone); assert cursor advance, tombstone removal, and that **no `*_minor` key** is ever read (money-free). Assert `42501` → re-auth.
- **Reports:** mock the view SELECTs; assert integer-minor parsing (no float), branch-vs-org aggregation, empty/zero-row scope.
- **Platform admin (after RF-125 merges):** mock `public.platform_admin_*` jsonb; assert read-only rendering, reason passed, `42501` (no grant / no `aal2`) → clear "platform access denied" state. Never test a mutation.
- **POS (mock now; flip to live after RF-126 merges):** define `RealOutboxRepository`/`RealPaymentRepository` against the `public.sync_push` envelope shape (§2.2) and mock `BackendApi.rpc('sync_push', …)` returning the per-op `results` array; assert integer-minor money end-to-end, idempotency-key (`device_id+local_operation_id`) construction, `idempotency_replay` handling, and per-op `rejected`/`conflict` surfacing (the batch envelope stays `ok:true`). Leave the live push behind the mode gate until RF-126 is merged.
- **Config:** assert demo is default; assert real requires url+anon key (else demo fallback + honest label); assert **no `service_role`** key is ever accepted.

---

## 5. Newly-discovered required backend work — **DONE on the RF-126 branch**

**`public.sync_push` wrapper** — the POS real submit/payment/outbox path (handoff
ticket #4) was **blocked** without it. **Delivered under RF-126** (PROPOSED
**DECISION D-036**) on branch `m7/public-sync-push-pos-write-contract`: a single
faithful `SECURITY INVOKER` pass-through over `app.sync_push` (the same
RF-064/RF-123/RF-124/RF-109/RF-125 pattern), left **VOLATILE** because `sync_push`
is a **write/dispatch** surface (PostgREST POST-routes it; the delegate's
ledger/audit/business writes run in a writable context). Per CLAUDE.md §4 this got
its **own dedicated, change-controlled ticket** (RF-126) with its own DECISION
entry (D-036, drafted before the SQL), pgTAP (`rf126_…`, 36/36), and — pending —
Codex review + human approval at merge; it was **not** folded into RF-125
(read-only) and **not** silently added. The **dispatched mutators were
deliberately not wrapped** (dispatcher-only). Once RF-126 merges, Agent B's POS
real submit/payment/outbox wiring unblocks (§2.2, §4.3, §6).

---

## 6. Dependency summary — what Agent B can start now vs must wait for

**Start now (contracts callable today, on `main`):**
- **Auth/session foundation** — Supabase client (anon key + JWT), `public.get_my_context` routing, `public.start_pin_session`. *Start here; it unblocks the rest.*
- **KDS real polling** — `RealKitchenOrdersRepository` / `KdsSyncSource` over `public.sync_pull` (use the §2.3 shape; money-free).
- **Owner dashboard real reports** — `RealOwnerReportsRepository` over the five RLS views (§2.4).
- **Repository interfaces / DI / mode-switch / mock tests** for **every** seam (incl. POS + platform-admin) — these need no live endpoint.

**Must wait:**
- **Platform-admin real data** — wait until **RF-125 is committed AND merged** to `main` (then wire `RealPlatformAdminRepository`, read-only). End-to-end also needs the platform-admin `aal2` MFA + active-grant sign-in flow.
- **POS real submit / payment / outbox** — the **`public.sync_push` wrapper now exists** (RF-126, PROPOSED D-036, §2.2); wait only until **RF-126 is committed AND merged** to `main`, then wire `RealOutboxRepository`/`RealPaymentRepository` over `public.sync_push`. Build interfaces + mocks meanwhile; the live push is behind the mode gate until merge. End-to-end also needs the client auth foundation (JWT + an established PIN session).

---

## 7. Tests run (Agent A)

**RF-125 baseline:**
- `supabase db reset` — all migrations incl. `20260626120000_rf125_public_platform_admin_wrappers.sql` replay cleanly (exit 0).
- `rf125_public_platform_admin_wrapper_test.sql` — **34/34 pass, 0 failures.**

**RF-126 (`public.sync_push`):**
- `supabase db reset` — all migrations incl. `20260628090000_rf126_public_sync_push_wrapper.sql` replay cleanly (exit 0).
- `rf126_public_sync_push_wrapper_test.sql` — **36/36 pass, 0 failures.**
- The two cross-test exposure guards repointed (RF-126 intentionally wraps `sync_push`): `rf064_…` and `rf123_…` now assert `hasnt_function` on a still-unexposed mutator (`open_shift` / `close_shift`) — both still green.
- Full `supabase test db` suite — **Files=150, Tests=2190, Result: PASS** (no regressions; +1 file / +36 assertions over the RF-125 baseline of 149/2154).
