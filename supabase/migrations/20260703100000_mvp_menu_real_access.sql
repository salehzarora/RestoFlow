-- ============================================================================
-- MVP (product-rescue) — menu real access: GUC-free app.menu_guard swap +
-- app.list_menu management read RPC. DECISIONS D-001/D-007/D-011/D-012/D-020/
-- D-031/D-033; API_CONTRACT §4.23; RISK R-003; T-003.
-- ============================================================================
-- WHY (the load-bearing fix): the RF-109 app.menu_guard authorizes via
-- app.current_org_id() + app.has_scope() + app.has_role_in_scope(), which ALL
-- pin to the GUC app.current_organization_id that NO production client sets
-- (only pgTAP sets it) — so EVERY real dashboard JWT calling the 7
-- public.menu_upsert_*/menu_soft_delete RPCs fails closed with 42501 and the
-- dashboard cannot manage menus at all. This migration replaces the guard body
-- with the RF-112 GUC-free pattern (app.actor_rank_in_scope, D-033) and adds
-- the missing JWT-usable management READ (app.list_menu + thin public wrapper;
-- the menu tables' RLS SELECT policies are equally GUC-dead for real JWTs).
--
-- OBSERVABLE CONTRACT PRESERVED (RF-109 convention):
--   * unauthenticated/unlinked                    -> 42501 (unchanged);
--   * non-member / cross-org / out-of-scope       -> 42501 (unchanged);
--   * covering member below manager (cashier/kitchen_staff/accountant)
--     -> guard returns FALSE -> the RPCs' existing committed `*_denied` audit
--        row + {ok:false, error:'permission_denied'} envelope (unchanged);
--   * covering member at manager+ (org_owner/restaurant_owner/manager)
--     -> guard returns TRUE (write proceeds; unchanged).
--
-- NOTE — ONE INTENTIONAL TIGHTENING: app.actor_rank_in_scope has NO
-- `target is null` escape (unlike the old app.has_scope, RF-015), so a
-- BRANCH-scoped actor can no longer write RESTAURANT-wide (branch_id null)
-- menu rows: that call now raises 42501 (no covering membership) instead of
-- succeeding. Org-wide and restaurant-scoped actors are unaffected. This is
-- the same downward-only coverage rule RF-112/RF-160 already enforce.
--
-- GUC-FREE authorization (mirrors RF-112 / RF-160 / MVP list_printers, D-033):
--   * caller identity from auth.uid() -> app.current_app_user_id();
--   * authority via app.actor_rank_in_scope over the PASSED (org, restaurant,
--     branch?) scope, downward-only coverage;
--   * rank >= manager(2) may write/list; rank 1 in-scope -> permission_denied;
--   * no covering membership -> 42501 (fail closed). No anon / service_role
--     path (D-011); app.is_platform_admin() is NEVER referenced (D-026).
--
-- list_menu is the MANAGEMENT view (manager+ only — consistent with T-003,
-- kitchen_staff/cashier/accountant are excluded, so NO money redaction is
-- needed): tombstones (deleted_at) are excluded, but is_active = false rows
-- ARE returned (the dashboard shows disabled entries). Money stays integer
-- minor bigint (D-007). The POS/KDS sell view remains app.pos_menu (session-
-- authorized, kitchen-redacted); the sync feed remains sync_pull (D-020).
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real
-- tenant data (AGENTS.md).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.menu_guard — SAME signature/return type as RF-109; GUC-free body.
--    Raises 42501 for unauthenticated / non-member / cross-org / out-of-scope;
--    returns TRUE for manager+ in scope, FALSE for a covering member below
--    manager (the RPCs' role-denied audit path).
-- ---------------------------------------------------------------------------
create or replace function app.menu_guard(p_org uuid, p_restaurant uuid, p_branch uuid)
  returns boolean
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_rank integer;
begin
  if app.current_app_user_id() is null then
    raise exception 'menu: authentication required' using errcode = '42501';
  end if;
  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_rank_in_scope(p_org, p_restaurant, p_branch);
  if v_rank = 0 then
    raise exception 'menu: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  return v_rank >= app.role_rank('manager');
end;
$$;

comment on function app.menu_guard(uuid, uuid, uuid) is
  'MVP (D-033): GUC-free replacement of the RF-109 guard so real dashboard JWTs can manage menus (the old body pinned to the app.current_organization_id GUC no production client sets). Identity = app.current_app_user_id(); authority = app.actor_rank_in_scope over the PASSED scope. 42501 for unauthenticated/non-member/cross-org/out-of-scope; TRUE for manager+ (org_owner/restaurant_owner/manager); FALSE for a covering rank-1 member (the RPCs'' committed denial-audit + permission_denied path). INTENTIONAL TIGHTENING: no `target is null` escape, so a branch-scoped actor can no longer write restaurant-wide (branch_id null) rows.';

-- defensive re-lock (create or replace preserves ACLs; keep the RF-109 posture:
-- internal helper, callable only inside the DEFINER menu RPCs as their owner).
revoke all on function app.menu_guard(uuid, uuid, uuid) from public;

-- ---------------------------------------------------------------------------
-- 2. app.list_menu — the dashboard MANAGEMENT menu read (manager+ only).
--    There is no other JWT-usable menu read: the RF-109 RLS SELECT policies
--    key on the org GUC, so a real JWT sees nothing via the Data API.
-- ---------------------------------------------------------------------------
create or replace function app.list_menu(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();
  v_rank       integer;
  v_currency   text;
  v_categories jsonb;
  v_items      jsonb;
  v_sizes      jsonb;
  v_variants   jsonb;
  v_modifiers  jsonb;
  v_options    jsonb;
begin
  if v_actor is null then
    raise exception 'list_menu: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'list_menu: organization_id and restaurant_id are required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_menu: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    -- kitchen_staff/cashier/accountant are excluded from the management view
    -- (consistent with T-003: menu rows carry money and this surface is manager+
    -- only, so no per-row redaction is needed below).
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'menu');
  end if;

  -- structural validation: the restaurant must belong to the org, and the
  -- branch (when passed) must belong to that restaurant (IDOR fail-closed).
  if not exists (select 1 from public.restaurants r
                 where r.id = p_restaurant_id and r.organization_id = p_organization_id) then
    raise exception 'list_menu: restaurant not found in the target organization' using errcode = '42501';
  end if;
  if p_branch_id is not null and not exists (
       select 1 from public.branches b
       where b.id = p_branch_id
         and b.organization_id = p_organization_id
         and b.restaurant_id   = p_restaurant_id) then
    raise exception 'list_menu: branch not found in the target restaurant' using errcode = '42501';
  end if;

  -- the REAL tenant currency: restaurants.currency_override, else the
  -- organization default (so menu writes stop defaulting to USD client-side).
  select coalesce(r.currency_override, o.default_currency)
    into v_currency
    from public.restaurants r
    join public.organizations o on o.id = r.organization_id
    where r.id = p_restaurant_id and r.organization_id = p_organization_id;

  -- Every returned row carries organization_id / restaurant_id / branch_id
  -- (the Dart fromJson factories require the tenant keys on every row; D-001).

  -- categories: tombstone-excluded, INACTIVE INCLUDED (management view);
  -- branch-visible (restaurant-wide branch-null rows + the requested branch).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'organization_id', c.organization_id, 'restaurant_id', c.restaurant_id,
           'branch_id', c.branch_id, 'name', c.name, 'display_order', c.display_order,
           'is_active', c.is_active)
           order by c.display_order, c.name), '[]'::jsonb)
    into v_categories
    from public.menu_categories c
    where c.organization_id = p_organization_id
      and c.restaurant_id   = p_restaurant_id
      and c.deleted_at is null
      and (p_branch_id is null or c.branch_id is null or c.branch_id = p_branch_id);

  -- items: same filters; base_price_minor is integer minor bigint (D-007);
  -- NO redaction (manager+ only surface).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', i.id, 'organization_id', i.organization_id, 'restaurant_id', i.restaurant_id,
           'branch_id', i.branch_id, 'menu_category_id', i.menu_category_id, 'name', i.name,
           'description', i.description, 'base_price_minor', i.base_price_minor,
           'currency_code', i.currency_code, 'default_station_id', i.default_station_id,
           'display_order', i.display_order, 'is_active', i.is_active)
           order by i.display_order, i.name), '[]'::jsonb)
    into v_items
    from public.menu_items i
    where i.organization_id = p_organization_id
      and i.restaurant_id   = p_restaurant_id
      and i.deleted_at is null
      and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id);

  -- sizes: children of the RETURNED item set (join, tombstone-filtered at
  -- each level, child branch-visible too).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'organization_id', s.organization_id, 'restaurant_id', s.restaurant_id,
           'branch_id', s.branch_id, 'menu_item_id', s.menu_item_id, 'name', s.name,
           'price_delta_minor', s.price_delta_minor,
           'display_order', s.display_order, 'is_active', s.is_active)
           order by s.display_order, s.name), '[]'::jsonb)
    into v_sizes
    from public.item_sizes s
    join public.menu_items i
      on i.organization_id = s.organization_id and i.id = s.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where s.organization_id = p_organization_id
      and s.restaurant_id   = p_restaurant_id
      and s.deleted_at is null
      and (p_branch_id is null or s.branch_id is null or s.branch_id = p_branch_id);

  -- variants: same shape/filters as sizes.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', v.id, 'organization_id', v.organization_id, 'restaurant_id', v.restaurant_id,
           'branch_id', v.branch_id, 'menu_item_id', v.menu_item_id, 'name', v.name,
           'price_delta_minor', v.price_delta_minor,
           'display_order', v.display_order, 'is_active', v.is_active)
           order by v.display_order, v.name), '[]'::jsonb)
    into v_variants
    from public.item_variants v
    join public.menu_items i
      on i.organization_id = v.organization_id and i.id = v.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where v.organization_id = p_organization_id
      and v.restaurant_id   = p_restaurant_id
      and v.deleted_at is null
      and (p_branch_id is null or v.branch_id is null or v.branch_id = p_branch_id);

  -- modifiers: children of the RETURNED item set.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'organization_id', m.organization_id, 'restaurant_id', m.restaurant_id,
           'branch_id', m.branch_id, 'menu_item_id', m.menu_item_id, 'name', m.name,
           'selection_type', m.selection_type, 'min_select', m.min_select,
           'max_select', m.max_select, 'is_required', m.is_required,
           'display_order', m.display_order, 'is_active', m.is_active)
           order by m.display_order, m.name), '[]'::jsonb)
    into v_modifiers
    from public.modifiers m
    join public.menu_items i
      on i.organization_id = m.organization_id and i.id = m.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where m.organization_id = p_organization_id
      and m.restaurant_id   = p_restaurant_id
      and m.deleted_at is null
      and (p_branch_id is null or m.branch_id is null or m.branch_id = p_branch_id);

  -- modifier options: children of the RETURNED modifier set (which itself
  -- requires the parent item in the set) — tombstone-filtered at each level.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', mo.id, 'organization_id', mo.organization_id, 'restaurant_id', mo.restaurant_id,
           'branch_id', mo.branch_id, 'modifier_id', mo.modifier_id, 'name', mo.name,
           'price_delta_minor', mo.price_delta_minor,
           'display_order', mo.display_order, 'is_active', mo.is_active)
           order by mo.display_order, mo.name), '[]'::jsonb)
    into v_options
    from public.modifier_options mo
    join public.modifiers m
      on m.organization_id = mo.organization_id and m.id = mo.modifier_id
     and m.restaurant_id = p_restaurant_id
     and m.deleted_at is null
     and (p_branch_id is null or m.branch_id is null or m.branch_id = p_branch_id)
    join public.menu_items i
      on i.organization_id = m.organization_id and i.id = m.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where mo.organization_id = p_organization_id
      and mo.restaurant_id   = p_restaurant_id
      and mo.deleted_at is null
      and (p_branch_id is null or mo.branch_id is null or mo.branch_id = p_branch_id);

  return jsonb_build_object(
    'ok', true,
    'entity', 'menu',
    'currency_code', v_currency,
    'categories', v_categories,
    'items', v_items,
    'sizes', v_sizes,
    'variants', v_variants,
    'modifiers', v_modifiers,
    'modifier_options', v_options,
    'server_ts', now());
end;
$$;

comment on function app.list_menu(uuid, uuid, uuid) is
  'MVP (D-033; API_CONTRACT §4.23): GUC-free menu MANAGEMENT read for the owner/manager dashboard (the RF-109 RLS SELECT policies are GUC-dead for real JWTs). Auth: app.current_app_user_id() null -> 42501; app.actor_rank_in_scope over the PASSED (org, restaurant, branch?) — 0 -> 42501, < manager -> {ok:false, error:permission_denied, entity:menu} (kitchen_staff/cashier/accountant excluded, consistent with T-003; manager+ only, so no money redaction). Restaurant/branch validated against the org (42501 on mismatch). Returns currency_code = restaurants.currency_override ?? organizations.default_currency + categories/items/sizes/variants/modifiers/modifier_options: deleted_at excluded, is_active=false INCLUDED, branch-visible (branch null OR = p_branch), children only under returned parents; EVERY row carries organization_id/restaurant_id/branch_id (the Dart fromJson factories require the tenant keys; D-001); money integer minor bigint (D-007). Read-only; scope-safe (no GUC trusted; R-003).';

-- ---------------------------------------------------------------------------
-- 3. Thin public SECURITY INVOKER wrapper (RF-064 / RF-109 / RF-160 pattern).
-- ---------------------------------------------------------------------------
create or replace function public.list_menu(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.list_menu(p_organization_id, p_restaurant_id, p_branch_id); $$;

-- ---------------------------------------------------------------------------
-- 4. Grants: authenticated only (never anon / service_role; D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.list_menu(uuid, uuid, uuid)    from public;
grant execute on function app.list_menu(uuid, uuid, uuid) to authenticated;
revoke all on function public.list_menu(uuid, uuid, uuid)    from public;
grant execute on function public.list_menu(uuid, uuid, uuid) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.list_menu(uuid, uuid, uuid);
--   drop function if exists app.list_menu(uuid, uuid, uuid);
--   restore the RF-109 app.menu_guard body (20260625100000_rf109_menu_management_rpcs.sql).
-- ============================================================================
