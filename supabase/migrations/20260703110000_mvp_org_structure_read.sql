-- ============================================================================
-- MVP (product-rescue) — app.list_org_structure: GUC-free org-structure READ
-- RPC for the owner/manager dashboard. DECISIONS D-001/D-011/D-020/D-033;
-- RISK R-003.
-- ============================================================================
-- WHY: a real dashboard JWT must resolve a CONCRETE restaurant/branch (+ the
-- real currency) before it can call any scoped RPC — but an org-wide owner's
-- membership carries restaurant_id/branch_id NULL, get_my_context (RF-110)
-- faithfully echoes those NULLs, and the organizations/restaurants/branches
-- RLS SELECT policies key on the app.current_organization_id GUC that no
-- production client sets, so a JWT caller cannot read the structure tables at
-- all. This additive, forward-only migration adds the missing read:
-- app.list_org_structure + a thin public SECURITY INVOKER wrapper (the RF-160
-- list_devices pattern). It also supplies the REAL tenant currency
-- (organization default + per-restaurant override) so menu writes stop
-- defaulting to USD client-side. It writes nothing and returns no secret.
--
-- AUTHORIZATION (GUC-free, D-033) — DELIBERATELY NOT SCOPE-COVERING: the rank
-- gate is the caller's highest ACTIVE membership rank ANYWHERE in this org
-- (a direct memberships lookup on (actor, org, status=active, not deleted)),
-- NOT app.actor_rank_in_scope against a passed sub-scope. A branch-scoped
-- manager may therefore read the org's structure NAMES/currency: they already
-- see these names via get_my_context, the payload is structure-only (names,
-- timezones, statuses, currency — no money amounts, no credentials, no
-- devices), and the dashboard needs the tree to render the org/branch picker.
--   * app.current_app_user_id() null -> 42501 (fail closed);
--   * rank 0 (non-member / cross-org / anon)  -> 42501 (fail closed);
--   * rank < manager(2) (cashier/kitchen_staff/accountant)
--     -> {ok:false, error:'permission_denied', entity:'org_structure'};
--   * rank >= manager(2) -> the structure tree.
--   No anon / service_role path (D-011); app.is_platform_admin() NEVER (D-026).
--
-- TOMBSTONES (D-020): only deleted_at IS NULL organizations/restaurants/
-- branches are returned. `status` (active/suspended) IS returned and NOT
-- filtered here — suspension display/handling is the client's decision.
-- Ordering: created_at then name at every level, so the dashboard's
-- "first restaurant / first branch" pick is deterministic.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real
-- tenant data (AGENTS.md).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.list_org_structure — the org -> restaurants -> branches tree.
-- ---------------------------------------------------------------------------
create or replace function app.list_org_structure(
  p_organization_id uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor       uuid := app.current_app_user_id();
  v_rank        integer;
  v_org         jsonb;
  v_restaurants jsonb;
begin
  if v_actor is null then
    raise exception 'list_org_structure: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_org_structure: organization_id is required' using errcode = '42501';
  end if;

  -- the caller's highest ACTIVE membership rank ANYWHERE in this org
  -- (deliberately NOT scope-covering — see the header); 0 => not a member.
  select coalesce(max(app.role_rank(m.role)), 0)
    into v_rank
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null;
  if v_rank = 0 then
    raise exception 'list_org_structure: caller has no active membership in the target organization' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then  -- cashier/kitchen_staff/accountant excluded
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'org_structure');
  end if;

  -- the organization itself (live only; a tombstoned org is fail-closed).
  select jsonb_build_object('id', o.id, 'name', o.name, 'default_currency', o.default_currency)
    into v_org
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if v_org is null then
    raise exception 'list_org_structure: organization not found' using errcode = '42501';
  end if;

  -- live restaurants with their live branches nested; created_at then name at
  -- both levels (deterministic first-pick for the dashboard).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'name', r.name,
           'currency_override', r.currency_override,
           'timezone', r.timezone,
           'status', r.status,
           'branches', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'id', b.id, 'name', b.name, 'timezone', b.timezone, 'status', b.status)
                      order by b.created_at, b.name)
             from public.branches b
             where b.organization_id = r.organization_id
               and b.restaurant_id   = r.id
               and b.deleted_at is null), '[]'::jsonb))
           order by r.created_at, r.name), '[]'::jsonb)
    into v_restaurants
    from public.restaurants r
    where r.organization_id = p_organization_id
      and r.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'entity', 'org_structure',
    'organization', v_org,
    'restaurants', v_restaurants,
    'server_ts', now());
end;
$$;

comment on function app.list_org_structure(uuid) is
  'MVP (D-033): GUC-free org-structure READ for the owner/manager dashboard — resolves a concrete restaurant/branch + the real currency (organizations.default_currency + restaurants.currency_override) for JWT callers whose org-wide membership carries NULL restaurant/branch (get_my_context echoes the NULLs; the structure tables'' RLS SELECTs are GUC-dead). Auth: unauthenticated -> 42501; rank = the caller''s highest ACTIVE membership rank ANYWHERE in the org (DELIBERATELY not scope-covering: a branch manager may read their own org''s structure names/currency — names they already see via get_my_context; payload is structure-only, no money/credentials); 0 -> 42501; < manager -> permission_denied. Live rows only (deleted_at IS NULL; status returned, filtered client-side); ordered created_at then name (deterministic first-pick). Read-only; no secret; scope-safe (no GUC trusted; R-003).';

-- ---------------------------------------------------------------------------
-- 2. Thin public SECURITY INVOKER wrapper (RF-064 / RF-109 / RF-160 pattern).
-- ---------------------------------------------------------------------------
create or replace function public.list_org_structure(p_organization_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.list_org_structure(p_organization_id); $$;

-- ---------------------------------------------------------------------------
-- 3. Grants: authenticated only (never anon / service_role; D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.list_org_structure(uuid)    from public;
grant execute on function app.list_org_structure(uuid) to authenticated;
revoke all on function public.list_org_structure(uuid)    from public;
grant execute on function public.list_org_structure(uuid) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.list_org_structure(uuid);
--   drop function if exists app.list_org_structure(uuid);
-- ============================================================================
