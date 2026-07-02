-- RF-160 Phase B -- GUC-free device LIST (read) RPC for the owner/manager dashboard.
--
-- The RF-112 device backend (D-033/D-034) ships create/issue/redeem/approve/activate/start_session
-- but NO read path, so the dashboard cannot show real devices. This additive, forward-only migration
-- adds the missing read: app.list_devices + a thin public SECURITY INVOKER wrapper. It writes nothing
-- and returns NO secret (enrollment_code_hash / session_token_ref never leave the DB).
--
-- GUC-FREE authorization (mirrors RF-112 Stage 1/2/3 EXACTLY -- D-033):
--   * caller identity from auth.uid() -> app.current_app_user_id();
--   * authority via app.actor_rank_in_scope over the PASSED (org, restaurant?, branch?) scope,
--     downward-only coverage (an org-wide member covers any restaurant/branch; a restaurant member
--     covers its branches; a branch member covers only that branch);
--   * rank >= manager(2) may list; rank 1 (cashier/kitchen_staff/accountant) IN-scope -> permission_denied;
--   * no covering membership (non-member / cross-org / out-of-scope / anon) -> 42501 (fail closed).
--   NEVER app.current_org_id()/has_scope()/has_role_in_scope()/menu_guard; NEVER app.is_platform_admin().
--   No anon / service_role path (D-011).
--
-- SCOPE-SAFE (RISK R-003): the device filter uses the SAME (org, restaurant?, branch?) that was
--   authorized, so a caller can only ever see devices inside a scope their membership covers. A branch
--   manager cannot widen to the restaurant (actor_rank_in_scope returns 0 -> 42501); a restaurant_owner
--   cannot reach a sibling restaurant; an org_owner sees the whole org. NO GUC is trusted.
--
-- Each returned device carries its CURRENT lifecycle status (the latest LIVE pairing's status, or
-- 'none'), the current pairing id, and whether an open (non-revoked) device session exists. Direct DML
-- on devices/device_pairings/device_sessions stays RLS-denied (RF-059); this DEFINER RPC reads as the
-- BYPASSRLS owner behind the rank gate. FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
--
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real tenant data (AGENTS.md).

-- ===========================================================================
-- 1. app.list_devices -- read the devices in the caller's authorized scope.
-- ===========================================================================
create or replace function app.list_devices(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_items jsonb;
begin
  if v_actor is null then
    raise exception 'list_devices: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_devices: organization_id is required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_devices: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < 2 then     -- cashier/kitchen_staff/accountant cannot manage/list devices
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device');
  end if;

  select coalesce(jsonb_agg(item order by (item ->> 'label'), (item ->> 'device_id')), '[]'::jsonb)
    into v_items
  from (
    select jsonb_build_object(
      'device_id',         d.id,
      'label',             d.label,
      'device_type',       d.device_type,
      'branch_id',         d.branch_id,
      'branch_label',      b.name,
      'status',            coalesce(lp.status, 'none'),
      'device_pairing_id', lp.id,
      'has_open_session',  exists (
        select 1 from public.device_sessions ds
        where ds.device_id = d.id and ds.revoked_at is null
      )
    ) as item
    from public.devices d
    join public.branches b on b.id = d.branch_id
    left join lateral (
      select p.id, p.status
      from public.device_pairings p
      where p.device_id = d.id and p.deleted_at is null
      order by p.created_at desc
      limit 1
    ) lp on true
    where d.organization_id = p_organization_id
      and (p_restaurant_id is null or d.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or d.branch_id     = p_branch_id)
      and d.deleted_at is null
  ) t;

  return jsonb_build_object('ok', true, 'entity', 'device', 'devices', v_items);
end;
$$;

comment on function app.list_devices(uuid, uuid, uuid) is
  'RF-160 (D-033): GUC-free device LIST for the owner/manager dashboard. Reads devices in the PASSED (org, restaurant?, branch?) scope after app.actor_rank_in_scope >= manager (rank 1 in-scope -> permission_denied; no covering membership -> 42501). Returns each device + its latest live pairing status + open-session flag; NEVER returns a secret. Read-only; scope-safe (no GUC trusted).';

-- ===========================================================================
-- 2. Thin public SECURITY INVOKER wrapper (RF-064 / RF-109 pattern).
-- ===========================================================================
create or replace function public.list_devices(
  p_organization_id uuid, p_restaurant_id uuid default null, p_branch_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.list_devices(p_organization_id, p_restaurant_id, p_branch_id); $$;

-- ===========================================================================
-- 3. Grants: authenticated only (never anon/service_role).
-- ===========================================================================
revoke all on function app.list_devices(uuid, uuid, uuid)    from public;
grant execute on function app.list_devices(uuid, uuid, uuid) to authenticated;
revoke all on function public.list_devices(uuid, uuid, uuid)    from public;
grant execute on function public.list_devices(uuid, uuid, uuid) to authenticated;

-- ===========================================================================
-- DOWN (manual; Supabase is forward-only -- `supabase db reset` replays):
--   drop function if exists public.list_devices(uuid, uuid, uuid);
--   drop function if exists app.list_devices(uuid, uuid, uuid);
-- ===========================================================================
