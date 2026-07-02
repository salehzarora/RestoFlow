-- RF-161 -- Device-auth bridge: DEVICE-ORIGINATED pairing-code redemption + session
-- restore/revoke (ADR docs/RF_161_DEVICE_AUTH_BRIDGE.md). SECURITY-CRITICAL (RISK R-003).
--
-- Closes the frozen gap: RF-112's redeem/activate/start_session are MANAGEMENT-driven
-- (app.actor_rank_in_scope >= manager), so a device can never obtain its own session. This
-- adds a DEVICE-ORIGINATED path authorized by the ONE-TIME ENROLLMENT CODE (the owner's
-- authorization, issued by an authenticated manager at RF-160), not by membership. A device
-- reaches the `authenticated` grant gate via Supabase ANONYMOUS sign-in (role=authenticated,
-- NO membership) -- so this preserves D-011 (no anon-ROLE path, no service-role key) and reuses
-- the existing PIN-session -> sync_push/sync_pull operational chain UNCHANGED.
--
-- WHAT THIS DOES (additive, forward-only; NEVER edits a prior migration):
--   * app.redeem_device_pairing(code, device_type) -- validate the code by HASH (must be
--     code_issued, unexpired, unrevoked, live device+scope, device_type matches); consume it
--     (code_issued -> active, guarded/race-safe); revoke any prior active sessions for the
--     device; mint a device_session (session_token_ref = SHA-256 of a fresh token); return the
--     device_session_id + raw token ONCE + non-secret context ids. Scope is SERVER-DERIVED from
--     the code's pairing row -- the client supplies NO org/branch/role, so cross-org/branch
--     injection is structurally impossible.
--   * app.restore_device_session(device_id, token) -- hash the token, find the device's ACTIVE,
--     non-revoked session on an ACTIVE pairing; return device_session_id + context. NO token.
--   * app.revoke_device_session(device_id, token) -- token-proven SELF-unpair (set revoked_at).
--
-- SECURITY (SECURITY REQUIREMENT / D-011 / D-013):
--   * SECURITY DEFINER, search_path='' locked; runs as the BYPASSRLS owner (direct DML on
--     device_pairings/device_sessions stays RLS-denied for app roles -- RF-059).
--   * Secrets: the enrollment code hash (device_pairings.enrollment_code_hash) and the session
--     token hash (device_sessions.session_token_ref) are the ONLY forms stored; the raw token is
--     returned EXACTLY ONCE and NEVER persisted/logged/audited in plaintext. A code is one-time
--     (consumed on redeem). No read RPC returns a secret.
--   * Audit: audit_events requires a HUMAN actor (its CHECK: app_user OR employee not null), and
--     an anonymous device has neither -- so the redeem is audited ONLY when a human actor is
--     present (else the device_pairings.status + device_sessions row + the owner's issue-code
--     audit are the durable trail). A device-actor audit column is a documented future gap.
--   * Grants: authenticated only (anonymous authenticated devices qualify); never anon/service_role.
--
-- Trade-off (ADR §6): redeeming the one-time code advances the pairing straight to `active`,
-- COLLAPSING the manager pending->paired->active checkpoints (the code IS the owner's one-time,
-- expiring, revocable, high-entropy authorization). PENDING mandatory human RLS/security sign-off.
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.

-- ===========================================================================
-- 1. app.redeem_device_pairing -- device-originated code redemption -> active + session.
-- ===========================================================================
create or replace function app.redeem_device_pairing(
  p_enrollment_code text,
  p_device_type     text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();  -- null for an anonymous device
  v_hash       text;
  v_pairing    uuid;
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_device     uuid;
  v_expires    timestamptz;
  v_dtype      text;
  v_dactive    boolean;
  v_ddeleted   timestamptz;
  v_session    uuid := gen_random_uuid();
  v_token      text;
  v_token_hash text;
  v_rows       integer;
begin
  if p_enrollment_code is null or btrim(p_enrollment_code) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if p_device_type is null or p_device_type not in ('pos', 'kds') then
    return jsonb_build_object('ok', false, 'error', 'invalid_type', 'entity', 'device_pairing');
  end if;

  v_hash := app.hash_provisioning_secret(btrim(p_enrollment_code));

  -- redeemable pairing by code hash: code_issued + live + unrevoked. Scope is DERIVED here.
  select dp.id, dp.organization_id, dp.restaurant_id, dp.branch_id, dp.device_id, dp.code_expires_at
    into v_pairing, v_org, v_rest, v_branch, v_device, v_expires
    from public.device_pairings dp
    where dp.enrollment_code_hash = v_hash
      and dp.status = 'code_issued'
      and dp.revoked_at is null
      and dp.deleted_at is null
    order by dp.created_at desc
    limit 1;
  if v_pairing is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if v_expires is not null and v_expires <= now() then
    return jsonb_build_object('ok', false, 'error', 'expired', 'entity', 'device_pairing');
  end if;

  -- the device must be live on a LIVE branch/restaurant, and its declared type must match.
  select d.device_type, d.is_active, d.deleted_at
    into v_dtype, v_dactive, v_ddeleted
    from public.devices d
    join public.branches b on b.id = d.branch_id and b.organization_id = d.organization_id
      and b.restaurant_id = d.restaurant_id and b.deleted_at is null
    join public.restaurants r on r.id = d.restaurant_id and r.organization_id = d.organization_id
      and r.deleted_at is null
    where d.id = v_device and d.organization_id = v_org;
  if v_dtype is null or not v_dactive or v_ddeleted is not null then
    -- device or scope not live => invalid (fail closed; no scope leak).
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if v_dtype <> p_device_type then
    return jsonb_build_object('ok', false, 'error', 'wrong_type', 'entity', 'device_pairing');
  end if;

  -- consume the code + activate the pairing (guarded; race-safe one-time redemption).
  update public.device_pairings
     set status = 'active', paired_at = now()
     where id = v_pairing and status = 'code_issued';
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;

  -- hygiene: one active session per device -> revoke any prior live sessions.
  update public.device_sessions
     set is_active = false, revoked_at = now()
     where device_id = v_device and revoked_at is null;

  -- mint the session: store ONLY the hash; return the raw token ONCE.
  v_token      := replace(gen_random_uuid()::text, '-', '');
  v_token_hash := app.hash_provisioning_secret(v_token);
  insert into public.device_sessions
    (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active)
  values (v_session, v_org, v_rest, v_branch, v_device, v_pairing, v_token_hash, true);

  -- audit ONLY when a human actor exists (audit_events requires a human actor; a device has none).
  if v_actor is not null then
    insert into public.audit_events
      (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id, action, reason, old_values, new_values)
    values
      (v_org, v_rest, v_branch, v_actor, v_device, 'device.redeemed_by_code', null,
       jsonb_build_object('device_pairing_id', v_pairing, 'from', 'code_issued'),
       jsonb_build_object('device_pairing_id', v_pairing, 'device_session_id', v_session, 'status', 'active'));
  end if;

  return jsonb_build_object('ok', true, 'entity', 'device_session',
    'device_session_id', v_session, 'session_token', v_token,
    'organization_id', v_org, 'restaurant_id', v_rest, 'branch_id', v_branch,
    'device_id', v_device, 'device_type', v_dtype);
end;
$$;

comment on function app.redeem_device_pairing(text, text) is
  'RF-161: DEVICE-ORIGINATED code redemption. Authorized by the one-time enrollment code (hash), NOT membership; scope is server-derived from the pairing (no cross-org/branch injection). Consumes the code (code_issued -> active), revokes prior device sessions, mints a new session (hash stored; raw token returned ONCE). SECURITY DEFINER, search_path locked. authenticated only (anonymous devices qualify).';

-- ===========================================================================
-- 2. app.restore_device_session -- token-proven session restore (read-only, no token out).
-- ===========================================================================
create or replace function app.restore_device_session(
  p_device_id     uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_hash   text;
  v_sid    uuid;
  v_org    uuid;
  v_rest   uuid;
  v_branch uuid;
  v_dtype  text;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_session');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));
  -- The branch + restaurant tombstone joins MIRROR redeem (fail closed on a dead scope):
  -- decommissioning a branch/restaurant (soft-delete) must invalidate restore, not leave the
  -- device serving a tombstoned scope (RISK R-003 / R-007). NOTE: the downstream operational
  -- gates (start_pin_session/sync_push, RF-051/056) do NOT yet re-check these tombstones -- a
  -- pre-existing gap tracked for the human sign-off (ADR RF-161 §7); this closes the redeem/
  -- restore asymmetry introduced here.
  select ds.id, ds.organization_id, ds.restaurant_id, ds.branch_id, d.device_type
    into v_sid, v_org, v_rest, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    join public.devices d on d.id = ds.device_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id and b.deleted_at is null
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_session');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'device_session',
    'device_session_id', v_sid, 'organization_id', v_org, 'restaurant_id', v_rest,
    'branch_id', v_branch, 'device_id', p_device_id, 'device_type', v_dtype);
end;
$$;

comment on function app.restore_device_session(uuid, text) is
  'RF-161: token-proven device-session restore. Returns the live device_session_id + context iff the raw token hashes to an ACTIVE, non-revoked session on an ACTIVE pairing for the device; otherwise invalid_session (fail closed). NEVER returns a token.';

-- ===========================================================================
-- 3. app.revoke_device_session -- token-proven self-unpair (idempotent).
-- ===========================================================================
create or replace function app.revoke_device_session(
  p_device_id     uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash text;
  v_rows integer;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_session');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));
  update public.device_sessions
     set is_active = false, revoked_at = now()
     where device_id = p_device_id and session_token_ref = v_hash and revoked_at is null;
  get diagnostics v_rows = row_count;
  return jsonb_build_object('ok', true, 'entity', 'device_session', 'revoked', v_rows);
end;
$$;

comment on function app.revoke_device_session(uuid, text) is
  'RF-161: token-proven device self-unpair. Sets is_active=false + revoked_at on the caller''s OWN session(s) matching (device_id, token hash). Idempotent (already-revoked => revoked:0, still ok). Owner-side revoke uses RF-061 revoke_device.';

-- ===========================================================================
-- 4. Thin public SECURITY INVOKER wrappers (RF-064 / RF-109 pattern; token args are text).
-- ===========================================================================
create or replace function public.redeem_device_pairing(
  p_enrollment_code text, p_device_type text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.redeem_device_pairing(p_enrollment_code, p_device_type); $$;

create or replace function public.restore_device_session(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.restore_device_session(p_device_id, p_session_token); $$;

create or replace function public.revoke_device_session(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.revoke_device_session(p_device_id, p_session_token); $$;

-- ===========================================================================
-- 5. Grants: authenticated only (never anon/service_role). Anonymous authenticated
--    devices qualify; authorization is the code/token, not membership.
-- ===========================================================================
revoke all on function app.redeem_device_pairing(text, text)         from public;
revoke all on function app.restore_device_session(uuid, text)        from public;
revoke all on function app.revoke_device_session(uuid, text)         from public;
grant execute on function app.redeem_device_pairing(text, text)      to authenticated;
grant execute on function app.restore_device_session(uuid, text)     to authenticated;
grant execute on function app.revoke_device_session(uuid, text)      to authenticated;

revoke all on function public.redeem_device_pairing(text, text)      from public;
revoke all on function public.restore_device_session(uuid, text)     from public;
revoke all on function public.revoke_device_session(uuid, text)      from public;
grant execute on function public.redeem_device_pairing(text, text)   to authenticated;
grant execute on function public.restore_device_session(uuid, text)  to authenticated;
grant execute on function public.revoke_device_session(uuid, text)   to authenticated;

-- ===========================================================================
-- DOWN (manual; Supabase is forward-only -- `supabase db reset` replays):
--   drop function if exists public.revoke_device_session(uuid, text);
--   drop function if exists public.restore_device_session(uuid, text);
--   drop function if exists public.redeem_device_pairing(text, text);
--   drop function if exists app.revoke_device_session(uuid, text);
--   drop function if exists app.restore_device_session(uuid, text);
--   drop function if exists app.redeem_device_pairing(text, text);
-- ===========================================================================
