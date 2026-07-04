-- RF-119 -- Platform-admin MFA hardening + client MFA-required signal. Additive,
-- forward-only. Two narrow server changes; the platform enforcement boundary
-- (app.platform_admin_guard: authenticated + ACTIVE platform_admin grant + MFA
-- aal2 + non-empty reason, RF-091/RF-050) is UNCHANGED and remains the authority.
--
-- 1. app.get_my_context() -- REPLACED (RF-124 body reproduced verbatim, single
--    definition, no later override) + ONE additive field: is_mfa_aal2. This lets
--    the ADMIN app show an HONEST "MFA required" state (an active platform grant
--    WITHOUT an aal2 session) instead of entering the panel and hitting a generic
--    denial on the first read. It is the caller's OWN session assurance (no leak;
--    is_platform_admin was already returned). SECURITY DEFINER, so
--    app.current_auth_assurance_level() (reads the verified request.jwt.claims) is
--    callable here. Enforcement is still server-side in platform_admin_guard --
--    this flag is a UX signal, NOT an authorization decision.
--
-- 2. app.platform_admin_list_organizations(p_reason) -- REPLACED to gate via
--    app.platform_admin_guard (adds the MISSING aal2/MFA check). The RF-091 header
--    explicitly deferred this RF-059 path's aal2 gate as a "Q-008/hardening
--    follow-up" (its RF-059 test called it without an aal2 claim). RF-119 closes
--    it: a cross-tenant organization list must NOT be readable by an active
--    platform admin who lacks MFA. Grant + reason + audit are preserved (the guard
--    subsumes the grant + reason checks and additionally requires aal2). The
--    rf059 test is updated to supply an aal2 claim (it now provides the required
--    MFA -- NOT a weakened assertion).
--
-- No new tables, no grants widened, no service-role, no RLS change. FORWARD-ONLY.

-- ============================================================================
-- 1. app.get_my_context() + is_mfa_aal2 (RF-124 body verbatim; ONE added field)
-- ============================================================================
create or replace function app.get_my_context()
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_app_user_id uuid := app.current_app_user_id();
  v_user        record;
  v_memberships jsonb;
begin
  -- Fail closed: unauthenticated / unlinked principal => 42501.
  -- (app.current_app_user_id() resolves NULL for an unlinked auth principal.)
  if v_app_user_id is null then
    raise exception 'get_my_context: no linked, authenticated principal'
      using errcode = '42501';
  end if;

  select au.id, au.email, au.display_name, au.is_active
    into v_user
    from public.app_users au
   where au.id = v_app_user_id;

  -- Fail closed: inactive app user => 42501. (current_app_user_id() does NOT
  -- enforce is_active, so the resolver re-checks it here.)
  if not found or v_user.is_active is not true then
    raise exception 'get_my_context: principal is not an active app user'
      using errcode = '42501';
  end if;

  -- Only this caller's ACTIVE, non-tombstoned memberships, with org/restaurant/
  -- branch NAMES. INNER join on organizations (deleted_at IS NULL) so a
  -- soft-deleted parent org never surfaces. LEFT joins on restaurant/branch
  -- (deleted_at IS NULL) keep org-wide memberships (null restaurant/branch),
  -- and the WHERE guard EXCLUDES a scoped membership whose named restaurant or
  -- branch parent is soft-deleted or missing (RF124-B1): a scoped membership
  -- must resolve a LIVE parent, never surface a stale id with a null name.
  -- Deterministic order for stable client routing.
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id',                m.id,
               'organization_id',   m.organization_id,
               'organization_name', o.name,
               'restaurant_id',     m.restaurant_id,
               'restaurant_name',   r.name,
               'branch_id',         m.branch_id,
               'branch_name',       b.name,
               'role',              m.role,
               'status',            m.status
             )
             order by m.organization_id, m.restaurant_id nulls first,
                      m.branch_id nulls first, m.id
           ),
           '[]'::jsonb
         )
    into v_memberships
    from public.memberships m
    join public.organizations o
      on o.id = m.organization_id
     and o.deleted_at is null
    left join public.restaurants r
      on r.id = m.restaurant_id
     and r.deleted_at is null
    left join public.branches b
      on b.id = m.branch_id
     and b.deleted_at is null
   where m.app_user_id = v_app_user_id
     and m.status = 'active'
     and m.deleted_at is null
     -- RF124-B1: a scoped membership must resolve a LIVE parent; exclude rows
     -- whose restaurant/branch is soft-deleted or missing (org-wide rows pass).
     and (m.restaurant_id is null or r.id is not null)
     and (m.branch_id is null or b.id is not null);

  return jsonb_build_object(
    'ok', true,
    'app_user', jsonb_build_object(
      'id',           v_user.id,
      'email',        v_user.email,
      'display_name', v_user.display_name,
      'is_active',    v_user.is_active
    ),
    'is_platform_admin', app.is_platform_admin(),
    -- RF-119: the caller's OWN session assurance level == aal2 (a UX signal for
    -- the admin gate's honest "MFA required" state; NOT an authorization
    -- decision -- platform reads are still gated server-side by
    -- app.platform_admin_guard). Factor-agnostic (Q-008); null/aal1 => false.
    'is_mfa_aal2', (app.current_auth_assurance_level() is not distinct from 'aal2'),
    'memberships', v_memberships
  );
end;
$$;

comment on function app.get_my_context() is
  'RF-124 + RF-119 (API_CONTRACT section 4.22, DECISION D-029, T-012): read-only self-context resolver. Identity from app.current_app_user_id() (auth.uid()); NEVER an argument. Returns the caller''s own {id,email,display_name,is_active} app_user, is_platform_admin as a SEPARATE boolean (app.is_platform_admin(); no organization_id derivable -- D-026), RF-119 is_mfa_aal2 = the caller''s OWN session assurance level == aal2 (a UX signal for the admin gate; NOT authorization -- platform reads stay gated by app.platform_admin_guard), and the LIST of the caller''s own ACTIVE memberships (six-key role, status) with org/restaurant/branch NAMES for display; a membership whose org/restaurant/branch parent is soft-deleted or missing is EXCLUDED (RF124-B1). SECURITY DEFINER ONLY to bypass the per-org name-RLS gates (RF-059); the strict app_user self-filter preserves cross-user/cross-org isolation (D-001/R-003). Unauthenticated/unlinked/inactive principal => 42501. No money fields. Writes NO audit_events row.';

-- ============================================================================
-- 2. app.platform_admin_list_organizations -- REPLACED: gate via platform_admin_guard
--    (adds the missing aal2 MFA check; grant + reason + audit preserved).
-- ============================================================================
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
  -- RF-119: full platform gate -- authenticated + ACTIVE platform_admin grant
  -- (D-026; a tenant membership can NEVER satisfy it) + MFA aal2 (RF-050) +
  -- non-empty reason. Closes the RF-091-documented Q-008 follow-up: this RF-059
  -- cross-tenant read previously lacked the aal2 check. Returns the actor id.
  v_actor := app.platform_admin_guard(p_reason);

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
  'RF-059 + RF-119 (A6, SECURITY §6, T-007): minimal audited platform-admin cross-tenant organization list. RF-119 gates it via app.platform_admin_guard -- authenticated + ACTIVE platform_admin grant (D-026/T-008; a tenant membership can never satisfy it) + MFA aal2 (RF-050) + non-empty reason -- closing the RF-091-documented Q-008 follow-up (this path previously lacked the aal2 check). Writes a platform_admin_audit_events row; returns the org list. Separate from the tenant path (no tenant RLS). No UI/panel.';

-- Re-assert grants (create-or-replace preserves ACLs; re-issued per house pattern).
revoke all on function app.get_my_context()                         from public;
grant execute on function app.get_my_context()                      to authenticated;
revoke all on function app.platform_admin_list_organizations(text)  from public;
grant execute on function app.platform_admin_list_organizations(text) to authenticated;

-- ============================================================================
-- DOWN (manual) -- Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse: re-apply the RF-124 app.get_my_context() body
-- (without is_mfa_aal2) and the RF-059 app.platform_admin_list_organizations
-- body (inline grant/reason checks, no aal2). No schema/table/grant changes.
-- ============================================================================
