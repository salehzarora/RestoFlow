-- ============================================================================
-- RF-057 — app.sync_pull: server-authoritative pull sync + revisions + tombstones
-- ============================================================================
-- The PULL half of offline sync (DECISION D-010). Builds on RF-014 (org/branch +
-- app.is_pin_session_valid context), RF-016/051 (devices/sessions), RF-052..RF-055
-- (the operational tables it READS), and RF-056 (sync_operations, whose per-device
-- status/conflict feed it exposes). Additive and FORWARD-ONLY: it adds NO columns,
-- ALTERs NO prior table, creates NO new table — it reuses the trigger-maintained
-- `updated_at` (the server-authoritative change clock), `deleted_at` (tombstones,
-- D-020), and existing `revision` columns. It performs NO mutation.
--
-- WHAT THIS DOES (API_CONTRACT §4.15 sync_pull; OFFLINE_SYNC_SPEC §2/§10/§13/§14)
--   1. app.sync_pull(p_pin_session_id, p_device_id, p_entities, p_cursors, p_limit)
--      — a read-only SECURITY DEFINER RPC returning, for the caller's session-derived
--      org+branch scope, each requested operational entity's rows changed since a
--      per-entity (updated_at, id) cursor (tombstones included inline, A9), plus a
--      CURRENT-DEVICE operation-status feed from sync_operations (A4) so the client
--      can reconcile its outbox (statuses/conflicts/rejections recorded by sync_push).
--   2. app.sync_pull_changes(...) — an internal dynamic helper that pages one
--      allow-listed entity table by the (updated_at, id) cursor. Never client-facing.
--
-- APPROVED DECISIONS (RF-057; human-approved A1..A9)
--   * A1: per-entity (updated_at, id) cursor; NO global change_seq; NO prior-table ALTER;
--     reuse trigger-maintained updated_at / deleted_at / existing revision.
--   * A2: NO auto-merge / per-entity resolution policy (Q-010 deferred). Pull EXPOSES
--     the push-side recorded conflict/status (operation_statuses), never hides it.
--   * A3: DB/server core only — no Dart/client/packages.
--   * A4: business entities = orders, order_items, order_item_modifiers, payments,
--     shifts, cash_drawer_sessions; plus a CURRENT-ORG+CURRENT-DEVICE sync_operations
--     status feed (no global ledger exposure).
--   * A5: kitchen_staff -> non-financial entities only (orders/order_items/
--     order_item_modifiers); cashier/manager/restaurant_owner/org_owner + accountant ->
--     full operational set. Role derived from the PIN session membership, never payload.
--   * A6: response { ok, server_ts, changes:{<entity>:{rows,next_cursor,has_more}},
--     operation_statuses:{rows,next_cursor,has_more} }.
--   * A7: default limit 500, hard cap 1000, reject <=0 or >1000.
--   * A8: SECURITY DEFINER + search_path=''; explicit organization_id + branch filter;
--     validate PIN session + device session/pairing + device match; never trust payload.
--   * A9: tombstones inline (rows carry deleted_at); cursor advance prevents re-pull.
--
-- OUT OF SCOPE: RF-058 realtime; client Drift pull-apply; packages/sync|data_remote;
--   auto-merge/conflict-resolution policy (Q-010); reports; printing; conflict UI;
--   kitchen routing; menu pull (no server menu table); audit_events / order_operations /
--   shift_operations / branch_receipt_counters / config tables; any ALTER of prior
--   tables; remote Supabase; secrets/service-role.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.sync_pull_changes — internal dynamic pager for ONE allow-listed entity.
--    Filters by (organization_id, branch_id) [server-derived, never client] and the
--    (updated_at, id) cursor; returns {rows, next_cursor, has_more}. Tombstones
--    (deleted_at not null) are NOT filtered out — a soft-delete bumps updated_at via
--    app.set_updated_at, so the tombstone surfaces inline once and then sits behind
--    the advanced cursor (A9). to_jsonb(t) emits every column incl. `revision` where
--    the table has it (A1). NOT granted to authenticated — only app.sync_pull calls it.
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
  v_rows  jsonb;
  v_count integer;
  v_last  jsonb;
begin
  -- defence in depth: only the six approved operational tables are pageable here.
  if p_table not in ('orders', 'order_items', 'order_item_modifiers', 'payments', 'shifts', 'cash_drawer_sessions') then
    raise exception 'sync_pull_changes: % is not a pull-allowed entity', p_table using errcode = '42501';
  end if;

  -- (RF057-B1) LOOKAHEAD pagination: fetch p_limit + 1 rows (`look`), return only the
  -- first p_limit (`page`), and set has_more = (look count > p_limit). This avoids the
  -- false-positive has_more when EXACTLY p_limit rows remain (count >= limit was wrong).
  -- next_cursor is the last row actually RETURNED (from `page`), never the extra
  -- lookahead row; zero rows -> empty rows + null cursor + has_more false. v_count is the
  -- look count (<= p_limit + 1).
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

  return jsonb_build_object(
    'rows',        v_rows,
    'next_cursor', case when v_count > 0 then v_last else null end,
    'has_more',    (v_count > p_limit));
end;
$$;

comment on function app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer) is
  'RF-057 internal helper for app.sync_pull: pages ONE allow-listed operational table by (updated_at, id) within (organization_id, branch_id). Returns {rows (incl. tombstones via deleted_at), next_cursor, has_more}. NOT client-facing (no authenticated grant); table name is allow-listed (no injection).';

revoke all on function app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer) from public;

-- ----------------------------------------------------------------------------
-- 2. app.sync_pull — the API_CONTRACT §4.15 read-only pull RPC. Validates the PIN
--    session + active device (A8), derives org/branch/role server-side, resolves the
--    role-permitted entity set (A5), pages each requested entity by its cursor, and
--    appends a current-device operation-status feed (A4). Read-only: mutates nothing,
--    writes no audit (§4.15). Returns server_ts + per-entity {rows,next_cursor,has_more}.
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

  -- (b) role-permitted business entities (A5): kitchen_staff -> non-financial only.
  if v_role = 'kitchen_staff' then
    v_allowed := array['orders', 'order_items', 'order_item_modifiers'];
  elsif v_role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant') then
    v_allowed := c_business;
  else
    v_allowed := array[]::text[];
  end if;

  -- (c) resolve the requested set. null -> all role-permitted + operation_statuses.
  --     Otherwise validate each name: unknown -> reject; financial-for-kitchen -> reject.
  if p_entities is null then
    v_requested   := v_allowed;
    v_include_ops := true;
  else
    v_requested   := array[]::text[];
    v_include_ops := false;
    foreach v_entity in array p_entities loop
      if v_entity = 'operation_statuses' then
        v_include_ops := true;
      elsif v_entity = any(c_business) then
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

  -- (d) page each requested business entity by its per-entity (updated_at, id) cursor.
  foreach v_entity in array v_requested loop
    v_cur   := p_cursors -> v_entity;
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    v_changes := v_changes || jsonb_build_object(
      v_entity, app.sync_pull_changes(v_entity, v_org, v_branch, v_c_uat, v_c_id, v_limit));
  end loop;

  -- (e) current-device operation-status feed (A4): sync_operations for THIS org + THIS
  --     device only (no cross-device, no cross-org). Projects status/conflict fields;
  --     deliberately EXCLUDES the raw `payload` to minimise exposure. Empty when not requested.
  if v_include_ops then
    v_cur   := p_cursors -> 'operation_statuses';
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    -- (RF057-B1) LOOKAHEAD pagination, same as app.sync_pull_changes: fetch v_limit + 1
    -- (`look`), return only the first v_limit (`page`), has_more = (look count > v_limit),
    -- next_cursor from the last RETURNED row. Avoids the false has_more at exactly v_limit.
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
  'RF-057 (API_CONTRACT §4.15, D-010/D-020) SECURITY DEFINER read-only pull RPC. Validates the PIN session + active device/pairing + device match (A8; revoked/expired -> 42501); derives org/branch/role from the session (never payload). Returns, per role-permitted operational entity (A5: kitchen_staff -> orders/order_items/order_item_modifiers only; cashier/manager/restaurant_owner/org_owner/accountant -> + payments/shifts/cash_drawer_sessions), rows changed since a per-entity (updated_at, id) cursor (A1), tombstones inline via deleted_at (A9), with next_cursor + has_more (limit default 500, cap 1000, reject <=0 or >1000; A7). Also returns a CURRENT-ORG+CURRENT-DEVICE sync_operations status/conflict feed (A4; raw payload excluded). Mutates nothing; writes no audit (read). Org+branch filter is the isolation boundary (RISK R-003).';

revoke all on function app.sync_pull(uuid, uuid, text[], jsonb, integer) from public;
grant execute on function app.sync_pull(uuid, uuid, text[], jsonb, integer) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop function if exists app.sync_pull(uuid, uuid, text[], jsonb, integer);
-- drop function if exists app.sync_pull_changes(text, uuid, uuid, timestamptz, uuid, integer);
-- ============================================================================
