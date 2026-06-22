-- ============================================================================
-- RF-059 — Full RLS: explicit per-command policies, role/branch/device scoping,
--          kitchen financial isolation, sync_operations lockdown, and a minimal
--          isolated + audited platform-admin path
-- ============================================================================
-- The complete tenant-isolation policy set (RISK R-003, CRITICAL — requires human
-- RLS sign-off). Builds on RF-014..RF-057. Additive and FORWARD-ONLY: it edits NO
-- prior migration file. It DROPS the interim broad `FOR ALL` policies (created in
-- RF-014/015/016/017/051/052/053/054/055/056) and RECREATES them as EXPLICIT
-- per-command SELECT / INSERT / UPDATE / DELETE policies (the established RF-015
-- "drop + recreate a prior table's policy in a later migration" pattern), tightens
-- direct-write grants, adds role-aware read helpers, redacts money from KDS reads,
-- and lays a separate audited platform-admin path.
--
-- APPROVED DECISIONS (RF-059; human-approved A1..A6)
--   * A1: explicit per-command policies (no broad FOR ALL); self-documenting + testable.
--   * A2: REVOKE direct INSERT/UPDATE/DELETE from `authenticated` on the sensitive
--     MANAGEMENT tables (memberships, employee_profiles, devices, device_pairings,
--     device_sessions, organizations, restaurants, branches, stations) — closing the
--     membership/device self-escalation hole. Management/provisioning writes become
--     RPC-only in a FUTURE ticket. (NOT role-gated here.)
--   * A3: kitchen money-column redaction NOW. kitchen_staff must not read ANY money
--     figure — financial tables (direct), order/order_item/order_item_modifier money
--     columns, and sync_pull output for kitchen_staff. Any `*_minor`/receipt field is
--     stripped for kitchen. Non-kitchen financial roles still receive full data.
--   * A4: do NOT add an app.current_device_id GUC. Deny direct `authenticated` SELECT
--     on sync_operations; current-device status stays via RF-057 sync_pull
--     operation_statuses (already current-device filtered).
--   * A5: no new JWT org claim invented; RF-050/RF-015 expose no org claim, so
--     app.current_org_id() is LEFT UNCHANGED (GUC-validated-against-membership). Real
--     client org-selection remains a follow-up (documented).
--   * A6: minimal isolated platform-admin helper/path only (no UI/panel). Platform
--     admin must not become a tenant membership and must not appear in any tenant RLS
--     policy. A NARROW, separate platform_admin_audit_events table is created (the
--     tenant audit_events cannot safely carry platform-scoped rows: it is NOT NULL on
--     organization_id and is tenant-RLS-scoped). Platform access is separate + audited.
--
-- DECISIONS: D-001/D-002 tenant hierarchy; D-004/D-005 membership-scoped roles, six
--   identity concepts; D-011 SECURITY DEFINER RPC writes (no client direct writes);
--   D-012 four defence layers; D-013 append-only audit; D-026 platform_admin is NOT a
--   tenant membership (separate, audited path). T-001..T-011 isolation assertions.
--
-- DEFENCE-IN-DEPTH NOTE: business mutations stay RPC-only. The SECURITY DEFINER RPCs
--   (RF-051..057) are owned by the migration runner (a BYPASSRLS role), so they keep
--   writing regardless of the explicit INSERT/UPDATE/DELETE DENY policies added here;
--   the DENY policies + REVOKEd grants only stop DIRECT client DML.
--
-- OUT OF SCOPE: RF-058 realtime; RF-060 full canonical T-008..T-011 suite + harness;
--   RF-061 revocation propagation; RF-090/091 provisioning/admin panel; membership/
--   device management RPCs; Dart/apps/packages; remote Supabase; service-role secrets.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Role-aware scope helpers. SECURITY DEFINER + locked empty search_path (the
--    RF-015 rationale: the membership lookup must not recurse through the
--    memberships policy and the path cannot be hijacked). STABLE, read-only,
--    take no caller identity (identity is always app.current_app_user_id()).
--    Fail-closed: unknown principal / unset org => no membership row => false.
-- ----------------------------------------------------------------------------

-- has_role_in_scope: the role-aware sibling of app.has_scope(). True iff the
-- current principal holds an ACTIVE membership in the active org whose scope
-- covers (target_org, target_restaurant, target_branch) AND whose role is in
-- p_roles. NULL targets mean "that-or-broader level" (same semantics as has_scope).
create or replace function app.has_role_in_scope(
  target_org        uuid,
  target_restaurant uuid,
  target_branch     uuid,
  variadic p_roles  text[]
)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.app_user_id = app.current_app_user_id()
      and m.organization_id = app.current_org_id()
      and m.organization_id = target_org
      and m.status = 'active'
      and m.deleted_at is null
      and m.role = any (p_roles)
      and (m.restaurant_id is null or target_restaurant is null or m.restaurant_id = target_restaurant)
      and (m.branch_id     is null or target_branch     is null or m.branch_id     = target_branch)
  )
$$;

comment on function app.has_role_in_scope(uuid, uuid, uuid, text[]) is
  'RF-059: true iff the current principal has an ACTIVE membership in the active org covering (target_org, target_restaurant, target_branch) with role in p_roles. Role-aware sibling of app.has_scope(). SECURITY DEFINER (membership lookup only); fail-closed.';

-- can_read_financials: every tenant role that may see money EXCEPT kitchen_staff
-- (T-003). Used by the SELECT policies of money-bearing tables so a kitchen_staff
-- membership returns zero rows from them at the RLS backstop (defence in depth).
create or replace function app.can_read_financials(
  target_org        uuid,
  target_restaurant uuid,
  target_branch     uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select app.has_role_in_scope(
    target_org, target_restaurant, target_branch,
    'cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
$$;

comment on function app.can_read_financials(uuid, uuid, uuid) is
  'RF-059 (A3/T-003): true for cashier/manager/restaurant_owner/org_owner/accountant in scope; FALSE for kitchen_staff. Gates direct SELECT on money-bearing tables so kitchen_staff sees no financial rows at the RLS layer.';

-- is_platform_admin: an ACTIVE platform_admin_grants row for the current principal.
-- NEVER referenced by any tenant-table RLS policy (D-026, A6); only the separate
-- platform path consults it. A grant confers NO tenant membership.
create or replace function app.is_platform_admin()
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_admin_grants g
    where g.app_user_id = app.current_app_user_id()
      and g.status = 'active'
  )
$$;

comment on function app.is_platform_admin() is
  'RF-059 (A6/D-026): true iff the current principal holds an ACTIVE platform_admin_grants row. SECURITY DEFINER (platform-grant lookup only). NEVER used in tenant RLS — a platform-admin grant grants NO tenant access; it gates only the separate, audited platform path.';

-- redact_money: strips every money/receipt field from a row jsonb for KDS reads
-- (A3). Removes top-level keys ending in `_minor` plus the receipt fields. Used by
-- app.sync_pull for kitchen_staff so no money figure ever reaches KDS.
create or replace function app.redact_money(p_row jsonb)
  returns jsonb
  language sql
  immutable
  set search_path = ''
as $$
  -- RF059-B1: redact any key where `minor` appears as a TOKEN (bounded by start/end
  -- or an underscore), so it catches not only suffix keys (amount_minor,
  -- grand_total_minor, line_total_minor) but also INFIX snapshot keys
  -- (unit_price_minor_snapshot, price_minor_snapshot, tax_minor_snapshot,
  -- discount_minor_snapshot, ...). The earlier '_minor$' suffix pattern leaked the
  -- order_items/order_item_modifiers price snapshot fields. Non-money snapshot keys
  -- (menu_item_name_snapshot, item_size_snapshot, ...) contain no `minor` token and
  -- are preserved. The explicit receipt denylist stays.
  select coalesce(
    (select jsonb_object_agg(k, v)
     from jsonb_each(p_row) as kv(k, v)
     where k !~ '(^|_)minor($|_)'
       and k not in ('receipt_number', 'receipt_provisional_id')),
    '{}'::jsonb)
$$;

comment on function app.redact_money(jsonb) is
  'RF-059 (A3, RF059-B1): returns the row jsonb with every money field removed — any key where `minor` appears as a token (regex (^|_)minor($|_): amount_minor, grand_total_minor, line_total_minor, unit_price_minor_snapshot, price_minor_snapshot, tax_minor_snapshot, ...) plus the explicit receipt_number/receipt_provisional_id. Non-money *_snapshot keys (names, sizes, variants) are preserved. Used to redact KDS (kitchen_staff) sync_pull rows so no money figure reaches KDS (T-003).';

-- Helper grants: least privilege. has_role_in_scope/can_read_financials run inside
-- RLS policy expressions => the querying role (authenticated) needs EXECUTE.
-- is_platform_admin is used by the (authenticated-callable, self-gated) platform
-- path + tests. redact_money is called only by app.sync_pull (as its DEFINER owner),
-- so it needs no authenticated grant.
revoke all on function app.has_role_in_scope(uuid, uuid, uuid, text[]) from public;
revoke all on function app.can_read_financials(uuid, uuid, uuid)       from public;
revoke all on function app.is_platform_admin()                          from public;
revoke all on function app.redact_money(jsonb)                          from public;
grant execute on function app.has_role_in_scope(uuid, uuid, uuid, text[]) to authenticated;
grant execute on function app.can_read_financials(uuid, uuid, uuid)       to authenticated;
grant execute on function app.is_platform_admin()                          to authenticated;

-- ----------------------------------------------------------------------------
-- 2. Platform-admin audited path (A6, D-026, SECURITY §6). A SEPARATE plane:
--    platform_admin_audit_events carries NO tenant `organization_id` boundary
--    (it uses a SOFT target_organization_id ref, like audit_events' soft refs),
--    so the RF-019 detector never classifies it as tenant-scoped and no tenant
--    RLS predicate ever touches it. Append-only; written ONLY by the DEFINER
--    platform function; fully denied to the tenant `authenticated` path.
-- ----------------------------------------------------------------------------
create table platform_admin_audit_events (
  id                     uuid        primary key default gen_random_uuid(),
  actor_app_user_id      uuid        not null,                       -- soft ref to app_users (the platform admin); no FK (audit resilience)
  target_organization_id uuid,                                       -- soft ref: which tenant was accessed (NULL = platform-wide). NOT named organization_id => not tenant-scoped.
  action                 text        not null check (length(btrim(action)) > 0),
  reason                 text        not null check (length(btrim(reason)) > 0),  -- platform access is ALWAYS reason-tagged (SECURITY §6)
  details                jsonb,
  occurred_at            timestamptz not null default now(),
  created_at             timestamptz not null default now()
  -- DELIBERATELY no organization_id (platform plane, D-026), no updated_at/deleted_at
  -- (append-only & permanent), no FKs (soft refs keep the audit resilient).
);

comment on table platform_admin_audit_events is
  'RF-059 (A6, D-026, SECURITY §6/§7): append-only platform-scoped audit trail for the separate platform-admin path. NOT tenant-scoped (no organization_id; target_organization_id is a SOFT ref to the tenant accessed). Written ONLY by SECURITY DEFINER platform functions; the tenant authenticated path has NO grant + the append-only trigger blocks UPDATE/DELETE/TRUNCATE.';

create index platform_admin_audit_events_actor_idx  on platform_admin_audit_events (actor_app_user_id, occurred_at desc);
create index platform_admin_audit_events_target_idx on platform_admin_audit_events (target_organization_id, occurred_at desc);

-- Append-only: reuse the RF-017 invoker guard (raises 42501 on UPDATE/DELETE/TRUNCATE).
create trigger platform_admin_audit_events_append_only
  before update or delete on platform_admin_audit_events
  for each row execute function app.enforce_audit_append_only();
create trigger platform_admin_audit_events_no_truncate
  before truncate on platform_admin_audit_events
  for each statement execute function app.enforce_audit_append_only();

-- RLS enabled + forced; NO policy + NO grant for `authenticated` => the tenant path
-- is fully denied (like platform_admin_grants). Only the DEFINER platform function
-- (as table owner) writes/reads it.
alter table platform_admin_audit_events enable row level security;
alter table platform_admin_audit_events force  row level security;

-- app.platform_admin_list_organizations — the minimal, audited platform read path
-- (A6). Self-gated by is_platform_admin(); requires a reason; writes a platform
-- audit row; returns a cross-tenant org list ONLY a platform admin may see. This is
-- a SEPARATE path: a tenant member (no grant) is denied (42501); tenant RLS is not
-- involved (the cross-tenant read works only because this DEFINER function bypasses
-- RLS as its owner AND the caller passed the platform-admin gate).
create or replace function app.platform_admin_list_organizations(p_reason text)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid;
  v_rows  jsonb;
begin
  v_actor := app.current_app_user_id();
  if v_actor is null then
    raise exception 'platform_admin_list_organizations: no authenticated principal' using errcode = '42501';
  end if;
  -- platform gate: a tenant membership can NEVER satisfy this (is_platform_admin reads
  -- only platform_admin_grants); a platform-admin grant is required (D-026, T-008).
  if not app.is_platform_admin() then
    raise exception 'platform_admin_list_organizations: caller is not an active platform admin' using errcode = '42501';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'platform_admin_list_organizations: a non-empty reason is required (platform access is reason-tagged)' using errcode = '42501';
  end if;

  -- every platform access is audited on the separate plane (SECURITY §6/§7, T-007).
  insert into public.platform_admin_audit_events (actor_app_user_id, target_organization_id, action, reason, details)
    values (v_actor, null, 'platform.organizations.list', btrim(p_reason),
            jsonb_build_object('scope', 'all_organizations'));

  -- cross-tenant read available ONLY via this separate privileged path.
  select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'status', o.status) order by o.created_at, o.id), '[]'::jsonb)
    into v_rows
    from public.organizations o
    where o.deleted_at is null;

  return jsonb_build_object('ok', true, 'organizations', v_rows, 'server_ts', now());
end;
$$;

comment on function app.platform_admin_list_organizations(text) is
  'RF-059 (A6, SECURITY §6, T-007): minimal audited platform-admin read path. Self-gated by app.is_platform_admin() (a tenant membership can never satisfy it; D-026/T-008); requires a non-empty reason; writes a platform_admin_audit_events row; returns a cross-tenant organization list. Separate from the tenant path (no tenant RLS). No UI/panel (out of scope: RF-091).';

revoke all on function app.platform_admin_list_organizations(text) from public;
grant execute on function app.platform_admin_list_organizations(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. Explicit per-command policy matrix (A1). For each tenant table we DROP the
--    interim broad FOR ALL policy and CREATE explicit SELECT/INSERT/UPDATE/DELETE
--    policies. Direct writes are DENY-by-policy (with check false / using false)
--    AND, for the A2 management tables, REVOKEd at the grant level (section 4).
--    Business mutations remain RPC-only; the SECURITY DEFINER RPCs (BYPASSRLS owner)
--    are unaffected by the DENY write policies.
--
--    SELECT read predicates:
--      * tenant core / identity / device / session : org + app.has_scope(...)
--      * money-bearing (orders/items/modifiers/ledgers/payments/shifts/drawers/
--        receipt counters)                         : org + app.can_read_financials(...)
--        (kitchen_staff excluded — KDS data reaches kitchen only via redacted sync_pull)
--      * memberships                               : own membership OR in-scope (bootstrap)
--      * audit_events                              : org + has_scope (SELECT only; append-only)
--      * sync_operations                           : NO direct read (section 4 revokes SELECT)
--    `app_users` (global identity, no organization_id) and `platform_admin_grants`
--    (platform plane) are intentionally NOT touched here.
-- ----------------------------------------------------------------------------

-- ---- 3.1 Tenant core (RF-014; narrowed in RF-015) --------------------------
drop policy organizations_tenant_isolation on organizations;
create policy organizations_sel on organizations for select to authenticated
  using (id = app.current_org_id());
create policy organizations_ins_deny on organizations for insert to authenticated with check (false);
create policy organizations_upd_deny on organizations for update to authenticated using (false) with check (false);
create policy organizations_del_deny on organizations for delete to authenticated using (false);

drop policy restaurants_tenant_isolation on restaurants;
create policy restaurants_sel on restaurants for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, id, null));
create policy restaurants_ins_deny on restaurants for insert to authenticated with check (false);
create policy restaurants_upd_deny on restaurants for update to authenticated using (false) with check (false);
create policy restaurants_del_deny on restaurants for delete to authenticated using (false);

drop policy branches_tenant_isolation on branches;
create policy branches_sel on branches for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, id));
create policy branches_ins_deny on branches for insert to authenticated with check (false);
create policy branches_upd_deny on branches for update to authenticated using (false) with check (false);
create policy branches_del_deny on branches for delete to authenticated using (false);

drop policy stations_tenant_isolation on stations;
create policy stations_sel on stations for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy stations_ins_deny on stations for insert to authenticated with check (false);
create policy stations_upd_deny on stations for update to authenticated using (false) with check (false);
create policy stations_del_deny on stations for delete to authenticated using (false);

-- ---- 3.2 Identity (RF-015). app_users_self is LEFT UNCHANGED (global identity). --
drop policy memberships_scoped on memberships;
create policy memberships_sel on memberships for select to authenticated
  using (
    app_user_id = app.current_app_user_id()
    or (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  );
create policy memberships_ins_deny on memberships for insert to authenticated with check (false);
create policy memberships_upd_deny on memberships for update to authenticated using (false) with check (false);
create policy memberships_del_deny on memberships for delete to authenticated using (false);

drop policy employee_profiles_scoped on employee_profiles;
create policy employee_profiles_sel on employee_profiles for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy employee_profiles_ins_deny on employee_profiles for insert to authenticated with check (false);
create policy employee_profiles_upd_deny on employee_profiles for update to authenticated using (false) with check (false);
create policy employee_profiles_del_deny on employee_profiles for delete to authenticated using (false);

-- ---- 3.3 Device / session tables (RF-016, RF-051) --------------------------
drop policy devices_scoped on devices;
create policy devices_sel on devices for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy devices_ins_deny on devices for insert to authenticated with check (false);
create policy devices_upd_deny on devices for update to authenticated using (false) with check (false);
create policy devices_del_deny on devices for delete to authenticated using (false);

drop policy device_pairings_scoped on device_pairings;
create policy device_pairings_sel on device_pairings for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy device_pairings_ins_deny on device_pairings for insert to authenticated with check (false);
create policy device_pairings_upd_deny on device_pairings for update to authenticated using (false) with check (false);
create policy device_pairings_del_deny on device_pairings for delete to authenticated using (false);

drop policy device_sessions_scoped on device_sessions;
create policy device_sessions_sel on device_sessions for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy device_sessions_ins_deny on device_sessions for insert to authenticated with check (false);
create policy device_sessions_upd_deny on device_sessions for update to authenticated using (false) with check (false);
create policy device_sessions_del_deny on device_sessions for delete to authenticated using (false);

-- pin_sessions: NOT in the A2 grant-revoke list, but writes are RPC-only
-- (app.start_pin_session, RF-051). Explicit per-command policies; DENY direct
-- writes (the DENY UPDATE/DELETE policies neutralise the residual RF-016 grants —
-- closing direct session manipulation such as extending expires_at or swapping
-- resolved_membership_id). The DEFINER RPC + the enforce_pin_session_backing
-- trigger are unaffected.
drop policy pin_sessions_scoped on pin_sessions;
create policy pin_sessions_sel on pin_sessions for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy pin_sessions_ins_deny on pin_sessions for insert to authenticated with check (false);
create policy pin_sessions_upd_deny on pin_sessions for update to authenticated using (false) with check (false);
create policy pin_sessions_del_deny on pin_sessions for delete to authenticated using (false);

drop policy pin_attempt_states_scoped on pin_attempt_states;
create policy pin_attempt_states_sel on pin_attempt_states for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy pin_attempt_states_ins_deny on pin_attempt_states for insert to authenticated with check (false);
create policy pin_attempt_states_upd_deny on pin_attempt_states for update to authenticated using (false) with check (false);
create policy pin_attempt_states_del_deny on pin_attempt_states for delete to authenticated using (false);

-- ---- 3.4 Audit events (RF-017): SELECT-only + explicit write DENY ----------
drop policy audit_events_select on audit_events;
create policy audit_events_sel on audit_events for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy audit_events_ins_deny on audit_events for insert to authenticated with check (false);
create policy audit_events_upd_deny on audit_events for update to authenticated using (false) with check (false);
create policy audit_events_del_deny on audit_events for delete to authenticated using (false);

-- ---- 3.5 Order tables (RF-052): money-bearing => kitchen EXCLUDED from direct
--           read (A3). kitchen gets non-financial order data only via redacted
--           sync_pull. Writes remain RPC-only (already revoked in RF-052).
drop policy orders_scoped on orders;
create policy orders_sel on orders for select to authenticated
  using (organization_id = app.current_org_id() and app.can_read_financials(organization_id, restaurant_id, branch_id));
create policy orders_ins_deny on orders for insert to authenticated with check (false);
create policy orders_upd_deny on orders for update to authenticated using (false) with check (false);
create policy orders_del_deny on orders for delete to authenticated using (false);

drop policy order_items_scoped on order_items;
create policy order_items_sel on order_items for select to authenticated
  using (organization_id = app.current_org_id() and app.can_read_financials(organization_id, restaurant_id, branch_id));
create policy order_items_ins_deny on order_items for insert to authenticated with check (false);
create policy order_items_upd_deny on order_items for update to authenticated using (false) with check (false);
create policy order_items_del_deny on order_items for delete to authenticated using (false);

drop policy order_item_modifiers_scoped on order_item_modifiers;
create policy order_item_modifiers_sel on order_item_modifiers for select to authenticated
  using (organization_id = app.current_org_id() and app.can_read_financials(organization_id, restaurant_id, branch_id));
create policy order_item_modifiers_ins_deny on order_item_modifiers for insert to authenticated with check (false);
create policy order_item_modifiers_upd_deny on order_item_modifiers for update to authenticated using (false) with check (false);
create policy order_item_modifiers_del_deny on order_item_modifiers for delete to authenticated using (false);

-- ---- 3.6 order_operations (RF-053): result jsonb can carry money => can_read_financials
drop policy order_operations_scoped on order_operations;
create policy order_operations_sel on order_operations for select to authenticated
  using (organization_id = app.current_org_id() and app.can_read_financials(organization_id, restaurant_id, branch_id));
create policy order_operations_ins_deny on order_operations for insert to authenticated with check (false);
create policy order_operations_upd_deny on order_operations for update to authenticated using (false) with check (false);
create policy order_operations_del_deny on order_operations for delete to authenticated using (false);

-- ---- 3.7 Financial tables (RF-054/055): kitchen EXCLUDED (T-003) -----------
drop policy payments_scoped on payments;
create policy payments_sel on payments for select to authenticated
  using (organization_id = app.current_org_id() and app.can_read_financials(organization_id, restaurant_id, branch_id));
create policy payments_ins_deny on payments for insert to authenticated with check (false);
create policy payments_upd_deny on payments for update to authenticated using (false) with check (false);
create policy payments_del_deny on payments for delete to authenticated using (false);

drop policy branch_receipt_counters_scoped on branch_receipt_counters;
create policy branch_receipt_counters_sel on branch_receipt_counters for select to authenticated
  using (organization_id = app.current_org_id() and app.can_read_financials(organization_id, restaurant_id, branch_id));
create policy branch_receipt_counters_ins_deny on branch_receipt_counters for insert to authenticated with check (false);
create policy branch_receipt_counters_upd_deny on branch_receipt_counters for update to authenticated using (false) with check (false);
create policy branch_receipt_counters_del_deny on branch_receipt_counters for delete to authenticated using (false);

drop policy shifts_scoped on shifts;
create policy shifts_sel on shifts for select to authenticated
  using (organization_id = app.current_org_id() and app.can_read_financials(organization_id, restaurant_id, branch_id));
create policy shifts_ins_deny on shifts for insert to authenticated with check (false);
create policy shifts_upd_deny on shifts for update to authenticated using (false) with check (false);
create policy shifts_del_deny on shifts for delete to authenticated using (false);

drop policy cash_drawer_sessions_scoped on cash_drawer_sessions;
create policy cash_drawer_sessions_sel on cash_drawer_sessions for select to authenticated
  using (organization_id = app.current_org_id() and app.can_read_financials(organization_id, restaurant_id, branch_id));
create policy cash_drawer_sessions_ins_deny on cash_drawer_sessions for insert to authenticated with check (false);
create policy cash_drawer_sessions_upd_deny on cash_drawer_sessions for update to authenticated using (false) with check (false);
create policy cash_drawer_sessions_del_deny on cash_drawer_sessions for delete to authenticated using (false);

drop policy shift_operations_scoped on shift_operations;
create policy shift_operations_sel on shift_operations for select to authenticated
  using (organization_id = app.current_org_id() and app.can_read_financials(organization_id, restaurant_id, branch_id));
create policy shift_operations_ins_deny on shift_operations for insert to authenticated with check (false);
create policy shift_operations_upd_deny on shift_operations for update to authenticated using (false) with check (false);
create policy shift_operations_del_deny on shift_operations for delete to authenticated using (false);

-- ---- 3.8 sync_operations (RF-056): NO direct authenticated access (A4) ------
--          Current-device status visibility stays via RF-057 sync_pull
--          operation_statuses (current-device filtered). SELECT is revoked at the
--          grant level (section 4); the explicit DENY policies keep >=1 policy on
--          the table (RF-019 detector) and document the intent. A direct
--          `select from sync_operations` as authenticated raises 42501 (no grant).
drop policy sync_operations_scoped on sync_operations;
create policy sync_operations_sel_deny on sync_operations for select to authenticated using (false);
create policy sync_operations_ins_deny on sync_operations for insert to authenticated with check (false);
create policy sync_operations_upd_deny on sync_operations for update to authenticated using (false) with check (false);
create policy sync_operations_del_deny on sync_operations for delete to authenticated using (false);

-- ----------------------------------------------------------------------------
-- 4. Grant lockdown.
--    (A2) Revoke direct INSERT/UPDATE/DELETE on the sensitive MANAGEMENT tables
--         from `authenticated` (closes self-escalation; writes become RPC-only).
--         SELECT stays (role/scope-safe via the SELECT policies above).
--    (A4) Revoke SELECT on sync_operations from `authenticated` (no direct read).
--    Business tables (orders/payments/shifts/...) already had writes revoked in
--    RF-052..056; the DENY policies in section 3 make that explicit per-command.
-- ----------------------------------------------------------------------------
revoke insert, update, delete on organizations     from authenticated;
revoke insert, update, delete on restaurants        from authenticated;
revoke insert, update, delete on branches           from authenticated;
revoke insert, update, delete on stations           from authenticated;
revoke insert, update, delete on memberships        from authenticated;
revoke insert, update, delete on employee_profiles  from authenticated;
revoke insert, update, delete on devices            from authenticated;
revoke insert, update, delete on device_pairings    from authenticated;
revoke insert, update, delete on device_sessions    from authenticated;

revoke select on sync_operations from authenticated;

-- ----------------------------------------------------------------------------
-- 5. app.sync_pull — CREATE OR REPLACE to enforce kitchen money redaction (A3).
--    IDENTICAL to RF-057 EXCEPT: when the resolved role is kitchen_staff, every
--    returned business-entity row is passed through app.redact_money (strips
--    *_minor + receipt fields) before the response is built. The cursor model,
--    response shape, operation_statuses current-device filtering, pagination, the
--    RF057-B1 limit+1 lookahead, and tombstone behavior are UNCHANGED (the cursor
--    columns updated_at/id and deleted_at are never money keys, so redaction does
--    not affect paging or tombstones). app.sync_pull_changes is reused unchanged.
-- ----------------------------------------------------------------------------
create or replace function app.sync_pull(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_entities       text[]  default null,
  p_cursors        jsonb   default '{}'::jsonb,
  p_limit          integer default 500
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_emp         uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_limit       integer;
  v_allowed     text[];
  v_requested   text[];
  v_include_ops boolean;
  v_entity      text;
  v_cur         jsonb;
  v_c_uat       timestamptz;
  v_c_id        uuid;
  v_changes     jsonb := '{}'::jsonb;
  v_op_rows     jsonb;
  v_op_count    integer;
  v_op_last     jsonb;
  v_op_statuses jsonb;
  c_financial   constant text[] := array['payments', 'shifts', 'cash_drawer_sessions'];
  c_business    constant text[] := array['orders', 'order_items', 'order_item_modifiers', 'payments', 'shifts', 'cash_drawer_sessions'];
begin
  -- (0) limit validation (A7): default 500, reject <=0 or >1000 (validation-error style).
  v_limit := coalesce(p_limit, 500);
  if v_limit <= 0 or v_limit > 1000 then
    raise exception 'sync_pull: p_limit must be between 1 and 1000 (got %)', v_limit using errcode = '42501';
  end if;
  if p_cursors is null or jsonb_typeof(p_cursors) <> 'object' then
    raise exception 'sync_pull: p_cursors must be a JSON object' using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing active; device match (A8).
  --     Scope (org/restaurant/branch) + actor + role are derived HERE, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'sync_pull: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'sync_pull: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'sync_pull: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_pull: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'sync_pull: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) role-permitted business entities (A5): kitchen_staff -> non-financial only.
  if v_role = 'kitchen_staff' then
    v_allowed := array['orders', 'order_items', 'order_item_modifiers'];
  elsif v_role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant') then
    v_allowed := c_business;
  else
    v_allowed := array[]::text[];
  end if;

  -- (c) resolve the requested set. null -> all role-permitted + operation_statuses.
  --     Otherwise validate each name: unknown -> reject; financial-for-kitchen -> reject.
  if p_entities is null then
    v_requested   := v_allowed;
    v_include_ops := true;
  else
    v_requested   := array[]::text[];
    v_include_ops := false;
    foreach v_entity in array p_entities loop
      if v_entity = 'operation_statuses' then
        v_include_ops := true;
      elsif v_entity = any(c_business) then
        if not (v_entity = any(v_allowed)) then
          raise exception 'sync_pull: entity % is not permitted for role %', v_entity, v_role using errcode = '42501';
        end if;
        if not (v_entity = any(v_requested)) then
          v_requested := array_append(v_requested, v_entity);
        end if;
      else
        raise exception 'sync_pull: unknown entity %', v_entity using errcode = '42501';
      end if;
    end loop;
  end if;

  -- (d) page each requested business entity by its per-entity (updated_at, id) cursor.
  foreach v_entity in array v_requested loop
    v_cur   := p_cursors -> v_entity;
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    v_changes := v_changes || jsonb_build_object(
      v_entity, app.sync_pull_changes(v_entity, v_org, v_branch, v_c_uat, v_c_id, v_limit));
  end loop;

  -- (d2) KITCHEN MONEY REDACTION (RF-059, A3/T-003): kitchen_staff must receive NO
  --      money figure. Strip every money/receipt field (app.redact_money) from each
  --      returned business-entity row. Only the `rows` array is rewritten — next_cursor
  --      and has_more (built from the real updated_at/id columns) are untouched, so the
  --      cursor model, pagination, and tombstone (deleted_at) behavior do NOT regress.
  if v_role = 'kitchen_staff' then
    select coalesce(
             jsonb_object_agg(
               ent,
               case when jsonb_typeof(val -> 'rows') = 'array'
                 then jsonb_set(val, '{rows}',
                        coalesce((select jsonb_agg(app.redact_money(r))
                                  from jsonb_array_elements(val -> 'rows') as r), '[]'::jsonb))
                 else val end),
             '{}'::jsonb)
      into v_changes
      from jsonb_each(v_changes) as ec(ent, val);
  end if;

  -- (e) current-device operation-status feed (A4): sync_operations for THIS org + THIS
  --     device only (no cross-device, no cross-org). Projects status/conflict fields;
  --     deliberately EXCLUDES the raw `payload` to minimise exposure. Empty when not requested.
  if v_include_ops then
    v_cur   := p_cursors -> 'operation_statuses';
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    -- (RF057-B1) LOOKAHEAD pagination, same as app.sync_pull_changes: fetch v_limit + 1
    -- (`look`), return only the first v_limit (`page`), has_more = (look count > v_limit),
    -- next_cursor from the last RETURNED row. Avoids the false has_more at exactly v_limit.
    with look as (
      select so.id as _id, so.updated_at as _uat,
             jsonb_build_object(
               'id',                 so.id,
               'local_operation_id', so.local_operation_id,
               'operation_type',     so.operation_type,
               'target_entity',      so.target_entity,
               'target_id',          so.target_id,
               'status',             so.status,
               'result',             so.result,
               'last_error_code',    so.last_error_code,
               'last_error_class',   so.last_error_class,
               'conflict_info',      so.conflict_info,
               'rejection_reason',   so.rejection_reason,
               'retry_count',        so.retry_count,
               'updated_at',         so.updated_at,
               'applied_at',         so.applied_at,
               'server_received_at', so.server_received_at) as _row,
             row_number() over (order by so.updated_at asc, so.id asc) as _rn
      from public.sync_operations so
      where so.organization_id = v_org
        and so.device_id = p_device_id
        and (v_c_uat is null or so.updated_at > v_c_uat or (so.updated_at = v_c_uat and so.id > v_c_id))
      order by so.updated_at asc, so.id asc
      limit v_limit + 1
    ),
    page as (
      select _id, _uat, _row from look where _rn <= v_limit
    )
    select coalesce(jsonb_agg(_row order by _uat asc, _id asc), '[]'::jsonb),
           (select count(*) from look)::int,
           (select jsonb_build_object('updated_at', _uat, 'id', _id) from page order by _uat desc, _id desc limit 1)
      into v_op_rows, v_op_count, v_op_last
      from page;
    v_op_statuses := jsonb_build_object(
      'rows', v_op_rows,
      'next_cursor', case when v_op_count > 0 then v_op_last else null end,
      'has_more', (v_op_count > v_limit));
  else
    v_op_statuses := jsonb_build_object('rows', '[]'::jsonb, 'next_cursor', null, 'has_more', false);
  end if;

  return jsonb_build_object(
    'ok', true,
    'server_ts', now(),
    'changes', v_changes,
    'operation_statuses', v_op_statuses);
end;
$$;

comment on function app.sync_pull(uuid, uuid, text[], jsonb, integer) is
  'RF-057 pull RPC, hardened by RF-059 (A3/T-003): for kitchen_staff, every returned business-entity row is passed through app.redact_money (strips *_minor + receipt fields) so NO money figure reaches KDS. All other RF-057 behavior is preserved verbatim: session/device validation (A8), role-permitted entity set (A5), per-entity (updated_at,id) cursor (A1), tombstones inline (A9), limit default 500/cap 1000, current-device operation_statuses feed (A4; raw payload excluded), RF057-B1 limit+1 lookahead. Read-only; no audit. Org+branch filter is the isolation boundary (R-003).';

revoke all on function app.sync_pull(uuid, uuid, text[], jsonb, integer) from public;
grant execute on function app.sync_pull(uuid, uuid, text[], jsonb, integer) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. To undo by hand (reverse order): drop the RF-059 per-command
-- policies and recreate the prior FOR ALL `*_scoped`/`*_tenant_isolation` policies;
-- re-grant insert/update/delete on the A2 management tables and select on
-- sync_operations to authenticated; restore the RF-057 app.sync_pull body (without
-- the kitchen redaction block); drop platform_admin_audit_events + its triggers;
-- drop app.platform_admin_list_organizations, app.redact_money, app.is_platform_admin,
-- app.can_read_financials, app.has_role_in_scope.
-- ============================================================================
