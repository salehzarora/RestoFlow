-- ============================================================================
-- MVP (product-rescue) — sync_pull: expose the `tables` floor entity.
-- DOMAIN_MODEL §5.1 ("Sync: standard set"); DECISIONS D-010/D-020/D-031;
-- SECURITY T-003; RISK R-003.
-- ============================================================================
-- WHY: orders carry a non-FK table_id (RF-052) and the KDS/POS need the floor
-- map offline — the KDS maps orders.table_id -> a HUMAN TABLE LABEL via this
-- entity ("Table 5 is ready", not a bare uuid), and the POS caches the picker
-- list through the same outbox/inbox loop as everything else (D-010; Realtime
-- stays an enhancement). This forward-only CREATE OR REPLACE copies the LATEST
-- authoritative bodies (app.sync_pull_changes + app.sync_pull from
-- 20260625110000_rf109_menu_sync_pull.sql) VERBATIM and makes exactly ONE
-- addition: 'tables' becomes a pull-allowed entity
--   * for kitchen_staff (a dining-table row is MONEY-FREE — label/seats/area/
--     status only — so T-003 is not implicated; the kitchen pull path keeps the
--     app.redact_money backstop, which is a harmless no-op on these rows), AND
--   * for the price-capable business roles (org_owner/restaurant_owner/manager/
--     cashier/accountant).
-- 'tables' pages like the other BRANCH-SCOPED operational entities: STRICT
-- branch_id = device branch (tables.branch_id is NOT NULL — a dining table
-- exists at exactly one branch; the menu restaurant-scope OR-branch rule does
-- NOT apply). Tombstones flow inline via deleted_at (D-020). All existing
-- behavior — session/device validation (A8), per-entity (updated_at,id) cursor
-- + lookahead (A1/RF057-B1), limit default 500 / cap 1000 (A7), the
-- operation_statuses feed (A4), kitchen money redaction (A3/T-003), grants —
-- is preserved verbatim. No schema change; the public.sync_pull wrapper
-- (RF-064) is untouched. FORWARD-ONLY (Supabase replays on db reset).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.sync_pull_changes — RF-109 body + 'tables' in the allow-list. 'tables'
--    is NOT a menu entity, so it falls through to the strict-branch operational
--    pager (branch_id = device branch), which is exactly right for a floor row.
-- ----------------------------------------------------------------------------
create or replace function app.sync_pull_changes(
  p_table            text,
  p_org              uuid,
  p_branch           uuid,
  p_since_updated_at timestamptz,
  p_since_id         uuid,
  p_limit            integer
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_rows    jsonb;
  v_count   integer;
  v_last    jsonb;
  v_is_menu boolean;
begin
  -- defence in depth: only the six approved operational tables + the six RF-109
  -- menu tables + the MVP `tables` floor entity are pageable here (unknown
  -- entity validation is preserved).
  if p_table not in ('orders', 'order_items', 'order_item_modifiers', 'payments', 'shifts', 'cash_drawer_sessions',
                     'menu_categories', 'menu_items', 'item_sizes', 'item_variants', 'modifiers', 'modifier_options',
                     'tables') then
    raise exception 'sync_pull_changes: % is not a pull-allowed entity', p_table using errcode = '42501';
  end if;

  v_is_menu := p_table in ('menu_categories', 'menu_items', 'item_sizes', 'item_variants', 'modifiers', 'modifier_options');

  if v_is_menu then
    -- RF-109 menu scope: branch-specific rows for the device branch PLUS restaurant-scoped rows
    -- (branch_id null) of the device's own restaurant (derived from the device branch so other
    -- restaurants' restaurant-scoped menu never leaks). Same (updated_at,id) cursor + lookahead +
    -- tombstones (deleted_at) as the operational pager.
    execute format($q$
      with look as (
        select t.id as _id, t.updated_at as _uat, to_jsonb(t) as _row,
               row_number() over (order by t.updated_at asc, t.id asc) as _rn
        from public.%I t
        where t.organization_id = $1
          and (t.branch_id = $2
               or (t.branch_id is null
                   and t.restaurant_id = (select b.restaurant_id from public.branches b where b.id = $2)))
          and ($3 is null or t.updated_at > $3 or (t.updated_at = $3 and t.id > $4))
        order by t.updated_at asc, t.id asc
        limit $5 + 1
      ),
      page as (
        select _id, _uat, _row from look where _rn <= $5
      )
      select coalesce(jsonb_agg(_row order by _uat asc, _id asc), '[]'::jsonb),
             (select count(*) from look)::int,
             (select jsonb_build_object('updated_at', _uat, 'id', _id) from page order by _uat desc, _id desc limit 1)
      from page
    $q$, p_table)
    into v_rows, v_count, v_last
    using p_org, p_branch, p_since_updated_at, p_since_id, p_limit;
  else
    -- existing RF-057 operational-table pager, UNCHANGED (strict branch_id = device
    -- branch). The MVP `tables` entity pages HERE: tables.branch_id is NOT NULL.
    execute format($q$
      with look as (
        select t.id as _id, t.updated_at as _uat, to_jsonb(t) as _row,
               row_number() over (order by t.updated_at asc, t.id asc) as _rn
        from public.%I t
        where t.organization_id = $1
          and t.branch_id = $2
          and ($3 is null or t.updated_at > $3 or (t.updated_at = $3 and t.id > $4))
        order by t.updated_at asc, t.id asc
        limit $5 + 1
      ),
      page as (
        select _id, _uat, _row from look where _rn <= $5
      )
      select coalesce(jsonb_agg(_row order by _uat asc, _id asc), '[]'::jsonb),
             (select count(*) from look)::int,
             (select jsonb_build_object('updated_at', _uat, 'id', _id) from page order by _uat desc, _id desc limit 1)
      from page
    $q$, p_table)
    into v_rows, v_count, v_last
    using p_org, p_branch, p_since_updated_at, p_since_id, p_limit;
  end if;

  return jsonb_build_object(
    'rows',        v_rows,
    'next_cursor', case when v_count > 0 then v_last else null end,
    'has_more',    (v_count > p_limit));
end;
$$;

comment on function app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer) is
  'RF-057 internal helper for app.sync_pull, extended by RF-109 (menu) and the MVP `tables` floor entity: pages ONE allow-listed table by (updated_at, id). Operational tables (orders/order_items/order_item_modifiers/payments/shifts/cash_drawer_sessions) AND `tables` page within (organization_id, branch_id) — a dining table is strictly branch-scoped (branch_id NOT NULL), letting the KDS map orders.table_id -> a human label offline. The six RF-109 menu tables page within organization_id and (branch_id = device branch OR branch_id null AND restaurant_id = device restaurant). Returns {rows (incl. tombstones via deleted_at), next_cursor, has_more}. NOT client-facing (no authenticated grant); table name is allow-listed (no injection).';

revoke all on function app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer) from public;

-- ----------------------------------------------------------------------------
-- 2. app.sync_pull — RF-109 body + 'tables' allowed for BOTH the kitchen_staff
--    allow-list (money-free rows; redact_money backstop preserved and harmless)
--    and the price-capable business set.
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
  -- RF-109: the six menu reference entities. Price-capable roles only (menu rows carry money, T-003).
  c_menu        constant text[] := array['menu_categories', 'menu_items', 'item_sizes', 'item_variants', 'modifiers', 'modifier_options'];
  -- MVP: the money-free floor entity — EVERY device role may pull it (the KDS
  -- maps orders.table_id -> a human table label through this feed).
  c_floor       constant text[] := array['tables'];
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

  -- (b) role-permitted entities (A5): kitchen_staff -> non-financial operational
  --     + the money-free `tables` floor entity (NO menu -- menu rows carry money,
  --     T-003). Price-capable roles -> operational business + RF-109 menu + tables.
  if v_role = 'kitchen_staff' then
    v_allowed := array['orders', 'order_items', 'order_item_modifiers'] || c_floor;
  elsif v_role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant') then
    v_allowed := c_business || c_menu || c_floor;
  else
    v_allowed := array[]::text[];
  end if;

  -- (c) resolve the requested set. null -> all role-permitted + operation_statuses.
  --     Otherwise validate each name: unknown -> reject; not-permitted-for-role -> reject.
  if p_entities is null then
    v_requested   := v_allowed;
    v_include_ops := true;
  else
    v_requested   := array[]::text[];
    v_include_ops := false;
    foreach v_entity in array p_entities loop
      if v_entity = 'operation_statuses' then
        v_include_ops := true;
      elsif v_entity = any(c_business) or v_entity = any(c_menu) or v_entity = any(c_floor) then
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

  -- (d) page each requested entity by its per-entity (updated_at, id) cursor.
  foreach v_entity in array v_requested loop
    v_cur   := p_cursors -> v_entity;
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    v_changes := v_changes || jsonb_build_object(
      v_entity, app.sync_pull_changes(v_entity, v_org, v_branch, v_c_uat, v_c_id, v_limit));
  end loop;

  -- (d2) KITCHEN MONEY REDACTION (RF-059, A3/T-003): kitchen_staff must receive NO money figure.
  --      Preserved verbatim. (Kitchen never reaches the paging loop for a menu entity -- a menu
  --      request is rejected in (c) -- so this strips money only from the operational rows kitchen
  --      legitimately receives; it remains a defence-in-depth backstop for any *_minor key.
  --      `tables` rows are money-free, so redact_money is a harmless no-op on them.)
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

  -- (e) current-device operation-status feed (A4): sync_operations for THIS org + THIS device
  --     only. Projects status/conflict fields; excludes raw payload. Empty when not requested.
  if v_include_ops then
    v_cur   := p_cursors -> 'operation_statuses';
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
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
  'RF-057 pull RPC, hardened by RF-059 (A3/T-003), extended by RF-109 (menu) and the MVP `tables` floor entity. Session/device validation (A8), role-permitted entity set (A5), per-entity (updated_at,id) cursor (A1), tombstones inline (A9), limit default 500/cap 1000, current-device operation_statuses feed (A4), RF057-B1 lookahead, and kitchen money redaction are preserved verbatim. RF-109: the six menu entities stay price-capable-roles-only (kitchen 42501 -- menu rows carry money, T-003). MVP: `tables` is pull-allowed for EVERY device role INCLUDING kitchen_staff -- a dining-table row is money-free (label/seats/area/status) and the KDS maps orders.table_id -> a human label through it; the redact_money backstop still passes over kitchen `tables` rows (harmless no-op). Strict branch scope for `tables` (branch_id = device branch). Read-only; no audit. Org+branch (and, for menu, restaurant-scoped) filter is the isolation boundary (R-003).';

revoke all on function app.sync_pull(uuid, uuid, text[], jsonb, integer) from public;
grant execute on function app.sync_pull(uuid, uuid, text[], jsonb, integer) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   restore the 20260625110000_rf109_menu_sync_pull.sql bodies of
--   app.sync_pull_changes and app.sync_pull (no 'tables' entity).
--   The public.sync_pull wrapper (RF-064) is untouched by this migration.
-- ============================================================================
