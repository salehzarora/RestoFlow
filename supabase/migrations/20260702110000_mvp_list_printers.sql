-- ============================================================================
-- MVP (product-rescue) — app.list_printers: GUC-free printer-config LIST (read)
-- RPC for the owner/manager dashboard. DECISIONS D-001/D-011/D-012/D-020/D-033;
-- PRINTERS_AND_HARDWARE_SPEC §2/§3/§4/§6; RISK R-003.
-- ============================================================================
-- RF-150 ships the printer-config WRITE path (upsert_printer_device /
-- set_printer_route / soft_delete_printer_device) but NO read path a real JWT
-- caller can use: the printer_devices/printer_routes SELECT policies key on the
-- app.current_organization_id GUC that production clients never set, so the
-- dashboard cannot show the configuration it just wrote. This additive,
-- forward-only migration adds the missing read: app.list_printers + a thin
-- public SECURITY INVOKER wrapper (the RF-160 list_devices pattern EXACTLY).
-- It writes nothing and touches no policy.
--
-- GUC-FREE authorization (mirrors RF-160 / RF-112 D-033):
--   * caller identity from auth.uid() -> app.current_app_user_id();
--   * authority via app.actor_rank_in_scope over the PASSED (org, restaurant?,
--     branch?) scope, downward-only coverage;
--   * rank >= manager(2) may list; rank 1 (cashier/kitchen_staff/accountant)
--     IN-scope -> {ok:false, error:'permission_denied'} (read path — no audit,
--     matching list_devices);
--   * no covering membership (non-member / cross-org / out-of-scope / anon)
--     -> 42501 (fail closed). No anon / service_role path (D-011).
--
-- SCOPE-SAFE (RISK R-003): the row filters use the SAME (org, restaurant?,
-- branch?) that was authorized, so a caller only ever sees configuration inside
-- a scope their membership covers. NO GUC is trusted.
--
-- TOMBSTONES (D-020): printers and routes are tombstone-filtered
-- (deleted_at IS NULL) AND filtered through LIVE branches/restaurants joins, so
-- configuration on a soft-deleted branch/restaurant never resurfaces. Stations
-- are returned live-only (is_active AND deleted_at IS NULL) so the dashboard can
-- draw the station -> printer routing map (spec §6). No money columns anywhere
-- (printer config touches no money; D-007 spirit). connection_config is
-- LAN-transport config (spec §3), not a secret/credential.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real
-- tenant data (AGENTS.md).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.list_printers — read the printer config in the caller's authorized scope.
-- ---------------------------------------------------------------------------
create or replace function app.list_printers(
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
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_printers jsonb;
  v_routes   jsonb;
  v_stations jsonb;
begin
  if v_actor is null then
    raise exception 'list_printers: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_printers: organization_id is required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_printers: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then  -- cashier/kitchen_staff/accountant cannot manage printers
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'printer_device');
  end if;

  -- printers: tombstone-filtered + LIVE branch/restaurant only; ordered by display_name.
  select coalesce(jsonb_agg(item order by (item ->> 'display_name'), (item ->> 'id')), '[]'::jsonb)
    into v_printers
  from (
    select jsonb_build_object(
      'id',                pd.id,
      'display_name',      pd.display_name,
      'connection_type',   pd.connection_type,
      'role',              pd.role,
      'paper_width',       pd.paper_width,
      'connection_config', pd.connection_config,
      'is_enabled',        pd.is_enabled,
      'revision',          pd.revision,
      'created_at',        pd.created_at,
      'updated_at',        pd.updated_at
    ) as item
    from public.printer_devices pd
    join public.branches b
      on b.organization_id = pd.organization_id
     and b.restaurant_id   = pd.restaurant_id
     and b.id              = pd.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = pd.organization_id
     and r.id              = pd.restaurant_id
     and r.deleted_at is null
    where pd.organization_id = p_organization_id
      and (p_restaurant_id is null or pd.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or pd.branch_id     = p_branch_id)
      and pd.deleted_at is null
  ) t;

  -- routes: the station -> printer map (spec §6); tombstone-filtered + LIVE
  -- branch/restaurant only (soft_delete_printer_device already tombstones a
  -- removed printer's routes, so no extra printer-liveness filter is needed).
  select coalesce(jsonb_agg(item order by (item ->> 'id')), '[]'::jsonb)
    into v_routes
  from (
    select jsonb_build_object(
      'id',                pr.id,
      'station_id',        pr.station_id,
      'printer_device_id', pr.printer_device_id,
      'is_enabled',        pr.is_enabled
    ) as item
    from public.printer_routes pr
    join public.branches b
      on b.organization_id = pr.organization_id
     and b.restaurant_id   = pr.restaurant_id
     and b.id              = pr.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = pr.organization_id
     and r.id              = pr.restaurant_id
     and r.deleted_at is null
    where pr.organization_id = p_organization_id
      and (p_restaurant_id is null or pr.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or pr.branch_id     = p_branch_id)
      and pr.deleted_at is null
  ) t;

  -- stations: LIVE only (is_active + not tombstoned) on a LIVE branch/restaurant,
  -- so the dashboard can offer valid routing targets; ordered by name.
  select coalesce(jsonb_agg(item order by (item ->> 'name'), (item ->> 'id')), '[]'::jsonb)
    into v_stations
  from (
    select jsonb_build_object('id', s.id, 'name', s.name) as item
    from public.stations s
    join public.branches b
      on b.organization_id = s.organization_id
     and b.restaurant_id   = s.restaurant_id
     and b.id              = s.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = s.organization_id
     and r.id              = s.restaurant_id
     and r.deleted_at is null
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.is_active
      and s.deleted_at is null
  ) t;

  return jsonb_build_object('ok', true, 'entity', 'printer_device',
    'printers', v_printers, 'routes', v_routes, 'stations', v_stations);
end;
$$;

comment on function app.list_printers(uuid, uuid, uuid) is
  'MVP (D-011/D-020/D-033; PRINTERS_AND_HARDWARE_SPEC §6): GUC-free printer-config LIST for the owner/manager dashboard. Reads printer_devices + printer_routes + live stations in the PASSED (org, restaurant?, branch?) scope after app.actor_rank_in_scope >= manager (rank 1 in-scope -> permission_denied; no covering membership -> 42501). Printers/routes are tombstone-filtered and joined through LIVE branches/restaurants; stations are is_active + not tombstoned. Read-only; scope-safe (no GUC trusted); never returns a secret.';

-- ---------------------------------------------------------------------------
-- 2. Thin public SECURITY INVOKER wrapper (RF-064 / RF-109 / RF-160 pattern).
-- ---------------------------------------------------------------------------
create or replace function public.list_printers(
  p_organization_id uuid, p_restaurant_id uuid default null, p_branch_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.list_printers(p_organization_id, p_restaurant_id, p_branch_id); $$;

-- ---------------------------------------------------------------------------
-- 3. Grants: authenticated only (never anon / service_role; D-011).
-- ---------------------------------------------------------------------------
revoke all on function app.list_printers(uuid, uuid, uuid)    from public;
grant execute on function app.list_printers(uuid, uuid, uuid) to authenticated;
revoke all on function public.list_printers(uuid, uuid, uuid)    from public;
grant execute on function public.list_printers(uuid, uuid, uuid) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.list_printers(uuid, uuid, uuid);
--   drop function if exists app.list_printers(uuid, uuid, uuid);
-- ============================================================================
