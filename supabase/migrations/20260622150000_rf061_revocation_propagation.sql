-- ============================================================================
-- RF-061 — Device & employee revocation propagation (incl. offline)
-- ============================================================================
-- Adds the authoritative, server-side revocation actions (documented in API_CONTRACT
-- §4.11/§4.12 but previously unimplemented — RF-059 revoked direct writes so there was
-- no app path to revoke) and makes a revoked device's queued offline operations be
-- RECORDED as rejected on reconnect rather than silently lost by a batch-level raise.
-- Builds on RF-016 (devices/pairings/sessions), RF-051 (PIN sessions + offline window),
-- RF-056 (sync_push), RF-057 (sync_pull), RF-059 (RLS). Additive and FORWARD-ONLY.
--
-- WHAT THIS DOES
--   1. app.revoke_device(...) — SECURITY DEFINER: manager/restaurant_owner/org_owner
--      revoke a same-org, in-scope target device: its non-terminal pairings -> 'revoked'
--      (+ revoked_at) and its live device_sessions -> is_active=false + revoked_at. Writes
--      device.revoked audit; idempotent (already-revoked -> clean replay); cross-org/
--      out-of-scope target rejected; unauthorized -> device.revoke_denied + permission_denied.
--   2. app.revoke_employee(...) — SECURITY DEFINER: manager+ revoke a same-org target
--      employee: employee_profiles.employment_status -> 'terminated' and the resolved org
--      memberships -> status='revoked'. Writes employee.revoked audit; idempotent; existing
--      completed orders/payments are NOT touched (no historical rewrite, D-024/D-013).
--   3. app.sync_push CREATE OR REPLACE (RF061-A1): when the backing device session/pairing
--      is revoked/inactive, do NOT dispatch business ops; instead RECORD each pushed op in
--      sync_operations as status='rejected', last_error_code/rejection_reason='revoked_device',
--      last_error_class='permanent', write a sync.operation_rejected audit per op, and RETURN
--      a per-op rejected result array (no business state). The revoked-EMPLOYEE per-op
--      rejection (dispatched-RPC raise) is preserved and its rejection reason is clarified to
--      'revoked_employee'. All other RF-056 behavior is verbatim (dedup/replay, dependency
--      guard, dispatch, conflict, applied). Idempotency/exactly-once preserved: a previously
--      APPLIED op still replays its stored result even on a revoked device.
--
-- DECISIONS / SECURITY: D-005/D-006 device & human identity; D-011 SECURITY DEFINER RPC;
--   D-012 four layers; D-013 append-only audit (incl. denied attempts); D-022 idempotency
--   key (device_id + local_operation_id); R-007 offline revocation staleness; Q-009 offline
--   window (reused interim 8h via app.pin_session_offline_window(), NOT frozen here).
--   Authorization is INGEST-TIME; client timestamps are informational only (OFFLINE_SYNC §12).
--
-- OUT OF SCOPE: client offline UX (wipe/forced re-auth/badge — DEFERRED); packages/sync;
--   RF-058 realtime; new tables/columns; RLS/policy changes; pair_device/suspend_device;
--   any order/payment/shift/menu/report behavior change; freezing Q-009.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.revoke_device — authoritative device revocation (API_CONTRACT §4.11).
--    Actor/org/branch/role derived from the PIN session (never client-supplied org).
-- ----------------------------------------------------------------------------
create or replace function app.revoke_device(
  p_pin_session_id     uuid,
  p_device_id          uuid,
  p_target_device_id   uuid,
  p_local_operation_id text,
  p_reason             text
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
  v_m_rest       uuid;
  v_m_branch     uuid;
  v_t_org        uuid;
  v_t_rest       uuid;
  v_t_branch     uuid;
  v_pairings     integer;
  v_sessions     integer;
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'revoke_device: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'revoke_device: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'revoke_device: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'revoke_device: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.restaurant_id, m.branch_id
    into v_role, v_m_status, v_m_deleted, v_m_rest, v_m_branch
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'revoke_device: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) authorization: a management role only. An unauthorized actor gets a
  --     device.revoke_denied audit + a returned permission_denied (no raise so it persists).
  if v_role not in ('manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'device.revoke_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
            jsonb_build_object('attempted_action', 'revoke_device', 'target_device_id', p_target_device_id, 'role', v_role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'target_device_id', p_target_device_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (c) reason mandatory (audited financial/security action; D-013)
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'revoke_device: a non-empty reason is required' using errcode = '42501';
  end if;

  -- (d) load the target device; it MUST be in the actor's org + membership scope
  --     (cross-org / out-of-scope is rejected; scope derived from the session, never payload).
  select d.organization_id, d.restaurant_id, d.branch_id
    into v_t_org, v_t_rest, v_t_branch
    from public.devices d where d.id = p_target_device_id;
  if not found then
    raise exception 'revoke_device: target device not found' using errcode = '42501';
  end if;
  if v_t_org <> v_org then
    raise exception 'revoke_device: target device is not in the caller organization' using errcode = '42501';
  end if;
  if not (v_m_rest is null or v_m_rest = v_t_rest) or not (v_m_branch is null or v_m_branch = v_t_branch) then
    raise exception 'revoke_device: target device is outside the caller membership scope' using errcode = '42501';
  end if;

  -- (e) idempotency (natural, state-based; A2): if the target has no non-terminal pairing
  --     and no live device session, it is ALREADY revoked -> clean replay, no extra mutation.
  select count(*) into v_pairings
    from public.device_pairings dp
    where dp.organization_id = v_org and dp.device_id = p_target_device_id
      and dp.deleted_at is null and dp.status not in ('revoked', 'code_expired', 'rejected');
  select count(*) into v_sessions
    from public.device_sessions ds
    where ds.organization_id = v_org and ds.device_id = p_target_device_id
      and (ds.is_active or ds.revoked_at is null);
  if v_pairings = 0 and v_sessions = 0 then
    return jsonb_build_object('ok', true, 'target_device_id', p_target_device_id, 'status', 'revoked',
                              'already_revoked', true, 'server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) revoke: non-terminal pairings -> revoked; live device sessions -> inactive + revoked.
  update public.device_pairings
    set status = 'revoked', revoked_at = now()
    where organization_id = v_org and device_id = p_target_device_id
      and deleted_at is null and status not in ('revoked', 'code_expired', 'rejected');
  update public.device_sessions
    set is_active = false, revoked_at = now()
    where organization_id = v_org and device_id = p_target_device_id
      and (is_active or revoked_at is null);

  -- (g) audit device.revoked (D-013) with old/new + reason
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_t_rest, v_t_branch, null, v_emp, p_device_id, 'device.revoked', btrim(p_reason),
          jsonb_build_object('target_device_id', p_target_device_id, 'pairing_status', 'active', 'revoked_pairings', v_pairings, 'revoked_sessions', v_sessions),
          jsonb_build_object('target_device_id', p_target_device_id, 'pairing_status', 'revoked', 'resolved_membership_id', v_membership));

  return jsonb_build_object('ok', true, 'target_device_id', p_target_device_id, 'status', 'revoked',
                            'revoked_pairings', v_pairings, 'revoked_sessions', v_sessions,
                            'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.revoke_device(uuid, uuid, uuid, text, text) is
  'RF-061 (API_CONTRACT §4.11, D-006/D-011/D-013) SECURITY DEFINER RPC: revokes a device. Actor/org/scope from the PIN session (never client). manager/restaurant_owner/org_owner only (else device.revoke_denied audit + permission_denied); reason required; cross-org/out-of-scope target rejected (42501). Sets the target''s non-terminal device_pairings -> revoked (+revoked_at) and live device_sessions -> is_active=false +revoked_at, so future sessions/pushes/pulls fail the existing active-pairing/session checks (R-007). Writes device.revoked audit. Idempotent (already-revoked -> clean replay; A2). No new columns/tables; no service-role.';

revoke all on function app.revoke_device(uuid, uuid, uuid, text, text) from public;
grant execute on function app.revoke_device(uuid, uuid, uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. app.revoke_employee — authoritative employee revocation (API_CONTRACT §4.12).
-- ----------------------------------------------------------------------------
create or replace function app.revoke_employee(
  p_pin_session_id            uuid,
  p_device_id                 uuid,
  p_target_employee_profile_id uuid,
  p_local_operation_id        text,
  p_reason                    text
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
  v_m_rest       uuid;
  v_m_branch     uuid;
  v_t_org        uuid;
  v_t_rest       uuid;
  v_t_branch     uuid;
  v_t_appuser    uuid;
  v_t_membership uuid;
  v_t_empstatus  text;
  v_revoked_ms   integer;
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'revoke_employee: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'revoke_employee: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'revoke_employee: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'revoke_employee: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.restaurant_id, m.branch_id
    into v_role, v_m_status, v_m_deleted, v_m_rest, v_m_branch
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'revoke_employee: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) authorization: management role only (else audited denial + permission_denied)
  if v_role not in ('manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'employee.revoke_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
            jsonb_build_object('attempted_action', 'revoke_employee', 'target_employee_profile_id', p_target_employee_profile_id, 'role', v_role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'target_employee_profile_id', p_target_employee_profile_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (c) reason mandatory
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'revoke_employee: a non-empty reason is required' using errcode = '42501';
  end if;

  -- (d) load target employee profile; MUST be same org + within membership scope
  select ep.organization_id, ep.restaurant_id, ep.branch_id, ep.app_user_id, ep.membership_id, ep.employment_status
    into v_t_org, v_t_rest, v_t_branch, v_t_appuser, v_t_membership, v_t_empstatus
    from public.employee_profiles ep where ep.id = p_target_employee_profile_id;
  if not found then
    raise exception 'revoke_employee: target employee not found' using errcode = '42501';
  end if;
  if v_t_org <> v_org then
    raise exception 'revoke_employee: target employee is not in the caller organization' using errcode = '42501';
  end if;
  if not (v_m_rest is null or v_m_rest = v_t_rest) or not (v_m_branch is null or v_m_branch = v_t_branch) then
    raise exception 'revoke_employee: target employee is outside the caller membership scope' using errcode = '42501';
  end if;

  -- (e) revoke ALL relevant org memberships for the target (A6): the resolved membership_id
  --     and any active membership of the target's app_user in this org. Idempotent.
  update public.memberships m
    set status = 'revoked'
    where m.organization_id = v_org and m.status = 'active'
      and ( (v_t_membership is not null and m.id = v_t_membership)
            or (v_t_appuser is not null and m.app_user_id = v_t_appuser) );
  get diagnostics v_revoked_ms = row_count;

  -- (f) terminate the employment profile (idempotent: only if not already terminated)
  if v_t_empstatus <> 'terminated' then
    update public.employee_profiles
      set employment_status = 'terminated'
      where id = p_target_employee_profile_id and organization_id = v_org;
  end if;

  -- (g) natural idempotency: nothing left to revoke -> clean replay (no audit on a no-op)
  if v_revoked_ms = 0 and v_t_empstatus = 'terminated' then
    return jsonb_build_object('ok', true, 'target_employee_profile_id', p_target_employee_profile_id, 'status', 'terminated',
                              'already_revoked', true, 'server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (h) audit employee.revoked (D-013). Existing completed orders/payments are NOT touched.
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (v_org, v_t_rest, v_t_branch, null, v_emp, p_device_id, 'employee.revoked', btrim(p_reason),
          jsonb_build_object('target_employee_profile_id', p_target_employee_profile_id, 'employment_status', v_t_empstatus),
          jsonb_build_object('target_employee_profile_id', p_target_employee_profile_id, 'employment_status', 'terminated',
                             'revoked_membership_count', v_revoked_ms, 'resolved_membership_id', v_membership));

  return jsonb_build_object('ok', true, 'target_employee_profile_id', p_target_employee_profile_id, 'status', 'terminated',
                            'revoked_membership_count', v_revoked_ms, 'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.revoke_employee(uuid, uuid, uuid, text, text) is
  'RF-061 (API_CONTRACT §4.12, D-005/D-011/D-013) SECURITY DEFINER RPC: revokes an employee. Actor/org/scope from the PIN session. manager/restaurant_owner/org_owner only (else employee.revoke_denied + permission_denied); reason required; cross-org/out-of-scope target rejected. Sets employee_profiles.employment_status=terminated and ALL the target''s active org memberships (by membership_id and by app_user_id) -> status=revoked (A6), so future operations fail the existing membership-active check (R-007). Existing COMPLETED orders/payments are untouched (no historical rewrite, D-024). Writes employee.revoked audit. Idempotent (A2). No new columns/tables.';

revoke all on function app.revoke_employee(uuid, uuid, uuid, text, text) from public;
grant execute on function app.revoke_employee(uuid, uuid, uuid, text, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.sync_push — CREATE OR REPLACE. RF-056 body verbatim EXCEPT (RF061-A1): the
--    revoked/inactive backing device session/pairing branch no longer RAISES; it RECORDS
--    each pushed op as rejected (revoked_device) + audits + returns per-op rejected results
--    (no dispatch, no business state). A previously-APPLIED op still replays (idempotency
--    preserved). The revoked-EMPLOYEE per-op rejection (dispatched-RPC raise) is preserved
--    and its rejection reason is clarified to 'revoked_employee'.
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
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close') then
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
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close') then
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
  'RF-056/RF-061 (API_CONTRACT §4.14, D-010/D-022) SECURITY DEFINER batch push RPC. Validates the PIN session (offline-window bounded, Q-009) + device match. RF-061 (A1): a REVOKED/inactive backing device session/pairing no longer fails the whole batch with a silent raise — each pushed op is RECORDED rejected (revoked_device) + audited (sync.operation_rejected) and returned, with NO dispatch and NO business state (R-007/AC1); a previously-APPLIED op still replays (idempotency preserved). For a VALID device: per-op dedup/replay, dependency guard, dispatch (per-op EXCEPTION subtransaction), conflict(40001)/rejected/applied classification + audit; a revoked-MEMBERSHIP op is rejected by the dispatched RPC and tagged rejection_reason=revoked_employee. Authorization is INGEST-TIME; client timestamps are informational only. Reimplements NO business logic.';

revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. To undo by hand: drop app.revoke_device / app.revoke_employee,
-- and restore the RF-056 app.sync_push body (which raised 42501 on a revoked device).
-- No tables, columns, policies, or grants are added/removed by this migration.
-- ============================================================================
