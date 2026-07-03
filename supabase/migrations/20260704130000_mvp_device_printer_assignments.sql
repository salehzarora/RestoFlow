-- ============================================================================
-- MVP (product-rescue) — app.get_device_printer_assignments: the TOKEN-PROVEN
-- printer-assignment read for POS/KDS devices. DECISIONS D-001/D-006/D-011/
-- D-012/D-020; PRINTERS_AND_HARDWARE_SPEC §2/§3/§6; RISK R-003.
-- ============================================================================
-- RF-150 shipped the printer CONFIGURATION (printer_devices + printer_routes)
-- and the owner/manager read (app.list_printers), but a POS/KDS device has NO
-- way to learn which printers it should drive: the printer_* SELECT policies
-- are membership/GUC-gated, and a device is an ANONYMOUS authenticated
-- principal with ZERO tenant authority (RF-161). This additive, forward-only
-- migration adds the missing device-facing read:
--
--   app.get_device_printer_assignments(p_device_id, p_session_token)
--
-- TOKEN PROOF (RF-161 pattern, copied EXACTLY from app.list_device_staff):
-- the raw session token is hashed (app.hash_provisioning_secret) and must
-- match a live ACTIVE, non-revoked device_session on an ACTIVE pairing for
-- THIS device, on a live device + live branch + live restaurant. ANY failure
-- returns {ok:false, error:'invalid_session'} (fail closed, never raises,
-- no scope leak).
--
-- ROLE VISIBILITY BY DEVICE TYPE (spec §2/§6): the architecture routes
-- kitchen tickets through the KDS; the POS never prints kitchen tickets.
--   * device_type 'pos' -> printers with role = 'receipt' ONLY;
--   * device_type 'kds' -> printers with role = 'kitchen' ONLY.
--
-- PAYLOAD (device's OWN branch only; scope comes from the proven session,
-- never from the caller):
--   * printers: LIVE (deleted_at IS NULL) printer_devices of the device's
--     branch filtered to the visible role. Disabled rows ARE included —
--     is_enabled says so. NEVER connection_config (the LAN host/port target
--     is sensitive transport config: it stays server-side for the owner
--     surface; no secrets / no LAN targets in a device payload).
--   * routes: LIVE printer_routes of that branch pointing at VISIBLE
--     printers only (station_id, printer_device_id, is_enabled).
--   * stations: LIVE + ACTIVE stations of the branch that are referenced by
--     the returned routes (only valid routing sources, nothing else).
--   * device: device_id/device_type/label/branch_id/branch_name/
--     restaurant_name — display context only.
--
-- TOMBSTONES (D-020): printers/routes tombstone-filtered; the branch and
-- restaurant liveness is already proven by the token joins, and every row is
-- pinned to that same (org, restaurant, branch), so nothing on a dead scope
-- can resurface. No money columns anywhere (D-007 spirit).
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual DOWN at the foot.
-- PENDING: RISK R-003 human RLS/security sign-off before this serves real
-- tenant data (AGENTS.md).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.get_device_printer_assignments — token-proven device printer read.
-- ---------------------------------------------------------------------------
create or replace function app.get_device_printer_assignments(
  p_device_id     uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_hash     text;
  v_sid      uuid;
  v_org      uuid;
  v_rest     uuid;
  v_branch   uuid;
  v_dtype    text;
  v_label    text;
  v_bname    text;
  v_rname    text;
  v_role     text;
  v_printers jsonb;
  v_routes   jsonb;
  v_stations jsonb;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_printer_assignments');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- token proof EXACTLY like app.list_device_staff / app.restore_device_session
  -- (RF-161): a live ACTIVE session on an ACTIVE pairing for THIS device, on a
  -- live device + live branch/restaurant (fail closed on a dead/decommissioned
  -- scope). Also pull the display context (type/label/branch/restaurant names).
  select ds.id, ds.organization_id, ds.restaurant_id, ds.branch_id,
         d.device_type, d.label, b.name, r.name
    into v_sid, v_org, v_rest, v_branch, v_dtype, v_label, v_bname, v_rname
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    join public.devices d on d.id = ds.device_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id and b.deleted_at is null
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_printer_assignments');
  end if;

  -- role visibility BY DEVICE TYPE: POS is receipt-only; KDS is kitchen-only
  -- (kitchen tickets route through the KDS — the POS never prints them).
  v_role := case v_dtype when 'pos' then 'receipt' when 'kds' then 'kitchen' end;
  if v_role is null then
    -- defensive: the devices CHECK pins device_type to pos|kds; fail closed anyway.
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_printer_assignments');
  end if;

  -- printers: LIVE rows of the device's OWN branch, visible role only,
  -- disabled rows included (is_enabled says so). NEVER connection_config —
  -- no secrets / LAN targets in a device payload.
  select coalesce(jsonb_agg(item order by (item ->> 'display_name'), (item ->> 'id')), '[]'::jsonb)
    into v_printers
  from (
    select jsonb_build_object(
      'id',              pd.id,
      'display_name',    pd.display_name,
      'role',            pd.role,
      'connection_type', pd.connection_type,
      'paper_width',     pd.paper_width,
      'is_enabled',      pd.is_enabled
    ) as item
    from public.printer_devices pd
    where pd.organization_id = v_org
      and pd.restaurant_id   = v_rest
      and pd.branch_id       = v_branch
      and pd.role            = v_role
      and pd.deleted_at is null
  ) t;

  -- routes: LIVE routes of that branch pointing at VISIBLE printers only
  -- (the composite FK already pins station + printer to this same branch).
  select coalesce(jsonb_agg(item order by (item ->> 'station_id'), (item ->> 'printer_device_id')), '[]'::jsonb)
    into v_routes
  from (
    select jsonb_build_object(
      'station_id',        pr.station_id,
      'printer_device_id', pr.printer_device_id,
      'is_enabled',        pr.is_enabled
    ) as item
    from public.printer_routes pr
    join public.printer_devices pd
      on pd.organization_id = pr.organization_id
     and pd.restaurant_id   = pr.restaurant_id
     and pd.branch_id       = pr.branch_id
     and pd.id              = pr.printer_device_id
     and pd.role            = v_role
     and pd.deleted_at is null
    where pr.organization_id = v_org
      and pr.restaurant_id   = v_rest
      and pr.branch_id       = v_branch
      and pr.deleted_at is null
  ) t;

  -- stations: LIVE + ACTIVE stations of the branch referenced by the RETURNED
  -- routes only (just enough for the device to label its routing map).
  select coalesce(jsonb_agg(item order by (item ->> 'name'), (item ->> 'id')), '[]'::jsonb)
    into v_stations
  from (
    select jsonb_build_object('id', s.id, 'name', s.name) as item
    from public.stations s
    where s.organization_id = v_org
      and s.restaurant_id   = v_rest
      and s.branch_id       = v_branch
      and s.is_active
      and s.deleted_at is null
      and exists (
        select 1
        from public.printer_routes pr
        join public.printer_devices pd
          on pd.organization_id = pr.organization_id
         and pd.restaurant_id   = pr.restaurant_id
         and pd.branch_id       = pr.branch_id
         and pd.id              = pr.printer_device_id
         and pd.role            = v_role
         and pd.deleted_at is null
        where pr.organization_id = v_org
          and pr.restaurant_id   = v_rest
          and pr.branch_id       = v_branch
          and pr.station_id      = s.id
          and pr.deleted_at is null
      )
  ) t;

  return jsonb_build_object(
    'ok', true, 'entity', 'device_printer_assignments',
    'device', jsonb_build_object(
      'device_id',       p_device_id,
      'device_type',     v_dtype,
      'label',           v_label,
      'branch_id',       v_branch,
      'branch_name',     v_bname,
      'restaurant_name', v_rname
    ),
    'printers',  v_printers,
    'routes',    v_routes,
    'stations',  v_stations,
    'server_ts', now()
  );
end;
$$;

comment on function app.get_device_printer_assignments(uuid, text) is
  'MVP (D-006/D-011/D-020; PRINTERS_AND_HARDWARE_SPEC §2/§6; RF-161 token-proof pattern): the printer-assignment read for a TOKEN-PROVEN POS/KDS device. Proves the session token exactly like app.list_device_staff (hash match on a live ACTIVE session on an ACTIVE pairing, live device/branch/restaurant); any failure => {ok:false, error:invalid_session} (fail closed, no scope leak). Returns the device''s OWN-branch LIVE printers filtered by device type (pos -> receipt-role only, kds -> kitchen-role only; disabled rows included with is_enabled=false), the live routes pointing at those visible printers, the live+active stations referenced by those routes, and display context (device_type/label/branch_name/restaurant_name). NEVER returns connection_config (no secrets / LAN targets in a device payload). Callable by anonymous authenticated devices (authorization is the token, not membership).';

-- ---------------------------------------------------------------------------
-- 2. Thin public SECURITY INVOKER wrapper (RF-064 / RF-109 / RF-123 pattern).
-- ---------------------------------------------------------------------------
create or replace function public.get_device_printer_assignments(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_device_printer_assignments(p_device_id, p_session_token); $$;

-- ---------------------------------------------------------------------------
-- 3. Grants: authenticated only (never anon / service_role; D-011). Anonymous
--    authenticated devices qualify (RF-161 posture).
-- ---------------------------------------------------------------------------
revoke all on function app.get_device_printer_assignments(uuid, text)    from public;
grant execute on function app.get_device_printer_assignments(uuid, text) to authenticated;
revoke all on function public.get_device_printer_assignments(uuid, text)    from public;
grant execute on function public.get_device_printer_assignments(uuid, text) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.get_device_printer_assignments(uuid, text);
--   drop function if exists app.get_device_printer_assignments(uuid, text);
-- ============================================================================
