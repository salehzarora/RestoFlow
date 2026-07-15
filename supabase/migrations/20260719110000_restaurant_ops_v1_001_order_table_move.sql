-- ============================================================================
-- RESTAURANT-OPERATIONS-V1-001 — atomic order table move + Activity Log
-- classification for the phase's two new actions
-- ============================================================================
-- Daily reality: a dine-in party sits down, orders, and then moves. Until now
-- `orders.table_id` was written exactly once (at submit) and never again.
-- This migration adds the ONE post-submit table mutation:
--
--   * app.move_order_table — SECURITY DEFINER, PIN-session path (D-011):
--     canonical preamble; order row locked FOR UPDATE (serializes with
--     record_payment / void_order / status transitions — the established
--     concurrency discipline); roles cashier/manager/restaurant_owner/
--     org_owner (an operational floor action, NOT a money action — no new
--     capability); ORDER-BOUND idempotency via the order_operations ledger
--     (action 'move_table', D-022); optional p_expected_revision -> RAISE
--     40001 (sync_push maps to a typed per-op conflict); typed RETURN
--     refusals (survive sync_push verbatim, §4.35):
--       takeaway order            -> {error:'table_not_allowed', detail:'takeaway_order'}
--       terminal / illegal status -> {error:'invalid_transition', detail:'order_not_movable', order_status}
--       bad target table          -> {error:'table_not_available'} (same-branch live+active only; R-003)
--       role denial               -> {error:'permission_denied'}
--     Success sets orders.table_id, bumps revision (the updated_at trigger
--     moves the POS snapshot + KDS pull cursors, so every surface converges),
--     audits `order.table_moved` with before/after labels, and ledgers the
--     result. A same-table move is an explicit ok/no_change (ledgered, NOT
--     audited, revision unchanged). A LEGACY tableless dine-in order CAN be
--     moved (move = assign — the recovery path for pre-phase rows).
--   * sync_push gains the 'order.table_move' op type (CHECK + both envelope
--     allowlists + dispatch branch) — FAITHFUL re-creation of the newest
--     (MONEY-VOID-001) body; everything else verbatim, incl. the
--     ORDER-CUSTOMER-001 customer_name stamp.
--   * app.audit_action_has_detail / app.audit_safe_detail — ONE stacked
--     re-create adding this phase's two action families
--     (menu.<entity>.availability*, order.table_mov*) and their safe scalar
--     keys (availability, availability_reason, item_name, table_label,
--     from_table_label, to_table_label). Labels are floor names, reasons are
--     closed enums — never money, never identifiers (T-003 holds).
--
-- Dashboard note (documented product decision): the Dashboard shows DERIVED
-- occupancy read-only; the move ACTION lives on the POS (one mutation path,
-- one authorization model in this phase — no decorative dashboard button).
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Ledger + transport op-type CHECKs (drop + re-add, additive).
-- ----------------------------------------------------------------------------
alter table public.order_operations drop constraint order_operations_action_check;
alter table public.order_operations add  constraint order_operations_action_check
  check (action in ('void_order', 'apply_discount', 'record_payment', 'move_table'));

comment on constraint order_operations_action_check on public.order_operations is
  'RF-053/RF-054 + RESTAURANT-OPERATIONS-V1-001: business-idempotency actions — void_order / apply_discount / record_payment / move_table.';

alter table public.sync_operations drop constraint if exists sync_operations_operation_type_check;
alter table public.sync_operations add constraint sync_operations_operation_type_check
  check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move'));

-- ----------------------------------------------------------------------------
-- 2. app.move_order_table — the atomic move.
-- ----------------------------------------------------------------------------
create function app.move_order_table(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_table_id           uuid,
  p_expected_revision  integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org          uuid;
  v_rest         uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_emp          uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_role         text;
  v_m_status     text;
  v_m_deleted    timestamptz;
  v_o_org        uuid;
  v_o_branch     uuid;
  v_o_status     text;
  v_o_type       text;
  v_o_rev        integer;
  v_o_table      uuid;
  v_old_label    text;
  v_new_label    text;
  v_new_rev      integer;
  v_stored       jsonb;
  v_stored_order uuid;
  v_result       jsonb;
begin
  -- (a) canonical PIN-session preamble; actor + scope derived here, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'move_order_table: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'move_order_table: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'move_order_table: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'move_order_table: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'move_order_table: resolved membership is not active' using errcode = '42501';
  end if;

  -- shape: the target table is mandatory (the POS always sends one).
  if p_table_id is null then
    raise exception 'move_order_table: table_id is required' using errcode = '42501';
  end if;

  -- (b) load + LOCK the order; it MUST be in the actor's org + branch. The FOR
  --     UPDATE serializes the move with record_payment / void_order / status
  --     transitions on the SAME order (the established discipline).
  select o.organization_id, o.branch_id, o.status, o.order_type, o.revision, o.table_id
    into v_o_org, v_o_branch, v_o_status, v_o_type, v_o_rev, v_o_table
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'move_order_table: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'move_order_table: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization BEFORE the idempotency replay (RF053-B1 rule: an
  --     unauthorized actor never replays a prior success). Floor action: every
  --     order-taking role may move a table; kitchen/accountant may not.
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.table_move_denied', null, null,
      jsonb_build_object('attempted_action', 'move_table', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) idempotency replay — ORDER-BOUND (same key on a different order = 40001
  --     conflict, never a leak of the original result).
  select oo.result, oo.order_id into v_stored, v_stored_order
    from public.order_operations oo
    where oo.organization_id = v_org and oo.device_id = p_device_id
      and oo.local_operation_id = p_local_operation_id and oo.action = 'move_table';
  if found then
    if v_stored_order <> p_order_id then
      raise exception 'move_order_table: idempotency key already used for a different order (%, not %)', v_stored_order, p_order_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (e) optimistic concurrency (optional): another device changed the order.
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    raise exception 'move_order_table: revision conflict (expected %, got %)', p_expected_revision, v_o_rev using errcode = '40001';
  end if;

  -- (f) only DINE-IN orders sit at tables. Typed + audited refusal.
  if v_o_type <> 'dine_in' then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.table_move_denied', null, null,
      jsonb_build_object('attempted_action', 'move_table', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'order_status', v_o_status, 'order_type', v_o_type,
                         'denied_reason', 'takeaway_order'));
    return jsonb_build_object('ok', false, 'error', 'table_not_allowed',
                              'detail', 'takeaway_order', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (g) only ACTIVE orders move; terminal orders keep their historical table.
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.table_move_denied', null, null,
      jsonb_build_object('attempted_action', 'move_table', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_not_movable'));
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'detail', 'order_not_movable', 'order_id', p_order_id,
                              'order_status', v_o_status,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (h) the TARGET table must be a live, active table of the SESSION branch —
  --     the same rule submit_order enforces (foreign / tombstoned / inactive /
  --     unknown are indistinguishable, R-003). Moving ONTO an occupied table is
  --     allowed (parties merge in real restaurants; occupancy counts stay honest).
  select t.label into v_new_label
    from public.tables t
    where t.id              = p_table_id
      and t.organization_id = v_org
      and t.restaurant_id   = v_rest
      and t.branch_id       = v_branch
      and t.is_active
      and t.deleted_at is null;
  if not found then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.table_move_denied', null, null,
      jsonb_build_object('attempted_action', 'move_table', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'table_not_available'));
    return jsonb_build_object('ok', false, 'error', 'table_not_available', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (i) same-table move: explicit no-op success. Ledgered (so a retry replays),
  --     NOT audited (nothing changed), revision NOT bumped (no state moved).
  if v_o_table is not null and v_o_table = p_table_id then
    v_result := jsonb_build_object('ok', true, 'order_id', p_order_id,
                                   'table_id', p_table_id, 'table_label', v_new_label,
                                   'revision', v_o_rev, 'no_change', true);
    insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
      values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'move_table', p_order_id, v_result);
    return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (j) mutate: the ONE post-submit table write. revision+1; the updated_at
  --     trigger advances the POS snapshot / KDS pull cursors so every surface
  --     converges on the new table. The SOURCE may be null (legacy tableless
  --     dine-in row) — the move doubles as the assign/recovery path.
  select t.label into v_old_label from public.tables t
    where t.id = v_o_table and t.organization_id = v_org;
  v_new_rev := v_o_rev + 1;
  update public.orders
    set table_id = p_table_id, revision = v_new_rev
    where id = p_order_id;

  -- (k) audit (D-013): WHAT moved, WHO, WHEN, SCOPE, BEFORE, AFTER. Labels are
  --     floor names (safe display); from/to duplicated in new_values so the one
  --     projected row reads as a complete sentence.
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'order.table_moved', null,
    jsonb_build_object('table_id', v_o_table, 'table_label', v_old_label, 'revision', v_o_rev),
    jsonb_build_object('table_id', p_table_id, 'table_label', v_new_label,
                       'from_table_label', v_old_label, 'to_table_label', v_new_label,
                       'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                       'revision', v_new_rev,
                       'resolved_membership_id', v_membership));

  -- (l) ledger + return.
  v_result := jsonb_build_object('ok', true, 'order_id', p_order_id,
                                 'table_id', p_table_id, 'table_label', v_new_label,
                                 'revision', v_new_rev);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'move_table', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.move_order_table(uuid, uuid, uuid, text, uuid, integer) is
  'RESTAURANT-OPERATIONS-V1-001 (API_CONTRACT §4.39, D-011/D-022): SECURITY DEFINER atomic table move for an ACTIVE dine-in order. Canonical PIN preamble; order row FOR UPDATE (serializes with payment/void/status transitions); roles cashier/manager/restaurant_owner/org_owner (floor action, not money); ORDER-BOUND idempotency (action move_table); optional expected_revision -> 40001 (sync_push maps to typed conflict). Typed RETURN refusals, each audited order.table_move_denied with a closed denied_reason: permission_denied (role), table_not_allowed + detail=takeaway_order, invalid_transition + detail=order_not_movable + order_status (terminal), table_not_available (target not a live+active SESSION-branch table — foreign/tombstoned/inactive/unknown indistinguishable, R-003). Same-table move = ok/no_change (ledgered, not audited, revision unchanged). A legacy tableless dine-in order CAN be moved (assign/recovery). Success bumps revision (sync feeds converge) and audits order.table_moved with before/after labels. Moving onto an occupied table is allowed (honest occupancy counts). MONEY-FREE.';

revoke all on function app.move_order_table(uuid, uuid, uuid, text, uuid, integer) from public;
revoke all on function app.move_order_table(uuid, uuid, uuid, text, uuid, integer) from anon;
grant execute on function app.move_order_table(uuid, uuid, uuid, text, uuid, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.sync_push — CREATE OR REPLACE. FAITHFUL re-creation of the NEWEST
--    (MONEY-VOID-001) body with exactly THREE changes: 'order.table_move' in
--    BOTH envelope allowlists + one dispatch branch. Everything else —
--    revoked-device recording, dedup/replay, dependency guard, per-op
--    subtransactions, finalization, the ORDER-CUSTOMER-001 customer_name
--    stamp — is verbatim.
-- ----------------------------------------------------------------------------
create or replace function app.sync_push(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_operations     jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org          uuid;
  v_rest         uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_emp          uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_op           jsonb;
  v_local_op     text;
  v_op_type      text;
  v_payload      jsonb;
  v_depends      jsonb;
  v_target_ent   text;
  v_target_id    uuid;
  v_client_ts    timestamptz;
  v_fingerprint  text;
  v_dep          text;
  v_dep_ok       boolean;
  v_ex_status    text;
  v_ex_result    jsonb;
  v_ex_optype    text;
  v_ex_fp        text;
  v_so_id        uuid;
  v_dispatch     jsonb;
  v_dispatch_ok  boolean;
  v_caught_state text;
  v_caught_msg   text;
  v_results      jsonb := '[]'::jsonb;
  v_op_result    jsonb;
  v_device_revoked boolean := false;
  v_customer_name text;
begin
  -- (0) batch shape + a conservative size cap (no frozen limit in docs; 100 is the
  --     interim cap, surfaced here and in the tests — keeps a push transaction bounded).
  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then
    raise exception 'sync_push: p_operations must be a JSON array' using errcode = '42501';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'sync_push: batch too large (max 100 operations, got %)', jsonb_array_length(p_operations) using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing. Scope is derived here. The PIN
  --     session must exist + be valid (offline-window bounded, Q-009); a missing session
  --     or expired PIN still raises (cannot key/record safely without a session/window).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'sync_push: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'sync_push: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found then
    raise exception 'sync_push: backing device session not found' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_push: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  -- RF061-A1: a REVOKED / inactive device session or pairing no longer fails the whole
  -- batch with a silent raise. Instead each pushed op is RECORDED as rejected
  -- (revoked_device) and surfaced, so the offline-queued operations are not lost (R-007;
  -- AC1). Authorization is INGEST-TIME (the device is revoked NOW); client timestamps are
  -- never trusted. A previously-APPLIED op still replays its stored result (idempotency).
  if not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    v_device_revoked := true;
    for v_op in select * from jsonb_array_elements(p_operations)
    loop
      v_local_op   := v_op ->> 'local_operation_id';
      v_op_type    := v_op ->> 'operation_type';
      v_payload    := v_op -> 'payload';
      v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
      v_target_ent := v_op ->> 'target_entity';
      v_target_id  := nullif(v_op ->> 'target_id', '')::uuid;
      v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

      -- envelope validation (same as the valid path): malformed -> rejected result, NO ledger row
      if v_local_op is null or btrim(v_local_op) = '' then
        v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
          'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move') then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
          'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;

      v_fingerprint := md5(v_op_type || '|' || v_payload::text);

      -- dedup/replay: a stored op with the SAME identity that is TERMINAL replays its
      -- result (a legitimately-APPLIED op before revocation is NOT re-rejected); a
      -- different identity is a conflict; otherwise record the op as rejected (revoked_device).
      select so.status, so.result, so.operation_type, so.payload_fingerprint
        into v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
        from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op;
      if found then
        if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
          insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
          values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                  jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                     'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
            'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
          continue;
        end if;
        if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
          v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
            || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
          continue;
        end if;
      end if;

      -- record the op as rejected (revoked_device); NO business mutation, NO dispatch.
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, rejection_reason,
        result, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'rejected',
              'revoked_device', 'permanent', 'revoked_device',
              jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'), v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do update
        set status = 'rejected', last_error_code = 'revoked_device', last_error_class = 'permanent',
            rejection_reason = 'revoked_device',
            result = jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'),
            retry_count = so.retry_count + 1, updated_at = now();
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', 'revoked_device', null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'reason', 'revoked_device'));
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'rejected', 'detail', 'revoked_device', 'status', 'rejected', 'idempotency_replay', false);
    end loop;
    return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now(), 'device_revoked', true);
  end if;

  -- (b) per-operation loop (ordered) — VALID device path (unchanged from RF-056)
  for v_op in select * from jsonb_array_elements(p_operations)
  loop
    v_caught_state := null;
    v_caught_msg   := null;
    v_dispatch     := null;
    v_dispatch_ok  := null;
    v_so_id        := null;

    v_local_op   := v_op ->> 'local_operation_id';
    v_op_type    := v_op ->> 'operation_type';
    v_payload    := v_op -> 'payload';
    v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
    v_target_ent := v_op ->> 'target_entity';
    v_target_id  := nullif(v_op ->> 'target_id', '')::uuid;
    v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

    -- (b1) envelope shape validation. Malformed envelopes are returned rejected
    --      WITHOUT a ledger row (they cannot be keyed/stored safely); they never dispatch.
    if v_local_op is null or btrim(v_local_op) = '' then
      v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
        'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move') then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
        'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if jsonb_typeof(v_depends) <> 'array' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_depends_on', 'detail', 'depends_on must be a JSON array', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;

    v_fingerprint := md5(v_op_type || '|' || v_payload::text);

    -- (b2) dedup / replay (transport identity = org + device + local_operation_id).
    select so.status, so.result, so.operation_type, so.payload_fingerprint
      into v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
      from public.sync_operations so
      where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op;
    if found then
      if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                   'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
        continue;
      end if;
      if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
        v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
          || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
        continue;
      end if;
    end if;

    -- (b3) dependency guard.
    v_dep_ok := true;
    for v_dep in select jsonb_array_elements_text(v_depends)
    loop
      if not exists (
        select 1 from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id
          and so.local_operation_id = v_dep and so.status = 'applied'
      ) then
        v_dep_ok := false;
        exit;
      end if;
    end loop;

    if not v_dep_ok then
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'pending',
              'dependency_not_ready', 'transient', v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do update
        set status = 'pending', last_error_code = 'dependency_not_ready', last_error_class = 'transient',
            retry_count = so.retry_count + 1, updated_at = now();
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'dependency_not_ready', 'retryable', true, 'status', 'pending', 'idempotency_replay', false);
      continue;
    end if;

    -- (b4) mark in_flight (insert new, or bump a re-attempt)
    insert into public.sync_operations as so (
      organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
      target_entity, target_id, payload, payload_fingerprint, depends_on, status, client_created_at)
    values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
            v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'in_flight', v_client_ts)
    on conflict (organization_id, device_id, local_operation_id) do update
      set status = 'in_flight', retry_count = so.retry_count + 1, updated_at = now()
    returning so.id into v_so_id;

    -- (b5) dispatch to the matching business RPC inside a per-op EXCEPTION subtransaction.
    begin
      case v_op_type
        when 'shift.open' then
          v_dispatch := app.open_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            (v_payload ->> 'cash_drawer_session_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'opening_float_minor')::bigint);
        when 'order.submit' then
          v_dispatch := app.submit_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'order_type',
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'shift_id', '')::uuid,
            v_payload ->> 'currency_code',
            v_payload ->> 'notes',
            v_payload -> 'order_items',
            (v_payload ->> 'subtotal_minor')::bigint,
            (v_payload ->> 'discount_total_minor')::bigint,
            (v_payload ->> 'tax_total_minor')::bigint,
            (v_payload ->> 'grand_total_minor')::bigint,
            v_client_ts);
          -- ORDER-CUSTOMER-001: stamp the OPTIONAL customer display name on the
          -- order app.submit_order just created. Kept OUT of submit_order so its
          -- validated INSERT stays byte-unchanged. Money-free display text: trim
          -- + empty->null + 80-char cap. Tenant-scoped by v_org; the
          -- `customer_name is null` guard makes it idempotent (a replay returns
          -- the same order_id, already stamped) and never overwrites.
          v_customer_name := left(btrim(coalesce(v_payload ->> 'customer_name', '')), 80);
          if v_customer_name <> '' then
            update public.orders
              set customer_name = v_customer_name
              where id = (v_dispatch ->> 'order_id')::uuid
                and organization_id = v_org
                and customer_name is null;
          end if;
        when 'order.discount' then
          v_dispatch := app.apply_discount(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'scope',
            nullif(v_payload ->> 'order_item_id', '')::uuid,
            v_payload ->> 'discount_type',
            (v_payload ->> 'value')::bigint,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'payment.create' then
          v_dispatch := app.record_payment(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'tender_type',
            (v_payload ->> 'amount_tendered_minor')::bigint,
            nullif(v_payload ->> 'provisional_receipt_number', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'shift.close' then
          v_dispatch := app.close_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'counted_amount_minor')::bigint,
            nullif(v_payload ->> 'reason', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        -- MVP addition: KDS/POS order-status updates ride the SAME outbox/ledger
        -- (D-010/D-022). Scope/actor come from the pin session + device passed
        -- through (A8); the payload contributes ONLY {order_id, new_status}.
        when 'order.status' then
          v_dispatch := app.update_order_status(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'order_id')::uuid,
            v_payload ->> 'new_status',
            v_local_op);
        when 'order.void' then
          -- MONEY-VOID-001: role-gated void of a wrong UNPAID order. Mirrors the
          -- order.discount branch - actor/org/branch come from the PIN session
          -- (never the payload) and the op's local_operation_id threads
          -- app.void_order's own idempotency (D-022). app.void_order (RF-053,
          -- hardened by RF-062) enforces manager/restaurant_owner/org_owner (or a
          -- cashier with permissions.void_order='true'), a mandatory reason, legal
          -- source states (submitted/accepted/preparing/ready/served), and the
          -- completed-payment block (an order with a live completed payment
          -- returns permission_denied) - so paid orders are refused server-side.
          -- Money-free: it only sets orders.status='voided' + void_reason +
          -- revision and cascades items -> voided; no payment/total is touched.
          v_dispatch := app.void_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'order.table_move' then
          -- RESTAURANT-OPERATIONS-V1-001: atomic dine-in table move. Mirrors the
          -- order.void branch — actor/org/branch come from the PIN session
          -- (never the payload); the op's local_operation_id threads
          -- app.move_order_table's ORDER-BOUND idempotency (D-022); the payload
          -- contributes ONLY {order_id, table_id[, expected_revision]}. Typed
          -- refusals (table_not_allowed / invalid_transition+order_not_movable /
          -- table_not_available / permission_denied) RETURN through verbatim;
          -- a revision conflict raises 40001 -> the per-op 'conflict' status.
          -- Money-free: only orders.table_id + revision move.
          v_dispatch := app.move_order_table(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'expected_revision', '')::integer);
      end case;
      v_dispatch_ok := coalesce((v_dispatch ->> 'ok')::boolean, false);
    exception
      when others then
        v_caught_state := SQLSTATE;
        v_caught_msg   := SQLERRM;
    end;

    -- (b6) finalize the operation outcome
    if v_caught_state is not null then
      if v_caught_state = '40001' then
        update public.sync_operations
          set status = 'conflict', last_error_code = v_caught_state, last_error_class = 'conflict',
              conflict_info = jsonb_build_object('sqlstate', v_caught_state, 'message', v_caught_msg),
              result = jsonb_build_object('ok', false, 'error', 'conflict', 'sqlstate', v_caught_state), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', v_caught_msg, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'sqlstate', v_caught_state, 'status', 'conflict', 'idempotency_replay', false);
      else
        -- validation / state / business-rule failure -> permanent rejected. RF-061: a
        -- revoked-MEMBERSHIP op fails membership-active in the dispatched RPC; classify its
        -- rejection reason as 'revoked_employee' so the offline-revoked-employee case is clear.
        update public.sync_operations
          set status = 'rejected', last_error_code = v_caught_state, last_error_class = 'permanent',
              rejection_reason = case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else v_caught_msg end,
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', v_caught_state,
                         'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else null end), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected',
                case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else v_caught_msg end, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'rejected', 'sqlstate', v_caught_state,
          'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else null end,
          'status', 'rejected', 'idempotency_replay', false);
      end if;
    elsif v_dispatch_ok then
      update public.sync_operations
        set status = 'applied', result = v_dispatch, applied_at = now(),
            target_id = coalesce(v_target_id, nullif(v_dispatch ->> 'order_id', '')::uuid, nullif(v_dispatch ->> 'shift_id', '')::uuid, nullif(v_dispatch ->> 'payment_id', '')::uuid),
            updated_at = now()
        where id = v_so_id;
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'applied', 'idempotency_replay', false));
    else
      update public.sync_operations
        set status = 'rejected', last_error_code = coalesce(v_dispatch ->> 'error', 'rejected'), last_error_class = 'permanent',
            rejection_reason = coalesce(v_dispatch ->> 'error', 'rejected'), result = v_dispatch, updated_at = now()
        where id = v_so_id;
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', coalesce(v_dispatch ->> 'error', 'rejected'), null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'error', coalesce(v_dispatch ->> 'error', 'rejected')));
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'rejected', 'idempotency_replay', false));
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now());
end;
$$;

comment on function app.sync_push(uuid, uuid, jsonb) is
  'RF-056/RF-061 + MVP order.status + ORDER-CUSTOMER-001 + MONEY-VOID-001 + RESTAURANT-OPERATIONS-V1-001 (API_CONTRACT §4.14, D-010/D-022) SECURITY DEFINER batch push RPC. FAITHFUL re-creation of the MONEY-VOID-001 body with ONE added dispatch branch: order.table_move (payload {order_id, table_id[, expected_revision]}) -> app.move_order_table, using the SAME pin session + device + the op local_operation_id; the accepted operation_type set gains order.table_move in both envelope validation lists. All prior behavior is otherwise verbatim: batch cap 100; PIN session + device match gate; RF061-A1 revoked-device per-op recording; per-op dedup/replay via the sync_operations ledger; payload-fingerprint conflict detection; dependency guard; per-op EXCEPTION subtransactions; applied/rejected/conflict/pending finalization + result storage; revoked_employee tagging; the ORDER-CUSTOMER-001 customer_name stamp after order.submit. Authorization is INGEST-TIME; scope is derived from the session, never the payload. Reimplements NO business logic.';

revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Activity Log classification for the phase's TWO new action families —
--    one stacked re-create of both classifier functions (newest bodies =
--    FULL-COMP-PERMISSION-001), additive only.
-- ----------------------------------------------------------------------------
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
      or p_action =    'pin_session.failed';
$$;

comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001 + AUDIT-COVERAGE-002 + FULL-COMP-PERMISSION-001 + RESTAURANT-OPERATIONS-V1-001: is p_action a SUPPORTED action that may carry a safe payload projection? Unknown/unsupported actions return NO payload details (metadata + category only). RESTAURANT-OPERATIONS-V1-001 adds order.table_mov% (moved/denied — before/after floor labels) and menu.%.availability% (availability changes/denials — the ONLY menu.* family with detail). Gates app.audit_safe_detail.';

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
    'table_label','from_table_label','to_table_label'
  ] loop
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
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp']) as k
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
  'AUDIT-LOG-DASHBOARD-001 .. FULL-COMP-PERMISSION-001 + RESTAURANT-OPERATIONS-V1-001: ALLOWLIST projection of ONE audit payload (old or new) to canonical safe fields. Gated by app.audit_action_has_detail (unsupported action -> ''{}''). RESTAURANT-OPERATIONS-V1-001 appends: availability + availability_reason (closed enums available|unavailable / sold_out|paused), item_name (menu display name — tenant display text already printed on receipts), table_label / from_table_label / to_table_label (floor names). Everything else unchanged: only allowlisted SCALAR keys emit; the nested `capabilities` object keeps its four boolean keys; every un-listed key and nested structure is DROPPED; malformed -> ''{}''; never throws. This is the server-side privacy boundary; the RPC returns NO raw payload JSON.';

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   restore app.sync_push + both CHECK constraints from 20260710100000;
--   restore app.audit_action_has_detail / app.audit_safe_detail from 20260717090000;
--   drop function if exists app.move_order_table(uuid, uuid, uuid, text, uuid, integer);
-- ============================================================================
