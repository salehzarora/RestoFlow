-- ============================================================================
-- ORDER-EDIT-001B — the READ and SYNC surface of editing a sent order
-- (API_CONTRACT §4.15, §4.30b, §4.30c, §4.45.10; ORDER_EDIT_DESIGN §8.6;
-- DECISION D-043 / D-044). DB only; every change is ADDITIVE.
--
-- Each body is copied mechanically from its LIVE definition and changed ONLY
-- where noted; every other byte is preserved.
--
--   1. app.sync_pull_changes (live 20260722090000) — + 'order_edits' in the
--      pull allowlist (strict-branch operational pager; branch_id NOT NULL).
--   2. app.sync_pull (live 20260729090000) — the money-free order_edits entity,
--      pull-allowed to the SAME role set as order_service_rounds and under the
--      SAME kitchen containment: a kitchen_staff session on a printer_only
--      branch still gets the floor only (an explicit request rejects 42501),
--      and on a KDS device the direct-print graph filter also drops the edits
--      of direct_print orders. Raw rows (to_jsonb), like every entity.
--   3. app.pos_order_detail (live 20261008150000, POS-ORDER-DETAIL-IDS-001) —
--      per item unit_status / legacy / edit_id; per order dispatch_mode,
--      kitchen_channel, edit_count, has_active_round; envelope edits[] and
--      branch_features {order_edit_enabled, order_edit_finished_food_manager_only}.
--   4. app.pos_order_snapshots (live 20260718090000) — per row edit_count,
--      kitchen_edit_ack_pending, has_active_round; the SYNC STAMP also takes
--      the order's rounds' and edits' updated_at, because a kitchen
--      acknowledgement (§4.46) and a round status change write no orders row
--      (the payment precedent): without it those flips never reach a POS.
--   5. app.pin_session_capabilities (live 20261006140000) — the advisory
--      capabilities.void_order and the top-level branch_features.
--
-- Signatures, volatility, SECURITY DEFINER, search_path and ACLs are unchanged
-- (CREATE OR REPLACE; ACLs re-stated). No public wrapper changes (each is a
-- pass-through). Reads only: no audit, no write, no new grant.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.sync_pull_changes — + order_edits in the allowlist.
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
  -- entity validation is preserved). ORDER-EDIT-001B: + the money-free
  -- order_edits entity (strict-branch operational pager: branch_id NOT NULL).
  if p_table not in ('orders', 'order_items', 'order_item_modifiers', 'payments', 'shifts', 'cash_drawer_sessions',
                     'menu_categories', 'menu_items', 'item_sizes', 'item_variants', 'modifiers', 'modifier_options',
                     'tables', 'order_service_rounds', 'order_edits') then
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
do $do$
begin
  execute format('comment on function app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer) is %L',
    obj_description('app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer)'::regprocedure, 'pg_proc')
    || ' ORDER-EDIT-001B: order_edits (money-free, append-only) joins the STRICT-BRANCH operational set.');
end;
$do$;

revoke all on function app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer) from public;

-- ----------------------------------------------------------------------------
-- 2. app.sync_pull — the order_edits entity under the kitchen containment.
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
  v_kitchen_mode text;      -- KITCHEN-MODE-001A: branch workflow mode (kitchen gate)
  v_ops_suppressed boolean := false;  -- KITCHEN-MODE-001A (HIGH-1): op-status feed off for printer-only kitchen
  v_device_type text;                 -- KITCHEN-PRINT-DUAL-001C: kind of the session-backing device
  v_is_kds boolean := false;          -- KITCHEN-PRINT-DUAL-001C: caller is a KDS device (device_type='kds')
  c_financial   constant text[] := array['payments', 'shifts', 'cash_drawer_sessions'];
  -- ORDER-EDIT-001B: + order_edits (money-free; the order_service_rounds role set).
  c_business    constant text[] := array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds', 'order_edits', 'payments', 'shifts', 'cash_drawer_sessions'];
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

  -- KITCHEN-PRINT-DUAL-001C: resolve the TRUSTED device kind for the KDS filter.
  -- v_ds_device is the session-backing device (validated == p_device_id above), so
  -- devices.device_type here is server-owned and NOT client-spoofable; this mirrors
  -- the shipped KDS-class gate in app.kitchen_ack_void / app.update_round_status.
  select d.device_type into v_device_type
    from public.devices d
    where d.id = v_ds_device;
  v_is_kds := coalesce(v_device_type, '') = 'kds';

  -- (b) role-permitted entities (A5): kitchen_staff -> non-financial operational
  --     + the money-free `tables` floor entity (NO menu -- menu rows carry money,
  --     T-003). Price-capable roles -> operational business + RF-109 menu + tables.
  if v_role = 'kitchen_staff' then
    -- KITCHEN-MODE-001A: the AUTHORITATIVE kitchen exclusion. In a
    -- `printer_only` branch there is no kitchen board — the kitchen ticket is
    -- paper — so a kitchen_staff session is served NO actionable order
    -- entities (orders / order_items / order_item_modifiers /
    -- order_service_rounds / order_edits are all withheld). Only the money-free `tables`
    -- floor entity remains, which is exactly enough for a safe, honest EMPTY
    -- board on any KDS that is (accidentally) paired to such a branch. An
    -- EXPLICIT request for an order entity rejects with the existing
    -- not-permitted-for-role 42501 in (c) below — fail closed, never a
    -- silently truncated feed dressed up as a full one. The mode read
    -- fail-closes to 'kds', so a missing branch row can only ever produce the
    -- historical allow-list. No other role's exposure changes.
    select b.kitchen_workflow_mode into v_kitchen_mode
      from public.branches b
      where b.id              = v_branch
        and b.organization_id = v_org
        and b.deleted_at is null;
    if coalesce(v_kitchen_mode, 'kds') = 'printer_only' then
      v_allowed := c_floor;
      -- KITCHEN-MODE-001A (HIGH-1): the paper-only kitchen does not consume
      -- order sync operations — the operation-status feed projects target_id,
      -- result and conflict_info, which carry order identifiers and
      -- money-shaped keys (e.g. change_due_minor) and must remain
      -- money-free and order-identifier-free on this surface. Suppressed
      -- authoritatively below (empty collection), even when explicitly
      -- requested.
      v_ops_suppressed := true;
    else
      -- KDS MODE (default) — the PSC-001C allow-list plus ORDER-EDIT-001B's
      -- order_edits: order_service_rounds is MONEY-FREE by schema — the kitchen
      -- needs it to render Addition/Round N tickets with the round's own status;
      -- order_edits is money-free too — the kitchen learns of each edit, and of
      -- its acknowledgement (which writes no orders row), through it (D-044).
      v_allowed := array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds', 'order_edits'] || c_floor;
    end if;
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

  -- KITCHEN-MODE-001A (HIGH-1): the AUTHORITATIVE operation-status exclusion
  -- for the printer-only kitchen. Forcing v_include_ops off routes section (e)
  -- to its existing empty-collection branch — {rows: [], next_cursor: null,
  -- has_more: false} — a valid envelope carrying NO operation metadata, order
  -- identifier or money-shaped key. Backend-side by design: cosmetic
  -- client-side redaction would leave the wire payload exposed. kitchen_staff
  -- in kds mode and every other role keep the existing feed unchanged.
  if v_ops_suppressed then
    v_include_ops := false;
  end if;

  -- (d) page each requested entity by its per-entity (updated_at, id) cursor.
  foreach v_entity in array v_requested loop
    v_cur   := p_cursors -> v_entity;
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    v_changes := v_changes || jsonb_build_object(
      v_entity, app.sync_pull_changes(v_entity, v_org, v_branch, v_c_uat, v_c_id, v_limit));
  end loop;

  -- (d1) KITCHEN-PRINT-DUAL-001C: a KDS DEVICE never receives the graph of a
  --      direct_print order. Such an order is authoritatively finalized OUT of the
  --      active KDS workflow (the POS printed its ticket in app.sync_push), so its
  --      complete order graph must never enter KDS local state. The entity-generic
  --      pager (app.sync_pull_changes) ships full rows and has no dispatch awareness,
  --      so the exclusion is applied HERE, keyed on the TRUSTED device kind
  --      (v_is_kds), never the membership role (a manager may sit at a KDS;
  --      kitchen_staff may sit at a POS) nor the client p_device_id. It runs AFTER
  --      the pager has already computed each entity's next_cursor + has_more over the
  --      EXAMINED rows, and it DROPS ROWS ONLY (never touches next_cursor/has_more) —
  --      so the KDS cursor still advances PAST filtered direct_print rows (a branch
  --      that runs direct_print as its primary workflow never stalls or re-scans the
  --      backlog) and pagination is preserved verbatim. The graph is the five order
  --      entities a KDS can pull: orders (dispatch_mode inline), order_items +
  --      order_service_rounds + order_edits (direct order_id; order_edits since
  --      ORDER-EDIT-001B), order_item_modifiers (TRANSITIVE via its parent
  --      order_item). Money/menu entities are role-gated out of a KDS, so these
  --      five are the complete KDS-visible graph. Non-KDS callers are untouched.
  if v_is_kds then
    select coalesce(
             jsonb_object_agg(
               ent,
               case
                 when jsonb_typeof(val -> 'rows') <> 'array' then val
                 when ent = 'orders' then
                   jsonb_set(val, '{rows}', coalesce((
                     select jsonb_agg(r)
                       from jsonb_array_elements(val -> 'rows') as r
                      where coalesce(r ->> 'dispatch_mode', 'kds') <> 'direct_print'), '[]'::jsonb))
                 when ent in ('order_items', 'order_service_rounds', 'order_edits') then
                   jsonb_set(val, '{rows}', coalesce((
                     select jsonb_agg(r)
                       from jsonb_array_elements(val -> 'rows') as r
                      where not exists (
                        select 1 from public.orders o
                         where o.organization_id = v_org
                           and o.id = (r ->> 'order_id')::uuid
                           and coalesce(o.dispatch_mode, 'kds') = 'direct_print')), '[]'::jsonb))
                 when ent = 'order_item_modifiers' then
                   jsonb_set(val, '{rows}', coalesce((
                     select jsonb_agg(r)
                       from jsonb_array_elements(val -> 'rows') as r
                      where not exists (
                        select 1 from public.order_items oi
                          join public.orders o
                            on o.organization_id = oi.organization_id and o.id = oi.order_id
                         where oi.organization_id = v_org
                           and oi.id = (r ->> 'order_item_id')::uuid
                           and coalesce(o.dispatch_mode, 'kds') = 'direct_print')), '[]'::jsonb))
                 else val
               end),
             '{}'::jsonb)
      into v_changes
      from jsonb_each(v_changes) as ec(ent, val);
  end if;

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
do $do$
begin
  execute format('comment on function app.sync_pull(uuid, uuid, text[], jsonb, integer) is %L',
    obj_description('app.sync_pull(uuid, uuid, text[], jsonb, integer)'::regprocedure, 'pg_proc')
    || ' ORDER-EDIT-001B (D-044): + the money-free order_edits entity, pull-allowed to the order_service_rounds role set (kitchen_staff in kds mode and every price-capable role); a kitchen_staff session on a printer_only branch still gets the floor only (an explicit order_edits request rejects 42501), and the KDS direct-print graph filter now drops order_edits of direct_print orders too (five entities). Raw rows, like every entity; an acknowledgement stamps the edit row and reaches every KDS through this entity.');
end;
$do$;

revoke all on function app.sync_pull(uuid, uuid, text[], jsonb, integer) from public;
grant execute on function app.sync_pull(uuid, uuid, text[], jsonb, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.pos_order_detail — the remaining §4.45.10 fields.
-- ----------------------------------------------------------------------------
create or replace function app.pos_order_detail(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_order_id       uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_device_type text;
  v_order       jsonb;
  v_items       jsonb;
  v_rounds      jsonb;
  v_payment     jsonb;
  v_b_mode      text;     -- ORDER-EDIT-001B: the session branch's kitchen mode
  v_b_enabled   boolean;  -- ORDER-EDIT-001B: branches.order_edit_enabled
  v_b_ff        boolean;  -- ORDER-EDIT-001B: branches.order_edit_finished_food_manager_only
  v_channel     text;     -- ORDER-EDIT-001B: the order's resolved kitchen channel
  v_edits       jsonb;    -- ORDER-EDIT-001B: the order's edits
begin
  -- (a) THE CANONICAL PIN-SESSION PREAMBLE (pos_order_snapshots parity):
  --     every structural failure collapses to ONE indistinguishable envelope.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found or not app.is_pin_session_valid(p_pin_session_id) then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found
     or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active')
     or v_ds_device is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;

  -- (b) POS-class device + price-capable POS role (this read carries money).
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;
  if v_device_type is distinct from 'pos' then
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'entity', 'order_detail');
  end if;
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'order_detail');
  end if;

  -- (c) the order — SESSION org+branch scope only. A nonexistent and a
  --     foreign-scope order collapse to the SAME envelope (no oracle, R-003).
  select jsonb_build_object(
           'order_id',             o.id,
           'order_code',           '#' || upper(right(replace(o.id::text, '-', ''), 6)),
           'order_type',           o.order_type,
           'status',               o.status,
           'revision',             o.revision,
           'table_label',          tbl.label,
           'customer_name',        o.customer_name,
           'customer_phone',       o.customer_phone,
           'currency_code',        o.currency_code,
           'subtotal_minor',       o.subtotal_minor,
           'discount_total_minor', o.discount_total_minor,
           'tax_total_minor',      o.tax_total_minor,
           'grand_total_minor',    o.grand_total_minor,
           'receipt_number',       o.receipt_number,
           'created_at',           o.created_at,
           'updated_at',           o.updated_at,
           -- ORDER-EDIT-001B (D-043): additive, money-free. has_active_round =
           -- any live service round of the order in submitted..ready (the
           -- app.void_order live-round predicate; an edit-emptied round is
           -- 'voided'). On a printer_only branch nothing advances a round, so
           -- it stays 'submitted' (and this flag TRUE) until completion.
           'dispatch_mode',        o.dispatch_mode,
           'edit_count',           o.edit_count,
           'has_active_round',     exists (
                                     select 1 from public.order_service_rounds ar
                                      where ar.organization_id = o.organization_id
                                        and ar.order_id        = o.id
                                        and ar.deleted_at is null
                                        and ar.status in ('submitted', 'accepted', 'preparing', 'ready')))
    into v_order
    from public.orders o
    left join public.tables tbl
      on  tbl.organization_id = o.organization_id
      and tbl.id              = o.table_id
    where o.id              = p_order_id
      and o.organization_id = v_org
      and o.branch_id       = v_branch
      and o.deleted_at is null;
  if v_order is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found', 'entity', 'order_detail');
  end if;

  -- (c1) ORDER-EDIT-001B: the session branch's kitchen mode and its two edit
  --      switches (§4.45.8): the SAME row predicate app.edit_order reads, but
  --      without its share lock (this read is STABLE) and without its raise.
  --      An unreadable branch row yields both switches FALSE (the "Edit order"
  --      entry hides) and kitchen_channel NULL; the reprint read never fails.
  --      kitchen_channel mirrors edit_order step 5: 'paper' on a printer_only
  --      branch; otherwise 'kds' unless the order is direct_print, whose
  --      channel is unresolvable (edit_order refuses it kitchen_mode_changed)
  --      and reads NULL.
  select b.kitchen_workflow_mode, b.order_edit_enabled, b.order_edit_finished_food_manager_only
    into v_b_mode, v_b_enabled, v_b_ff
    from public.branches b
    where b.id              = v_branch
      and b.organization_id = v_org
      and b.deleted_at is null;
  v_channel := case
                 when v_b_mode = 'printer_only' then 'paper'
                 when v_b_mode is not null
                      and coalesce(v_order ->> 'dispatch_mode', 'kds') <> 'direct_print' then 'kds'
                 else null
               end;
  v_order := v_order || jsonb_build_object('kitchen_channel', v_channel);

  -- (d) every ACTIVE customer-visible item, with modifiers and round
  --     membership (NULL service_round_id = the original submission).
  --     MENU-ORDER-001: carries + orders by the menu-configured print snapshots.
  --     KIOSK-PRINT-114B.5B: + the ALLOWLISTED order-time kitchen snapshots
  --     (per unit; NULL when never stored; nothing re-derived).
  select coalesce(jsonb_agg(jsonb_build_object(
           'order_item_id',             oi.id,
           'menu_item_id',              oi.menu_item_id,
           'menu_item_name_snapshot',   oi.menu_item_name_snapshot,
           'quantity',                  oi.quantity,
           'unit_price_minor_snapshot', oi.unit_price_minor_snapshot,
           'line_discount_minor',       oi.line_discount_minor,
           'line_total_minor',          oi.line_total_minor,
           -- MENU-ORDER-001: the menu-configured print-order snapshots so a
           -- cross-device reprint matches the live receipt (the client sorts too).
           'category_display_order_snapshot', oi.category_display_order_snapshot,
           'item_display_order_snapshot',     oi.item_display_order_snapshot,
           'line_position',             oi.line_position,
           'status',                    oi.status,
           'notes',                     oi.notes,
           'item_size_snapshot',        oi.item_size_snapshot,
           'item_variant_snapshot',     oi.item_variant_snapshot,
           'service_round_id',          oi.service_round_id,
           'round_number',              r.round_number,
           -- 114B.5B: the item's PER-UNIT prep snapshot through the 017
           -- allowlist (the SAME projection the dispatch payload carries).
           'prep_snapshot',             app.kitchen_prep_projection(oi.prep_snapshot),
           'modifiers',                 coalesce(mods.list, '[]'::jsonb),
           -- ORDER-EDIT-001B (D-043): the stage of the line's WORK UNIT (the
           -- order status for the original ticket, the round status for a
           -- round line; edit_order step 6, raw D-018 values, never a
           -- pseudo-state), the server-computed M1a legacy-price flag (the
           -- SAME helper edit_order step 6 calls) and the edit that wrote it.
           'unit_status',               case when oi.service_round_id is null
                                             then v_order ->> 'status' else r.status end,
           'legacy',                    app.order_item_is_legacy_priced(v_org, oi.id),
           'edit_id',                   oi.edit_id
         ) order by oi.category_display_order_snapshot asc,
                    oi.item_display_order_snapshot asc,
                    oi.line_position asc,
                    oi.created_at asc, oi.id asc), '[]'::jsonb)
    into v_items
    from public.order_items oi
    left join public.order_service_rounds r
      on  r.organization_id = oi.organization_id
      and r.id              = oi.service_round_id
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'modifier_name_snapshot', m.modifier_name_snapshot,
               'option_name_snapshot',   m.option_name_snapshot,
               'price_minor_snapshot',   m.price_minor_snapshot,
               'quantity',               m.quantity,
               -- 114B.5B: the option's PER-MODIFIER-UNIT meat contribution
               -- through the 019 allowlist (the SAME projection the dispatch
               -- payload carries); NULL when the option contributes nothing.
               'meat_snapshot',          app.kitchen_modifier_prep_projection(m.meat_snapshot),
               -- POS-ORDER-DETAIL-IDS-001 (ORDER-EDIT slice 2): the option's
               -- non-FK reference id and its order-time display-order ranks
               -- (MENU-ORDER-001 trigger-stamped; until now used only in the
               -- ORDER BY below), so a POS can rebuild the line faithfully.
               'modifier_option_id',                     m.modifier_option_id,
               'modifier_group_display_order_snapshot',  m.modifier_group_display_order_snapshot,
               'modifier_option_display_order_snapshot', m.modifier_option_display_order_snapshot
             ) order by m.modifier_group_display_order_snapshot asc,
                        m.modifier_option_display_order_snapshot asc,
                        m.line_position asc,
                        m.created_at asc, m.id asc) as list
        from public.order_item_modifiers m
        where m.organization_id = oi.organization_id
          and m.order_item_id   = oi.id
          and m.deleted_at is null
    ) mods on true
    where oi.organization_id = v_org
      and oi.order_id        = p_order_id
      and oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled');

  -- (e) the round list (voided rounds included — status says so).
  select coalesce(jsonb_agg(jsonb_build_object(
           'round_id',     r.id,
           'round_number', r.round_number,
           'status',       r.status,
           'ready_at',     r.ready_at,
           'created_at',   r.created_at
         ) order by r.round_number asc), '[]'::jsonb)
    into v_rounds
    from public.order_service_rounds r
    where r.organization_id = v_org
      and r.order_id        = p_order_id
      and r.deleted_at is null;

  -- (f) the (at most one) completed payment — enough for a faithful reprint.
  select jsonb_build_object(
           'payment_id',     p.id,
           'payment_status', p.status,
           'method',         p.method,
           'amount_minor',   p.amount_minor,
           'tendered_minor', p.tendered_minor,
           'change_minor',   p.change_minor,
           'receipt_number', p.receipt_number,
           'created_at',     p.created_at)
    into v_payment
    from public.payments p
    where p.organization_id = v_org
      and p.order_id        = p_order_id
      and p.status          = 'completed'
      and p.deleted_at is null
    limit 1;

  -- (g) ORDER-EDIT-001B (D-043 / D-044): the order's edits, oldest first.
  --     Money-free, and no staff, session or device identifier.
  --     kitchen_ack_pending is the server's verdict per edit (the SAME rule as
  --     pos_order_snapshots.kitchen_edit_ack_pending): a required confirmation
  --     not yet given, FALSE on a voided order (a whole-order void supersedes
  --     every pending edit confirmation, §4.46).
  select coalesce(jsonb_agg(jsonb_build_object(
           'order_edit_id',        e.id,
           'edit_number',          e.edit_number,
           'created_at',           e.created_at,
           'reason_code',          e.reason_code,
           'reason_text',          e.reason_text,
           'kitchen_channel',      e.kitchen_channel,
           'kitchen_ack_required', e.kitchen_ack_required,
           'kitchen_ack_at',       e.kitchen_ack_at,
           'kitchen_ack_pending',  e.kitchen_ack_required
                                   and e.kitchen_ack_at is null
                                   and (v_order ->> 'status') <> 'voided'
         ) order by e.edit_number asc), '[]'::jsonb)
    into v_edits
    from public.order_edits e
    where e.organization_id = v_org
      and e.order_id        = p_order_id
      and e.branch_id       = v_branch
      and e.deleted_at is null;

  return jsonb_build_object(
    'ok', true, 'entity', 'order_detail', 'server_ts', now(),
    'order',   v_order,
    'items',   v_items,
    'rounds',  v_rounds,
    'payment', v_payment,
    -- ORDER-EDIT-001B: the edits and the branch's two switches (the
    -- pin_session_capabilities.branch_features shape; FALSE when unreadable).
    'edits',   v_edits,
    'branch_features', jsonb_build_object(
      'order_edit_enabled',                    coalesce(v_b_enabled, false),
      'order_edit_finished_food_manager_only', coalesce(v_b_ff, false)));
end;
$$;
do $do$
begin
  execute format('comment on function app.pos_order_detail(uuid, uuid, uuid) is %L',
    obj_description('app.pos_order_detail(uuid, uuid, uuid)'::regprocedure, 'pg_proc')
    || ' ORDER-EDIT-001B (D-043): + per item unit_status (the raw status of the line''s work unit: the order for the original ticket, the round for a round line), legacy (the M1a predicate, app.order_item_is_legacy_priced) and edit_id; + per order dispatch_mode, kitchen_channel (paper on a printer_only branch, else kds, NULL when unresolvable or the branch row is unreadable), edit_count and has_active_round; + envelope edits[] (money-free, oldest first, with a server-computed kitchen_ack_pending) and branch_features {order_edit_enabled, order_edit_finished_food_manager_only} (FALSE when unreadable). Nothing else changed.');
end;
$do$;

revoke all on function app.pos_order_detail(uuid, uuid, uuid) from public;
revoke all on function app.pos_order_detail(uuid, uuid, uuid) from anon;
grant execute on function app.pos_order_detail(uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. app.pos_order_snapshots — + edit_count, kitchen_edit_ack_pending,
--    has_active_round; the sync stamp covers rounds and edits.
-- ----------------------------------------------------------------------------
create or replace function app.pos_order_snapshots(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_since_at       timestamptz default null,
  p_since_id       uuid        default null,
  p_before_at      timestamptz default null,
  p_before_id      uuid        default null,
  p_order_ids      uuid[]      default null,
  p_limit          integer     default 50,
  p_window_days    integer     default 2
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org          uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_role         text;
  v_m_status     text;
  v_m_deleted    timestamptz;
  v_limit        integer;
  v_window_start timestamptz;
  v_rows         jsonb;
  v_count        integer;
  v_next_at      timestamptz;
  v_next_id      uuid;
  v_max_at       timestamptz;
  v_max_id       uuid;
  v_min_at       timestamptz;
  v_min_id       uuid;
  -- TRUE only for the INCREMENTAL change feed. The WINDOW pages DESCENDING.
  v_ascending    boolean;
begin
  -- (a) THE CANONICAL PIN-SESSION PREAMBLE (identical to app.apply_discount).
  --     Every failure -- bad session, expired, revoked device, wrong device,
  --     dead membership -- collapses to ONE indistinguishable envelope: a caller
  --     must not be able to probe WHICH check failed (RISK R-003).
  select ps.organization_id, ps.branch_id, ps.device_session_id, ps.resolved_membership_id
    into v_org, v_branch, v_dsid, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found or not app.is_pin_session_valid(p_pin_session_id) then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_snapshot');
  end if;

  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found
     or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active')
     or v_ds_device is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_snapshot');
  end if;

  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_snapshot');
  end if;

  -- (b) INPUT VALIDATION -- FAIL CLOSED. A malformed cursor is REFUSED, never
  --     silently coerced into "start from the beginning": quietly restarting the
  --     cursor would re-deliver the whole window and look like success.
  if (p_since_at is null) <> (p_since_id is null) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'order_snapshot');
  end if;
  if (p_before_at is null) <> (p_before_id is null) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'order_snapshot');
  end if;
  -- The two cursors are DIFFERENT QUESTIONS and must never be asked at once: an
  -- ascending "what changed" and a descending "show me older" cannot both be honoured
  -- by one page, and silently picking one would give the caller a page it did not ask
  -- for while advancing a cursor it did not mean to move.
  if p_since_at is not null and p_before_at is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'order_snapshot');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    return jsonb_build_object('ok', false, 'error', 'invalid_limit', 'entity', 'order_snapshot');
  end if;
  if p_window_days is null or p_window_days < 1 or p_window_days > 14 then
    return jsonb_build_object('ok', false, 'error', 'invalid_window', 'entity', 'order_snapshot');
  end if;
  if p_order_ids is not null and array_length(p_order_ids, 1) > 100 then
    return jsonb_build_object('ok', false, 'error', 'invalid_limit', 'entity', 'order_snapshot');
  end if;
  v_limit        := p_limit;
  v_window_start := (now() at time zone 'utc')::date - make_interval(days => p_window_days - 1);

  -- MODE. Only an explicit `since` cursor asks the ASCENDING question ("what changed
  -- since I last looked"). Everything else -- including the very first, cursorless
  -- call -- is the WINDOW: newest first. That default is the whole fix. A cursorless
  -- call used to mean "ascend from the start of the window", which handed a busy
  -- branch its OLDEST rows and buried the newest order thousands of rows deep.
  v_ascending := (p_since_at is not null);

  -- (c) THE SNAPSHOT.
  --
  --     SCOPE: the PIN session's OWN organization_id AND branch_id, taken from the
  --     SERVER's session row -- never from anything the client sent. There is no
  --     parameter by which a caller could name another branch, restaurant or
  --     tenant, so a sibling-branch/sibling-restaurant/cross-tenant read is not
  --     "denied", it is UNREACHABLE.
  --
  --     SETTLEMENT: one LEFT JOIN on payments' UNIQUE partial index
  --     (payments_one_completed_per_order_uidx: at most ONE completed payment per
  --     order), so coverage is set-based -- no correlated subquery, no per-row
  --     aggregate, no N+1.
  --
  --     SYNC STAMP: greatest(o.updated_at, pay.updated_at). A payment does not
  --     touch the order row, so ordering on o.updated_at alone would never deliver
  --     a paid-but-not-yet-completed order to an incremental cursor.
  --
  --     ORDER-EDIT-001B: the stamp ALSO takes the newest updated_at of the
  --     order's service rounds and edits, for the same reason: a kitchen
  --     acknowledgement of an edit (§4.46) and a round status change write no
  --     orders row, so kitchen_edit_ack_pending and has_active_round would
  --     otherwise flip without ever reaching a POS. The max runs over EVERY
  --     round and edit row of the order (no status or tombstone filter), so the
  --     stamp never moves backwards; it is never lower than the old stamp. The
  --     two aggregates are bounded probes on (organization_id, order_id).
  with scoped as (
    select
      o.id,
      o.status,
      o.revision,
      o.order_type,
      o.created_at,
      o.updated_at,
      o.subtotal_minor,
      o.discount_total_minor,
      o.tax_total_minor,
      o.grand_total_minor,
      o.currency_code,
      o.edit_count,                                   -- ORDER-EDIT-001B
      -- The table's human LABEL, never its internal UUID (T-003 forbids projecting
      -- an internal id). `notes` and `customer_name` are deliberately NOT selected:
      -- private order notes are explicitly out of the safe set, and the POS already
      -- holds the customer name it typed -- a reconciliation read has no reason to
      -- ship personal data back.
      tbl.label as table_label,
      pay.amount_minor as covered_minor,
      -- ORDER-EDIT-001B: the order's live-round and pending-edit flags.
      rnd.active      as has_active_round,
      ed.ack_pending  as edit_ack_pending,
      greatest(o.updated_at, coalesce(pay.updated_at, o.updated_at),
               coalesce(rnd.touched_at, o.updated_at),
               coalesce(ed.touched_at, o.updated_at)) as sync_at
    from public.orders o
    left join public.tables tbl
      on  tbl.organization_id = o.organization_id
      and tbl.id              = o.table_id
    left join public.payments pay
      on  pay.organization_id = o.organization_id
      and pay.order_id        = o.id
      and pay.status          = 'completed'
      and pay.deleted_at is null
    -- ORDER-EDIT-001B: has_active_round = any live service round of the order
    -- in submitted..ready (the app.void_order live-round predicate).
    left join lateral (
      select max(r.updated_at) as touched_at,
             coalesce(bool_or(r.deleted_at is null
                              and r.status in ('submitted', 'accepted', 'preparing', 'ready')),
                      false) as active
        from public.order_service_rounds r
       where r.organization_id = o.organization_id
         and r.order_id        = o.id
    ) rnd on true
    -- ORDER-EDIT-001B: a required kitchen confirmation of an edit not yet
    -- given (the order_edits_pending_ack_idx predicate).
    left join lateral (
      select max(e.updated_at) as touched_at,
             coalesce(bool_or(e.deleted_at is null
                              and e.kitchen_ack_required
                              and e.kitchen_ack_at is null),
                      false) as ack_pending
        from public.order_edits e
       where e.organization_id = o.organization_id
         and e.order_id        = o.id
    ) ed on true
    where o.organization_id = v_org
      and o.branch_id       = v_branch
      and o.deleted_at is null
      -- TARGETED mode ignores the window: a snapshot requested for a SPECIFIC
      -- order after a write must return it even if it sits outside the window.
      and (p_order_ids is not null or o.created_at >= v_window_start)
      and (p_order_ids is null or o.id = any (p_order_ids))
  ),
  stamped as (
    select
      s.*,
      case
        when s.grand_total_minor < 0  then 'unpaid'            -- FAIL CLOSED (money defect stays visible)
        when s.grand_total_minor = 0  then 'not_chargeable'    -- owes nothing; carries no payment row
        when coalesce(s.covered_minor, 0) >= s.grand_total_minor then 'paid'
        else 'unpaid'
      end as payment_status
    from scoped s
  ),
  -- THE PAGE. `v_ascending` is TRUE only for the INCREMENTAL feed; the WINDOW pages
  -- DESCENDING so the NEWEST order is the first row of the first page, whatever the
  -- volume. Both directions keyset on (sync_at, id) -- the ORDER ID is the
  -- tie-breaker, so rows sharing a sync_at to the microsecond cannot be duplicated
  -- across pages or skipped between them.
  page as (
    select *
    from stamped st
    where p_order_ids is not null
       or (v_ascending
             and (p_since_at is null
                  or (st.sync_at, st.id) > (p_since_at, p_since_id)))
       or ((not v_ascending)
             and (p_before_at is null
                  or (st.sync_at, st.id) < (p_before_at, p_before_id)))
    order by
      case when v_ascending then st.sync_at end asc,
      case when v_ascending then st.id      end asc,
      case when not v_ascending then st.sync_at end desc,
      case when not v_ascending then st.id      end desc
    limit v_limit
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'order_id',             p.id,
        -- The SAFE public reference, never the raw UUID (T-003).
        'order_code',           '#' || upper(right(replace(p.id::text, '-', ''), 6)),
        'revision',             p.revision,
        'status',               p.status,
        'order_type',           p.order_type,
        'table_label',          p.table_label,
        'currency_code',        p.currency_code,
        'created_at',           p.created_at,
        'updated_at',           p.updated_at,
        'sync_at',              p.sync_at,
        'subtotal_minor',       p.subtotal_minor,
        'discount_total_minor', p.discount_total_minor,
        'tax_total_minor',      p.tax_total_minor,
        'grand_total_minor',    p.grand_total_minor,
        'payment_status',       p.payment_status,
        -- ORDER-EDIT-001B (D-043 / D-044): money-free. A whole-order void
        -- supersedes every pending edit confirmation (§4.46).
        'edit_count',               p.edit_count,
        'kitchen_edit_ack_pending', (p.status <> 'voided' and p.edit_ack_pending),
        'has_active_round',         p.has_active_round
      ) order by
        case when v_ascending then p.sync_at end asc,
        case when v_ascending then p.id      end asc,
        case when not v_ascending then p.sync_at end desc,
        case when not v_ascending then p.id      end desc
    ), '[]'::jsonb),
    count(*)::integer,
    -- The cursor to RESUME from is the LAST row of this page in ITS OWN direction:
    -- the greatest (sync_at, id) when ascending, the least when descending.
    (array_agg(p.sync_at order by p.sync_at desc, p.id desc))[1],
    (array_agg(p.id      order by p.sync_at desc, p.id desc))[1],
    (array_agg(p.sync_at order by p.sync_at asc,  p.id asc))[1],
    (array_agg(p.id      order by p.sync_at asc,  p.id asc))[1]
  into v_rows, v_count, v_max_at, v_max_id, v_min_at, v_min_id
  from page p;

  if v_ascending then
    v_next_at := v_max_at;  -- resume AFTER the newest row we just took
    v_next_id := v_max_id;
  else
    v_next_at := v_min_at;  -- resume BEFORE the oldest row we just took
    v_next_id := v_min_id;
  end if;

  -- A page that filled the limit MAY have more behind it; a short page is the end.
  -- A caller must NEVER read "this bounded page did not contain order X" as "order
  -- X was deleted" -- the envelope says so explicitly by never claiming completeness.
  return jsonb_build_object(
    'ok',            true,
    'entity',        'order_snapshot',
    'server_ts',     now(),
    'window_start',  v_window_start,
    'orders',        v_rows,
    'has_more',      (v_count = v_limit and p_order_ids is null),
    'next_cursor',   case
                       when v_count = v_limit and p_order_ids is null
                       then jsonb_build_object('at', v_next_at, 'id', v_next_id)
                       else null
                     end);
end;
$$;
do $do$
begin
  execute format('comment on function app.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) is %L',
    obj_description('app.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer)'::regprocedure, 'pg_proc')
    || ' ORDER-EDIT-001B (D-043 / D-044): every row also carries edit_count, kitchen_edit_ack_pending (a required edit confirmation not yet given; FALSE on a voided order) and has_active_round (any live service round in submitted..ready). The sync stamp is now greatest(orders.updated_at, the completed payment''s updated_at, the newest updated_at of the order''s service rounds and of its edits): an edit acknowledgement and a round status change write no orders row, exactly like a payment. The stamp is never lower than before, so stored cursors stay valid.');
end;
$do$;

revoke all on function app.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) from public;
revoke all on function app.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) from anon;
grant execute on function app.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. app.pin_session_capabilities — + void_order and branch_features.
-- ----------------------------------------------------------------------------
create or replace function app.pin_session_capabilities(
  p_pin_session_id uuid,
  p_device_id      uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_dsid       uuid;
  v_membership uuid;
  v_ds_org     uuid;
  v_ds_rest    uuid;
  v_ds_branch  uuid;
  v_ds_device  uuid;
  v_ds_active  boolean;
  v_ds_revoked timestamptz;
  v_pairing    text;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_m_perms    jsonb;
  v_b_enabled  boolean;  -- ORDER-EDIT-001B: branches.order_edit_enabled
  v_b_ff       boolean;  -- ORDER-EDIT-001B: branches.order_edit_finished_food_manager_only
begin
  -- (a) THE CANONICAL PIN-SESSION PREAMBLE — the one app.apply_discount actually
  --     uses, not an approximation of it. EVERY failure below (unknown session,
  --     inactive, expired, dead device session, revoked device, inactive pairing,
  --     device mismatch, scope mismatch, dead membership) returns ONE
  --     INDISTINGUISHABLE envelope. A caller must never learn WHICH check failed —
  --     that would turn a capability probe into an existence/scope oracle across
  --     tenants (RISK R-003).
  select ps.organization_id, ps.restaurant_id, ps.branch_id,
         ps.device_session_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  -- app.is_pin_session_valid is the SHARED validity rule (active + not expired +
  -- not ended). Use the helper; do not re-implement its predicate here.
  if not found or not app.is_pin_session_valid(p_pin_session_id) then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;

  select ds.organization_id, ds.restaurant_id, ds.branch_id,
         ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_org, v_ds_rest, v_ds_branch,
         v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found
     or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active')
     or v_ds_device is distinct from p_device_id
     -- The PIN session and its backing device session MUST agree on scope. They are
     -- FK-linked at creation so this cannot diverge today; a capability oracle is
     -- precisely the wrong place to take that on trust.
     or v_ds_org    is distinct from v_org
     or v_ds_rest   is distinct from v_rest
     or v_ds_branch is distinct from v_branch then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;

  -- The membership is resolved through the session's OWN resolved_membership_id --
  -- the authoritative pointer -- not by re-deriving it from employee_profiles.
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;

  -- (a1) ORDER-EDIT-001B: the session branch's two edit switches (§4.45.8),
  --      read with app.edit_order's row predicate but without its share lock
  --      (this read is STABLE). An unreadable branch row leaves both NULL and
  --      they are reported FALSE (the POS hides "Edit order"); it never fails
  --      the probe, so the existing capabilities are unaffected.
  select b.order_edit_enabled, b.order_edit_finished_food_manager_only
    into v_b_enabled, v_b_ff
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;

  -- (b) EFFECTIVE rights -- byte-for-byte the predicates app.apply_discount enforces,
  --     so the client can never disagree with the server about what it may do. The
  --     capability MODEL is unchanged by this hotfix:
  --       apply_discount  = manager+ OR the DEFAULT-ON cashier capability (deny-only)
  --       apply_full_comp = manager+ OR the DEFAULT-OFF cashier grant (grant-only)
  --     Both resolvers are total and return BOOLEAN, never null: a missing override
  --     key resolves to false for apply_full_comp (grant-only => absence denies), and
  --     malformed permissions JSON fails closed in both.
  --     NOTHING here leaks: no permissions JSON, no membership/employee/session UUID,
  --     no PIN material, no money, no order data -- only the role and two booleans.
  return jsonb_build_object(
    'ok', true, 'entity', 'pin_session', 'role', v_role,
    'capabilities', jsonb_build_object(
      'apply_discount',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_allowed(v_role, v_m_perms, 'apply_discount'),
      'apply_full_comp',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_granted(v_role, v_m_perms, 'apply_full_comp'),
      'manage_menu_availability',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_allowed(v_role, v_m_perms, 'manage_menu_availability'),
      'manage_table_operations',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_allowed(v_role, v_m_perms, 'manage_table_operations'),
      -- POS-CASH-DRAWER-MANUAL-OPEN-001: manual drawer open. manager+ BY ROLE, or a
      -- cashier the owner explicitly GRANTED (grant-only => absence denies).
      'open_cash_drawer',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_granted(v_role, v_m_perms, 'open_cash_drawer'),
      -- ORDER-EDIT-001B (D-043): the effective void_order right, byte-for-byte
      -- the predicate app.void_order and app.edit_order's removal gate enforce
      -- (manager+ BY ROLE, or the DEFAULT-ON cashier capability, deny-only).
      'void_order',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_allowed(v_role, v_m_perms, 'void_order')),
    -- ORDER-EDIT-001B: the session branch's two switches, for every role; two
    -- money-free booleans of the caller's OWN branch (no identifier).
    'branch_features', jsonb_build_object(
      'order_edit_enabled',                    coalesce(v_b_enabled, false),
      'order_edit_finished_food_manager_only', coalesce(v_b_ff, false)));
end;
$$;
do $do$
begin
  execute format('comment on function app.pin_session_capabilities(uuid, uuid) is %L',
    obj_description('app.pin_session_capabilities(uuid, uuid)'::regprocedure, 'pg_proc')
    || ' ORDER-EDIT-001B (D-043): + a SIXTH effective boolean, capabilities.void_order (manager+ by role OR the deny-only cashier capability: the predicate app.void_order and app.edit_order enforce), and the top-level branch_features {order_edit_enabled, order_edit_finished_food_manager_only} of the session''s own branch, FALSE when the branch row is unreadable. Advisory, additive; the failure envelopes are unchanged.');
end;
$do$;

revoke all on function app.pin_session_capabilities(uuid, uuid) from public;
revoke all on function app.pin_session_capabilities(uuid, uuid) from anon;
grant execute on function app.pin_session_capabilities(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- The re-emits never broaden either global public surface (D-037). These
-- assertions match ORDER-EDIT-001A and pending #288 in either apply order.
-- ----------------------------------------------------------------------------
do $$
declare
  v_anon_set text;
  v_defs text;
begin
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_anon_set from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
      and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon_set <> 'storefront_menu(text)' then
    raise exception 'ORDER-EDIT-001B: unexpected anon public surface [%]', v_anon_set;
  end if;
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_defs from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef;
  if v_defs <> 'storefront_menu(text)' then
    raise exception 'ORDER-EDIT-001B: unexpected public DEFINER surface [%]', v_defs;
  end if;
  if has_schema_privilege('anon', 'app', 'USAGE') then
    raise exception 'ORDER-EDIT-001B: anon has app schema usage';
  end if;
end;
$$;
