-- ============================================================================
-- ORDER-EDIT-001A (3 of 3) — RE-EMITS of live functions for editing a sent
-- order (API_CONTRACT §4.45 / §4.46; ORDER_EDIT_DESIGN §8.5). Each body is
-- copied mechanically from its LIVE definition and changed ONLY where noted;
-- every other byte (including the historical mis-encoded comment bytes of the
-- sync_push and owner_active_orders bodies) is preserved.
--
--   1. app.sync_push (live 20261006140000)            — op 'order.edit' and
--      'order.edit_ack' in BOTH allowlists, in the six target-bound identity
--      lists (target_id must equal payload.order_id; the fingerprint binds it)
--      and two dispatch arms. Semantics otherwise unchanged.
--   2. app.void_order (live 20260725090000)           — kitchen_ack_required
--      (and the matching order.voided audit scalar) is ALSO true when a live
--      service round is still submitted..ready or an edit confirmation is
--      pending, so live kitchen work never vanishes without a red card. The
--      printer-only VOID dispatch predicate is unchanged.
--   3. app.order_rounds_all_served (live 20260722090000) — ignores ONLY rounds
--      an edit emptied (voided_by_edit_id).
--   4. app.audit_action_has_detail (live 20260726090000) — + order.edit%.
--   5. app.audit_safe_detail (live 20261006140000)    — + the edit scalars.
--   6. app.owner_order_history (live 20260818090000) and
--   7. app.owner_active_orders (live 20260905090000)  — item counts exclude
--      lines retired by an edit (removed_by_edit_id); counts of unedited and
--      voided orders are unchanged.
--   6b. app.owner_order_detail (live 20260802090000)  — the items list
--      excludes lines retired by an edit (same rule).
--   6c. app.owner_audit_events (live 20260711120000)  — order.edited is a
--      sensitive action (API §4.33 item 9).
--   6d. COMMENTs made stale by the 001A rules (sync_push, orders columns).
-- ============================================================================
-- ----------------------------------------------------------------------------
-- 1. app.sync_push -- re-emitted from its LIVE body
--    (20261006140000_pos_cash_drawer_manual_open_001) with ONLY: the two new
--    ops in BOTH allowlists (valid path AND revoked-device path, so a revoked
--    device's edit is still ledgered + audited as sync.operation_rejected), in
--    the six target-bound identity lists, and two dispatch arms. Everything
--    else is byte-identical.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.sync_push(p_pin_session_id uuid, p_device_id uuid, p_operations jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- row (the only case that bumps retry_count â€” the pre-fix contract).
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
  -- KITCHEN-DISPATCH-ENFORCE-001: the REQUESTED order.submit dispatch mode
  -- (defaulted, so an absent key is the deployed 'kds' contract) and the
  -- AUTHORITATIVE branch kitchen workflow mode read under a FOR SHARE lock.
  v_requested_dispatch  text;
  v_branch_kitchen_mode text;
begin
  -- (0) batch shape + a conservative size cap (no frozen limit in docs; 100 is the
  --     interim cap, surfaced here and in the tests â€” keeps a push transaction bounded).
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
      -- target id is parsed inside a PROTECTED boundary â€” a malformed uuid
      -- must reject only ITS operation, never abort the whole batch. The 12
      -- prior operations keep their exact existing parse semantics.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status', 'order.edit', 'order.edit_ack') then
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
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status', 'cash_drawer.no_sale_open', 'order.edit', 'order.edit_ack') then
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
      -- or malformed envelope â€” rejected with NO ledger row (the malformed-
      -- envelope convention), the batch continues. Only that op is affected.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status', 'order.edit', 'order.edit_ack') then
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
      -- operations â€” the target component is the PARSED uuid's text
      -- (guaranteed non-null and equal to the parsed payload identity by the
      -- check above), so a legitimately-applied op still replays its stored
      -- result after a revocation (identical identity -> identical
      -- fingerprint), while the 12 prior operations are unchanged.
      if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status', 'order.edit', 'order.edit_ack') then
        v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
      else
        -- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 4): customer_phone is DATA
        -- ONLY on an order.submit â€” carried in the payload for persistence but
        -- EXCLUDED from the operation identity, so re-sending the same op with only
        -- a different phone is an idempotent replay, not a conflict. Removing an
        -- absent key is a no-op, so a phone-less op keeps its EXACT prior
        -- fingerprint (backward compatible); every other field and every other
        -- operation type is unchanged.
        v_fingerprint := md5(v_op_type || '|' || (case when v_op_type = 'order.submit' then v_payload - 'customer_phone' else v_payload end)::text);
      end if;

      -- dedup/replay (PSC-001C correction, Finding 1 â€” ATOMIC CLAIM): the
      -- rejected/revoked_device recording is now claimed with ONE
      -- INSERT .. ON CONFLICT DO NOTHING on the transport identity. When the
      -- claim loses, the existing row is LOCKED (waiting out any concurrent
      -- claimant's COMMIT) and decided from its COMMITTED state: a TERMINAL
      -- row replays its stored result (a legitimately-APPLIED op before
      -- revocation is NOT re-rejected â€” and can no longer be OVERWRITTEN by
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
        -- under the held lock â€” the pre-fix on-conflict contract, verbatim.
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

  -- (b) per-operation loop (ordered) â€” VALID device path (unchanged from RF-056)
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
    -- identity-hardened operations â€” a malformed target uuid rejects only ITS
    -- operation (below), never the batch. The 12 prior operations keep their
    -- exact existing semantics.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status', 'order.edit', 'order.edit_ack') then
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
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status', 'cash_drawer.no_sale_open', 'order.edit', 'order.edit_ack') then
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
    -- order.round_status) and they MUST be the same uuid â€” a missing,
    -- malformed or CONTRADICTORY pair is a hostile/malformed envelope:
    -- rejected with NO ledger row (the malformed-envelope convention), so a
    -- replayed local_operation_id with a swapped target can never reach the
    -- stored terminal result, mutate anything, or learn anything about
    -- another order or round. Only that operation is affected.
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status', 'order.edit', 'order.edit_ack') then
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
    if v_op_type in ('order.void_ack', 'order.items_add', 'order.round_status', 'order.edit', 'order.edit_ack') then
      v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
    else
      -- POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 (Finding 4): order.submit identity
      -- EXCLUDES customer_phone (data-only) â€” same canonical rule as the
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
    --   * claim LOST -> the existing row is LOCKED (FOR UPDATE â€” waiting out a
    --     concurrent claimant's COMMIT) and decided from COMMITTED state: a
    --     fingerprint/op mismatch keeps the exact idempotency-conflict
    --     contract; a TERMINAL row replays its stored result (and can never be
    --     overwritten or reset to in_flight again); only a genuinely stale
    --     NON-terminal row (pending / crashed in_flight) is ADOPTED â€” the
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
    -- row is parked as pending exactly like the pre-fix contract â€” a fresh
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
          -- KITCHEN-DISPATCH-ENFORCE-001: resolve the REQUESTED dispatch mode
          -- (an absent key is the deployed 'kds' contract) and, ONLY for the
          -- privileged direct_print request, read the AUTHORITATIVE branch mode
          -- under a FOR SHARE row lock held to transaction end. The predicate is
          -- the same tenant-scoped one app.submit_order's dispatch gate uses and
          -- the scope comes from the SESSION (v_org/v_branch), never the payload.
          -- FOR SHARE conflicts with the FOR NO KEY UPDATE lock a
          -- kitchen_workflow_mode UPDATE takes, so a mode change cannot commit
          -- underneath an in-flight acceptance (and vice versa), while concurrent
          -- direct_print submits share the lock. The common absent/'kds' path
          -- reads nothing here and takes NO lock.
          v_requested_dispatch  := coalesce(v_payload ->> 'dispatch_mode', 'kds');
          v_branch_kitchen_mode := null;
          if v_requested_dispatch = 'direct_print' then
            select b.kitchen_workflow_mode
              into v_branch_kitchen_mode
              from public.branches b
              where b.id              = v_branch
                and b.organization_id = v_org
                and b.deleted_at is null
              for share;
          end if;
          -- Validation runs BEFORE app.submit_order, so every rejection below
          -- creates NO business rows at all (the shipped customer-phone guard
          -- precedent). Anything but an affirmative 'printer_only' â€” including a
          -- missing or tombstoned branch row â€” fails CLOSED.
          if v_customer_phone <> '' and not app.is_valid_customer_phone(v_customer_phone) then
            v_dispatch := jsonb_build_object(
              'ok', false, 'error', 'invalid_payload', 'detail', 'customer_phone');
          elsif v_requested_dispatch not in ('kds', 'direct_print') then
            v_dispatch := jsonb_build_object(
              'ok', false, 'error', 'invalid_payload', 'detail', 'dispatch_mode');
          elsif v_requested_dispatch = 'direct_print'
                and coalesce(v_branch_kitchen_mode, '') <> 'printer_only' then
            v_dispatch := jsonb_build_object(
              'ok', false, 'error', 'dispatch_mode_not_allowed',
              'detail', 'direct_print_requires_printer_only_branch');
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
            -- builder IN THIS SAME TRANSACTION â€” never by patching client JSON
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
            -- kitchen via the POS printer (no KDS device), IN THIS SAME transaction
            -- â€” a concurrent sync_pull can never observe an intermediate active
            -- state (sync_push commits once). app.submit_order already ran above, so
            -- the outcome here is CONDITIONAL, not an unconditional promotion:
            --   * CHARGEABLE printer_only order, still `submitted` -> the helper
            --     routes it OUT of the KDS active workflow: served +
            --     dispatch_mode=direct_print, dispatched=true; completion still
            --     waits for settlement.
            --   * ZERO-TOTAL printer_only order -> app.submit_order ALREADY
            --     completed it (a zero balance is settled on arrival), so the helper
            --     declines with dispatched=false / reason=not_eligible and the order
            --     stays completed / dispatch_mode='kds' / revision 2.
            -- Settlement is NEVER bypassed and physical print success NEVER completes
            -- an order; the POS local kitchen print is a separate best-effort client
            -- path and is not represented in this result. A 'kds' (default) order is
            -- a structural no-op here.
            if v_requested_dispatch = 'direct_print' then
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
          -- order.void branch â€” actor/org/branch come from the PIN session
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
        when 'cash_drawer.no_sale_open' then
          -- POS-CASH-DRAWER-MANUAL-OPEN-001: a MANUAL ("no-sale") drawer open
          -- recorded from the POS. Actor/org/branch/device come from the PIN
          -- session (NEVER the payload); the payload contributes ONLY the
          -- client's own occurrence time and, for a journaled offline open, the
          -- PIN session that made it (validated inside against THIS device +
          -- branch). A malformed occurrence time degrades to NULL rather than
          -- rejecting the record of a physical open. The permission is enforced
          -- inside; typed refusals (permission_denied / invalid_device_type /
          -- invalid_origin_session) RETURN through verbatim. Transport dedup
          -- (sync_operations) makes a replay return the stored result -- one
          -- open, one audit row. MONEY-FREE.
          v_dispatch := app.pos_record_drawer_no_sale(
            p_pin_session_id, p_device_id,
            case when pg_input_is_valid(v_payload ->> 'client_occurred_at', 'timestamptz')
                 then (v_payload ->> 'client_occurred_at')::timestamptz end,
            nullif(v_payload ->> 'origin_pin_session_id', '')::uuid);
        when 'order.void_ack' then
          -- PSC-001D: the kitchen's cancellation acknowledgement. Mirrors the
          -- order.status branch â€” actor/org/branch come from the PIN session
          -- (never the payload); the payload contributes ONLY {order_id}.
          -- app.kitchen_ack_void enforces the KDS-class device, the kitchen
          -- role set, the voided + ack-required state, and the idempotent
          -- already-acknowledged replay; its flat typed refusals
          -- (invalid_device_type / permission_denied / order_not_voided /
          -- acknowledgement_not_required) RETURN through verbatim. TARGET-ID
          -- CONSISTENCY is enforced at (b1+) BEFORE the fingerprint and the
          -- terminal replay â€” by the time this arm runs, target_id and
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
          -- (b1+) BEFORE the fingerprint and the terminal replay â€” the check
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
          -- enforced at (b1+) â€” the check below is pure defence-in-depth and
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
        when 'order.edit' then
          -- ORDER-EDIT-001A (D-043): edit a sent, open, unpaid order in place.
          -- An ONLINE-ONLY direct op (never the offline outbox). Actor/org/branch
          -- come from the PIN session; the payload contributes {order_id,
          -- reason_code?, reason_text?, bill_presented_at?, expected, changes}.
          -- app.edit_order decides EVERY refusal before its first write and
          -- RETURNs it verbatim (audited order.edit_denied); it RAISES only
          -- 42501 (structural / anti-oracle) and 40001 (operation id reused on
          -- another order). TARGET-ID CONSISTENCY is enforced at (b1+) - the
          -- check below is pure defence-in-depth and unreachable.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.edit target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.edit_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload,
            v_client_ts);
        when 'order.edit_ack' then
          -- ORDER-EDIT-001A (D-044): the kitchen's "Got it" for order edits.
          -- The payload contributes ONLY {order_id, up_to_edit_number}; a
          -- missing or malformed number reaches app.kitchen_ack_order_edit as
          -- NULL and is refused there (invalid_edit_number). Its flat typed
          -- refusals (invalid_device_type / permission_denied /
          -- invalid_edit_number / order_voided) RETURN through verbatim.
          -- TARGET-ID CONSISTENCY is enforced at (b1+) - the check below is pure
          -- defence-in-depth and unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.edit_ack target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.kitchen_ack_order_edit(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            case when jsonb_typeof(v_payload -> 'up_to_edit_number') = 'number'
                      and (v_payload ->> 'up_to_edit_number') ~ '^[0-9]{1,9}$'
                 then (v_payload ->> 'up_to_edit_number')::integer end);
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
      elsif v_caught_state = 'RFDM0' then
        -- KITCHEN-DISPATCH-ENFORCE-001: the app.apply_direct_print_dispatch
        -- defensive belt fired. Normalize the DEDICATED internal SQLSTATE to the
        -- SAME terminal typed rejection the primary ingest guard returns â€” the
        -- ledger, the audit and the client envelope all carry
        -- `dispatch_mode_not_allowed` (class permanent) and NEVER a raw SQLSTATE
        -- or any internal branch-mode detail. The raise already rolled this
        -- operation's subtransaction back, so no business rows survive. The
        -- stored result is what a replay returns, so the rejection is idempotent.
        update public.sync_operations
          set status = 'rejected', last_error_code = 'dispatch_mode_not_allowed', last_error_class = 'permanent',
              rejection_reason = 'dispatch_mode_not_allowed',
              result = jsonb_build_object('ok', false, 'error', 'dispatch_mode_not_allowed',
                         'detail', 'direct_print_requires_printer_only_branch'), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', 'dispatch_mode_not_allowed', null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'error', 'dispatch_mode_not_allowed'));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'dispatch_mode_not_allowed', 'detail', 'direct_print_requires_printer_only_branch',
          'status', 'rejected', 'idempotency_replay', false);
      else
        -- STALE-TABLE-ORDER-RECOVERY-001 (error contract): a dispatched RPC's
        -- PRECONDITION refusal - the message carries '(precondition_failed)', e.g.
        -- record_payment with no open shift / no active drawer on the paying device -
        -- is classified as the stable detail token 'precondition_failed' so the POS
        -- can say exactly that (open a shift) instead of a generic failure. Every
        -- other message still collapses to the generic 'rejected' (never raw text).
        -- validation / state / business-rule failure -> permanent rejected. RF-061: a
        -- revoked-MEMBERSHIP op fails membership-active in the dispatched RPC; classify its
        -- rejection reason as 'revoked_employee' so the offline-revoked-employee case is clear.
        update public.sync_operations
          set status = 'rejected', last_error_code = v_caught_state, last_error_class = 'permanent',
              rejection_reason = case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee'
                                 when v_caught_msg ilike '%(precondition_failed)%' then 'precondition_failed'
                                 else v_caught_msg end,
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', v_caught_state,
                         'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee'
                                 when v_caught_msg ilike '%(precondition_failed)%' then 'precondition_failed'
                                 else null end), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected',
                case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee'
                                 when v_caught_msg ilike '%(precondition_failed)%' then 'precondition_failed'
                                 else v_caught_msg end, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'rejected', 'sqlstate', v_caught_state,
          'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee'
                                 when v_caught_msg ilike '%(precondition_failed)%' then 'precondition_failed'
                                 else null end,
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
$function$;
-- ACL parity (CREATE OR REPLACE preserves grants; re-issued explicitly, verbatim).
revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
revoke all on function app.sync_push(uuid, uuid, jsonb) from anon;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. app.void_order -- re-emitted from its LIVE body
--    (20260725090000_kitchen_mode_001c1_dispatch_ledger lines 1709-2006) with
--    ONE surgical delta: kitchen_ack_required and the matching order.voided
--    audit scalar become TRUE when the order status is submitted..ready, OR a
--    live service round of the order is submitted..ready, OR an order edit of
--    the order requires a kitchen confirmation that is still pending. The
--    printer-only VOID dispatch predicate is UNCHANGED (an edit always leaves
--    an order_edit dispatch). Signature, lock text, refusals, ledger and
--    every other behaviour byte-for-byte unchanged.
-- ----------------------------------------------------------------------------
create or replace function app.void_order(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_reason             text,
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
  v_m_perms      jsonb;
  v_o_org        uuid;
  v_o_branch     uuid;
  v_o_status     text;
  v_o_rev        integer;
  v_authorized   boolean;
  v_new_rev      integer;
  v_voided_items integer;
  v_stored       jsonb;
  v_stored_order uuid;
  v_result       jsonb;
  v_kitchen_mode text;  -- KITCHEN-MODE-001C1: branch workflow mode (dispatch gate)
  v_ack_required boolean;  -- ORDER-EDIT-001A: the widened kitchen-acknowledgement predicate
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'void_order: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'void_order: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'void_order: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'void_order: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'void_order: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the order; it MUST be in the actor's org + branch (no cross-tenant).
  --     RF-062 (A4): FOR UPDATE locks the order row so void_order serializes with
  --     record_payment (which now also locks the order row) on the SAME order — a
  --     payment cannot complete between the (g2) guard and the void.
  select o.organization_id, o.branch_id, o.status, o.revision
    into v_o_org, v_o_branch, v_o_status, v_o_rev
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'void_order: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'void_order: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (A1): manager/restaurant_owner/org_owner, OR a cashier with an
  --     explicit memberships.permissions->>'void_order' = 'true' grant. RF053-B1:
  --     authorization runs BEFORE the idempotency replay so an unauthorized actor can
  --     never replay a prior SUCCESS result. A DENIAL is audited (order.void_denied)
  --     + RETURNED (no raise, so the audit persists) with NO state change and NO ledger
  --     write (the ledger holds only authorized successes; denials are always re-audited
  --     as probe attempts, never replayed).
  v_authorized := (v_role in ('manager', 'restaurant_owner', 'org_owner'))
                  or app.cashier_capability_allowed(v_role, v_m_perms, 'void_order');

  if not v_authorized then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) reason mandatory (AC#2)
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'void_order: a non-empty reason is required' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + reason, BEFORE the
  --     voidable-source-state check (the order becomes 'voided' after the first
  --     success). ORDER-BOUND: the stored op MUST be for the same order; the same
  --     (org, device, local_operation_id, action) reused on a DIFFERENT order is a
  --     conflict, not a replay (never leaks the original order's result).
  select oo.result, oo.order_id into v_stored, v_stored_order
    from public.order_operations oo
    where oo.organization_id = v_org and oo.device_id = p_device_id
      and oo.local_operation_id = p_local_operation_id and oo.action = 'void_order';
  if found then
    if v_stored_order <> p_order_id then
      raise exception 'void_order: idempotency key already used for a different order (%, not %)', v_stored_order, p_order_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) optimistic concurrency (optional)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    raise exception 'void_order: revision conflict (expected %, got %)', p_expected_revision, v_o_rev using errcode = '40001';
  end if;

  -- (g) state legality (AC#3, D-024): only pre-completion non-terminal source states.
  --     ELIGIBILITY IS UNCHANGED — the legal set is still exactly
  --     submitted/accepted/preparing/ready/served, `completed` remains TERMINAL, and there
  --     is NO completed -> void path. Only the SHAPE of the refusal changes.
  --
  --     MONEY-SETTLEMENT-CONSISTENCY-001 (corrective): RETURN the stable domain code
  --     instead of raising. app.sync_push REBUILDS the envelope from scratch for a RAISE
  --     (collapsing every domain code to the generic literal 'rejected'), but merges a
  --     RETURNED envelope through VERBATIM. Raising left the POS unable to tell
  --     "this order is already closed" apart from a dropped network, a malformed response
  --     or any other rejection — so it was reduced to GUESSING from the order's total, and
  --     could tell an operator an order was closed when the connection had merely failed.
  --
  --     `error` is the established coarse class for an illegal state change
  --     (`invalid_transition`, as the order state machine already uses) and `detail` is the
  --     established fine-grained safe token (as order_has_completed_payment already is).
  --     `order_status` is a STATE, never an identifier — safe to return.
  --
  --     AUDITED like the other two RETURN-based denials in this function
  --     (order.void_denied + denied_reason). A raise could not have audited at all: it
  --     would have rolled the audit row back. NO state change, NO revision bump, NO
  --     order_operations ledger row (denials are re-audited as probe attempts, never
  --     replayed).
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_not_voidable'));
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'detail', 'order_not_voidable', 'order_id', p_order_id,
                              'order_status', v_o_status,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (g2) RF-062 COMPLETED-PAYMENT GUARD (D-023/D-024; STATE_MACHINES §1; API_CONTRACT
  --      §4.6): an order with a LIVE `completed` payment cannot be voided in MVP — there
  --      is no refund/reversal flow. Checked AFTER authorization, reason, the idempotency
  --      replay, expected_revision, and state legality, BEFORE any mutation, so: a prior
  --      successful void still replays at (e) (a voided order can never acquire a
  --      completed payment afterward — record_payment rejects non-eligible orders); a
  --      genuinely terminal status is still refused at (g), which now RETURNS the typed
  --      domain refusal (invalid_transition + detail=order_not_voidable + order_status)
  --      rather than raising an untyped 42501 — so the two refusals stay DISTINGUISHABLE
  --      to the client; and only a
  --      legal-source order that nonetheless carries settled money reaches here. The
  --      order row is locked FOR UPDATE (b) and record_payment also locks it, so a
  --      concurrent payment cannot slip in. A4/A5/A3 decisions: block ONLY a live
  --      `completed` payment (deleted_at IS NULL; no method filter — any completed
  --      payment blocks); org-scoped to the session-derived v_org (tenant-safe); AUDIT
  --      `order.void_denied` (denied_reason=order_has_completed_payment) + RETURN a
  --      permission_denied envelope (NO raise — a raise would roll back the audit), with
  --      NO state change to order/order_items/payment and NO order_operations ledger row
  --      (denials are re-audited as probe attempts on retry, never replayed).
  if exists (
    select 1
    from public.payments p
    where p.organization_id = v_org
      and p.order_id = p_order_id
      and p.status = 'completed'
      and p.deleted_at is null
  ) then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_has_completed_payment'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'detail', 'order_has_completed_payment', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (h) mutate: order -> voided (+reason, +revision); cascade items -> voided.
  --     PSC-001D: the SAME statement stamps the void PROVENANCE — when it
  --     happened, which state it was in, and whether the kitchen must
  --     acknowledge (an ACTIVE kitchen source: submitted|accepted|preparing|
  --     ready; a served-source void is already off the board). The
  --     acknowledgement triple stays NULL until app.kitchen_ack_void.
  --     ORDER-EDIT-001A: the kitchen must ALSO acknowledge when, besides an
  --     active parent, any LIVE service round of the order is still
  --     submitted..ready (a parent an edit — or add-items after served — left
  --     at `served` while kitchen work is live) or an edit confirmation is
  --     still pending. Computed ONCE, before the round sweep below. (As with
  --     every printer-only void since PSC-001D, a paper-channel order may
  --     carry the flag with no KDS to clear it; only the KDS reads it.)
  v_ack_required := (v_o_status in ('submitted', 'accepted', 'preparing', 'ready'))
    or exists (select 1 from public.order_service_rounds r
                where r.organization_id = v_org and r.order_id = p_order_id
                  and r.deleted_at is null
                  and r.status in ('submitted', 'accepted', 'preparing', 'ready'))
    or exists (select 1 from public.order_edits e
                where e.organization_id = v_org and e.order_id = p_order_id
                  and e.kitchen_ack_required and e.kitchen_ack_at is null);
  v_new_rev := v_o_rev + 1;
  update public.orders
    set status = 'voided', void_reason = p_reason, revision = v_new_rev,
        voided_at = now(),
        voided_from_status = v_o_status,
        kitchen_ack_required = v_ack_required
    where id = p_order_id;

  update public.order_items
    set status = 'voided', void_reason = p_reason
    where order_id = p_order_id and organization_id = v_org
      and status not in ('voided', 'cancelled');
  get diagnostics v_voided_items = row_count;
  -- PSC-001C: the whole-order void ALSO sweeps every live ADDITIONAL service
  -- round to `voided` (round void_reason stamped; ready_at PRESERVED — the
  -- historical ready occurrence must survive for the feed; item snapshots and
  -- round membership untouched — the items were already cascaded above). After
  -- this no round transition is possible (parent_order_voided) and the parent
  -- can never complete (voided is terminal AND a voided round blocks
  -- app.order_rounds_all_served). There is NO independent round-void feature.
  update public.order_service_rounds
    set status = 'voided', void_reason = p_reason, revision = revision + 1
    where order_id = p_order_id and organization_id = v_org
      and status <> 'voided';

  -- (i) audit (order.voided) with old/new values (D-013). PSC-001D adds the two
  --     safe provenance scalars (a closed status enum + a boolean — never money,
  --     never an identifier; T-003 holds).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'order.voided', p_reason,
    jsonb_build_object('status', v_o_status, 'revision', v_o_rev),
    jsonb_build_object('status', 'voided', 'revision', v_new_rev,
                       'void_reason', p_reason, 'voided_item_count', v_voided_items,
                       'resolved_membership_id', v_membership,
                       'voided_from_status', v_o_status,
                       'kitchen_ack_required', v_ack_required));

  -- (j) record ledger + return
  v_result := jsonb_build_object('ok', true, 'order_id', p_order_id, 'status', 'voided', 'revision', v_new_rev);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'void_order', p_order_id, v_result);

  -- KITCHEN-MODE-001C1 (DORMANT): when the branch is printer_only and the
  -- kitchen MAY HAVE SEEN this order — the SAME conservative PSC-001D
  -- predicate that drives kitchen_ack_required, OR any prior kitchen dispatch
  -- exists for the order — one durable VOID dispatch is created in this SAME
  -- transaction. CORRECTION-001: the void supersedes EVERY unresolved prior
  -- dispatch of the order (claimed / failed / possibly_printed included) so
  -- no original can ever print after it; completed priors stay (the kitchen
  -- may hold their paper — the VOID slip corrects them). kds branches create
  -- nothing; a rollback leaves nothing; a missing branch row here is a state
  -- inconsistency — never a silent kds fallback.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if v_kitchen_mode is null then
    raise exception 'void_order: branch row unavailable during the kitchen dispatch gate (state inconsistency)';
  end if;
  if v_kitchen_mode = 'printer_only'
     and ((v_o_status in ('submitted', 'accepted', 'preparing', 'ready'))
          or exists (select 1 from public.kitchen_print_dispatches d
                      where d.organization_id = v_org and d.order_id = p_order_id)) then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, null, 'void',
      app.kitchen_dispatch_payload_void(v_org, p_order_id, p_reason),
      v_emp, v_membership, p_device_id);
  end if;

  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;
comment on function app.void_order(uuid, uuid, uuid, text, text, integer) is
  'RF-062 .. MONEY-VOID-001 .. PSC-001D/PSC-001C + KITCHEN-MODE-001C1 + ORDER-EDIT-001A. Signature, paid-order restrictions, provenance stamps (voided_from_status / kitchen_ack_required), the PSC-001C whole-order round sweep, audit and every kds-mode behavior UNCHANGED (faithful re-creation of the 20260725090000 body) EXCEPT the ORDER-EDIT-001A acknowledgement predicate: kitchen_ack_required (and the order.voided audit scalar) is TRUE when the source status is submitted..ready, OR any live service round of the order is submitted..ready, OR an order edit''s required kitchen confirmation is still pending — so a parent left at served while kitchen work is live never vanishes from the KDS without a red card. KITCHEN-MODE-001C1 (DORMANT): a printer_only branch whose kitchen MAY HAVE SEEN the order (the unchanged status predicate, or any prior dispatch) additionally writes ONE idempotent money-free VOID dispatch in the SAME transaction, superseding EVERY unresolved prior dispatch of the order (CORRECTION-001 — no original can print after its void).';

revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from public;
revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from anon;
grant execute on function app.void_order(uuid, uuid, uuid, text, text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.order_rounds_all_served -- re-emitted from its LIVE body
--    (20260722090000_psc_001c_service_rounds lines 178-196): ignores ONLY the
--    rounds an order edit emptied (voided_by_edit_id is not null).
-- ----------------------------------------------------------------------------
create or replace function app.order_rounds_all_served(
  p_organization_id uuid,
  p_order_id        uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select not exists (
    select 1
    from public.order_service_rounds r
    where r.organization_id = p_organization_id
      and r.order_id        = p_order_id
      and r.deleted_at is null
      and r.status <> 'served'
      -- ORDER-EDIT-001A: a round an EDIT emptied (voided while
      -- submitted..ready) owes the kitchen nothing; ONLY such rounds are
      -- ignored. A round voided by a whole-order void still blocks (its
      -- parent is terminal anyway).
      and r.voided_by_edit_id is null
  );
$$;
comment on function app.order_rounds_all_served(uuid, uuid) is
  'PSC-001C + ORDER-EDIT-001A: the ONE canonical completion predicate for additional kitchen work — TRUE iff NO live service round of the order has a status other than `served`, IGNORING ONLY rounds an order edit emptied (voided_by_edit_id is not null; D-043). Zero rounds (every historical order) passes trivially. Any other voided round is NOT completion-eligible (locked decision: `served` only — never "served OR voided"); it blocks this predicate and only ever exists on a voided parent, which is terminal anyway. Consulted by app.try_auto_complete_order and by the manual served->completed gate in app.apply_order_status_transition. INTERNAL: granted to no client role.';

revoke all on function app.order_rounds_all_served(uuid, uuid) from public;
revoke all on function app.order_rounds_all_served(uuid, uuid) from anon;
revoke all on function app.order_rounds_all_served(uuid, uuid) from authenticated;

-- ----------------------------------------------------------------------------
-- 4. app.audit_action_has_detail -- re-emitted from its LIVE body
--    (20260726090000_kitchen_mode_001c3a_trusted_revision_observability lines
--    282-331) + the order.edit% family. settings.branch.order_edit_updated is
--    already covered by settings.% and kitchen.dispatch_created by kitchen.%.
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
      -- ORDER-EDIT-001A: sent-order edits and their kitchen confirmations
      -- (order.edited / order.edit_denied / order.edit_acknowledged /
      -- order.edit_ack_denied) carry safe scalars (edit number, counts,
      -- kitchen channel, reason code, denied reason, totals of order.edited).
      or p_action like 'order.edit%'
      -- KITCHEN-MODE-001B: printer configuration actions carry a safe scalar
      -- projection (display_name / role / paper_width / is_enabled /
      -- connection_type). connection_config stays a nested object, so the
      -- scalar-only allowlist can never surface host/port/addresses.
      or p_action like 'printer.%'
      -- KITCHEN-MODE-001C1: kitchen dispatch events carry safe scalars only
      -- (order_code / dispatch_type / membership) — never the payload.
      -- KITCHEN-MODE-001C3A: the same prefix covers the upcoming
      -- kitchen.dispatch_hold_resolved (001C3B) — no new pattern needed.
      or p_action like 'kitchen.%'
      or p_action =    'pin_session.failed';
$$;
comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001 .. KITCHEN-MODE-001C1 + 001C3A + ORDER-EDIT-001A: faithful re-creation + the order.edit% family (order.edited / order.edit_denied / order.edit_acknowledged / order.edit_ack_denied). settings.branch.order_edit_updated passes via settings.% and the order_edit kitchen.dispatch_created via kitchen.% (no new pattern). Gates app.audit_safe_detail.';

revoke all on function app.audit_action_has_detail(text) from public;
revoke all on function app.audit_action_has_detail(text) from anon;

-- ----------------------------------------------------------------------------
-- 5. app.audit_safe_detail -- re-emitted from its LIVE body
--    (20261006140000_pos_cash_drawer_manual_open_001 lines 683-808) + the edit
--    scalars on the global SAFE SCALAR allowlist. Ids, revision,
--    local_operation_id and the changes[] array stay unprojected.
-- ----------------------------------------------------------------------------
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
    'dispatch_mode',   -- KITCHEN-PRINT-DUAL-001C: closed dispatch enum (kds|direct_print); money-free state (T-003)
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
    'display_name','paper_width','is_enabled','connection_type',
    -- KITCHEN-MODE-001C1: kitchen dispatch safe scalars (closed enum + the
    -- existing safe order_code class). The money_free_payload itself is
    -- NEVER projected into audit detail.
    'dispatch_type',
    -- KITCHEN-MODE-001C3A: the kitchen-mode family scalars. kitchen_workflow_mode
    -- is the closed kds|printer_only enum; kitchen_workflow_mode_revision is a
    -- small positive integer (never money, never an identifier — T-003 holds);
    -- resolution / reason_code are CLOSED safe state tokens written only by the
    -- future 001C3B owner setter + hold resolution (human-actor paths). NOTE:
    -- settings.branch.updated projects full branch-row snapshots, so the mode
    -- and revision now also surface there — both are safe display state, the
    -- timezone/name class.
    'kitchen_workflow_mode','kitchen_workflow_mode_revision','resolution','reason_code',
    -- POS-CASH-DRAWER-MANUAL-OPEN-001: a manual drawer open that reached the
    -- server LATE (made offline, journaled on the till). A boolean -- never
    -- money, never an identifier (T-003 holds).
    'recorded_offline',
    -- ORDER-EDIT-001A: sent-order edits. edit_number / up_to_edit_number are
    -- small positive integers (a position in the order's edit history) and
    -- removed_item_count / modified_item_count / acknowledged_count are line
    -- counts; kitchen_channel is the closed kds|paper enum; the two branch
    -- switches are booleans. Never money, never identifiers (T-003 holds).
    -- NOTE: settings.branch.updated projects full branch-row snapshots, so
    -- the two switches now also surface there — safe display state.
    'edit_number','up_to_edit_number','removed_item_count','modified_item_count',
    'acknowledged_count','kitchen_channel',
    'order_edit_enabled','order_edit_finished_food_manager_only'
  ] loop
    -- PSC-001C correction (Finding 6): the four service-round actions are
    -- MONEY-FREE by approved contract — any *_minor key (hostile, manual, or
    -- accidental) is dropped for EXACTLY these actions, action-specifically:
    -- the approved money-carrying actions (payments / discounts / shifts /
    -- order.submitted / completion) keep their allowlisted money keys.
    if (p_action like 'order.items_add%' or p_action like 'order.round_status%'
        -- KITCHEN-MODE-001B: printer configuration is MONEY-FREE by contract —
        -- the same hostile-key hardening applies to the whole printer family.
        or p_action like 'printer.%'
        -- KITCHEN-MODE-001C1: kitchen dispatch events are MONEY-FREE too.
        or p_action like 'kitchen.%')
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
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp','manage_menu_availability','manage_table_operations','open_cash_drawer']) as k
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
  'ALLOWLIST projection of one audit payload to canonical safe fields (see 20260724090000 + 20260725090000) + KITCHEN-MODE-001C3A kitchen_workflow_mode / kitchen_workflow_mode_revision / resolution / reason_code + POS-CASH-DRAWER-MANUAL-OPEN-001 recorded_offline + ORDER-EDIT-001A edit_number / up_to_edit_number / removed_item_count / modified_item_count / acknowledged_count / kitchen_channel / order_edit_enabled / order_edit_finished_food_manager_only (closed safe scalars; never money, never identifiers). kitchen.% keeps the MONEY-FREE hostile-key hardening. Faithful re-creation otherwise; every un-listed key/structure dropped; malformed -> ''{}''; never throws.';

revoke all on function app.audit_safe_detail(text, jsonb) from public;
revoke all on function app.audit_safe_detail(text, jsonb) from anon;

-- ----------------------------------------------------------------------------
-- 6. app.owner_order_history -- re-emitted from its LIVE body
--    (20260818090000_ops043_p2_currency_row_and_breakdown lines 47-348): the
--    item_count lateral excludes lines retired by an order edit. Filtering on
--    the provenance column (never on status) keeps every unedited and every
--    voided order's count byte-identical.
-- ----------------------------------------------------------------------------
create or replace function app.owner_order_history(
  p_organization_id uuid,
  p_restaurant_id   uuid  default null,
  p_branch_id       uuid  default null,
  p_range           text  default 'today',
  p_search          text  default null,
  p_status          text  default null,
  p_order_type      text  default null,
  p_payment         text  default null,   -- null | paid | unpaid | cash | card | bit | external
  p_limit           int   default 25,
  p_cursor          text  default null,    -- keyset cursor "<created_at>|<id>"
  p_start           date  default null,
  p_end             date  default null
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
  v_custom     boolean := false;
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

  -- Window selection — the shared block (see the header).
  if p_start is not null or p_end is not null then
    if p_start is null or p_end is null then
      raise exception 'owner_order_history: p_start and p_end must be supplied together'
        using errcode = '22023';
    end if;
    if p_end < p_start then
      raise exception 'owner_order_history: p_end precedes p_start'
        using errcode = '22023';
    end if;
    if (p_end - p_start) > 91 then
      raise exception 'owner_order_history: window exceeds 92 days'
        using errcode = '22023';
    end if;
    v_custom := true;
  else
    -- Range -> (span, end_offset). Unknown range is a bad request, not a denial.
    case p_range
      when 'today'     then v_span := 1;  v_end_offset := 0;
      when 'yesterday' then v_span := 1;  v_end_offset := 1;
      when 'last7'     then v_span := 7;  v_end_offset := 0;
      when 'last30'    then v_span := 30; v_end_offset := 0;
      when 'last60'    then v_span := 60; v_end_offset := 0;
      when 'last90'    then v_span := 90; v_end_offset := 0;
      else raise exception 'owner_order_history: unknown range %', p_range using errcode = '22023';
    end case;
  end if;

  -- SERVER-B: p_payment was previously UNVALIDATED — an unknown token fell
  -- through every branch of the filter and returned an empty list, which is
  -- indistinguishable from "this window genuinely has no such orders". A
  -- filter the caller misspelled must fail loudly, using the same 22023 idiom
  -- this function already applies to p_range and p_cursor.
  if p_payment is not null
     and p_payment not in ('paid', 'unpaid', 'cash', 'card', 'bit', 'external') then
    raise exception 'owner_order_history: unknown payment filter %', p_payment using errcode = '22023';
  end if;

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

  -- OPS-043 Phase 2: the EFFECTIVE currency, not the organization default.
  -- Phase 1 made restaurants.currency_override writable, and the menu/POS
  -- path already prices in coalesce(currency_override, default_currency),
  -- so labelling this payload with the org default contradicted both the
  -- Settings screen and the currency the orders were actually taken in.
  -- An ORG-WIDE call (no restaurant in scope) keeps the org default: there
  -- is no single restaurant whose override could apply, and the per-row
  -- currency_code below carries the truth for a mixed scope.
  select coalesce(r.currency_override, o.default_currency) into v_currency
    from public.organizations o
    left join public.restaurants r
      on r.id              = p_restaurant_id
     and r.organization_id = o.id
     and r.deleted_at is null
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
    -- Presets are branch-local and relative; a custom pair is the same fixed
    -- calendar dates for every branch.
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           case when v_custom then p_end
                else (lt.local_today - v_end_offset) end                as cur_end,
           case when v_custom then p_start
                else (lt.local_today - v_end_offset - (v_span - 1)) end as cur_start
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
           -- OPS-043 Phase 2: the ORDER's OWN currency travels with the row.
           -- Without it the client had only the envelope code and stamped it
           -- onto every row, relabelling a stored ILS order as USD the moment
           -- the restaurant switched. Historical money is never relabelled.
           o.currency_code,
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
        -- ORDER-EDIT-001A: a line RETIRED by an order edit is replaced by its
        -- remainder / replacement rows; counting both would inflate the count.
        and oi.removed_by_edit_id is null
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
        -- SERVER-B: the method filters compare against `pay`, which is the
        -- single COMPLETED payment for the order. A pending or failed row is
        -- therefore never a method match — this is recorded-tender truth,
        -- not processor settlement.
        or (p_payment in ('cash', 'card', 'bit', 'external') and pay.method = p_payment)
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
               'currency_code',        n.currency_code,
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
    'range', case when v_custom then 'custom' else p_range end,
    'limit', v_limit
  ) || v_result;
end;
$$;
revoke all on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) from public;
revoke all on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) from anon;
grant execute on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text, date, date) to authenticated;

-- ----------------------------------------------------------------------------
-- 6b. app.owner_order_detail -- re-emitted from its LIVE body
--     (20260802090000_pos_customer_phone_dinein_close_001 lines 877-1033): the
--     items list excludes lines retired by an order edit (provenance column,
--     never status — unedited and voided orders are unchanged).
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
    and oi.deleted_at is null
    -- ORDER-EDIT-001A: a line RETIRED by an order edit is replaced by its
    -- remainder / replacement rows; listing both would double the lines and
    -- make the line totals disagree with the order subtotal.
    and oi.removed_by_edit_id is null;

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
do $do$
begin
  execute format('comment on function app.owner_order_detail(uuid, uuid, uuid, uuid) is %L',
    obj_description('app.owner_order_detail(uuid, uuid, uuid, uuid)'::regprocedure, 'pg_proc')
    || ' ORDER-EDIT-001A: the items list excludes lines retired by an order edit (removed_by_edit_id), so the listed lines sum to the order subtotal; unedited and voided orders are unchanged.');
end;
$do$;

revoke all on function app.owner_order_detail(uuid, uuid, uuid, uuid) from public;
revoke all on function app.owner_order_detail(uuid, uuid, uuid, uuid) from anon;
grant execute on function app.owner_order_detail(uuid, uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 6c. app.owner_audit_events -- re-emitted from its LIVE body
--     (20260711120000_audit_coverage_002_settings_classification lines
--     166-385): the API §4.33 item 9 sensitivity decision — order.edited is
--     SENSITIVE (the two denials already are, through %denied). Nothing else
--     changes.
-- ----------------------------------------------------------------------------
create or replace function app.owner_audit_events(
  p_organization_id           uuid,
  p_restaurant_id             uuid    default null,
  p_branch_id                 uuid    default null,
  p_range                     text    default 'today',
  p_category                  text    default null,
  p_action                    text    default null,
  p_sensitive_only            boolean default false,
  p_actor_app_user_id         uuid    default null,
  p_actor_employee_profile_id uuid    default null,
  p_limit                     int     default 25,
  p_cursor                    text    default null
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
  v_zone       text;
  v_span       integer;
  v_end_offset integer;
  v_limit      integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_cursor_ts  timestamptz;
  v_cursor_id  uuid;
  v_result     jsonb;
begin
  if v_actor is null then
    raise exception 'owner_audit_events: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_audit_events: organization_id is required' using errcode = '42501';
  end if;

  case p_range
    when 'today'     then v_span := 1;  v_end_offset := 0;
    when 'yesterday' then v_span := 1;  v_end_offset := 1;
    when 'last7'     then v_span := 7;  v_end_offset := 0;
    when 'last30'    then v_span := 30; v_end_offset := 0;
    else raise exception 'owner_audit_events: unknown range %', p_range using errcode = '22023';
  end case;

  -- 'settings' is now a first-class filter category (AUDIT-COVERAGE-002).
  if p_category is not null and p_category not in (
    'orders','voids','discounts','payments','shifts','staff',
    'access','devices','settings','menu','tables','organization','sync'
  ) then
    raise exception 'owner_audit_events: unknown category %', p_category using errcode = '22023';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_audit_events: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('manager', 'restaurant_owner', 'org_owner')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_audit_events');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_audit_events: organization not found (or deleted)' using errcode = '42501';
  end if;

  v_zone := coalesce(
    (select b.timezone from public.branches b
       where b.organization_id = p_organization_id and b.id = p_branch_id and b.deleted_at is null),
    (select r.timezone from public.restaurants r
       where r.organization_id = p_organization_id and r.id = p_restaurant_id and r.deleted_at is null),
    (select min(r2.timezone) from public.restaurants r2
       where r2.organization_id = p_organization_id and r2.deleted_at is null and r2.timezone is not null),
    'UTC'
  );

  if p_cursor is not null and btrim(p_cursor) <> '' then
    begin
      v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
    exception when others then
      raise exception 'owner_audit_events: invalid cursor' using errcode = '22023';
    end;
  end if;

  with matched as (
    select ae.id,
           ae.action,
           ae.occurred_at,
           ae.reason,
           ae.restaurant_id,
           ae.branch_id,
           ae.actor_app_user_id,
           ae.actor_employee_profile_id,
           ae.device_id,
           cat.category,
           ez.zone as event_zone,
           coalesce(ep_actor.display_name, ep_appuser.display_name) as actor_name,
           r.name  as restaurant_name,
           b.name  as branch_name,
           dev.label as device_label,
           app.audit_safe_detail(ae.action, ae.old_values) as old_values_safe,
           app.audit_safe_detail(ae.action, ae.new_values) as new_values_safe
    from public.audit_events ae
    -- Single source of truth for classification (AUDIT-COVERAGE-002).
    cross join lateral (select app.audit_category(ae.action) as category) cat
    left join public.employee_profiles ep_actor
      on ep_actor.organization_id = ae.organization_id
     and ep_actor.id             = ae.actor_employee_profile_id
    left join lateral (
      select ep.display_name
      from public.employee_profiles ep
      where ep.organization_id = ae.organization_id
        and ae.actor_employee_profile_id is null
        and ae.actor_app_user_id is not null
        and ep.app_user_id = ae.actor_app_user_id
        and ep.deleted_at is null
      order by ep.created_at, ep.id
      limit 1
    ) ep_appuser on true
    left join public.restaurants r
      on r.organization_id = ae.organization_id and r.id = ae.restaurant_id and r.deleted_at is null
    left join public.branches b
      on b.organization_id = ae.organization_id and b.id = ae.branch_id and b.deleted_at is null
    left join public.devices dev
      on dev.organization_id = ae.organization_id and dev.id = ae.device_id and dev.deleted_at is null
    cross join lateral (
      select coalesce(b.timezone, r.timezone, v_zone) as zone
    ) ez
    where ae.organization_id = p_organization_id
      and (p_restaurant_id is null or ae.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or ae.branch_id     = p_branch_id)
      and (ae.occurred_at at time zone ez.zone)::date
          between ((now() at time zone ez.zone)::date - v_end_offset - (v_span - 1))
              and ((now() at time zone ez.zone)::date - v_end_offset)
      and (p_category is null or cat.category = p_category)
      and (p_action   is null or ae.action    = p_action)
      and (p_actor_app_user_id is null or ae.actor_app_user_id = p_actor_app_user_id)
      and (p_actor_employee_profile_id is null or ae.actor_employee_profile_id = p_actor_employee_profile_id)
      and (
        not p_sensitive_only
        or ae.action like '%denied'
        or ae.action like 'order.void%'
        or ae.action like 'order.discount%'
        -- ORDER-EDIT-001A: an applied sent-order edit can remove or void
        -- kitchen food on an unpaid order (TH-7) — sensitive like a void.
        or ae.action =    'order.edited'
        or ae.action like 'staff.capabilities%'
        or ae.action =    'staff.pin_set'
        or ae.action like 'membership.%'
        or ae.action like 'employee.revok%'
        or ae.action like 'device.revok%'
        or ae.action like 'shift.%'
        or ae.action like 'cash_drawer.%'
        or ae.action like 'payment.%'
      )
      and (
        p_cursor is null
        or v_cursor_ts is null
        or ae.occurred_at < v_cursor_ts
        or (ae.occurred_at = v_cursor_ts and ae.id < v_cursor_id)
      )
  ),
  page as (
    select m.*, m.occurred_at::text || '|' || m.id::text as cursor
    from matched m
    order by m.occurred_at desc, m.id desc
    limit v_limit + 1
  ),
  numbered as (
    select p.*, row_number() over (order by p.occurred_at desc, p.id desc) as rn
    from page p
  )
  select jsonb_build_object(
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
               'event_id',        n.id,
               'action',          n.action,
               'category',        n.category,
               'occurred_at',     to_char(n.occurred_at at time zone n.event_zone, 'YYYY-MM-DD HH24:MI'),
               'timezone',        n.event_zone,
               'actor_name',      n.actor_name,
               'restaurant_id',   n.restaurant_id,
               'restaurant_name', n.restaurant_name,
               'branch_id',       n.branch_id,
               'branch_name',     n.branch_name,
               'device_label',    n.device_label,
               'reason',          n.reason,
               'old_values',      n.old_values_safe,
               'new_values',      n.new_values_safe)
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
    'entity', 'owner_audit_events',
    'currency_code', v_currency,
    'range', p_range,
    'limit', v_limit
  ) || v_result;
end;
$$;
do $do$
begin
  execute format('comment on function app.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) is %L',
    obj_description('app.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text)'::regprocedure, 'pg_proc')
    || ' ORDER-EDIT-001A: order.edited is in the sensitive-only set (order.edit_denied / order.edit_ack_denied already match %denied).');
end;
$do$;

revoke all on function app.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) from public;
revoke all on function app.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) from anon;
grant execute on function app.owner_audit_events(uuid, uuid, uuid, text, text, text, boolean, uuid, uuid, int, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 6d. Comments that the ORDER-EDIT-001A rules make stale (the byte-preserved
--     bodies above keep their historical in-body comments).
-- ----------------------------------------------------------------------------
do $do$
begin
  execute format('comment on function app.sync_push(uuid, uuid, jsonb) is %L',
    obj_description('app.sync_push(uuid, uuid, jsonb)'::regprocedure, 'pg_proc')
    || ' POS-CASH-DRAWER-MANUAL-OPEN-001 + ORDER-EDIT-001A: 18 canonical operations — + cash_drawer.no_sale_open, order.edit (app.edit_order) and order.edit_ack (app.kitchen_ack_order_edit); order.edit and order.edit_ack join the identity-hardened set (target_id must equal payload.order_id; the fingerprint binds it), which now has five operations.');
end;
$do$;

comment on column public.orders.kitchen_ack_required is
  'PSC-001D + ORDER-EDIT-001A: TRUE when the kitchen must explicitly acknowledge the cancellation: the void happened while the order was in an ACTIVE kitchen state (submitted|accepted|preparing|ready), OR a live service round was still submitted..ready, OR an order edit''s kitchen confirmation was still pending. FALSE otherwise and for every historical row. Only the KDS reads it (a printer-only order may carry it with no screen to clear it).';
comment on column public.orders.voided_from_status is
  'PSC-001D: the order status at the moment of the void (submitted|accepted|preparing|ready|served), write-once. Drives the KDS red-card column placement and (with the ORDER-EDIT-001A live-round / pending-edit rule) kitchen_ack_required.';

-- ----------------------------------------------------------------------------
-- 7. app.owner_active_orders -- re-emitted from its LIVE body
--    (20260905090000_stale_table_order_recovery_001 lines 228-579): the
--    item_count lateral excludes lines retired by an order edit (provenance
--    column, never status — unedited and voided orders are unchanged).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_active_orders(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_status text DEFAULT NULL::text, p_order_type text DEFAULT NULL::text, p_payment text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 100, p_queue text DEFAULT 'all_active'::text, p_sort text DEFAULT 'newest'::text, p_cursor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  -- The QUEUES. These are a PRESENTATION grouping OVER the canonical states â€”
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

  -- ---- ENUM-VALIDATED controls. An unknown token is a BAD REQUEST (22023) â€”
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
  -- queue â€” otherwise the two controls would silently contradict each other.
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

  -- OPS-043 Phase 2: the EFFECTIVE currency, not the organization default.
  -- Phase 1 made restaurants.currency_override writable, and the menu/POS
  -- path already prices in coalesce(currency_override, default_currency),
  -- so labelling this payload with the org default contradicted both the
  -- Settings screen and the currency the orders were actually taken in.
  -- An ORG-WIDE call (no restaurant in scope) keeps the org default: there
  -- is no single restaurant whose override could apply, and the per-row
  -- currency_code below carries the truth for a mixed scope.
  select coalesce(r.currency_override, o.default_currency) into v_currency
    from public.organizations o
    left join public.restaurants r
      on r.id              = p_restaurant_id
     and r.organization_id = o.id
     and r.deleted_at is null
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_active_orders: organization not found (or deleted)' using errcode = '42501';
  end if;

  with scoped as (
    -- EVERY active order in scope (all five canonical states), regardless of the
    -- selected queue â€” this is what the SUMMARY counts, so the cards stay stable
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
           -- OPS-043 Phase 2: the ORDER's OWN currency travels with the row.
           -- Without it the client had only the envelope code and stamped it
           -- onto every row, relabelling a stored ILS order as USD the moment
           -- the restaurant switched. Historical money is never relabelled.
           o.currency_code,
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
           (o.grand_total_minor > 0)               as is_chargeable,
           -- STALE-TABLE-ORDER-RECOVERY-001 (display-only operational facts;
           -- the read never mutates): originating shift state + live kitchen work
           case when sh.status in ('closed', 'reconciled') then 'closed'
                when sh.status is null then null
                else 'open' end                  as shift_status,
           ((coalesce(b.kitchen_workflow_mode, 'kds') = 'kds'
               and o.status in ('submitted', 'accepted', 'preparing', 'ready'))
            or exists (select 1 from public.kitchen_print_dispatches k
                        where k.organization_id = o.organization_id and k.order_id = o.id
                          and k.completed_at is null and k.superseded_by_dispatch_id is null)
            or exists (select 1 from public.order_service_rounds r
                        where r.organization_id = o.organization_id and r.order_id = o.id
                          and r.deleted_at is null and r.status not in ('served', 'voided')))
                                                   as kitchen_work_open
    from public.orders o
    left join public.shifts sh
      on sh.organization_id = o.organization_id
     and sh.id              = o.shift_id
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
        -- ORDER-EDIT-001A: a line RETIRED by an order edit is replaced by its
        -- remainder / replacement rows; counting both would inflate the count.
        and oi.removed_by_edit_id is null
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
      -- The QUEUE counters the cards render â€” scope-wide, never the page.
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
               'currency_code',     n.currency_code,
               'payment_method',    n.payment_method,
               -- THREE honest states. Saying "paid" for an order that was never charged
               -- would be a lie, and "unpaid" would imply money is owed when none is â€”
               -- the Activity Log already records exactly this as `not_chargeable`.
               'payment_status',    case when not n.is_chargeable then 'not_chargeable'
                                         when n.is_paid           then 'paid'
                                         else                          'unpaid' end,
               'paid_amount_minor', n.paid_amount_minor,
               -- STALE-TABLE-ORDER-RECOVERY-001: additive operational flags
               'shift_status',      n.shift_status,
               'kitchen_work_open', n.kitchen_work_open)
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
    -- the FULL filtered count â€” never the loaded page. The client renders the
    -- honest "showing the newest N of M" from it.
    'matching', v_matching,
    'has_more',    v_more,
    'truncated',   v_more,
    'next_cursor', case when v_more then v_next else null end,
    'summary', v_summary,
    'orders', v_rows
  );
end;
$function$;
-- ACLs re-stated VERBATIM from 20260905090000 (REPORT-123: the app.* body sits
-- behind a SECURITY INVOKER public wrapper, so authenticated keeps EXECUTE).
revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from public;
revoke all on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text)    from anon;
grant execute on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- The new functions never broaden either global public surface (D-037). These
-- assertions match STOREFRONT-READ-001, BIZBOT-DEVICE-SESSION-FIX-001,
-- POS-CASH-DRAWER-MANUAL-OPEN-001 and pending #288 in either apply order.
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
    raise exception 'ORDER-EDIT-001A: unexpected anon public surface [%]', v_anon_set;
  end if;
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_defs from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef;
  if v_defs <> 'storefront_menu(text)' then
    raise exception 'ORDER-EDIT-001A: unexpected public DEFINER surface [%]', v_defs;
  end if;
  if has_schema_privilege('anon', 'app', 'USAGE') then
    raise exception 'ORDER-EDIT-001A: anon has app schema usage';
  end if;
end;
$$;
