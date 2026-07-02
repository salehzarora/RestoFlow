-- ============================================================================
-- MVP — order.status through sync_push (KDS status persistence) + app.pos_menu
-- ============================================================================
-- Two ADDITIVE gaps closed for the visible-MVP order loop, both riding the
-- EXISTING offline sync architecture (DECISION D-010) — no new transport, no
-- new ledger, no client-trusted scope:
--
--   1. app.update_order_status — the KDS/POS order-status mutation RPC
--      (SECURITY DEFINER, D-011). Validates the PIN session + backing device
--      session/pairing + device match EXACTLY like app.submit_order (RF-052);
--      actor/org/restaurant/branch derived from the PIN session, NEVER the
--      payload. Enforces the FROZEN order state machine (STATE_MACHINES §1.1,
--      D-018): SINGLE-STEP forward transitions only —
--        submitted->accepted, accepted->preparing, preparing->ready,
--        ready->served (the KDS "bump")
--          (kitchen_staff / cashier / manager / restaurant_owner / org_owner)
--        served->completed
--          (cashier / manager / restaurant_owner / org_owner ONLY; kitchen_staff
--           may NOT complete -> audited permission_denied, T-006 style)
--      Anything else (skip / backward / terminal source / unknown / from==to)
--      -> {ok:false, error:'invalid_transition', from, to} with NO write.
--      Success bumps orders.revision, writes an append-only
--      order.status_updated audit (D-013) carrying old/new STATUS ONLY — a
--      kitchen actor drives this path, so the audit payload contains NO money
--      fields (T-003; money stays integer minor elsewhere, D-007).
--
--   2. app.sync_push CREATE OR REPLACE — faithful re-creation of
--      20260622150000_rf061_revocation_propagation.sql (the LATEST sync_push
--      body) with ONE added dispatch branch: operation_type 'order.status'
--      (payload {order_id, new_status}) -> app.update_order_status. The
--      accepted operation_type set gains 'order.status' in BOTH envelope
--      validation lists (valid-device path and RF-061 revoked-device recording
--      path) and in the sync_operations CHECK constraint. EVERYTHING else is
--      verbatim RF-061: batch cap 100, PIN-session/device gate, dedup/replay
--      via the sync_operations ledger (idempotency key = device_id +
--      local_operation_id, D-022), payload-fingerprint conflict detection,
--      dependency guard, per-op EXCEPTION subtransactions,
--      applied/rejected/conflict/pending finalization + result storage,
--      revoked_device / revoked_employee handling. No behavioral delta.
--
--   3. app.pos_menu — the POS menu READ RPC (STABLE, SECURITY DEFINER).
--      Validates session + device like app.sync_pull (RF-057); returns the
--      session restaurant's live menu (is_active, not soft-deleted, category
--      live, branch_id null OR = session branch) with the organization's
--      default_currency. MONEY REDACTION (T-003): when the resolved role is
--      kitchen_staff the base_price_minor key is OMITTED from every item —
--      no money figure ever reaches a kitchen principal. Exposed through ONE
--      thin public.pos_menu SECURITY INVOKER wrapper (RF-064/RF-126 pattern).
--      app.update_order_status gets NO public wrapper — it is reachable ONLY
--      through the sync_push dispatcher, mirroring app.submit_order's exposure.
--
-- DECISIONS: D-007 integer minor money (pos_menu emits bigint minor; no float);
--   D-010 offline-first outbox/inbox; D-011 SECURITY DEFINER RPC + search_path='';
--   D-013 append-only audit; D-018 frozen state names used EXACTLY; D-022
--   idempotency key device_id + local_operation_id; T-003 kitchen money redaction.
--
-- HARD RULES HONORED: no prior migration FILE is edited (forward-only; the
--   RF-150-precedent CREATE OR REPLACE of app.sync_push is a NEW migration);
--   grants to authenticated only; scope ALWAYS derived from the PIN session.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. sync_operations.operation_type CHECK — extend the accepted set with
--    'order.status'. Same constraint name as the RF-056 inline check so later
--    migrations/introspection keep working. Existing rows all satisfy the
--    superset (additive; no data rewrite).
-- ----------------------------------------------------------------------------
alter table sync_operations drop constraint sync_operations_operation_type_check;
alter table sync_operations add constraint sync_operations_operation_type_check
  check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status'));

-- ----------------------------------------------------------------------------
-- 2. app.update_order_status — the order fulfillment-status mutation RPC.
--    Validation order mirrors app.submit_order / app.void_order (RF051-B1):
--    PIN session -> backing device session/pairing -> device match ->
--    membership active -> load order FOR UPDATE -> tenant/branch scope ->
--    transition legality -> role authorization -> mutate + audit.
-- ----------------------------------------------------------------------------
create or replace function app.update_order_status(
  p_pin_session_id     uuid,
  p_device_id          uuid,
  p_order_id           uuid,
  p_new_status         text,
  p_local_operation_id text
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
  v_o_rev        integer;
  v_legal        boolean;
  v_new_rev      integer;
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  --     (identical gate to app.submit_order — never trusts client scope).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'update_order_status: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'update_order_status: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'update_order_status: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'update_order_status: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  -- membership active (message keeps the exact 'resolved membership is not active'
  -- fragment so the RF-061 revoked_employee classification in sync_push still applies).
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'update_order_status: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the order FOR UPDATE (serializes concurrent status pushes); it MUST
  --     be in the session organization AND the session branch (pin_sessions is
  --     always branch-scoped, RF-016). Cross-tenant -> fail-closed raise, no write.
  select o.organization_id, o.branch_id, o.status, o.revision
    into v_o_org, v_o_branch, v_o_status, v_o_rev
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'update_order_status: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'update_order_status: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) transition legality: SINGLE-STEP forward only over the FROZEN states
  --     (D-018, STATE_MACHINES §1.1). Skips, backwards, terminal sources
  --     (completed/cancelled/voided), unknown targets, and from==to are all
  --     invalid_transition (returned, not raised — a permanent per-op rejection
  --     through sync_push; no state change).
  v_legal := case
    when v_o_status = 'submitted' and p_new_status = 'accepted'  then true
    when v_o_status = 'accepted'  and p_new_status = 'preparing' then true
    when v_o_status = 'preparing' and p_new_status = 'ready'     then true
    when v_o_status = 'ready'     and p_new_status = 'served'    then true
    when v_o_status = 'served'    and p_new_status = 'completed' then true
    else false end;
  if not v_legal then
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'from', v_o_status, 'to', p_new_status, 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) role authorization: the production + service steps (->accepted/->preparing/
  --     ->ready/->served — the last is the KDS "bump") allow kitchen_staff + cashier
  --     + manager + restaurant_owner + org_owner; the settlement step (->completed)
  --     EXCLUDES kitchen_staff. A denial is audited (order.status_update_denied —
  --     NO money fields) and RETURNED (no raise, so the audit persists), with NO
  --     state change.
  if v_role not in ('kitchen_staff', 'cashier', 'manager', 'restaurant_owner', 'org_owner')
     or (v_role = 'kitchen_staff' and p_new_status = 'completed') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.status_update_denied', null, null,
            jsonb_build_object('attempted_action', 'update_order_status', 'order_id', p_order_id,
                               'role', v_role, 'from', v_o_status, 'to', p_new_status,
                               'local_operation_id', p_local_operation_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (e) mutate: status forward one step; bump revision (updated_at bumps via the
  --     RF-052 set_updated_at trigger, feeding the sync_pull change cursor).
  v_new_rev := v_o_rev + 1;
  update public.orders
    set status = p_new_status, revision = v_new_rev
    where id = p_order_id;

  -- (f) audit order.status_updated (D-013) — old/new STATUS + revision + actor
  --     linkage ONLY. Deliberately NO money fields: a kitchen actor drives this
  --     path and must never put a money figure on the wire or in its audit (T-003).
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.status_updated', null,
          jsonb_build_object('order_id', p_order_id, 'status', v_o_status, 'revision', v_o_rev),
          jsonb_build_object('order_id', p_order_id, 'status', p_new_status, 'revision', v_new_rev,
                             'resolved_membership_id', v_membership, 'role', v_role,
                             'local_operation_id', p_local_operation_id));

  return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                            'status', p_new_status, 'revision', v_new_rev,
                            'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.update_order_status(uuid, uuid, uuid, text, text) is
  'MVP order-status RPC (D-011, D-018, STATE_MACHINES §1.1). Actor/org/branch derived from the PIN session (submit_order gate: valid PIN session + active device session/pairing + device match + active membership); the order is loaded FOR UPDATE and must be in the session org+branch (cross-tenant -> 42501, fail-closed). SINGLE-STEP forward transitions only: submitted->accepted / accepted->preparing / preparing->ready / ready->served (the KDS bump; kitchen_staff/cashier/manager/restaurant_owner/org_owner) and served->completed (cashier/manager/restaurant_owner/org_owner ONLY; kitchen_staff denied -> audited order.status_update_denied + returned permission_denied). Any other from/to (skip, backward, terminal source, unknown, from==to) -> returned invalid_transition, no write. Success bumps orders.revision + updated_at (trigger) and writes an append-only order.status_updated audit with NO money fields (T-003/D-013). Transport idempotency is the sync_operations ledger in app.sync_push (D-022), identical to order.submit; a direct same-transition replay is inert (from==to -> invalid_transition). Dispatcher-reachable only: NO public wrapper (mirrors app.submit_order).';

revoke all on function app.update_order_status(uuid, uuid, uuid, text, text) from public;
grant execute on function app.update_order_status(uuid, uuid, uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.sync_push — CREATE OR REPLACE. FAITHFUL RE-CREATION OF
--    20260622150000_rf061_revocation_propagation.sql (the latest sync_push
--    body) + ONE added dispatch branch: 'order.status' -> app.update_order_status
--    (and 'order.status' added to the two envelope operation_type lists that
--    accept an op). All other behavior — batch cap, session/device gate,
--    RF061-A1 revoked-device recording, dedup/replay, fingerprint conflict,
--    dependency guard, per-op EXCEPTION subtransactions, finalization,
--    revoked_employee tagging — is verbatim RF-061.
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
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status') then
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
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status') then
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
  'RF-056/RF-061 + MVP order.status (API_CONTRACT §4.14, D-010/D-022) SECURITY DEFINER batch push RPC. FAITHFUL re-creation of the RF-061 body (20260622150000_rf061_revocation_propagation.sql) with ONE added dispatch branch: order.status (payload {order_id, new_status}) -> app.update_order_status, using the SAME pin session + device + the op local_operation_id; the accepted operation_type set gains order.status in both envelope validation lists. All RF-056/RF-061 behavior is otherwise verbatim: batch cap 100; PIN session (offline-window bounded, Q-009) + device match gate; RF061-A1 revoked-device per-op recording (rejected/revoked_device, previously-APPLIED ops still replay); per-op dedup/replay via the sync_operations ledger; payload-fingerprint conflict detection; dependency guard; per-op EXCEPTION subtransactions; applied/rejected/conflict/pending finalization + result storage; revoked_employee tagging. Authorization is INGEST-TIME; scope is derived from the session, never the payload. Reimplements NO business logic.';

revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. app.pos_menu — the POS menu READ RPC. Session/device validation identical
--    to app.sync_pull (RF-057 A8); org/restaurant/branch/role derived from the
--    PIN session. Returns the live menu (categories + items) for the session
--    restaurant: is_active, deleted_at null, parent category live, and
--    branch_id null (restaurant-scoped) OR branch_id = session branch.
--    T-003: kitchen_staff receives items WITHOUT the base_price_minor key.
-- ----------------------------------------------------------------------------
create or replace function app.pos_menu(
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
  v_emp        uuid;
  v_membership uuid;
  v_ds_device  uuid;
  v_ds_active  boolean;
  v_ds_revoked timestamptz;
  v_pairing    text;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_redact     boolean;
  v_currency   text;
  v_categories jsonb;
  v_items      jsonb;
begin
  -- (a) PIN session + backing device session/pairing active; device match (A8).
  --     Scope (org/restaurant/branch) + actor + role are derived HERE, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'pos_menu: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'pos_menu: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'pos_menu: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'pos_menu: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'pos_menu: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) T-003 money redaction: a kitchen principal never receives a money figure.
  --     The base_price_minor KEY is omitted (not nulled) from every item below.
  v_redact := (v_role = 'kitchen_staff');

  -- (c) organization default currency (RF-014 organizations.default_currency).
  select o.default_currency into v_currency
    from public.organizations o where o.id = v_org;

  -- (d) live categories of the session restaurant, branch-visible
  --     (branch_id null = restaurant-scoped, or the session branch). Tombstoned
  --     (deleted_at) and inactive rows are excluded — this is the LIVE sell menu,
  --     not the sync feed (tombstone propagation stays with sync_pull, D-020).
  select coalesce(jsonb_agg(
           jsonb_build_object('id', c.id, 'name', c.name, 'display_order', c.display_order)
           order by c.display_order, c.name), '[]'::jsonb)
    into v_categories
    from public.menu_categories c
    where c.organization_id = v_org
      and c.restaurant_id = v_rest
      and c.is_active
      and c.deleted_at is null
      and (c.branch_id is null or c.branch_id = v_branch);

  -- (e) live items: item live + branch-visible AND parent category live +
  --     branch-visible. base_price_minor is integer minor (bigint; D-007) and is
  --     OMITTED entirely for kitchen_staff (T-003).
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
               'description', i.description, 'display_order', i.display_order,
               'default_station_id', i.default_station_id)
           else
             jsonb_build_object(
               'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
               'description', i.description, 'display_order', i.display_order,
               'default_station_id', i.default_station_id,
               'base_price_minor', i.base_price_minor)
           end
           order by i.display_order, i.name), '[]'::jsonb)
    into v_items
    from public.menu_items i
    join public.menu_categories c
      on c.organization_id = i.organization_id and c.id = i.menu_category_id
    where i.organization_id = v_org
      and i.restaurant_id = v_rest
      and i.is_active
      and i.deleted_at is null
      and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active
      and c.deleted_at is null
      and (c.branch_id is null or c.branch_id = v_branch);

  return jsonb_build_object(
    'ok', true,
    'entity', 'menu',
    'currency_code', v_currency,
    'categories', v_categories,
    'items', v_items,
    'server_ts', now());
end;
$$;

comment on function app.pos_menu(uuid, uuid) is
  'MVP POS menu read RPC (D-011, RF-109 schema). STABLE + SECURITY DEFINER + search_path=''''. Validates the PIN session + active device session/pairing + device match exactly like app.sync_pull (A8; 42501 fail-closed) and derives org/restaurant/branch + resolved membership role from the session, never the payload. Returns {ok, entity:menu, currency_code (organizations.default_currency), categories:[{id,name,display_order}], items:[{id,menu_category_id,name,description,display_order,default_station_id[,base_price_minor]}]} for the session restaurant: rows is_active, deleted_at null, parent category live, branch_id null OR = session branch; ordered by display_order then name. T-003 MONEY REDACTION: for kitchen_staff the base_price_minor KEY is omitted from every item — no money figure reaches a kitchen principal (money is integer minor bigint everywhere else, D-007). Read-only; no audit; org+restaurant+branch filter is the isolation boundary (R-003).';

revoke all on function app.pos_menu(uuid, uuid) from public;
grant execute on function app.pos_menu(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. public.pos_menu — thin Data-API-reachable wrapper (RF-064/RF-126 pattern).
--    SECURITY INVOKER + search_path='' + fully-qualified delegate => no privilege
--    change, no search_path hijack, no logic of its own. STABLE (pure read).
--    NO wrapper is added for app.update_order_status: it mirrors app.submit_order
--    and stays reachable ONLY through the sync_push dispatcher.
-- ----------------------------------------------------------------------------
create or replace function public.pos_menu(
  p_pin_session_id uuid,
  p_device_id      uuid
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path = ''
as $$
  select app.pos_menu(
    p_pin_session_id,
    p_device_id
  );
$$;

comment on function public.pos_menu(uuid, uuid) is
  'MVP: NARROW PostgREST-reachable wrapper that delegates verbatim to app.pos_menu (the source of truth). SECURITY INVOKER — runs as the authenticated caller (who holds EXECUTE on app.pos_menu); adds NO authorization logic and NO transformation. All auth (valid PIN session + active device/pairing + device match, 42501 fail-closed) and the T-003 kitchen base_price_minor omission stay inside app.pos_menu. STABLE (pure read). Only this one wrapper is exposed: the `app` schema stays UNEXPOSED and app.update_order_status gets NO public sibling (dispatcher-only, mirroring app.submit_order).';

revoke all on function public.pos_menu(uuid, uuid) from public;
grant execute on function public.pos_menu(uuid, uuid) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop function if exists public.pos_menu(uuid, uuid);
-- drop function if exists app.pos_menu(uuid, uuid);
-- restore the RF-061 app.sync_push body (20260622150000) — no order.status branch;
-- drop function if exists app.update_order_status(uuid, uuid, uuid, text, text);
-- alter table sync_operations drop constraint sync_operations_operation_type_check;
-- alter table sync_operations add constraint sync_operations_operation_type_check
--   check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close'));
-- ============================================================================
