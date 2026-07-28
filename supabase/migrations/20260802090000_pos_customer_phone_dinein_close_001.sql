-- ============================================================================
-- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 — optional order-time customer phone
-- (forward-only, additive). Part A/B of the ticket; the dine-in CLOSE fix is
-- CLIENT-ONLY (the POS emits dispatch_mode='direct_print' for printer_only
-- branches) and needs NO server change — the direct_print lifecycle shipped in
-- 20260729090000 already rests such an order at `served` and completes it on the
-- UNCHANGED settlement rule. This migration only adds the optional phone.
--
-- Additive changes (nothing shipped is modified):
--   1. public.orders.customer_phone text NULL — an ORDER-TIME historical value,
--      mirroring customer_name (20260707120000). Existing rows stay NULL.
--   2. A defensive CHECK: when non-null, 1..32 chars of digits/space/+-() only
--      (no letters, control chars, newlines or tabs) AND at least 5 digits.
--   3. app.is_valid_customer_phone(text) — the ONE server-side phone predicate.
--   4. app.sync_push — re-emit of the 20260729090000 body; the order.submit arm
--      gains an UP-FRONT optional-phone validation (invalid non-empty -> typed
--      invalid_payload, NO order created) and a customer_phone stamp parallel to
--      the customer_name stamp (idempotent via customer_phone is null). Finding 4
--      (Codex): customer_phone is DATA ONLY — it is EXCLUDED from the order.submit
--      idempotency fingerprint (payload minus customer_phone), so re-sending the
--      same (device, local_operation_id) op with only a different phone is an
--      idempotent replay (the FIRST stored phone is kept), never a conflict.
--      Removing an absent key is a no-op, so a phone-less op keeps its EXACT prior
--      fingerprint (existing orders replay unchanged); every other field, every
--      other operation type, the direct_print dispatch, the kitchen payload
--      rebuild and the ledger machinery are unchanged.
--   5. app.owner_order_detail / app.owner_active_orders / app.owner_order_history
--      / app.pos_order_detail — byte-faithful re-emits with 'customer_phone'
--      added to their authorized result shapes (never to search, never to the
--      pos_order_snapshots projection, never to the kitchen dispatch generic JSON
--      ledger). Public SECURITY INVOKER wrappers are pass-through and UNCHANGED.
--
-- PRIVACY: the phone is exposed ONLY through the existing tenant-authorized order
-- reads. It is NOT added to audit free-text, the kitchen dispatch generic ledger,
-- order-status history, or any anonymous endpoint. All SECURITY DEFINER/INVOKER
-- properties, search_path='', grants and PUBLIC/anon revokes are preserved.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The additive order-time column + defensive CHECK.
-- ----------------------------------------------------------------------------
alter table public.orders
  add column customer_phone text;

comment on column public.orders.customer_phone is
  'POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: OPTIONAL order-time customer phone, captured as a display string at submit and never recomputed. Mirrors customer_name. Nullable; NULL = not provided. Validated by app.is_valid_customer_phone at submit and by orders_customer_phone_valid_chk as the final boundary. Never money, never an identifier (T-003); printed on the customer receipt + kitchen ticket when present; exposed ONLY via the tenant-authorized order reads.';

alter table public.orders
  add constraint orders_customer_phone_valid_chk
  check (
    customer_phone is null
    or (
      char_length(customer_phone) between 1 and 32
      and customer_phone ~ '^[0-9 ()+-]+$'
      and char_length(regexp_replace(customer_phone, '[^0-9]', '', 'g')) >= 5
    )
  );

-- ----------------------------------------------------------------------------
-- 2. app.is_valid_customer_phone — the ONE server-side phone predicate.
-- ----------------------------------------------------------------------------
create or replace function app.is_valid_customer_phone(p_phone text)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  select p_phone is not null
     and char_length(p_phone) between 1 and 32
     and p_phone ~ '^[0-9 ()+-]+$'
     and char_length(regexp_replace(p_phone, '[^0-9]', '', 'g')) >= 5;
$$;

comment on function app.is_valid_customer_phone(text) is
  'POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: pure predicate for the OPTIONAL customer phone. True iff the (already-trimmed) candidate is 1..32 chars of digits/space/+-() with at least 5 digits — no letters, control chars, newlines or tabs. INTERNAL: revoked from every client role; app.sync_push calls it after btrim to reject an invalid non-empty phone with a typed invalid_payload.';

revoke all on function app.is_valid_customer_phone(text) from public;
revoke all on function app.is_valid_customer_phone(text) from anon;
revoke all on function app.is_valid_customer_phone(text) from authenticated;


-- ----------------------------------------------------------------------------
-- 3. app.sync_push — byte-faithful re-emit of the 20260729090000 body with the
--    optional-phone validation + stamp added to the order.submit arm only.
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
  -- PSC-001C correction (Finding 1): the existing row's id when the atomic
  -- ledger claim loses, and whether this request ADOPTED a stale non-terminal
  -- row (the only case that bumps retry_count — the pre-fix contract).
  v_ex_id        uuid;
  v_adopted      boolean;
  v_so_id        uuid;
  v_dispatch     jsonb;
  v_dispatch_ok  boolean;
  v_caught_state text;
  v_caught_msg   text;
  v_results      jsonb := '[]'::jsonb;
  v_op_result    jsonb;
  v_device_revoked boolean := false;
  v_customer_name text;
  v_customer_phone text;
  v_ack_order    uuid;
  v_ack_ok       boolean;
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
      -- PSC-001D correction (F3) + PSC-001C: for the three IDENTITY-HARDENED
      -- operations (order.void_ack, order.items_add, order.round_status) the
      -- target id is parsed inside a PROTECTED boundary — a malformed uuid
      -- must reject only ITS operation, never abort the whole batch. The 12
      -- prior operations keep their exact existing parse semantics.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        begin
          v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
        exception when others then
          v_target_id := null;
        end;
      else
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      end if;
      v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

      -- envelope validation (same as the valid path): malformed -> rejected result, NO ledger row
      if v_local_op is null or btrim(v_local_op) = '' then
        v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
          'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status') then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
          'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;

      -- PSC-001D correction (final pass) + PSC-001C: the SAME canonical
      -- identity contract as the valid path for ALL THREE hardened operations,
      -- enforced BEFORE the fingerprint, the terminal-replay lookup, the
      -- idempotency-conflict comparison and the ledger write. A revoked device
      -- must not gain permission to submit ambiguous or contradictory
      -- operation identity: a missing, malformed or CONTRADICTORY
      -- target/payload-identity pair (payload.order_id for order.void_ack and
      -- order.items_add; payload.round_id for order.round_status) is a hostile
      -- or malformed envelope — rejected with NO ledger row (the malformed-
      -- envelope convention), the batch continues. Only that op is affected.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        v_ack_ok := v_target_id is not null;
        begin
          v_ack_order := nullif(v_payload ->> (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end), '')::uuid;
        exception when others then
          v_ack_order := null;
        end;
        if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
            'ok', false, 'error', 'invalid_payload',
            'detail', v_op_type || ' requires matching uuid target_id and payload.'
                      || (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end),
            'status', 'rejected', 'idempotency_replay', false);
          continue;
        end if;
      end if;

      -- PSC-001D correction (F2 + final pass) + PSC-001C: the SAME target-
      -- bound fingerprint SHAPE as the valid path for all three hardened
      -- operations — the target component is the PARSED uuid's text
      -- (guaranteed non-null and equal to the parsed payload identity by the
      -- check above), so a legitimately-applied op still replays its stored
      -- result after a revocation (identical identity -> identical
      -- fingerprint), while the 12 prior operations are unchanged.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
        v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
      else
        -- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 4): customer_phone is DATA
        -- ONLY on an order.submit — carried in the payload for persistence but
        -- EXCLUDED from the operation identity, so re-sending the same op with only
        -- a different phone is an idempotent replay, not a conflict. Removing an
        -- absent key is a no-op, so a phone-less op keeps its EXACT prior
        -- fingerprint (backward compatible); every other field and every other
        -- operation type is unchanged.
        v_fingerprint := md5(v_op_type || '|' || (case when v_op_type = 'order.submit' then v_payload - 'customer_phone' else v_payload end)::text);
      end if;

      -- dedup/replay (PSC-001C correction, Finding 1 — ATOMIC CLAIM): the
      -- rejected/revoked_device recording is now claimed with ONE
      -- INSERT .. ON CONFLICT DO NOTHING on the transport identity. When the
      -- claim loses, the existing row is LOCKED (waiting out any concurrent
      -- claimant's COMMIT) and decided from its COMMITTED state: a TERMINAL
      -- row replays its stored result (a legitimately-APPLIED op before
      -- revocation is NOT re-rejected — and can no longer be OVERWRITTEN by
      -- this path racing a valid-device apply); a different identity is a
      -- conflict; only a genuinely stale NON-terminal row is re-recorded as
      -- rejected (the pre-fix retry contract, bump included).
      v_so_id := null;
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, rejection_reason,
        result, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'rejected',
              'revoked_device', 'permanent', 'revoked_device',
              jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'), v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do nothing
      returning so.id into v_so_id;
      if v_so_id is null then
        select so.id, so.status, so.result, so.operation_type, so.payload_fingerprint
          into v_ex_id, v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
          from public.sync_operations so
          where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op
          for update;
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
        -- a stale NON-terminal row: re-record it as rejected (revoked_device)
        -- under the held lock — the pre-fix on-conflict contract, verbatim.
        update public.sync_operations as so
          set status = 'rejected', last_error_code = 'revoked_device', last_error_class = 'permanent',
              rejection_reason = 'revoked_device',
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'),
              retry_count = so.retry_count + 1, updated_at = now()
          where so.id = v_ex_id;
      end if;
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
    -- PSC-001D correction (F3) + PSC-001C: protected parse for the three
    -- identity-hardened operations — a malformed target uuid rejects only ITS
    -- operation (below), never the batch. The 12 prior operations keep their
    -- exact existing semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      begin
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      exception when others then
        v_target_id := null;
      end;
    else
      v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
    end if;
    v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

    -- (b1) envelope shape validation. Malformed envelopes are returned rejected
    --      WITHOUT a ledger row (they cannot be keyed/stored safely); they never dispatch.
    if v_local_op is null or btrim(v_local_op) = '' then
      v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
        'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status') then
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

    -- (b1+) PSC-001D correction (F2/F3) + PSC-001C: CANONICAL TARGET IDENTITY
    -- for the three hardened operations, enforced BEFORE the fingerprint, the
    -- terminal-replay lookup and the dispatch. The envelope MUST carry a
    -- parseable target_id AND a parseable payload identity (payload.order_id
    -- for order.void_ack and order.items_add; payload.round_id for
    -- order.round_status) and they MUST be the same uuid — a missing,
    -- malformed or CONTRADICTORY pair is a hostile/malformed envelope:
    -- rejected with NO ledger row (the malformed-envelope convention), so a
    -- replayed local_operation_id with a swapped target can never reach the
    -- stored terminal result, mutate anything, or learn anything about
    -- another order or round. Only that operation is affected.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      v_ack_ok := v_target_id is not null;
      begin
        v_ack_order := nullif(v_payload ->> (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end), '')::uuid;
      exception when others then
        v_ack_order := null;
      end;
      if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload',
          'detail', v_op_type || ' requires matching uuid target_id and payload.'
                    || (case when v_op_type = 'order.round_status' then 'round_id' else 'order_id' end),
          'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
    end if;

    -- PSC-001D correction (F2) + PSC-001C: the fingerprint of every hardened
    -- operation BINDS the canonical target identity, so a terminal replay is
    -- valid only for the same local_operation_id + operation + payload +
    -- TARGET. The 12 prior operations keep their exact existing fingerprint
    -- semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status') then
      v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
    else
      -- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 4): order.submit identity
      -- EXCLUDES customer_phone (data-only) — same canonical rule as the
      -- rejection path above, so both paths fingerprint an op identically. A
      -- phone-less op is byte-identical; all other fields/op-types unchanged.
      v_fingerprint := md5(v_op_type || '|' || (case when v_op_type = 'order.submit' then v_payload - 'customer_phone' else v_payload end)::text);
    end if;

    -- (b2) ATOMIC LEDGER CLAIM (PSC-001C correction, Finding 1). The pre-fix
    -- shape read the ledger and only LATER upserted it, so two concurrent
    -- requests with the SAME (org, device, local_operation_id) + fingerprint
    -- could both pass the read; the loser's upsert then dragged the winner's
    -- COMMITTED terminal row back to in_flight, re-dispatched (now an
    -- invalid_transition), and finalized the previously-successful row as
    -- rejected. The claim is now ONE INSERT .. ON CONFLICT DO NOTHING on the
    -- transport identity, computed AFTER envelope validation + identity
    -- canonicalization + the fingerprint:
    --   * claim WON  -> this transaction owns dispatch (fresh row, in_flight,
    --     retry_count 0) and finalizes it exactly once at (b6);
    --   * claim LOST -> the existing row is LOCKED (FOR UPDATE — waiting out a
    --     concurrent claimant's COMMIT) and decided from COMMITTED state: a
    --     fingerprint/op mismatch keeps the exact idempotency-conflict
    --     contract; a TERMINAL row replays its stored result (and can never be
    --     overwritten or reset to in_flight again); only a genuinely stale
    --     NON-terminal row (pending / crashed in_flight) is ADOPTED — the
    --     pre-fix retry contract, bump included. A losing concurrent caller
    --     therefore converges on the winner's stored terminal result.
    v_adopted := false;
    v_so_id   := null;
    insert into public.sync_operations as so (
      organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
      target_entity, target_id, payload, payload_fingerprint, depends_on, status, client_created_at)
    values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
            v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'in_flight', v_client_ts)
    on conflict (organization_id, device_id, local_operation_id) do nothing
    returning so.id into v_so_id;

    if v_so_id is null then
      select so.id, so.status, so.result, so.operation_type, so.payload_fingerprint
        into v_ex_id, v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
        from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op
        for update;
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
      v_so_id   := v_ex_id;
      v_adopted := true;
    end if;

    -- (b3) dependency guard (still BEFORE any dispatch; the claimed/adopted
    -- row is parked as pending exactly like the pre-fix contract — a fresh
    -- claim keeps retry_count 0, an adopted re-attempt bumps it).
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
      update public.sync_operations as so
        set status = 'pending', last_error_code = 'dependency_not_ready', last_error_class = 'transient',
            retry_count = so.retry_count + (case when v_adopted then 1 else 0 end),
            updated_at = now()
        where so.id = v_so_id;
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'dependency_not_ready', 'retryable', true, 'status', 'pending', 'idempotency_replay', false);
      continue;
    end if;

    -- (b4) an ADOPTED stale re-attempt returns to in_flight with the retry
    -- bump (the pre-fix on-conflict contract); a fresh claim is already
    -- in_flight and is never re-written here.
    if v_adopted then
      update public.sync_operations as so
        set status = 'in_flight', retry_count = so.retry_count + 1, updated_at = now()
        where so.id = v_so_id;
    end if;

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
          -- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: validate the OPTIONAL customer
          -- phone UP FRONT. Empty/whitespace -> null (the order proceeds). A
          -- non-empty value that is not a valid phone (>32 chars / a disallowed
          -- character / fewer than 5 digits) REJECTS the whole op with a typed
          -- invalid_payload and creates NO order (the POS UI already blocks
          -- submit on an invalid phone; this is server-side defence in depth,
          -- and the DB CHECK is the final boundary). A valid/empty phone falls
          -- through to the UNCHANGED submit path; a valid phone is stamped after.
          v_customer_phone := btrim(coalesce(v_payload ->> 'customer_phone', ''));
          if v_customer_phone <> '' and not app.is_valid_customer_phone(v_customer_phone) then
            v_dispatch := jsonb_build_object(
              'ok', false, 'error', 'invalid_payload', 'detail', 'customer_phone');
          else
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
            -- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001: stamp the validated OPTIONAL
            -- customer phone parallel to customer_name. Tenant-scoped; the
            -- `customer_phone is null` guard makes an offline replay idempotent
            -- (a replay returns the same order_id, already stamped) and never
            -- overwrites. The value was validated BEFORE submit_order below.
            if v_customer_phone <> '' then
              update public.orders
                set customer_phone = v_customer_phone
                where id = (v_dispatch ->> 'order_id')::uuid
                  and organization_id = v_org
                  and customer_phone is null;
            end if;
            -- KITCHEN-MODE-001C1-CORRECTION-001: the initial kitchen dispatch
            -- payload is built inside app.submit_order BEFORE this stamp, so on
            -- the REAL push path customer_display_name was missing. Rebuild the
            -- COMPLETE normalized payload through the trusted internal server
            -- builder IN THIS SAME TRANSACTION — never by patching client JSON
            -- in, never after a client could have seen it (claimed / completed
            -- / superseded rows are left untouched; inside this first-apply
            -- transaction the row is not yet visible to any puller), never
            -- duplicating the dispatch or its audit row (no INSERT, no audit
            -- here). The row only exists for printer_only branches, so kds
            -- branches are a structural no-op; the guard trigger re-proves the
            -- rebuilt payload money-free on UPDATE.
            if v_customer_name <> '' then
              update public.kitchen_print_dispatches kd
                set money_free_payload = app.kitchen_dispatch_payload_initial(v_org, (v_dispatch ->> 'order_id')::uuid),
                    updated_at = now()
                where kd.organization_id = v_org
                  and kd.order_id = (v_dispatch ->> 'order_id')::uuid
                  and kd.dispatch_type = 'initial_order'
                  and kd.claimed_at is null
                  and kd.completed_at is null
                  and kd.superseded_by_dispatch_id is null;
            end if;
            -- KITCHEN-PRINT-DUAL-001C: a direct_print order is dispatched to the
            -- kitchen via the POS printer (no KDS device). Route it OUT of the KDS
            -- active workflow IN THIS SAME transaction — a concurrent sync_pull can
            -- never observe an intermediate active state (sync_push commits once).
            -- Promotes the fresh submitted order to `served` + stamps dispatch_mode;
            -- the UNCHANGED served+paid rule still owns completion (settlement is
            -- NEVER bypassed). A 'kds' (default) order is a structural no-op here.
            if coalesce(v_payload ->> 'dispatch_mode', 'kds') = 'direct_print' then
              -- Merge the ADDITIVE outcome (order_status/revision/auto_completed)
              -- into the envelope so the client sees the FINAL committed state,
              -- exactly like the zero-total submit tail. A no-op replay merges only
              -- {dispatched:false} (submit_order's replay already re-reads the
              -- current revision), so the envelope stays correct.
              v_dispatch := v_dispatch || app.apply_direct_print_dispatch(
                v_org, v_rest, v_branch, (v_dispatch ->> 'order_id')::uuid,
                v_emp, v_membership, p_device_id, v_local_op);
            end if;
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
        when 'menu.availability_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: a cashier (default-ON
          -- manage_menu_availability) or manager+ sets a menu item's per-branch
          -- availability from the POS. Actor/org/branch derive from the PIN
          -- session (NEVER the payload); the capability is enforced inside. The
          -- payload contributes ONLY {menu_item_id, availability, reason}. The
          -- setter is naturally idempotent (no-change re-applies the same state
          -- with no audit) and transport dedup (sync_operations) guards replay.
          -- Typed RETURN refusals (permission_denied / not_found) survive
          -- verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_item_availability(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'menu_item_id')::uuid,
            v_payload ->> 'availability',
            nullif(v_payload ->> 'reason', ''));
        when 'table.status_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: manual table floor-state from the
          -- POS (manage_table_operations). Scope/actor from the session; payload
          -- {table_id, status}. Typed refusals survive verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_table_status(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid,
            v_payload ->> 'status');
        when 'table.link' then
          -- Link two same-branch tables into an operational group (no order/bill
          -- merge). Payload {table_id_a, table_id_b}. Deterministic lock order.
          v_dispatch := app.pos_link_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id_a')::uuid,
            (v_payload ->> 'table_id_b')::uuid);
        when 'table.unlink' then
          -- Dissolve the group a table belongs to (orders untouched). Payload
          -- {table_id}.
          v_dispatch := app.pos_unlink_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid);
        when 'order.void_ack' then
          -- PSC-001D: the kitchen's cancellation acknowledgement. Mirrors the
          -- order.status branch — actor/org/branch come from the PIN session
          -- (never the payload); the payload contributes ONLY {order_id}.
          -- app.kitchen_ack_void enforces the KDS-class device, the kitchen
          -- role set, the voided + ack-required state, and the idempotent
          -- already-acknowledged replay; its flat typed refusals
          -- (invalid_device_type / permission_denied / order_not_voided /
          -- acknowledgement_not_required) RETURN through verbatim. TARGET-ID
          -- CONSISTENCY is enforced at (b1+) BEFORE the fingerprint and the
          -- terminal replay — by the time this arm runs, target_id and
          -- payload.order_id are guaranteed present, valid and equal. The
          -- check below is pure defence-in-depth and unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.void_ack target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.kitchen_ack_void(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op);
        when 'order.items_add' then
          -- PSC-001C: add items to an existing eligible dine-in order as ONE
          -- new authoritative service round. Actor/org/branch come from the
          -- PIN session; the payload contributes {order_id, order_items}.
          -- app.add_order_items enforces the POS-class device, the cashier+
          -- role set, eligibility (dine_in, open status, no completed
          -- payment), submit_order-parity pricing/sellability, and round-level
          -- idempotency; its flat typed refusals (invalid_device_type /
          -- permission_denied / order_not_dine_in / order_not_eligible /
          -- order_already_settled / item_unavailable / invalid_item_payload)
          -- RETURN through verbatim. TARGET-ID CONSISTENCY is enforced at
          -- (b1+) BEFORE the fingerprint and the terminal replay — the check
          -- below is pure defence-in-depth and unreachable.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.items_add target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.add_order_items(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload -> 'order_items',
            v_client_ts);
        when 'order.round_status' then
          -- PSC-001C: the additional service round's own single-step
          -- lifecycle. Actor/org/branch come from the PIN session; the
          -- payload contributes {round_id, new_status}. app.update_round_status
          -- enforces the LOCKED device/role matrix (production steps KDS-only;
          -- ready->served KDS kitchen set or POS cashier set), the parent
          -- guards, single-step legality, the WRITE-ONCE ready_at stamp and
          -- the completion chain; its flat typed refusals RETURN through
          -- verbatim. TARGET-ID CONSISTENCY (against payload.round_id) is
          -- enforced at (b1+) — the check below is pure defence-in-depth and
          -- unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'round_id')::uuid then
            raise exception 'sync_push: order.round_status target_id does not match payload.round_id' using errcode = '42501';
          end if;
          v_dispatch := app.update_round_status(
            p_pin_session_id,
            (v_payload ->> 'round_id')::uuid,
            p_device_id,
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
  'RF-056/RF-061 + ... + PSC-001D + PSC-001C (D-010/D-022) SECURITY DEFINER batch push — faithful re-creation of the 20260722090000 body; all 15 canonical operations, identity hardening, atomic ledger claim, batch cap, result ordering, dependency guard, per-op subtransactions, finalization and the customer_name stamp are verbatim. KITCHEN-MODE-001C1-CORRECTION-001 (order.submit only): immediately after the customer_name stamp, the order''s still-unclaimed initial kitchen dispatch payload is REBUILT through app.kitchen_dispatch_payload_initial in the SAME transaction, so the REAL push path carries customer_display_name exactly like the direct-call path; kds branches are a structural no-op and claimed/completed/superseded dispatches are never touched. Authorization INGEST-TIME; scope from the session, never the payload.';

-- ACL parity (CREATE OR REPLACE preserves grants; re-issued explicitly).
revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
revoke all on function app.sync_push(uuid, uuid, jsonb) from anon;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;


-- ----------------------------------------------------------------------------
-- 4. app.owner_order_detail — re-emit with customer_phone in the order header.
-- ----------------------------------------------------------------------------
create or replace function app.owner_order_detail(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_order_id        uuid default null
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
  v_currency text;
  v_zone     text;
  v_order    jsonb;
  v_items    jsonb;
  v_payments jsonb;
begin
  if v_actor is null then
    raise exception 'owner_order_detail: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_order_detail: organization_id is required' using errcode = '42501';
  end if;
  if p_order_id is null then
    raise exception 'owner_order_detail: order_id is required' using errcode = '22023';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_order_detail: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_order_detail');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_order_detail: organization not found (or deleted)' using errcode = '42501';
  end if;

  -- The order, scoped. A miss (wrong tenant / out of scope / deleted) returns a
  -- clean not_found (never leaks that another tenant's order exists).
  select
    coalesce(b.timezone, r.timezone, 'UTC'),
    jsonb_build_object(
      'order_id',             o.id,
      'order_code',           '#' || upper(right(replace(o.id::text, '-', ''), 6)),
      'receipt_number',       o.receipt_number,
      'status',               o.status,
      'order_type',           o.order_type,
      'customer_name',        o.customer_name,
      'customer_phone',       o.customer_phone,
      'table_label',          tbl.label,
      'branch_name',          b.name,
      'staff_name',           ep.display_name,
      'notes',                o.notes,
      'created_at',           to_char(o.created_at at time zone coalesce(b.timezone, r.timezone, 'UTC'), 'YYYY-MM-DD HH24:MI'),
      'currency_code',        o.currency_code,
      'subtotal_minor',       o.subtotal_minor,
      'discount_total_minor', o.discount_total_minor,
      'tax_total_minor',      o.tax_total_minor,
      'grand_total_minor',    o.grand_total_minor)
    into v_zone, v_order
  from public.orders o
  left join public.branches b
    on b.organization_id = o.organization_id and b.id = o.branch_id
  left join public.restaurants r
    on r.organization_id = o.organization_id and r.id = o.restaurant_id
  left join public.tables tbl
    on tbl.organization_id = o.organization_id and tbl.id = o.table_id and tbl.deleted_at is null
  left join public.employee_profiles ep
    on ep.organization_id = o.organization_id and ep.id = o.opened_by_employee_profile_id
  where o.id              = p_order_id
    and o.organization_id = p_organization_id
    and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
    and (p_branch_id     is null or o.branch_id     = p_branch_id)
    and o.deleted_at is null;

  if v_order is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'owner_order_detail');
  end if;

  -- Line items with their captured modifier snapshots (option name/qty +
  -- price + the non-money meat_snapshot) and the item prep_snapshot. The KDS
  -- kitchen-count/prep totals are aggregated client-side from these snapshots.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'order_item_id',      oi.id,
             'name',               oi.menu_item_name_snapshot,
             'quantity',           oi.quantity,
             'station_id',         oi.station_id,
             'notes',              oi.notes,
             'unit_price_minor',   oi.unit_price_minor_snapshot,
             'line_discount_minor',oi.line_discount_minor,
             'line_total_minor',   oi.line_total_minor,
             'prep_snapshot',      oi.prep_snapshot,
             'modifiers', (
               select coalesce(jsonb_agg(
                        jsonb_build_object(
                          'option_name',   m.option_name_snapshot,
                          'modifier_name', m.modifier_name_snapshot,
                          'quantity',      m.quantity,
                          'price_minor',   m.price_minor_snapshot,
                          'meat_snapshot', m.meat_snapshot)
                        order by m.created_at, m.id), '[]'::jsonb)
               from public.order_item_modifiers m
               where m.organization_id = oi.organization_id
                 and m.order_item_id   = oi.id
                 and m.deleted_at is null))
           order by oi.created_at, oi.id), '[]'::jsonb)
    into v_items
  from public.order_items oi
  where oi.organization_id = p_organization_id
    and oi.order_id        = p_order_id
    and oi.deleted_at is null;

  select coalesce(jsonb_agg(
           jsonb_build_object(
             'method',         p.method,
             'status',         p.status,
             'amount_minor',   p.amount_minor,
             'tendered_minor', p.tendered_minor,
             'change_minor',   p.change_minor,
             'receipt_number', p.receipt_number,
             'created_at',     to_char(p.created_at at time zone v_zone, 'YYYY-MM-DD HH24:MI'))
           order by p.created_at, p.id), '[]'::jsonb)
    into v_payments
  from public.payments p
  where p.organization_id = p_organization_id
    and p.order_id        = p_order_id
    and p.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_order_detail',
    'currency_code', v_currency,
    'order', v_order
      || jsonb_build_object('items', v_items, 'payments', v_payments)
  );
end;
$$;

comment on function app.owner_order_detail(uuid, uuid, uuid, uuid) is
  'ORDERS-HISTORY-001 (read-only; D-007/D-008/D-011/D-020): GUC-free single-order DETAIL for the owner/manager Dashboard details drawer + receipt / money-free kitchen-ticket previews. Same authorization as owner_order_history (actor_rank_in_scope; GUC-free financial-read allowlist; kitchen_staff -> permission_denied). Returns the order header (customer/table/staff/status/times), line items with captured modifier + meat_snapshot + prep_snapshot, and payments — all money integer minor read from stored snapshots (never recomputed; D-008). Scoped; an out-of-scope/missing order -> {ok:false,error:not_found} (no cross-tenant leak). No anon/service_role.';


-- ----------------------------------------------------------------------------
-- 5. app.owner_active_orders — re-emit with customer_phone (scoped CTE + row).
-- ----------------------------------------------------------------------------
create or replace function app.owner_active_orders(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_status          text default null,   -- one ACTIVE status (must sit INSIDE p_queue)
  p_order_type      text default null,   -- 'dine_in' | 'takeaway'
  p_payment         text default null,   -- 'paid' | 'unpaid' | 'cash'
  p_search          text default null,   -- order code / customer / table / receipt
  p_limit           int  default 100,
  -- ACTIVE-ORDERS-002 (appended, backward-compatible defaults):
  p_queue           text default 'all_active',  -- in_progress | awaiting_close | all_active
  p_sort            text default 'newest',      -- newest | oldest
  p_cursor          text default null           -- "<sort>|<created_at>|<id>"
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid    := app.current_app_user_id();
  v_rank       integer;
  v_currency   text;
  v_limit      integer := least(greatest(coalesce(p_limit, 100), 1), 200);
  v_search     text    := nullif(btrim(coalesce(p_search, '')), '');
  v_queue      text    := coalesce(nullif(btrim(coalesce(p_queue, '')), ''), 'all_active');
  v_sort       text    := coalesce(nullif(btrim(coalesce(p_sort,  '')), ''), 'newest');
  -- The canonical OPERATIONALLY ACTIVE set (D-018). Terminal states
  -- (completed/cancelled/voided) and the local-only `draft` are excluded.
  v_active     text[]  := array['submitted', 'accepted', 'preparing', 'ready', 'served'];
  -- The QUEUES. These are a PRESENTATION grouping OVER the canonical states —
  -- not a new taxonomy: every member is one of the five canonical active states.
  v_in_prog    text[]  := array['submitted', 'accepted', 'preparing', 'ready'];
  v_awaiting   text[]  := array['served'];
  v_queue_set  text[];
  v_newest     boolean;
  v_cursor_ts  timestamptz;
  v_cursor_id  uuid;
  v_summary    jsonb;
  v_rows       jsonb;
  v_matching   bigint;
  v_fetched    bigint;
  v_more       boolean;
  v_next       text;
begin
  if v_actor is null then
    raise exception 'owner_active_orders: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_active_orders: organization_id is required' using errcode = '42501';
  end if;

  -- ---- ENUM-VALIDATED controls. An unknown token is a BAD REQUEST (22023) —
  --      never a silently-empty board, and NOTHING is interpolated into SQL.
  case v_queue
    when 'in_progress'    then v_queue_set := v_in_prog;
    when 'awaiting_close' then v_queue_set := v_awaiting;
    when 'all_active'     then v_queue_set := v_active;
    else raise exception 'owner_active_orders: unknown queue %', v_queue using errcode = '22023';
  end case;

  if v_sort not in ('newest', 'oldest') then
    raise exception 'owner_active_orders: unknown sort %', v_sort using errcode = '22023';
  end if;
  v_newest := (v_sort = 'newest');

  -- A status filter must be an ACTIVE status AND must sit INSIDE the selected
  -- queue — otherwise the two controls would silently contradict each other.
  if p_status is not null then
    if not (p_status = any (v_active)) then
      raise exception 'owner_active_orders: % is not an active order status', p_status using errcode = '22023';
    end if;
    if not (p_status = any (v_queue_set)) then
      raise exception 'owner_active_orders: status % is not in queue %', p_status, v_queue using errcode = '22023';
    end if;
  end if;

  if p_order_type is not null and p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'owner_active_orders: unknown order_type %', p_order_type using errcode = '22023';
  end if;
  if p_payment is not null and p_payment not in ('paid', 'unpaid', 'cash') then
    raise exception 'owner_active_orders: unknown payment filter %', p_payment using errcode = '22023';
  end if;

  -- ---- The keyset cursor is TAGGED with the sort it was minted under:
  --      "<sort>|<created_at>|<id>". Replaying a cursor under the OTHER direction
  --      would silently skip or duplicate rows, so it is REJECTED outright.
  if p_cursor is not null and btrim(p_cursor) <> '' then
    if split_part(p_cursor, '|', 1) <> v_sort then
      raise exception 'owner_active_orders: cursor was issued for sort % but sort % was requested',
        split_part(p_cursor, '|', 1), v_sort using errcode = '22023';
    end if;
    begin
      v_cursor_ts := split_part(p_cursor, '|', 2)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 3)::uuid;
    exception when others then
      raise exception 'owner_active_orders: invalid cursor' using errcode = '22023';
    end;
  end if;

  -- ---- authority over the PASSED scope (downward-only); 0 => not a member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_active_orders: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free); kitchen_staff DENIED (the board carries totals).
  if not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_active_orders');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_active_orders: organization not found (or deleted)' using errcode = '42501';
  end if;

  with scoped as (
    -- EVERY active order in scope (all five canonical states), regardless of the
    -- selected queue — this is what the SUMMARY counts, so the cards stay stable
    -- while the operator switches queues. Deliberately NO date window: an order
    -- still open across midnight must never vanish from an operations board.
    -- LEFT joins (+ a 'UTC' fallback) so a tz-less or soft-deleted branch can
    -- never silently DROP a live order.
    select o.id,
           o.status,
           o.order_type,
           o.customer_name,
           o.customer_phone,
           o.receipt_number,
           o.grand_total_minor,
           o.created_at,
           o.table_id,
           o.opened_by_employee_profile_id,
           coalesce(b.timezone, r.timezone, 'UTC') as zone,
           b.name                                  as branch_name,
           pay.method                              as payment_method,
           pay.amount_minor                        as paid_amount_minor,
           -- MONEY-SETTLEMENT-CONSISTENCY-001: SETTLEMENT, not a marker. `is_paid` now
           -- answers "does this order still owe money?" via THE one canonical predicate,
           -- so a NON-CHARGEABLE zero-total order is settled (it was reported UNPAID
           -- forever before, because there is no payment row to find) and an UNDER-COVERED
           -- order is NOT settled (it was reported PAID before). `payment_method` and
           -- `paid_amount_minor` still come from the payment row: they DISPLAY what was
           -- actually taken, and are legitimately null when nothing was.
           app.order_is_fully_settled(o.organization_id, o.id) as is_paid,
           (o.grand_total_minor > 0)               as is_chargeable
    from public.orders o
    left join public.branches b
      on b.organization_id = o.organization_id
     and b.id              = o.branch_id
     and b.deleted_at is null
    left join public.restaurants r
      on r.organization_id = o.organization_id
     and r.id              = o.restaurant_id
     and r.deleted_at is null
    left join lateral (
      -- the single completed payment for the order (at most one; D-024/D-025).
      select p.method, p.amount_minor
      from public.payments p
      where p.organization_id = o.organization_id
        and p.order_id        = o.id
        and p.deleted_at is null
        and p.status = 'completed'
      order by p.created_at desc, p.id desc
      limit 1
    ) pay on true
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and o.status = any (v_active)
  ),
  matched as (
    -- The QUEUE + the list filters. This is the set `matching` counts and the
    -- page is drawn from.
    select s.*,
           tbl.label                     as table_label,
           ep.display_name               as staff_name,
           coalesce(items.item_count, 0) as item_count
    from scoped s
    left join public.tables tbl
      on tbl.organization_id = p_organization_id
     and tbl.id             = s.table_id
     and tbl.deleted_at is null
    left join public.employee_profiles ep
      on ep.organization_id = p_organization_id
     and ep.id             = s.opened_by_employee_profile_id
    left join lateral (
      select sum(oi.quantity)::bigint as item_count
      from public.order_items oi
      where oi.organization_id = p_organization_id
        and oi.order_id        = s.id
        and oi.deleted_at is null
    ) items on true
    where s.status = any (v_queue_set)
      and (p_status     is null or s.status     = p_status)
      and (p_order_type is null or s.order_type = p_order_type)
      and (
        p_payment is null
        or (p_payment = 'paid'   and s.is_paid)
        or (p_payment = 'unpaid' and not s.is_paid)
        or (p_payment = 'cash'   and s.payment_method = 'cash')
      )
      and (
        v_search is null
        or s.customer_name ilike '%' || v_search || '%'
        or coalesce(s.receipt_number, '') ilike '%' || v_search || '%'
        or coalesce(tbl.label, '') ilike '%' || v_search || '%'
        or upper(right(replace(s.id::text, '-', ''), 6)) like '%' || upper(replace(v_search, '#', '')) || '%'
      )
  ),
  page as (
    -- SERVER-SIDE sort + keyset continuation. `id` breaks ties so equal
    -- timestamps order stably and paginate without duplicates or gaps.
    -- One extra row is fetched to decide has_more without a second count.
    select m.*
    from matched m
    where p_cursor is null
       or v_cursor_ts is null
       or (v_newest and (m.created_at, m.id) < (v_cursor_ts, v_cursor_id))
       or (not v_newest and (m.created_at, m.id) > (v_cursor_ts, v_cursor_id))
    order by
      case when v_newest then m.created_at end desc,
      case when v_newest then m.id         end desc,
      case when not v_newest then m.created_at end asc,
      case when not v_newest then m.id         end asc
    limit v_limit + 1
  ),
  numbered as (
    select p.*,
           row_number() over (
             order by
               case when v_newest then p.created_at end desc,
               case when v_newest then p.id         end desc,
               case when not v_newest then p.created_at end asc,
               case when not v_newest then p.id         end asc
           ) as rn
    from page p
  )
  select
    jsonb_build_object(
      'total',  (select count(*) from scoped),
      'unpaid', (select count(*) from scoped where not is_paid),
      -- The QUEUE counters the cards render — scope-wide, never the page.
      'in_progress',    (select count(*) from scoped where status = any (v_in_prog)),
      'awaiting_close', (select count(*) from scoped where status = any (v_awaiting)),
      'by_status', jsonb_build_object(
        'submitted', (select count(*) from scoped where status = 'submitted'),
        'accepted',  (select count(*) from scoped where status = 'accepted'),
        'preparing', (select count(*) from scoped where status = 'preparing'),
        'ready',     (select count(*) from scoped where status = 'ready'),
        'served',    (select count(*) from scoped where status = 'served'))),
    (select count(*) from matched),
    -- The EXTRA row fetched (limit v_limit + 1) is what decides has_more. It must
    -- NOT be derived from `matching`, which counts the WHOLE filtered set: on the
    -- last page of a paginated read, `matching` still exceeds the page size even
    -- though nothing remains after it.
    (select count(*) from numbered),
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id',          n.id,
               'order_code',        '#' || upper(right(replace(n.id::text, '-', ''), 6)),
               'receipt_number',    n.receipt_number,
               'status',            n.status,
               'order_type',        n.order_type,
               'customer_name',     n.customer_name,
               'customer_phone',    n.customer_phone,
               'table_label',       n.table_label,
               'branch_name',       n.branch_name,
               'staff_name',        n.staff_name,
               -- Branch-local DISPLAY string + the ABSOLUTE instant the client
               -- needs for elapsed time, plus the resolved zone. Storage is UTC.
               'created_at',        to_char(n.created_at at time zone n.zone, 'YYYY-MM-DD HH24:MI'),
               'created_at_utc',    to_char(n.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'timezone',          n.zone,
               'item_count',        n.item_count,
               'grand_total_minor', n.grand_total_minor,
               'payment_method',    n.payment_method,
               -- THREE honest states. Saying "paid" for an order that was never charged
               -- would be a lie, and "unpaid" would imply money is owed when none is —
               -- the Activity Log already records exactly this as `not_chargeable`.
               'payment_status',    case when not n.is_chargeable then 'not_chargeable'
                                         when n.is_paid           then 'paid'
                                         else                          'unpaid' end,
               'paid_amount_minor', n.paid_amount_minor)
             order by n.rn)
      from numbered n
      where n.rn <= v_limit), '[]'::jsonb),
    -- The continuation, TAGGED with this sort so it can never be replayed under
    -- the other direction.
    (select v_sort || '|' || n.created_at::text || '|' || n.id::text
       from numbered n where n.rn = v_limit)
    into v_summary, v_matching, v_fetched, v_rows, v_next;

  -- More rows exist AFTER this page iff the extra (v_limit + 1)-th row came back.
  v_more := v_fetched > v_limit;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_active_orders',
    'currency_code', v_currency,
    'queue', v_queue,
    'sort', v_sort,
    'limit', v_limit,
    'count', jsonb_array_length(v_rows),
    -- the FULL filtered count — never the loaded page. The client renders the
    -- honest "showing the newest N of M" from it.
    'matching', v_matching,
    'has_more',    v_more,
    'truncated',   v_more,
    'next_cursor', case when v_more then v_next else null end,
    'summary', v_summary,
    'orders', v_rows
  );
end;
$$;

comment on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text) is
  'ACTIVE-ORDERS-001 + ACTIVE-ORDERS-002 (READ-ONLY; D-007/D-008/D-011/D-018/D-020/D-025): the owner/manager Dashboard active-order operations board. Returns orders in the CANONICAL ACTIVE set (submitted/accepted/preparing/ready/served; terminal completed/cancelled/voided and local-only draft excluded) in the caller''s scope, with NO date window. QUEUES (a presentation grouping OVER the canonical states, not a new taxonomy): p_queue = in_progress (submitted/accepted/preparing/ready) | awaiting_close (served) | all_active (default; every existing caller is unchanged). SORT is AUTHORITATIVE and SERVER-SIDE: p_sort = newest (created_at desc, id desc; the Dashboard default) | oldest (asc, asc) — a client can never re-sort a capped page, because the un-fetched rows are not in the payload. KEYSET pagination: p_cursor is TAGGED with its sort ("<sort>|<created_at>|<id>") and is REJECTED (22023) if replayed under the other direction; id breaks ties so equal timestamps paginate stably; has_more/next_cursor page beyond the cap; p_limit CAPPED 1..200. A p_status filter must be an active status AND sit inside p_queue (else 22023). Same authorization as owner_order_history (actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free financial-read allowlist; kitchen_staff -> permission_denied). `summary` (total / unpaid / in_progress / awaiting_close / by_status) covers the SCOPE — never the page and never the filters — so the queue cards stay stable. `matching` is the FULL filtered count, never the loaded page. Money is integer minor units read from the stored snapshot. Payment status is a SEPARATE axis (D-025): a paid order stays active, and an unpaid served order belongs to awaiting_close. Returns created_at (branch-local) + created_at_utc (absolute) + timezone for ELAPSED time; there is NO promised/due field in the schema, so this NEVER reports "late" and ranks by nothing but time. Safe columns only. Scope-safe; no anon/service_role.';


-- ----------------------------------------------------------------------------
-- 6. app.owner_order_history — re-emit with customer_phone (matched CTE + row).
-- ----------------------------------------------------------------------------
create or replace function app.owner_order_history(
  p_organization_id uuid,
  p_restaurant_id   uuid  default null,
  p_branch_id       uuid  default null,
  p_range           text  default 'today',
  p_search          text  default null,
  p_status          text  default null,
  p_order_type      text  default null,
  p_payment         text  default null,   -- null | 'paid' | 'unpaid' | 'cash'
  p_limit           int   default 25,
  p_cursor          text  default null     -- keyset cursor "<created_at>|<id>"
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid    := app.current_app_user_id();
  v_rank       integer;
  v_currency   text;
  v_span       integer;
  v_end_offset integer;
  v_limit      integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_search     text    := nullif(btrim(coalesce(p_search, '')), '');
  v_cursor_ts  timestamptz;
  v_cursor_id  uuid;
  v_result     jsonb;
begin
  if v_actor is null then
    raise exception 'owner_order_history: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_order_history: organization_id is required' using errcode = '42501';
  end if;

  -- Range -> (span, end_offset). Unknown range is a bad request, not a denial.
  case p_range
    when 'today'     then v_span := 1;  v_end_offset := 0;
    when 'yesterday' then v_span := 1;  v_end_offset := 1;
    when 'last7'     then v_span := 7;  v_end_offset := 0;
    when 'last30'    then v_span := 30; v_end_offset := 0;
    else raise exception 'owner_order_history: unknown range %', p_range using errcode = '22023';
  end case;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_order_history: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE);
  -- kitchen_staff DENIED.
  if not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_order_history');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_order_history: organization not found (or deleted)' using errcode = '42501';
  end if;

  -- Keyset cursor: "<created_at::text>|<id>". A malformed cursor is a bad request.
  if p_cursor is not null and btrim(p_cursor) <> '' then
    begin
      v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
    exception when others then
      raise exception 'owner_order_history: invalid cursor' using errcode = '22023';
    end;
  end if;

  with branch_tz_base as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant, 'UTC'). UNLIKE the
    -- owner_* REPORTS (which exclude tz-less branches from an aggregate), a
    -- history LIST must never silently DROP an order, so a tz-less branch falls
    -- back to UTC for its day window rather than disappearing. ORG-SCOPED at the
    -- source so an org-wide call's windows are not computed over other tenants'
    -- branches (D-001 / RISK R-003).
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone, 'UTC') as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.organization_id = p_organization_id
      and b.deleted_at is null
  ),
  branch_tz as (
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           (lt.local_today - v_end_offset)                as cur_end,
           (lt.local_today - v_end_offset - (v_span - 1)) as cur_start
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
  ),
  matched as (
    select o.id,
           o.status,
           o.order_type,
           o.customer_name,
           o.customer_phone,
           o.receipt_number,
           o.subtotal_minor,
           o.discount_total_minor,
           o.tax_total_minor,
           o.grand_total_minor,
           o.created_at,
           t.zone,
           '#' || upper(right(replace(o.id::text, '-', ''), 6)) as order_code,
           tbl.label                                            as table_label,
           ep.display_name                                      as staff_name,
           coalesce(items.item_count, 0)                        as item_count,
           pay.method                                           as payment_method,
           pay.amount_minor                                     as paid_amount_minor,
           -- MONEY-SETTLEMENT-CONSISTENCY-001: SETTLEMENT, not a marker (see
           -- owner_active_orders). History and the live board must never disagree about
           -- whether the same order owes money.
           app.order_is_fully_settled(o.organization_id, o.id) as is_paid,
           (o.grand_total_minor > 0)                            as is_chargeable
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    left join public.tables tbl
      on tbl.organization_id = o.organization_id
     and tbl.id             = o.table_id
     and tbl.deleted_at is null
    left join public.employee_profiles ep
      on ep.organization_id = o.organization_id
     and ep.id             = o.opened_by_employee_profile_id
    left join lateral (
      select sum(oi.quantity)::bigint as item_count
      from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id        = o.id
        and oi.deleted_at is null
    ) items on true
    left join lateral (
      -- the single completed payment for the order (at most one; D-024/D-025).
      select p.method, p.amount_minor
      from public.payments p
      where p.organization_id = o.organization_id
        and p.order_id        = o.id
        and p.deleted_at is null
        and p.status = 'completed'
      order by p.created_at desc, p.id desc
      limit 1
    ) pay on true
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and (o.created_at at time zone t.zone)::date between t.cur_start and t.cur_end
      and (p_order_type is null or o.order_type = p_order_type)
      and (p_status     is null or o.status     = p_status)
      and (
        p_payment is null
        -- Settlement, not the marker — the SAME rule the badge renders, so filtering
        -- `unpaid` can never surface an order that owes nothing.
        or (p_payment = 'paid'   and app.order_is_fully_settled(o.organization_id, o.id))
        or (p_payment = 'unpaid' and not app.order_is_fully_settled(o.organization_id, o.id))
        or (p_payment = 'cash'   and pay.method = 'cash')
      )
      and (
        v_search is null
        or o.customer_name ilike '%' || v_search || '%'
        or coalesce(o.receipt_number, '') ilike '%' || v_search || '%'
        or coalesce(tbl.label, '') ilike '%' || v_search || '%'
        or upper(right(replace(o.id::text, '-', ''), 6)) like '%' || upper(replace(v_search, '#', '')) || '%'
      )
      and (
        p_cursor is null
        or v_cursor_ts is null
        or o.created_at < v_cursor_ts
        or (o.created_at = v_cursor_ts and o.id < v_cursor_id)
      )
  ),
  page as (
    select m.*, m.created_at::text || '|' || m.id::text as cursor
    from matched m
    order by m.created_at desc, m.id desc
    limit v_limit + 1
  ),
  numbered as (
    select p.*, row_number() over (order by p.created_at desc, p.id desc) as rn
    from page p
  )
  select jsonb_build_object(
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id',             n.id,
               'order_code',           n.order_code,
               'receipt_number',       n.receipt_number,
               'status',               n.status,
               'order_type',           n.order_type,
               'customer_name',        n.customer_name,
               'customer_phone',       n.customer_phone,
               'table_label',          n.table_label,
               'staff_name',           n.staff_name,
               'created_at',           to_char(n.created_at at time zone n.zone, 'YYYY-MM-DD HH24:MI'),
               'item_count',           n.item_count,
               'subtotal_minor',       n.subtotal_minor,
               'discount_total_minor', n.discount_total_minor,
               'tax_total_minor',      n.tax_total_minor,
               'grand_total_minor',    n.grand_total_minor,
               'payment_method',       n.payment_method,
               'payment_status',       case when not n.is_chargeable then 'not_chargeable'
                                             when n.is_paid           then 'paid'
                                             else                          'unpaid' end,
               'paid_amount_minor',    n.paid_amount_minor)
             order by n.rn)
      from numbered n
      where n.rn <= v_limit), '[]'::jsonb),
    'has_more',    (select count(*) from numbered) > v_limit,
    'next_cursor', case when (select count(*) from numbered) > v_limit
                        then (select cursor from numbered where rn = v_limit)
                        else null end,
    'count',       least((select count(*) from numbered), v_limit)
  ) into v_result;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_order_history',
    'currency_code', v_currency,
    'range', p_range,
    'limit', v_limit
  ) || v_result;
end;
$$;

comment on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text) is
  'ORDERS-HISTORY-001 (read-only; D-007/D-008/D-011/D-020): GUC-free paginated order-history LIST for the owner/manager Dashboard. Same authorization as owner_report_range (app.actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free can_read_financials-STYLE allowlist; kitchen_staff -> permission_denied). Branch-local date window (p_range in today/yesterday/last7/last30). Optional filters: p_status, p_order_type, p_payment (paid/unpaid/cash), p_search (order code #hex / customer / table / receipt). Keyset pagination ("<created_at>|<id>", newest first, p_limit clamped 1..100, has_more/next_cursor). Money integer minor, read from stored snapshots (never recomputed). Scope-safe (no GUC trusted); no anon/service_role.';


-- ----------------------------------------------------------------------------
-- 7. app.pos_order_detail — re-emit with customer_phone in the order header.
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
           'updated_at',           o.updated_at)
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

  -- (d) every ACTIVE customer-visible item, with modifiers and round
  --     membership (NULL service_round_id = the original submission).
  --     MENU-ORDER-001: carries + orders by the menu-configured print snapshots.
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
           'modifiers',                 coalesce(mods.list, '[]'::jsonb)
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
               'quantity',               m.quantity
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

  return jsonb_build_object(
    'ok', true, 'entity', 'order_detail', 'server_ts', now(),
    'order',   v_order,
    'items',   v_items,
    'rounds',  v_rounds,
    'payment', v_payment);
end;
$$;

comment on function app.pos_order_detail(uuid, uuid, uuid) is
  'PSC-001C + POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (read-only): the AUTHORITATIVE POS order detail. Byte-faithful re-emit of the 20260731090000 body with customer_phone added to the order header. SESSION org+branch scope; a nonexistent and a foreign-scope order collapse to the same order_not_found envelope (R-003). No anon/service_role.';


-- ----------------------------------------------------------------------------
-- ACL parity for the re-created read RPCs (CREATE OR REPLACE preserves grants;
-- re-issued explicitly to match each function's shipped grant, exactly).
-- ----------------------------------------------------------------------------
revoke all on function app.owner_order_detail(uuid, uuid, uuid, uuid)    from public;
grant execute on function app.owner_order_detail(uuid, uuid, uuid, uuid) to authenticated;

revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from public;
revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from anon;
grant execute on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text) to authenticated;

revoke all on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text)    from public;
grant execute on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text) to authenticated;

revoke all on function app.pos_order_detail(uuid, uuid, uuid) from public;
revoke all on function app.pos_order_detail(uuid, uuid, uuid) from anon;
grant execute on function app.pos_order_detail(uuid, uuid, uuid) to authenticated;
