-- RF-118 -- Rate limits + session-expiry policy: device-pairing brute-force
-- lockout (per calling principal) + device-session max-age expiry. Additive,
-- forward-only. Complements RF-051 (which already ships the PIN attempt-limit
-- lockout + the PIN-session offline/idle window); RF-118 closes the two
-- REMAINING server gaps identified in the RF-118 recon:
--   (B) app.redeem_device_pairing had NO attempt throttle -> unbounded blind
--       enrollment-code guessing (bounded only by the 15-min code TTL).
--   (C) device_sessions.expires_at EXISTED but was DEFERRED (Q-009/RF-016):
--       redeem minted sessions with expires_at = NULL and restore never checked
--       it, so a device session never expired (revocation-bounded only).
--
-- SECURITY / SCOPE (SECURITY REQUIREMENT / D-011 / D-012):
--   * Pairing lockout is keyed on the CALLER PRINCIPAL (auth.uid()) -- the only
--     handle an UNPAIRED attacker has. A wrong code resolves to no device/scope,
--     so the counter CANNOT be keyed on tenant/device. Tenant-safe: the row is
--     the caller's own principal, carries NO organization_id (it is pre-tenant,
--     like platform_admin_grants under D-026), and leaks nothing cross-tenant.
--   * The lockout is checked BEFORE the code hash + pairing lookup (before any
--     expensive/sensitive validation), per the RF-118 backend guidance.
--   * A locked caller receives a NEW safe 'locked' error. Being rate-limited is
--     NOT code/account-existence sensitive, so surfacing it leaks nothing. The
--     non-locked shapes are UNCHANGED from RF-161 and honest about disclosure: a
--     BLIND guess (a code hashing to no live pairing) always returns the generic
--     'invalid_code'; the more specific 'expired' / 'wrong_type' are returned ONLY
--     when the submitted code actually HASHES to a real pairing row -- i.e. to a
--     caller who already holds a valid code -- so they aid a legitimate operator
--     without leaking code existence to a guesser. Intentionally preserved (the
--     rf161 tests assert them); NOT collapsed by RF-118.
--   * Least privilege: device_pairing_attempt_states is written ONLY by the
--     SECURITY DEFINER RPC (via app.note_pairing_failure, NOT granted to app
--     roles); authenticated may READ only its OWN row (self-scoped RLS). No
--     service-role, no broad grants. search_path='' locked; runs as the BYPASSRLS
--     owner (direct DML stays RLS-denied for app roles).
--   * redeem RETURNS (never raises) on the failure paths, so the failed-attempt
--     increment COMMITS (unlike RF-051's wrong-PIN path, which must return NULL
--     to avoid a raise rolling the counter back).
--
-- KNOWN LIMITATION (documented; production-hardening, NOT solved here):
--   An attacker can call auth.signInAnonymously() to mint a FRESH auth.uid() per
--   attempt and bypass the per-principal counter. True brute-force protection
--   needs IP/edge/gateway rate-limiting and/or DISABLING anonymous sign-in in
--   production (anonymous auth is only needed to bootstrap device pairing). This
--   DB lockout stops the naive single-session loop and is defense-in-depth; it
--   does NOT claim production-grade protection. Enrollment codes remain
--   consume-once + 15-min TTL + high-entropy, which bounds blind guessing
--   regardless of the counter. See docs/RESTOFLOW_PRODUCT_COMPLETION_ROADMAP.md.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.

-- ============================================================================
-- 1. Centralized INTERIM constants (Q-009-aware; NOT frozen -- change here only).
-- ============================================================================
create or replace function app.pairing_max_failed_attempts()
  returns integer language sql immutable set search_path = ''
as $$ select 10 $$;  -- ASSUMPTION / Q-009

create or replace function app.pairing_lockout_duration()
  returns interval language sql immutable set search_path = ''
as $$ select interval '15 minutes' $$;  -- ASSUMPTION / Q-009

create or replace function app.device_session_max_age()
  returns interval language sql immutable set search_path = ''
as $$ select interval '7 days' $$;  -- ASSUMPTION / Q-009 (device-session max age)

comment on function app.pairing_max_failed_attempts() is
  'RF-118 INTERIM constant (ASSUMPTION / Q-009): consecutive failed device-pairing (redeem) attempts per caller principal before lockout. Centralized; change here only.';
comment on function app.pairing_lockout_duration() is
  'RF-118 INTERIM constant (ASSUMPTION / Q-009): device-pairing lockout duration after the cap is reached. Centralized; change here only.';
comment on function app.device_session_max_age() is
  'RF-118 INTERIM constant (ASSUMPTION / Q-009): device-session max age; redeem sets device_sessions.expires_at = now() + this, and restore rejects an expired session. Activates the RF-016-deferred column. Centralized; change here only. DURATION is NOT frozen (Q-009); only the mechanism is.';

revoke all on function app.pairing_max_failed_attempts() from public;
revoke all on function app.pairing_lockout_duration()     from public;
revoke all on function app.device_session_max_age()       from public;
grant execute on function app.pairing_max_failed_attempts() to authenticated;
grant execute on function app.pairing_lockout_duration()     to authenticated;
grant execute on function app.device_session_max_age()       to authenticated;

-- ============================================================================
-- 2. device_pairing_attempt_states -- durable pairing attempt/lockout state per
--    CALLER PRINCIPAL (auth.uid()). Pre-tenant: NO organization_id (an unpaired
--    attacker has no resolved tenant). Written ONLY by app.note_pairing_failure
--    / app.redeem_device_pairing (SECURITY DEFINER); authenticated reads only its
--    own row.
-- ============================================================================
create table device_pairing_attempt_states (
  auth_user_id         uuid        primary key,
  failed_attempt_count integer     not null default 0 check (failed_attempt_count >= 0),
  locked_until         timestamptz,
  last_failed_at       timestamptz,
  last_attempt_at      timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

comment on table device_pairing_attempt_states is
  'RF-118: durable device-pairing (redeem) attempt/lockout state per CALLER PRINCIPAL (auth.uid()). Pre-tenant by design -- NO organization_id (an unpaired attacker has no resolved tenant; the wrong code resolves to no scope). Written ONLY by the SECURITY DEFINER redeem RPC; authenticated has SELECT only, self-scoped. Thresholds are the centralized ASSUMPTION/Q-009 helpers. KNOWN LIMITATION: bypassable by re-anonymizing (auth.signInAnonymously) -> production needs IP/edge rate-limiting; this is defense-in-depth.';

create trigger device_pairing_attempt_states_set_updated_at
  before update on device_pairing_attempt_states for each row execute function app.set_updated_at();

-- RLS: enable + force, deny-by-default, self-scoped SELECT (satisfies the RF-019
-- default-deny presence detector: RLS enabled + forced + >= 1 policy). All writes
-- go through the SECURITY DEFINER RPC (owner is BYPASSRLS, so FORCE does not block
-- it); authenticated may read ONLY its own principal's row (its own attempt count
-- is not sensitive and leaks nothing cross-tenant).
alter table device_pairing_attempt_states enable row level security;
alter table device_pairing_attempt_states force  row level security;

create policy device_pairing_attempt_states_self on device_pairing_attempt_states
  for select to authenticated
  using (auth_user_id = auth.uid());

grant select on device_pairing_attempt_states to authenticated;

-- ============================================================================
-- 3. app.note_pairing_failure -- record ONE failed redeem for a principal;
--    lock at the cap. Trigger-free helper; called ONLY by redeem (definer).
-- ============================================================================
create or replace function app.note_pairing_failure(p_uid uuid)
  returns void
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_uid is null then
    return;  -- no principal to rate-limit (should not occur via the authenticated wrapper)
  end if;
  insert into public.device_pairing_attempt_states as s
      (auth_user_id, failed_attempt_count, last_failed_at, last_attempt_at)
    values (p_uid, 1, now(), now())
  on conflict (auth_user_id) do update
    set failed_attempt_count = s.failed_attempt_count + 1,
        last_failed_at = now(),
        last_attempt_at = now()
  returning failed_attempt_count into v_count;

  if v_count >= app.pairing_max_failed_attempts() then
    update public.device_pairing_attempt_states
      set locked_until = now() + app.pairing_lockout_duration()
      where auth_user_id = p_uid;
  end if;
end;
$$;

comment on function app.note_pairing_failure(uuid) is
  'RF-118: records one failed device-pairing redeem for a caller principal (auth.uid()); locks the principal at app.pairing_max_failed_attempts(). Called ONLY by app.redeem_device_pairing (SECURITY DEFINER). NOT granted to app roles.';

revoke all on function app.note_pairing_failure(uuid) from public;
-- intentionally NOT granted to authenticated: only the redeem RPC (definer) calls it.

-- ============================================================================
-- 4. app.redeem_device_pairing -- REPLACED. Base = the NEWEST body
--    (mvp_menu_item_images: RF-161 + auth_user_id = auth.uid() at mint, PRESERVED
--    unchanged). RF-118 adds:
--    (a) per-principal lockout check BEFORE the code hash/lookup;
--    (b) failed-attempt increment on every code-guess failure (returns commit);
--    (c) counter reset on success;
--    (d) minted device_sessions.expires_at = now() + app.device_session_max_age().
--    Everything else is byte-for-byte the current logic (scope server-derived,
--    consume-once, prior-session revoke, hash-only token, auth_user_id binding,
--    human-only audit).
-- ============================================================================
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
  v_actor      uuid := app.current_app_user_id();  -- null for an anonymous device (audit only)
  v_uid        uuid := auth.uid();                  -- RF-118: caller principal for the lockout
  v_locked     timestamptz;                         -- RF-118
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

  -- RF-118: per-principal brute-force lockout, checked BEFORE the expensive code
  -- hash + pairing lookup. A locked caller gets a SAFE generic 'locked' error
  -- (rate-limited != code exists), and no code lookup runs.
  if v_uid is not null then
    select s.locked_until into v_locked
      from public.device_pairing_attempt_states s
      where s.auth_user_id = v_uid;
    if v_locked is not null and v_locked > now() then
      return jsonb_build_object('ok', false, 'error', 'locked', 'entity', 'device_pairing');
    end if;
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
    perform app.note_pairing_failure(v_uid);  -- RF-118
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if v_expires is not null and v_expires <= now() then
    perform app.note_pairing_failure(v_uid);  -- RF-118
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
    perform app.note_pairing_failure(v_uid);  -- RF-118
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if v_dtype <> p_device_type then
    perform app.note_pairing_failure(v_uid);  -- RF-118
    return jsonb_build_object('ok', false, 'error', 'wrong_type', 'entity', 'device_pairing');
  end if;

  -- consume the code + activate the pairing (guarded; race-safe one-time redemption).
  update public.device_pairings
     set status = 'active', paired_at = now()
     where id = v_pairing and status = 'code_issued';
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    perform app.note_pairing_failure(v_uid);  -- RF-118
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;

  -- hygiene: one active session per device -> revoke any prior live sessions.
  update public.device_sessions
     set is_active = false, revoked_at = now()
     where device_id = v_device and revoked_at is null;

  -- mint the session: store ONLY the hash; return the raw token ONCE.
  -- MVP (menu/media sprint): also record auth_user_id = auth.uid() -- the storage
  -- device-read policy binding, PRESERVED here unchanged from mvp_menu_item_images
  -- (this migration REPLACES that newest redeem body; v_uid is that same auth.uid()).
  -- RF-118: additionally bound the session with expires_at = now() + the max age.
  v_token      := replace(gen_random_uuid()::text, '-', '');
  v_token_hash := app.hash_provisioning_secret(v_token);
  insert into public.device_sessions
    (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, auth_user_id, expires_at)
  values (v_session, v_org, v_rest, v_branch, v_device, v_pairing, v_token_hash, true,
          v_uid, now() + app.device_session_max_age());

  -- RF-118: a successful redemption clears the caller's failure counter.
  if v_uid is not null then
    delete from public.device_pairing_attempt_states where auth_user_id = v_uid;
  end if;

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
  'RF-161 + RF-118: DEVICE-ORIGINATED code redemption. Authorized by the one-time enrollment code (hash), NOT membership; scope is server-derived from the pairing (no cross-org/branch injection). RF-118: per-principal (auth.uid()) brute-force lockout checked BEFORE the code lookup (safe generic ''locked'' error), failed-attempt increment on each code-guess failure, counter reset on success, and the minted device_sessions.expires_at = now() + app.device_session_max_age(). Consumes the code (code_issued -> active), revokes prior device sessions, mints a new session (hash stored; raw token returned ONCE). SECURITY DEFINER, search_path locked. authenticated only (anonymous devices qualify). KNOWN LIMITATION: the per-principal lockout is bypassable by re-anonymizing -> production needs IP/edge rate-limiting.';

-- Re-issue grants (create-or-replace preserves ACLs, but re-assert per house pattern).
revoke all on function app.redeem_device_pairing(text, text)    from public;
grant execute on function app.redeem_device_pairing(text, text) to authenticated;

-- ============================================================================
-- 5. app.restore_device_session -- REPLACED (newest rebind body + RF-118 expiry):
--    reject a session past its expires_at (fail-closed invalid_session). Activates
--    the RF-016-deferred device_sessions.expires_at (a NULL expires_at -- pre-RF-118
--    rows -- is still accepted, so this is backward compatible).
-- ============================================================================
-- VOLATILE (NOT stable): the MVP POS-image fix re-binds auth_user_id on success,
-- so this migration REPLACES the mvp_pos_image_restore_rebind body (rebind PRESERVED
-- unchanged) and adds ONLY the RF-118 expires_at gate.
create or replace function app.restore_device_session(
  p_device_id     uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql
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
  -- pre-existing gap tracked for the human sign-off (ADR RF-161 section 7); this closes the
  -- redeem/restore asymmetry introduced there.
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
      and (ds.expires_at is null or ds.expires_at > now())  -- RF-118: reject an expired session
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_session');
  end if;
  -- MVP (POS image fix), PRESERVED: re-bind the storage-read principal to the
  -- CURRENT (fresh-per-launch) anonymous auth principal. Token proof succeeded
  -- above; the binding is ONLY the menu-image read-policy hook (never a credential).
  -- Skipped when there is no authenticated principal (e.g. direct DB calls).
  if auth.uid() is not null then
    update public.device_sessions
       set auth_user_id = auth.uid()
     where id = v_sid
       and auth_user_id is distinct from auth.uid();
  end if;
  return jsonb_build_object('ok', true, 'entity', 'device_session',
    'device_session_id', v_sid, 'organization_id', v_org, 'restaurant_id', v_rest,
    'branch_id', v_branch, 'device_id', p_device_id, 'device_type', v_dtype);
end;
$$;

comment on function app.restore_device_session(uuid, text) is
  'RF-161 + MVP(POS image fix) + RF-118: token-proven device-session restore. Returns the live device_session_id + context iff the raw token hashes to an ACTIVE, non-revoked, NON-EXPIRED (RF-118: expires_at > now(), or NULL for pre-RF-118 rows) session on an ACTIVE pairing for the device; otherwise invalid_session (fail closed). On success re-binds device_sessions.auth_user_id = auth.uid() (MVP menu-image storage policy hook; VOLATILE). NEVER returns a token. NOTE: expiry bites at restore/launch, not mid-session (an already-restored in-memory handle keeps working until the next launch; the PIN-session window + client inactivity policy bound within-session staleness).';

-- Re-issue the exact grants (house pattern for recreated functions; the public
-- wrapper public.restore_device_session is untouched and keeps delegating).
revoke all on function app.restore_device_session(uuid, text) from public;
grant execute on function app.restore_device_session(uuid, text) to authenticated;

-- NOTE: the public.* SECURITY INVOKER wrappers (RF-161) call app.redeem_device_pairing /
-- app.restore_device_session by signature and are UNCHANGED; the create-or-replace above
-- keeps them valid. Grants are unchanged (authenticated only). Not re-declared here.

-- ============================================================================
-- DOWN (manual) -- Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown (restores the RF-161 bodies):
-- ----------------------------------------------------------------------------
-- drop function if exists app.note_pairing_failure(uuid);
-- drop policy if exists device_pairing_attempt_states_self on device_pairing_attempt_states;
-- drop table if exists device_pairing_attempt_states;
-- drop function if exists app.device_session_max_age();
-- drop function if exists app.pairing_lockout_duration();
-- drop function if exists app.pairing_max_failed_attempts();
-- -- then re-apply the RF-161 app.redeem_device_pairing / app.restore_device_session bodies.
-- ============================================================================
