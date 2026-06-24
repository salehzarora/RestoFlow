-- ============================================================================
-- RF-124 — public.get_my_context(): authenticated-only, read-only SELF-CONTEXT
-- / membership resolver (API_CONTRACT §4.22, DECISION D-029, T-012).
-- ============================================================================
-- A plain authenticated Data-API caller can self-read its membership ID rows
-- (memberships_sel, RF-059) but CANNOT translate those org/restaurant/branch IDs
-- into NAMES across all of its memberships: the organizations/restaurants/
-- branches SELECT RLS policies gate on app.current_org_id() (RF-059), which is
-- NULL for a client (no settable org GUC) and single-org at best. RF-124 adds
-- ONE SECURITY DEFINER resolver in `app` that, scoped STRICTLY by
-- app.current_app_user_id(), joins memberships -> org/restaurant/branch names
-- for EVERY membership in one read, plus a thin SECURITY INVOKER wrapper in the
-- already-exposed `public` schema so clients can reach it WITHOUT exposing the
-- whole `app` schema (RISK R-003). Read-only: writes NO audit_events row.
--
-- Identity is ALWAYS app.current_app_user_id() (auth.uid()); NEVER an argument
-- (D-004/D-005). Fails closed (42501) for an unauthenticated / unlinked /
-- inactive principal. Returns only the caller's own app_users row + only
-- memberships whose app_user_id is the caller. The membership LIST preserves
-- D-004 multi-membership; is_platform_admin is a SEPARATE boolean (D-026), never
-- a membership and carrying no organization_id. No money fields. SECURITY
-- DEFINER is needed ONLY to bypass the per-org name-RLS gates; the strict
-- app_user self-filter preserves cross-user / cross-org tenant isolation.
--
-- Additive and FORWARD-ONLY: creates two functions; ALTERs nothing, creates no
-- table, touches no existing grant/policy. The `app` schema is NOT added to
-- [api].schemas. Manual teardown at foot; `supabase db reset` is the gate.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- app.get_my_context() — SECURITY DEFINER: the source of truth.
-- ----------------------------------------------------------------------------
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
    'memberships', v_memberships
  );
end;
$$;

comment on function app.get_my_context() is
  'RF-124 (API_CONTRACT §4.22, DECISION D-029, T-012): read-only self-context resolver. Identity from app.current_app_user_id() (auth.uid()); NEVER an argument. Returns the caller''s own {id,email,display_name,is_active} app_user, is_platform_admin as a SEPARATE boolean (app.is_platform_admin(); no organization_id derivable — D-026), and the LIST of the caller''s own ACTIVE memberships (six-key role, status) with org/restaurant/branch NAMES for display; a membership whose org/restaurant/branch parent is soft-deleted or missing is EXCLUDED (RF124-B1), never surfaced with a stale id and a null name. SECURITY DEFINER ONLY to bypass the per-org name-RLS gates (RF-059); the strict app_user self-filter preserves cross-user/cross-org isolation (D-001/R-003). Unauthenticated/unlinked/inactive principal => 42501. No money fields. Writes NO audit_events row.';

revoke all on function app.get_my_context() from public;
grant execute on function app.get_my_context() to authenticated;

-- ----------------------------------------------------------------------------
-- public.get_my_context() — thin SECURITY INVOKER pass-through (the only
--   Data-API-reachable surface). Runs as the caller, who already holds EXECUTE
--   on app.get_my_context(); no privilege change, no new app.* grant.
-- ----------------------------------------------------------------------------
create or replace function public.get_my_context()
  returns jsonb
  language sql
  security invoker
  set search_path = ''
as $$
  select app.get_my_context();
$$;

comment on function public.get_my_context() is
  'RF-124 (API_CONTRACT §4.22, DECISION D-029): NARROW Data-API-reachable wrapper that delegates verbatim to app.get_my_context (the source of truth). SECURITY INVOKER — runs as the authenticated caller (who already holds EXECUTE on app.get_my_context); adds NO authorization logic and NO transformation. Exposes ONLY get_my_context: the `app` schema stays UNEXPOSED (not added to [api].schemas).';

revoke all on function public.get_my_context() from public;
grant execute on function public.get_my_context() to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. Reverse:
-- ----------------------------------------------------------------------------
-- drop function if exists public.get_my_context();
-- drop function if exists app.get_my_context();
-- ============================================================================
