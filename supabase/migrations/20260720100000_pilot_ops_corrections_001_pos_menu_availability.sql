-- ============================================================================
-- PILOT-OPERATIONS-CORRECTIONS-001 (2/4) -- POS cashier menu-availability control
-- ============================================================================
-- The pilot cashier must flip a menu item Sold out / Paused straight from the POS
-- (not only from the Dashboard), server-authoritatively. This adds the POS write
-- path on top of the EXISTING RESTAURANT-OPERATIONS-V1-001 backend:
--
--   * app.pos_set_item_availability -- PIN-session + device path, gated by the
--     DEFAULT-ON manage_menu_availability capability (migration 1). It writes the
--     SAME menu_item_branch_availability override row and the SAME audit taxonomy
--     (menu.menu_item.availability_changed / availability_denied) that the
--     Dashboard app.menu_set_item_availability uses -- one override model, one
--     Activity-Log taxonomy, no second availability system.
--   * app.sync_push gains the 'menu.availability_set' op type (CHECK + both
--     envelope allowlists + one dispatch branch) -- a FAITHFUL re-creation of the
--     RESTAURANT-OPERATIONS-V1-001 body; everything else verbatim.
--
-- OFFLINE RULE (client-enforced, documented here): this op requires authoritative
-- server confirmation. The POS must NOT show fake local success while offline; the
-- transport (sync_operations) dedup makes a genuine retry idempotent, and the
-- setter itself is idempotent (no-change re-applies with no audit).
--
-- app.pos_menu already exposes availability + availability_reason per item, and
-- app.submit_order already refuses selling an unavailable item (item_unavailable),
-- so accepted orders are unaffected -- this migration only adds the POS WRITE.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Transport op-type CHECK -- additive (drop + re-add the full allowlist).
-- ----------------------------------------------------------------------------
alter table public.sync_operations drop constraint if exists sync_operations_operation_type_check;
alter table public.sync_operations add constraint sync_operations_operation_type_check
  check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set'));

-- ----------------------------------------------------------------------------
-- 2. app.pos_set_item_availability -- the POS PIN-session write path for the
--    per-branch availability override. It mirrors app.menu_set_item_availability
--    (the Dashboard/JWT path) but authorizes through the PIN session + device +
--    the default-ON manage_menu_availability capability, and derives org/rest/
--    branch from the SESSION (never the payload). It writes the SAME override row
--    and the SAME audit taxonomy (menu.menu_item.availability_changed /
--    availability_denied) so the Activity Log renders POS and Dashboard changes
--    identically. Reached ONLY via public.sync_push (menu.availability_set) --
--    no public wrapper (mirrors app.move_order_table). MONEY-FREE.
-- ----------------------------------------------------------------------------
create function app.pos_set_item_availability(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_menu_item_id   uuid,
  p_availability   text,
  p_reason         text
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
  v_m_perms     jsonb;
  v_item_rest   uuid;
  v_item_branch uuid;
  v_item_name   text;
  v_reason      text;
  v_old_avail   text;
  v_old_reason  text;
begin
  -- (a) canonical PIN-session preamble; actor + scope derived here, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'pos_set_item_availability: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'pos_set_item_availability: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'pos_set_item_availability: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'pos_set_item_availability: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'pos_set_item_availability: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) capability BEFORE any item lookup (so a denial is not an existence oracle,
  --     R-003): manager+ by role OR a cashier with the DEFAULT-ON
  --     manage_menu_availability capability. Denial is AUDITED
  --     (menu.menu_item.availability_denied) + RETURNED (no raise, so the audit
  --     persists) with NO state change -- the discount/void denial discipline.
  if not ((v_role in ('manager', 'restaurant_owner', 'org_owner'))
          or app.cashier_capability_allowed(v_role, v_m_perms, 'manage_menu_availability')) then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'menu.menu_item.availability_denied', null, null,
      jsonb_build_object('entity', 'menu_item', 'id', p_menu_item_id,
                         'role', v_role, 'denied_reason', 'permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'entity', 'menu_item_availability');
  end if;

  -- (c) shape validation (the POS can only ever produce these values).
  if p_availability is null or p_availability not in ('available', 'unavailable') then
    raise exception 'pos_set_item_availability: availability must be available|unavailable' using errcode = '42501';
  end if;
  v_reason := nullif(btrim(coalesce(p_reason, '')), '');
  if p_availability = 'unavailable' then
    if v_reason is null or v_reason not in ('sold_out', 'paused') then
      raise exception 'pos_set_item_availability: unavailable requires a structured reason (sold_out|paused)' using errcode = '42501';
    end if;
  else
    v_reason := null;   -- available never carries a reason
  end if;

  -- (d) the item must be live + visible in the SESSION branch. FOR UPDATE -- the
  --     SAME serialization point app.submit_order and app.menu_set_item_availability
  --     take (they lock the canonical menu_items row before validating/altering
  --     sellability), so a submit that locked first commits its accepted order
  --     before this change applies to later orders. A branch-pinned sibling, a
  --     foreign-restaurant item, or a tombstoned item is the SAME typed refusal
  --     (R-003 -- the caller learns nothing about siblings).
  select i.restaurant_id, i.branch_id, i.name
    into v_item_rest, v_item_branch, v_item_name
    from public.menu_items i
    where i.id = p_menu_item_id
      and i.organization_id = v_org
      and i.deleted_at is null
      and i.is_active
    for update;
  if not found
     or v_item_rest <> v_rest
     or (v_item_branch is not null and v_item_branch <> v_branch) then
    return jsonb_build_object('ok', false, 'error', 'not_found',
                              'entity', 'menu_item_availability');
  end if;

  -- (e) current effective override (absence = available); no-change is idempotent
  --     (no row write, no audit) so a replay/duplicate re-apply is silent.
  select a.availability, a.reason into v_old_avail, v_old_reason
    from public.menu_item_branch_availability a
    where a.organization_id = v_org and a.branch_id = v_branch and a.menu_item_id = p_menu_item_id;
  if not found then
    v_old_avail := 'available'; v_old_reason := null;
  end if;
  if v_old_avail = p_availability and v_old_reason is not distinct from v_reason then
    return jsonb_build_object('ok', true, 'entity', 'menu_item_availability',
                              'menu_item_id', p_menu_item_id, 'availability', p_availability,
                              'reason', v_reason, 'no_change', true);
  end if;

  insert into public.menu_item_branch_availability
    (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason)
  values
    (v_org, v_rest, v_branch, p_menu_item_id, p_availability, v_reason)
  on conflict (organization_id, branch_id, menu_item_id)
  do update set availability = excluded.availability, reason = excluded.reason;

  -- (f) audit -- the SAME taxonomy the Dashboard path writes, so the Activity Log
  --     is unified. Actor is the employee behind the PIN session; device_id stamps
  --     the POS origin. The structured reason token lives in old/new values (the
  --     client localizes sold_out/paused); the reason COLUMN is free-text only.
  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
     action, reason, old_values, new_values)
  values
    (v_org, v_rest, v_branch, null, v_emp, p_device_id,
     'menu.menu_item.availability_changed', null,
     jsonb_build_object('availability', v_old_avail, 'availability_reason', v_old_reason),
     jsonb_build_object('availability', p_availability, 'availability_reason', v_reason,
                        'item_name', v_item_name, 'menu_item_id', p_menu_item_id));

  return jsonb_build_object('ok', true, 'entity', 'menu_item_availability',
                            'menu_item_id', p_menu_item_id, 'availability', p_availability,
                            'reason', v_reason);
end;
$$;

comment on function app.pos_set_item_availability(uuid, uuid, uuid, text, text) is
  'PILOT-OPERATIONS-CORRECTIONS-001 (API_CONTRACT, D-011): SECURITY DEFINER POS write path for the per-branch menu-item availability override. Canonical PIN-session preamble; scope derived from the session (never the payload). Authorizes manager+ by role OR a cashier with the DEFAULT-ON manage_menu_availability capability (checked BEFORE any item lookup -- a denial is not an existence oracle, R-003); denial audits menu.menu_item.availability_denied + returns permission_denied. availability=available clears the reason; unavailable REQUIRES a structured reason (sold_out|paused). Target item must be live + visible in the session branch (FOR UPDATE -- the same serialization point app.submit_order / app.menu_set_item_availability use); a branch-pinned sibling / foreign-restaurant / tombstoned item is the SAME not_found refusal. No-change is idempotent (no row, no audit). Success writes the SAME menu.menu_item.availability_changed audit as the Dashboard path (unified Activity Log). Reached ONLY via public.sync_push (menu.availability_set); no public wrapper. MONEY-FREE.';

revoke all on function app.pos_set_item_availability(uuid, uuid, uuid, text, text) from public;
revoke all on function app.pos_set_item_availability(uuid, uuid, uuid, text, text) from anon;
grant execute on function app.pos_set_item_availability(uuid, uuid, uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.sync_push -- CREATE OR REPLACE. Faithful re-creation of the newest
--    (RESTAURANT-OPERATIONS-V1-001) body + the menu.availability_set dispatch.
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
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set') then
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
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set') then
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
  'RF-056/RF-061 + MVP order.status + ORDER-CUSTOMER-001 + MONEY-VOID-001 + RESTAURANT-OPERATIONS-V1-001 + PILOT-OPERATIONS-CORRECTIONS-001 (API_CONTRACT §4.14, D-010/D-022) SECURITY DEFINER batch push RPC. FAITHFUL re-creation of the RESTAURANT-OPERATIONS-V1-001 body with ONE added dispatch branch: menu.availability_set (payload {menu_item_id, availability, reason}) -> app.pos_set_item_availability, using the SAME pin session + device; the accepted operation_type set gains menu.availability_set in both envelope validation lists. All prior behaviour is verbatim: batch cap 100; PIN session + device gate; RF061-A1 revoked-device per-op recording; per-op dedup/replay; payload-fingerprint conflict; dependency guard; per-op EXCEPTION subtransactions; applied/rejected/conflict/pending finalization; revoked_employee tagging; the ORDER-CUSTOMER-001 customer_name stamp. Authorization is INGEST-TIME; scope is derived from the session, never the payload. Reimplements NO business logic.';
revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only -- `supabase db reset` replays):
--   restore app.sync_push from 20260719110000 (drop the menu.availability_set
--     branch + both allowlist entries);
--   restore sync_operations_operation_type_check without 'menu.availability_set';
--   drop function if exists app.pos_set_item_availability(uuid, uuid, uuid, text, text);
-- ============================================================================
