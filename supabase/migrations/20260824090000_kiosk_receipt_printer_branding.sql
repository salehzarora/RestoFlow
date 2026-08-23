-- ============================================================================
-- KIOSK-001-103 — kiosk receipt branding + receipt-only printer context.
--
-- The customer self-service kiosk prints an UNPAID customer receipt and shows
-- the restaurant's authoritative Dashboard receipt logo on its confirmation
-- slip. Both delivery paths were POS-gated before this migration:
--
--   A. app.device_can_read_restaurant_logo(text) allowed device_type='pos'
--      ONLY, and predated RF-118 (no session-expiry predicate).
--   B. app.get_device_printer_assignments(uuid, text) answered only
--      pos/kds; a kiosk session could not read its restaurant name or the
--      receipt_logo_path/enabled/version pointer.
--
-- This migration:
--   A. widens the restaurant-logo READ gate to ('pos','kiosk') — KDS stays
--      EXCLUDED (T-014: kitchen surfaces carry no customer branding) — and
--      adds the RF-118 expiry-parity predicate for EVERY device principal
--      (the exact follow-up deferred by 20260823090000's header note).
--   B. recreates get_device_printer_assignments with a KIOSK branch:
--      receipt-only purposes (customer_receipt; NEVER kitchen_ticket),
--      RF-118 expiry enforced for the NEW kiosk principal, POS/KDS
--      semantics preserved byte-for-byte (their proof predicates are
--      untouched — tightening them is a separate, owner-approved decision).
--      connection_config remains NEVER exposed.
--   C. adds NO write path: the kiosk keeps ZERO insert/update/delete access
--      to the restaurant-logos bucket (no new storage policy of any kind).
--   D. grants stay authenticated-only (no anon / service_role / public).
--
-- Forward-only; no old migration is edited. LOCAL ONLY until the owner
-- approves the hosted apply (KIOSK-001-103 §13/§22).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A. Restaurant-logo device read gate: pos + kiosk, RF-118 expiry parity.
--    Everything else is byte-identical to 20260801090000 §C4: auth.uid()
--    binding, live session/pairing/device, path-derived org+restaurant scope
--    via the strict app.restaurant_logo_scope parser (malformed => no row =>
--    deny), SECURITY DEFINER, empty search_path.
-- ----------------------------------------------------------------------------
create or replace function app.device_can_read_restaurant_logo(p_object_name text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from app.restaurant_logo_scope(p_object_name) s
    join public.device_sessions ds
      on ds.auth_user_id = auth.uid()
    join public.device_pairings dp
      on dp.id = ds.device_pairing_id
    join public.devices d
      on d.id = ds.device_id
    where ds.is_active
      and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())  -- RF-118 (103)
      and dp.status = 'active'
      and dp.revoked_at is null
      and dp.deleted_at is null
      and d.is_active
      and d.deleted_at is null
      and d.device_type in ('pos', 'kiosk')          -- KDS EXCLUDED (no receipts)
      and ds.organization_id = s.organization_id     -- tenant boundary (D-001)
      and ds.restaurant_id   = s.restaurant_id
  );
$$;

comment on function app.device_can_read_restaurant_logo(text) is
  'KIOSK-001-103 (was PRINT-BRANDING-LOGO-001): device read gate for the private restaurant-logos bucket. Allows ONLY an ACTIVE, unrevoked, NON-EXPIRED (RF-118 parity added by KIOSK-001-103) device session bound to auth.uid() on an ACTIVE pairing + ACTIVE device of type pos OR kiosk (KDS stays EXCLUDED — kitchen surfaces carry no customer branding), whose org+restaurant equal the strictly-parsed object path scope (malformed path => no row => deny). Read-only; never referenced by any write policy; authenticated-only.';

-- ----------------------------------------------------------------------------
-- B. Device printer/branding context: add the KIOSK principal.
--    Project pattern (20260801090000 §F): DROP both layers, recreate — no
--    stacked overloads. POS and KDS branches are preserved byte-for-byte.
-- ----------------------------------------------------------------------------
drop function if exists public.get_device_printer_assignments(uuid, text);
drop function if exists app.get_device_printer_assignments(uuid, text);

create function app.get_device_printer_assignments(
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
  v_hash      text;
  v_sid       uuid;
  v_org       uuid;
  v_rest      uuid;
  v_branch    uuid;
  v_dtype     text;
  v_label     text;
  v_bname     text;
  v_rname     text;
  v_expires   timestamptz;  -- KIOSK-001-103 (RF-118 for the kiosk principal)
  v_logo_path text;     -- PRINT-BRANDING-LOGO-001 (additive)
  v_logo_on   boolean;  -- PRINT-BRANDING-LOGO-001 (additive)
  v_logo_ver  integer;  -- PRINT-BRANDING-LOGO-001 (additive)
  v_roles     text[];
  v_kitchen_mode text;
  v_printers  jsonb;
  v_routes    jsonb;
  v_stations  jsonb;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_printer_assignments');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- token proof EXACTLY like app.list_device_staff / app.restore_device_session
  -- (RF-161). Also pull the display context AND (additive) the restaurant's
  -- current receipt-branding pointer for the device's OWN, already-proven
  -- restaurant (no extra scope check — it is the proven session's restaurant).
  select ds.id, ds.organization_id, ds.restaurant_id, ds.branch_id,
         d.device_type, d.label, b.name, r.name, ds.expires_at,
         r.receipt_logo_path, r.receipt_logo_enabled, r.receipt_logo_version
    into v_sid, v_org, v_rest, v_branch, v_dtype, v_label, v_bname, v_rname,
         v_expires, v_logo_path, v_logo_on, v_logo_ver
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

  -- KITCHEN-MODE-001B role membership BY DEVICE TYPE + branch workflow mode
  -- (fail-closes to 'kds'). POS/KDS unchanged.
  if v_dtype = 'pos' then
    select b.kitchen_workflow_mode into v_kitchen_mode
      from public.branches b
      where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
    if coalesce(v_kitchen_mode, 'kds') = 'printer_only' then
      v_roles := array['receipt', 'kitchen', 'both'];
    else
      v_roles := array['receipt', 'both'];
    end if;
  elsif v_dtype = 'kds' then
    v_roles := array['kitchen', 'both'];
  elsif v_dtype = 'kiosk' then
    -- KIOSK-001-103: the kiosk is a CUSTOMER-RECEIPT surface only — it can
    -- never see kitchen printers or kitchen purposes. RF-118 expiry is
    -- enforced for this NEW principal (the POS/KDS proofs above are
    -- deliberately byte-preserved; adding their parity is a separate,
    -- owner-approved decision).
    if not (v_expires is null or v_expires > now()) then
      return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_printer_assignments');
    end if;
    v_roles := array['receipt', 'both'];
  else
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_printer_assignments');
  end if;

  -- printers: LIVE rows of the device's OWN branch, visible role only, disabled
  -- rows included. NEVER connection_config. Unchanged (the kiosk reuses the
  -- POS-shaped 'receipt' projection: a 'both' printer collapses to 'receipt'
  -- and supported_purposes stays ["customer_receipt"] via the non-kds arms).
  select coalesce(jsonb_agg(item order by (item ->> 'display_name'), (item ->> 'id')), '[]'::jsonb)
    into v_printers
  from (
    select jsonb_build_object(
      'id',              pd.id,
      'display_name',    pd.display_name,
      'role',            case when pd.role = 'both'
                              then case v_dtype when 'kds' then 'kitchen' else 'receipt' end
                              else pd.role end,
      'configured_role', pd.role,
      'supported_purposes',
        case pd.role
          when 'receipt' then '["customer_receipt"]'::jsonb
          when 'kitchen' then '["kitchen_ticket"]'::jsonb
          else case
            when v_dtype = 'kds' then '["kitchen_ticket"]'::jsonb
            when coalesce(v_kitchen_mode, 'kds') = 'printer_only'
              then '["customer_receipt", "kitchen_ticket"]'::jsonb
            else '["customer_receipt"]'::jsonb
          end
        end,
      'connection_type', pd.connection_type,
      'paper_width',     pd.paper_width,
      'is_enabled',      pd.is_enabled
    ) as item
    from public.printer_devices pd
    where pd.organization_id = v_org
      and pd.restaurant_id   = v_rest
      and pd.branch_id       = v_branch
      and pd.role            = any(v_roles)
      and pd.deleted_at is null
  ) t;

  -- routes: LIVE routes of that branch pointing at VISIBLE printers only. Unchanged.
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
     and pd.role            = any(v_roles)
     and pd.deleted_at is null
    where pr.organization_id = v_org
      and pr.restaurant_id   = v_rest
      and pr.branch_id       = v_branch
      and pr.deleted_at is null
  ) t;

  -- stations: LIVE + ACTIVE stations referenced by the RETURNED routes. Unchanged.
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
         and pd.role            = any(v_roles)
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
      'restaurant_name', v_rname,
      -- PRINT-BRANDING-LOGO-001 additive keys (device's OWN proven scope +
      -- current branding pointer; all default-safe for a legacy restaurant).
      -- organization_id + restaurant_id give the POS a stable tenant identity
      -- for the offline raster-cache key (never a client-asserted value).
      'organization_id',      v_org,
      'restaurant_id',        v_rest,
      'receipt_logo_path',    v_logo_path,
      'receipt_logo_enabled', coalesce(v_logo_on, false),
      'receipt_logo_version', coalesce(v_logo_ver, 0)
    ),
    'printers',  v_printers,
    'routes',    v_routes,
    'stations',  v_stations,
    'server_ts', now()
  );
end;
$$;

comment on function app.get_device_printer_assignments(uuid, text) is
  'KIOSK-001-103 (was PRINT-BRANDING-LOGO-001 / KITCHEN-MODE-001B): token-proven device printer + branding context. POS: receipt(+kitchen in printer_only mode); KDS: kitchen only; KIOSK: customer_receipt ONLY (never kitchen_ticket), RF-118 expiry enforced for the kiosk principal. Returns display context + the restaurant receipt-logo pointer (path/enabled/version). connection_config is NEVER exposed. Fail-closed: any unknown device type, dead scope, or bad token => {ok:false, error:invalid_session}. Authenticated-only.';

create function public.get_device_printer_assignments(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_device_printer_assignments(p_device_id, p_session_token); $$;

revoke all on function app.get_device_printer_assignments(uuid, text)    from public;
grant execute on function app.get_device_printer_assignments(uuid, text) to authenticated;
revoke all on function public.get_device_printer_assignments(uuid, text)    from public;
grant execute on function public.get_device_printer_assignments(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- C. Deliberately NO storage write policy for devices: the kiosk (like POS)
--    can only SELECT restaurant-logo objects through the widened gate above.
--    The dashboard membership policies from 20260801090000 remain the only
--    write path. (Nothing to execute — recorded so the review sees the
--    decision; the pgTAP matrix asserts the absence.)
-- ----------------------------------------------------------------------------
