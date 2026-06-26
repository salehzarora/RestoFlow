-- RF-112 Stage 3 -- GUC-free device activation + session start (DECISION D-034; API_CONTRACT §4.28/§4.29).
--
-- Closes the Stage 2 contract gap (Codex-confirmed, ratified by D-034): the device lifecycle now has an
-- explicit, audited owner for the `paired → active` edge, and a device session can be started only on an
-- `active` pairing.
--   ... approve_device (pending -> paired, Stage 2)
--   -> activate_device (paired -> active)          [this migration]
--   -> start_device_session (mints a session on an ACTIVE pairing)  [this migration]
--
-- LIFECYCLE (STATE_MACHINES §9 / D-034):
--   * approve_device REMAINS pending -> paired (Stage 2); unchanged here.
--   * pending -> active is FORBIDDEN; activate_device requires `paired` (every other state -> 42501).
--   * activate_device owns paired -> active (a SEPARATE management step; never inside approve or session-start).
--   * start_device_session requires `active`; pending/paired/code_issued/suspended/revoked/code_expired/
--     rejected (any non-active) fail closed.
--
-- GUC-FREE (D-033/D-034): caller from auth.uid() -> app.current_app_user_id(); authority via the Stage 1
-- app.actor_rank_in_scope over the pairing's DERIVED scope (never app.current_org_id()/has_scope()/
-- has_role_in_scope()/menu_guard; never app.is_platform_admin()). Management-authorized: org_owner/
-- restaurant_owner/manager covering the device's scope (rank >= manager); cashier/kitchen_staff/
-- accountant -> permission_denied; non-member/cross-org/out-of-scope/anon -> 42501. No service_role/anon.
--
-- SESSION TOKEN (SECURITY REQUIREMENT, D-034/§4.29): server-generated, stored ONLY as
-- device_sessions.session_token_ref = its sha-256 hash (the Stage 2 app.hash_provisioning_secret pattern),
-- and the plaintext token is returned to the caller EXACTLY ONCE (only on the first/claiming call). It is
-- NEVER stored plaintext, NEVER in audit_events, and the idempotency ledger stores a NO-TOKEN result so a
-- replay can never re-return it. device_sessions.expires_at is left NULL: the device-session offline
-- window is DEFERRED (Q-009/RF-051; the RF-016 device_sessions comment) -- session validity is gated by the
-- ACTIVE pairing + revocation (RF-061 revoke_device invalidates the session). RF-112 is management-initiated
-- (client_request_id); the fully device-originated variant (device_id + local_operation_id, D-022) is the
-- follow-up once the deferred device-auth bridge lands (D-034).
--
-- Reuses Stage 1 (20260626090000): app.actor_rank_in_scope, app.management_audit, app.management_idem_check,
-- app.management_claim_request, public.management_request_results; and Stage 2 (20260626100000):
-- app.hash_provisioning_secret. Direct DML on device_pairings/device_sessions stays RLS-denied (RF-059);
-- these DEFINER RPCs write as the BYPASSRLS owner. FORWARD-ONLY. Manual teardown at the foot.

-- ===========================================================================
-- 1. app.activate_device -- the explicit paired -> active edge (D-034 / §4.28).
-- ===========================================================================
create or replace function app.activate_device(
  p_client_request_id uuid,
  p_device_pairing_id uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_org    uuid;
  v_rest   uuid;
  v_branch uuid;
  v_status text;
  v_rank   integer;
  v_fp     text;
  v_replay jsonb;
  v_rows   integer;
  v_result jsonb;
begin
  if v_actor is null then
    raise exception 'activate_device: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'activate_device: client_request_id is required' using errcode = '42501';
  end if;
  if p_device_pairing_id is null then
    raise exception 'activate_device: device_pairing_id is required' using errcode = '42501';
  end if;

  -- load the pairing; its device + branch/restaurant must be LIVE (fail closed on dead scope).
  select dp.organization_id, dp.restaurant_id, dp.branch_id, dp.status
    into v_org, v_rest, v_branch, v_status
    from public.device_pairings dp
    join public.devices d on d.id = dp.device_id and d.organization_id = dp.organization_id and d.deleted_at is null and d.is_active
    join public.branches b on b.id = dp.branch_id and b.organization_id = dp.organization_id and b.restaurant_id = dp.restaurant_id and b.deleted_at is null
    join public.restaurants r on r.id = dp.restaurant_id and r.organization_id = dp.organization_id and r.deleted_at is null
    where dp.id = p_device_pairing_id and dp.deleted_at is null;
  if not found then
    raise exception 'activate_device: pairing not found, or its device/scope is inactive or soft-deleted' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('device_pairing_id', p_device_pairing_id, 'op', 'activate')::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'activate_device', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'activate_device: caller has no active membership covering the device scope' using errcode = '42501';
  end if;
  if v_rank < 2 then     -- cashier/kitchen_staff/accountant cannot provision
    perform app.management_audit(v_org, v_rest, v_branch, 'device.activate_denied', null,
      jsonb_build_object('device_pairing_id', p_device_pairing_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device_pairing');
  end if;

  -- `paired` is the ONLY legal source for paired -> active. Every other state
  -- (code_issued/pending/active/suspended/revoked/code_expired/rejected) is rejected -> fail closed;
  -- pending -> active can NEVER happen here (a pending pairing is not `paired`).
  if v_status <> 'paired' then
    raise exception 'activate_device: pairing is not paired (status=%); only paired -> active is allowed', v_status using errcode = '42501';
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'device_pairing',
                'device_pairing_id', p_device_pairing_id, 'status', 'active');
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'activate_device', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- paired -> active. Guarded WHERE status='paired' is race-safe. Mints NO secret (device credential
  -- provisioning is RF-021). The RF-016 enforce_pairing_code_expiry trigger does NOT gate this
  -- post-enrollment edge (OLD.status='paired', not code_issued).
  update public.device_pairings
    set status = 'active'
    where id = p_device_pairing_id and status = 'paired';
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'activate_device: pairing was not paired at activation time' using errcode = '42501';
  end if;

  perform app.management_audit(v_org, v_rest, v_branch, 'device.activated', null,
    jsonb_build_object('device_pairing_id', p_device_pairing_id, 'status', 'active'));
  return v_result;
end;
$$;

-- ===========================================================================
-- 2. app.start_device_session -- mint a device session on an ACTIVE pairing (D-034 / §4.29).
--    Management-initiated (client_request_id); server-generated token returned once, stored hash-only.
-- ===========================================================================
create or replace function app.start_device_session(
  p_client_request_id uuid,
  p_device_pairing_id uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor   uuid := app.current_app_user_id();
  v_org     uuid;
  v_rest    uuid;
  v_branch  uuid;
  v_device  uuid;
  v_status  text;
  v_rank    integer;
  v_fp      text;
  v_replay  jsonb;
  v_session uuid := gen_random_uuid();
  v_token   text;
  v_hash    text;
  v_stored  jsonb;
begin
  if v_actor is null then
    raise exception 'start_device_session: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'start_device_session: client_request_id is required' using errcode = '42501';
  end if;
  if p_device_pairing_id is null then
    raise exception 'start_device_session: device_pairing_id is required' using errcode = '42501';
  end if;

  -- load the pairing + device; its device + branch/restaurant must be LIVE (fail closed). Capture device_id.
  select dp.organization_id, dp.restaurant_id, dp.branch_id, dp.device_id, dp.status
    into v_org, v_rest, v_branch, v_device, v_status
    from public.device_pairings dp
    join public.devices d on d.id = dp.device_id and d.organization_id = dp.organization_id and d.deleted_at is null and d.is_active
    join public.branches b on b.id = dp.branch_id and b.organization_id = dp.organization_id and b.restaurant_id = dp.restaurant_id and b.deleted_at is null
    join public.restaurants r on r.id = dp.restaurant_id and r.organization_id = dp.organization_id and r.deleted_at is null
    where dp.id = p_device_pairing_id and dp.deleted_at is null;
  if not found then
    raise exception 'start_device_session: pairing not found, or its device/scope is inactive or soft-deleted' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('device_pairing_id', p_device_pairing_id, 'op', 'start_session')::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'start_device_session', v_fp);
  if v_replay is not null then
    return v_replay;   -- committed replay: NO token (the stored result has none)
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'start_device_session: caller has no active membership covering the device scope' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(v_org, v_rest, v_branch, 'device.session_start_denied', null,
      jsonb_build_object('device_pairing_id', p_device_pairing_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device_session');
  end if;

  -- a device session may be opened ONLY on an ACTIVE pairing. Every other state
  -- (code_issued/pending/paired/suspended/revoked/code_expired/rejected) fails closed
  -- (T-004 / RISK R-007: revoked/suspended devices cannot start a session).
  if v_status <> 'active' then
    raise exception 'start_device_session: pairing is not active (status=%); a device session requires an active pairing', v_status using errcode = '42501';
  end if;

  -- server-generated token; store ONLY its hash; return the plaintext ONCE. expires_at left NULL:
  -- the device-session offline window is DEFERRED (Q-009/RF-051; RF-016 device_sessions comment) --
  -- validity is gated by the active pairing + revocation (RF-061 revoke invalidates the session).
  v_token := replace(gen_random_uuid()::text, '-', '');
  v_hash  := app.hash_provisioning_secret(v_token);

  -- the LEDGER stores a NO-TOKEN result, so a replay can never re-return the one-time token.
  v_stored := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'device_session',
                'device_session_id', v_session, 'device_pairing_id', p_device_pairing_id);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'start_device_session', v_fp, v_stored);
  if v_replay is not null then
    return v_replay;   -- lost the race: replay (no token)
  end if;

  insert into public.device_sessions
    (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active)
  values (v_session, v_org, v_rest, v_branch, v_device, p_device_pairing_id, v_hash, true);

  -- audit carries NO plaintext token (only the session/pairing ids).
  perform app.management_audit(v_org, v_rest, v_branch, 'device.session_started', null,
    jsonb_build_object('device_session_id', v_session, 'device_pairing_id', p_device_pairing_id));

  -- FIRST response ONLY: include the one-time plaintext session token.
  return v_stored || jsonb_build_object('session_token', v_token);
end;
$$;

-- ===========================================================================
-- 3. Thin public SECURITY INVOKER wrappers (RF-064 / RF-109 pattern).
-- ===========================================================================
create or replace function public.activate_device(
  p_client_request_id uuid, p_device_pairing_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.activate_device(p_client_request_id, p_device_pairing_id); $$;

create or replace function public.start_device_session(
  p_client_request_id uuid, p_device_pairing_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.start_device_session(p_client_request_id, p_device_pairing_id); $$;

-- ===========================================================================
-- 4. Grants: authenticated only (never anon/service_role).
-- ===========================================================================
revoke all on function app.activate_device(uuid, uuid)        from public;
revoke all on function app.start_device_session(uuid, uuid)   from public;
grant execute on function app.activate_device(uuid, uuid)      to authenticated;
grant execute on function app.start_device_session(uuid, uuid) to authenticated;

revoke all on function public.activate_device(uuid, uuid)        from public;
revoke all on function public.start_device_session(uuid, uuid)   from public;
grant execute on function public.activate_device(uuid, uuid)      to authenticated;
grant execute on function public.start_device_session(uuid, uuid) to authenticated;

-- ===========================================================================
-- DOWN (manual; Supabase is forward-only -- `supabase db reset` replays):
--   drop function if exists public.start_device_session(uuid, uuid);
--   drop function if exists public.activate_device(uuid, uuid);
--   drop function if exists app.start_device_session(uuid, uuid);
--   drop function if exists app.activate_device(uuid, uuid);
-- ===========================================================================
