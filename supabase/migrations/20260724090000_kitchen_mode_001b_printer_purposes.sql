-- ============================================================================
-- KITCHEN-MODE-001B — printer purposes: `both` role + purpose-aware device
-- assignments + printer Activity-Log classification. ADDITIVE ONLY.
--
-- DORMANCY UNCHANGED: this migration touches NOTHING about
-- branches.kitchen_workflow_mode — no setter, no activation path, no order
-- lifecycle change. The only mode READ added here (inside
-- get_device_printer_assignments) fail-closes to 'kds', so the widened POS
-- membership (receipt+kitchen+both) is reachable ONLY via privileged test
-- fixtures until a later phase ships the owner setter.
--
-- OLD-CLIENT COMPATIBILITY (hard requirement): deployed POS/KDS APKs parse the
-- assignment `role` as an OPAQUE STRING ((row['role'] ?? '').toString() in
-- packages/feature_auth) and never branch on or render it, and the Dashboard
-- skips unknown roles — so a raw 'both' could not crash them. The response
-- still keeps `role` in the LEGACY two-value vocabulary from the device's
-- perspective (both -> receipt for POS, kitchen for KDS) and adds ADDITIVE
-- `configured_role` + `supported_purposes` keys for new clients, so no
-- installed parser ever meets an unknown role value at all.
--
-- Contents:
--   1. printer_devices.role CHECK -> ('receipt','kitchen','both') (named
--      constraint swap; no data rewrite; existing rows stay valid).
--   2. app.upsert_printer_device — faithful re-creation of the NEWEST body
--      (20260630110000; the 20260701090000 hardening replaced only
--      printer_guard/soft_delete) with ONE delta: role validation accepts both.
--   3. app.get_device_printer_assignments — faithful re-creation of the NEWEST
--      body (20260704130000) with the role-membership + compatibility deltas.
--   4. Activity-Log classification: audit_category / audit_action_has_detail /
--      audit_safe_detail faithful re-creations — printer.% classifies as
--      'settings' and projects ONLY safe scalars (endpoints are nested objects
--      and structurally excluded).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Role CHECK: receipt | kitchen | both. The inline column CHECK from RF-150
--    auto-named printer_devices_role_check; swap it for the named three-value
--    constraint. ADD CHECK validates existing rows (all 'receipt'/'kitchen' —
--    trivially valid); nothing is rewritten or backfilled.
-- ----------------------------------------------------------------------------
alter table public.printer_devices
  drop constraint printer_devices_role_check;
alter table public.printer_devices
  add constraint printer_devices_role_check
  check (role in ('receipt', 'kitchen', 'both'));

comment on column public.printer_devices.role is
  'RF-150 + KITCHEN-MODE-001B: what this printer prints. receipt = customer receipts; kitchen = kitchen tickets; both = ONE physical printer eligible for BOTH purposes (no duplicate row). Purpose derivation: receipt->{customer_receipt}, kitchen->{kitchen_ticket}, both->{customer_receipt,kitchen_ticket}; device-facing exposure is filtered by device type + branch workflow mode in app.get_device_printer_assignments.';

-- ----------------------------------------------------------------------------
-- 2. app.upsert_printer_device — faithful re-creation (role accepts both).
-- ----------------------------------------------------------------------------

create or replace function app.upsert_printer_device(
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_id                uuid    default null,
  p_display_name      text    default null,
  p_connection_type   text    default null,
  p_role              text    default null,
  p_paper_width       text    default '80mm',
  p_connection_config jsonb   default '{}'::jsonb,
  p_is_enabled        boolean default true
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_found_org    uuid;
  v_found_rest   uuid;
  v_found_branch uuid;
  v_id           uuid;
  v_action       text;
  v_old          jsonb;
  v_new          jsonb;
  v_config       jsonb := coalesce(p_connection_config, '{}'::jsonb);
  v_width        text  := coalesce(p_paper_width, '80mm');
begin
  if not app.printer_guard(p_organization_id, p_restaurant_id, p_branch_id) then
    perform app.printer_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'printer.printer_device.upsert_denied', null,
      jsonb_build_object('entity', 'printer_device', 'id', p_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'printer_device');
  end if;

  -- input validation (no money; integer-free).
  if p_display_name is null or length(btrim(p_display_name)) = 0 then
    raise exception 'upsert_printer_device: display_name is required' using errcode = '42501';
  end if;
  if p_connection_type is null or p_connection_type not in ('network', 'usb', 'bluetooth') then
    raise exception 'upsert_printer_device: connection_type must be network|usb|bluetooth' using errcode = '42501';
  end if;
  -- KITCHEN-MODE-001B: `both` marks ONE physical printer as eligible for BOTH
  -- purposes (customer receipts + kitchen tickets) — no duplicate row needed.
  if p_role is null or p_role not in ('receipt', 'kitchen', 'both') then
    raise exception 'upsert_printer_device: role must be receipt|kitchen|both' using errcode = '42501';
  end if;
  if v_width not in ('58mm', '80mm') then
    raise exception 'upsert_printer_device: paper_width must be 58mm|80mm' using errcode = '42501';
  end if;
  if jsonb_typeof(v_config) <> 'object' then
    raise exception 'upsert_printer_device: connection_config must be a JSON object' using errcode = '42501';
  end if;

  if p_id is not null then
    select organization_id, restaurant_id, branch_id into v_found_org, v_found_rest, v_found_branch
      from public.printer_devices where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'upsert_printer_device: id belongs to another organization' using errcode = '42501';
      end if;
      -- org/restaurant/branch are IMMUTABLE on update (no scope move / hijack).
      if v_found_rest is distinct from p_restaurant_id or v_found_branch is distinct from p_branch_id then
        raise exception 'upsert_printer_device: organization/restaurant/branch are immutable on update' using errcode = '42501';
      end if;
    end if;
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    insert into public.printer_devices
      (id, organization_id, restaurant_id, branch_id, display_name, connection_type, role,
       paper_width, connection_config, is_enabled)
    values
      (v_id, p_organization_id, p_restaurant_id, p_branch_id, btrim(p_display_name), p_connection_type, p_role,
       v_width, v_config, coalesce(p_is_enabled, true));
    v_action := 'created';
  else
    v_id := p_id;
    select to_jsonb(t) into v_old from public.printer_devices t where t.id = p_id;
    update public.printer_devices set
      display_name = btrim(p_display_name), connection_type = p_connection_type, role = p_role,
      paper_width = v_width, connection_config = v_config, is_enabled = coalesce(p_is_enabled, true),
      revision = revision + 1
    where id = p_id;
    v_action := 'updated';
  end if;

  select to_jsonb(t) into v_new from public.printer_devices t where t.id = v_id;
  perform app.printer_audit(p_organization_id, p_restaurant_id, p_branch_id,
    'printer.printer_device.' || v_action, v_old, v_new);
  return jsonb_build_object('ok', true, 'entity', 'printer_device', 'id', v_id, 'action', v_action);
end;
$$;



comment on function app.upsert_printer_device(uuid, uuid, uuid, uuid, text, text, text, text, jsonb, boolean) is
  'RF-150 + KITCHEN-MODE-001B: create/update one printer_devices row (manager+ via app.printer_guard; scope immutable on update; full before/after audit printer.printer_device.created/updated). KITCHEN-MODE-001B widens role validation to receipt|kitchen|both — everything else is a faithful re-creation of the 20260630110000 body.';

revoke all on function app.upsert_printer_device(uuid, uuid, uuid, uuid, text, text, text, text, jsonb, boolean) from public;
grant execute on function app.upsert_printer_device(uuid, uuid, uuid, uuid, text, text, text, text, jsonb, boolean) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.get_device_printer_assignments — faithful re-creation with the
--    KITCHEN-MODE-001B role-membership + compatibility deltas. Response keys
--    are strictly ADDITIVE (configured_role, supported_purposes); the legacy
--    `role` key never carries an unknown value; connection_config is still
--    NEVER exposed.
-- ----------------------------------------------------------------------------

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
  v_roles    text[];
  v_kitchen_mode text;  -- KITCHEN-MODE-001B: branch workflow mode (POS role membership)
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

  -- KITCHEN-MODE-001B role membership BY DEVICE TYPE + branch workflow mode:
  --   * kds  -> kitchen + both (a `both` printer is kitchen-capable);
  --   * pos in a kds-mode branch -> receipt + both (kitchen-ONLY printers stay
  --     invisible to ordinary POS sessions before printer-only activation);
  --   * pos in a printer_only branch (reachable ONLY via privileged fixtures —
  --     no setter exists) -> receipt + kitchen + both.
  -- The mode read FAIL-CLOSES to 'kds' (001A convention): a missing branch row
  -- can only ever produce the historical narrow membership.
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
  else
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
      -- KITCHEN-MODE-001B old-client compatibility: `role` keeps the LEGACY
      -- two-value vocabulary from the DEVICE'S perspective (deployed APK
      -- parsers store it as an opaque string and never learned 'both');
      -- `configured_role` carries the REAL row value; `supported_purposes` is
      -- the additive purpose contract new clients key on.
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
            -- POS in a kds-mode branch: a `both` printer is usable for the
            -- customer purpose ONLY until printer-only activation (001C).
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
     and pd.role            = any(v_roles)
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
  'MVP + KITCHEN-MODE-001B: TOKEN-PROVEN printer-assignment read for POS/KDS devices (auth unchanged: hash match on a live ACTIVE session/pairing/device/branch/restaurant; any failure => invalid_session). KITCHEN-MODE-001B role membership: kds -> kitchen+both; pos in a kds-mode branch -> receipt+both (kitchen-only printers stay invisible before activation); pos in a printer_only branch (privileged fixtures only — no setter exists) -> receipt+kitchen+both. OLD-CLIENT COMPATIBILITY: `role` keeps the legacy two-value vocabulary from the device''s perspective (both -> receipt on POS / kitchen on KDS); ADDITIVE `configured_role` carries the real row value and `supported_purposes` the purpose contract (both is customer-only on a kds-mode POS until 001C activation). Still NEVER returns connection_config. Faithful re-creation of the 20260704130000 body.';

revoke all on function app.get_device_printer_assignments(uuid, text)    from public;
grant execute on function app.get_device_printer_assignments(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Activity-Log classification (faithful re-creations; printer.% additions).
-- ----------------------------------------------------------------------------

create or replace function app.audit_category(p_action text)
  returns text
  language sql
  immutable
  set search_path = ''
as $$
  select case
    when p_action like 'order.discount%'                               then 'discounts'
    when p_action like 'order.void%'                                   then 'voids'
    when p_action like 'order.%'                                       then 'orders'
    when p_action like 'payment.%' or p_action like 'receipt_number.%' then 'payments'
    when p_action like 'shift.%'   or p_action like 'cash_drawer.%'    then 'shifts'
    when p_action like 'staff.%'                                       then 'staff'
    when p_action like 'membership.%' or p_action like 'employee.%'
         or p_action like 'pin_session.%'                             then 'access'
    when p_action like 'device.%'                                     then 'devices'
    when p_action like 'settings.%'                                   then 'settings'
    -- KITCHEN-MODE-001B: printer configuration IS settings work — surface it
    -- under the settings category instead of the 'other' bucket.
    when p_action like 'printer.%'                                    then 'settings'
    when p_action like 'menu.%'                                       then 'menu'
    when p_action like 'table.%'                                      then 'tables'
    when p_action like 'organization.%'                               then 'organization'
    when p_action like 'sync.%'                                       then 'sync'
    else 'other'
  end;
$$;



comment on function app.audit_category(text) is
  'AUDIT-COVERAGE-002 + KITCHEN-MODE-001B: the single source of truth for Activity-log action classification. KITCHEN-MODE-001B maps printer.% to ''settings'' (printer configuration IS settings work; previously the ''other'' bucket). Faithful re-creation of the 20260711120000 body otherwise.';

revoke all on function app.audit_category(text) from public;


create or replace function app.audit_action_has_detail(p_action text)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  select coalesce(p_action, '') like 'order.void%'
      or p_action like 'order.discount%'
      or p_action like 'order.status%'
      or p_action =    'order.submitted'
      -- RESTAURANT-OPERATIONS-V1-001: table moves (order.table_moved +
      -- order.table_move_denied) carry before/after labels + denied reasons.
      or p_action like 'order.table_mov%'
      or p_action like 'staff.capabilities%'
      -- FULL-COMP-PERMISSION-001: staff.created was NOT projected, so the capabilities
      -- a cashier is PROVISIONED with were written to the append-only trail and then
      -- never shown. Granting "make orders free" invisibly is exactly what this ticket
      -- must not do, so the CREATE path is projected too.
      or p_action =    'staff.created'
      or p_action like 'membership.%'
      or p_action like 'shift.%'
      or p_action like 'cash_drawer.%'
      or p_action like 'payment.%'
      or p_action like 'settings.%'
      -- RESTAURANT-OPERATIONS-V1-001: branch availability changes/denials carry
      -- before/after availability + the item name (menu.* was previously
      -- metadata-only; ONLY the availability family gains detail).
      or p_action like 'menu.%.availability%'
      -- PILOT-OPERATIONS-CORRECTIONS-001: manual table status changes/denials
      -- (before/after floor status) and link/unlink (group label) carry detail.
      or p_action like 'table.status%'
      or p_action like 'table.tables_%'
      or p_action like 'table.link%'
      or p_action like 'table.unlink%'
      -- PSC-001C: order additions (round_number/added_item_count) and round
      -- status changes (round_number/from_status/to_status) carry safe detail.
      or p_action like 'order.items_add%'
      or p_action like 'order.round_status%'
      -- KITCHEN-MODE-001B: printer configuration actions carry a safe scalar
      -- projection (display_name / role / paper_width / is_enabled /
      -- connection_type). connection_config stays a nested object, so the
      -- scalar-only allowlist can never surface host/port/addresses.
      or p_action like 'printer.%'
      or p_action =    'pin_session.failed';
$$;


comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001 .. PSC-001C + KITCHEN-MODE-001B: is p_action a SUPPORTED action that may carry a safe payload projection? KITCHEN-MODE-001B adds the printer.% family (display_name / role / paper_width / is_enabled / connection_type safe scalars; endpoints are nested objects and structurally excluded). Faithful re-creation of the 20260722090000 body. Gates app.audit_safe_detail.';


create or replace function app.audit_safe_detail(p_action text, p_values jsonb)
  returns jsonb
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_out  jsonb := '{}'::jsonb;
  v_caps jsonb;
  v_key  text;
begin
  -- Unknown / unsupported action -> no payload details.
  if not app.audit_action_has_detail(p_action) then
    return '{}'::jsonb;
  end if;
  -- Malformed / missing / non-object payload -> empty safe detail (never throws).
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    return '{}'::jsonb;
  end if;

  -- Canonical SAFE SCALAR allowlist. A key is emitted ONLY when it is on this
  -- list AND its value is a scalar (string/number/boolean) — nested objects,
  -- arrays, and every un-listed key (secret OR merely unknown) are dropped.
  foreach v_key in array array[
    'status','order_status','scope','discount_type','value','attempted_action','order_type',
    'role','from_role','to_role','target_role',
    'discount_total_minor','grand_total_minor','subtotal_minor','line_total_minor','line_discount_minor',
    'amount_minor','tendered_minor','change_minor','opening_float_minor',
    'expected_cash_minor','counted_cash_minor','cash_variance_minor','variance_minor',
    'voided_item_count','failed_attempt_count','locked',
    'timezone','name','receipt_prefix',
    'order_code','payment_status',
    -- ORDER-AUTO-COMPLETION-001: how, and why, an order was completed. Both are
    -- STATES ('automatic'/'manual', 'order_served'/'payment_recorded'), not money
    -- and not identifiers — T-003 still holds.
    'completion_mode','completion_trigger',
    -- MONEY-SETTLEMENT-CONSISTENCY-001: WHY a mutation was denied. order.discount_denied
    -- and order.void_denied have always carried this, but it was never allowlisted — so
    -- the Activity Log showed THAT a discount was refused and never WHY. It is a closed
    -- enum of safe STATE tokens (order_has_completed_payment | full_comp_requires_manager),
    -- never money and never an identifier (T-003 holds).
    'denied_reason',
    -- FULL-COMP-PERMISSION-001: WHAT the mutation would have left the order as. A
    -- closed enum of STATE tokens ('not_chargeable') -- never money, never an
    -- identifier (T-003 holds).
    'resulting_charge_state',
    -- RESTAURANT-OPERATIONS-V1-001: branch availability (closed enums
    -- available|unavailable / sold_out|paused) + the menu item's display name,
    -- and table-move floor labels (human table names). Names/labels are tenant
    -- display text already shown on receipts/tickets — never money, never ids.
    'availability','availability_reason','item_name',
    'table_label','from_table_label','to_table_label',
    -- PILOT-OPERATIONS-CORRECTIONS-001: manual table status transition
    -- (closed enum available|reserved|occupied|out_of_service) + the combined
    -- group label (floor names). Never money, never identifiers (T-003 holds).
    'from_status','to_status','group_label',
    -- PSC-001D: void provenance + kitchen acknowledgement. voided_from_status
    -- is the closed order-status enum; device_type is the closed pos|kds enum;
    -- kitchen_ack_required is a boolean. Never money, never identifiers
    -- (T-003 holds).
    'voided_from_status','device_type','kitchen_ack_required',
    -- PSC-001C: service rounds. round_number and added_item_count are small
    -- integers (a position in the order and a line count) — never money,
    -- never identifiers (T-003 holds).
    'round_number','added_item_count',
    -- KITCHEN-MODE-001B: printer configuration scalars. display_name is tenant
    -- display text (the item_name/table_label class); the rest are closed
    -- enums/booleans. connection_config (host/port/addresses) is a NESTED
    -- OBJECT and is therefore structurally dropped by the scalar-only rule —
    -- endpoints never reach the Activity Log timeline.
    'display_name','paper_width','is_enabled','connection_type'
  ] loop
    -- PSC-001C correction (Finding 6): the four service-round actions are
    -- MONEY-FREE by approved contract — any *_minor key (hostile, manual, or
    -- accidental) is dropped for EXACTLY these actions, action-specifically:
    -- the approved money-carrying actions (payments / discounts / shifts /
    -- order.submitted / completion) keep their allowlisted money keys.
    if (p_action like 'order.items_add%' or p_action like 'order.round_status%'
        -- KITCHEN-MODE-001B: printer configuration is MONEY-FREE by contract —
        -- the same hostile-key hardening applies to the whole printer family.
        or p_action like 'printer.%')
       and v_key like '%\_minor' escape '\' then
      continue;
    end if;
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;

  -- The ONLY allowlisted nested object: `capabilities`, kept to its four
  -- canonical boolean capability keys (unknown nested keys dropped).
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp','manage_menu_availability','manage_table_operations']) as k
      where (p_values -> 'capabilities') ? k
        and jsonb_typeof(p_values -> 'capabilities' -> k) in ('string','number','boolean');
    if v_caps is distinct from '{}'::jsonb then
      v_out := v_out || jsonb_build_object('capabilities', v_caps);
    end if;
  end if;

  return v_out;
end;
$$;


comment on function app.audit_safe_detail(text, jsonb) is
  'ALLOWLIST projection of one audit payload to canonical safe fields (see 20260722090000) + KITCHEN-MODE-001B printer scalars (display_name / paper_width / is_enabled / connection_type; role was already listed). connection_config (host/port/addresses) is a NESTED OBJECT and therefore structurally dropped by the scalar-only rule — endpoints, credentials and payloads never reach the Activity Log timeline. printer.% joins the MONEY-FREE hostile-key hardening (every *_minor key dropped for the family). Faithful re-creation of the 20260722090000 body otherwise; every un-listed key/structure dropped; malformed -> ''{}''; never throws.';

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   re-create app.audit_safe_detail / app.audit_action_has_detail from
--     20260722090000, app.audit_category from 20260711120000,
--     app.get_device_printer_assignments from 20260704130000,
--     app.upsert_printer_device from 20260630110000;
--   alter table public.printer_devices drop constraint printer_devices_role_check;
--   alter table public.printer_devices add constraint printer_devices_role_check
--     check (role in ('receipt', 'kitchen'));  -- only if no 'both' rows exist
-- ============================================================================
