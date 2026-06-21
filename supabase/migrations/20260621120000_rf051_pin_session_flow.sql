-- ============================================================================
-- RF-051 — PIN session flow on a paired device: attempt-limit/lockout, offline
--          validity, membership resolution, and the start_pin_session RPC
-- ============================================================================
-- Builds on RF-016 (devices/device_pairings/device_sessions/pin_sessions + the
-- app.enforce_pin_session_backing guard) and RF-015 (employee_profiles,
-- memberships, resolver/scope helpers). Additive and FORWARD-ONLY: it NEVER edits
-- a prior migration.
--
-- WHAT THIS DOES
--   1. pin_attempt_states — a durable per-(employee + device) attempt/lockout
--      table (SECURITY §9: the PIN is locked "on that device"). Failed PIN
--      attempts precede session creation, so this state CANNOT live on
--      pin_sessions (no row exists yet during failures).
--   2. Centralized ASSUMPTION/Q-009 constants (one helper each) — no scattered
--      literals: max failed attempts (5), lockout duration (15 min), offline
--      validity window (8 h).
--   3. A PIN verifier SEAM (app.verify_pin_credential) — interim only; no real
--      cryptography, no plaintext PIN, verifier never logged/stored.
--   4. app.start_pin_session(...) — the API_CONTRACT §4.13 SECURITY DEFINER RPC:
--      validates the device session + pairing, resolves membership (DOMAIN_MODEL
--      §1.2 precedence), enforces lockout, verifies the PIN via the seam, and on
--      success issues a short-lived pin_session. Idempotent on local_operation_id.
--   5. Direct-insert bypass prevention — INSERT on pin_sessions is REVOKED from
--      `authenticated`, so a session can be established ONLY through the RPC
--      (D-011: PIN-session establishment is exposed only as a SECURITY DEFINER
--      RPC). The SECURITY DEFINER RPC (owned by the migration runner) still inserts.
--   6. app.enforce_pin_not_locked — defense-in-depth: a BEFORE trigger that
--      rejects an ACTIVE pin_session for a currently-locked (employee, device),
--      regardless of insert path.
--   7. app.is_pin_session_valid — the offline-validity MECHANISM: an expired
--      expires_at => invalid (forces re-auth). The window DURATION is Q-009.
--
-- DECISIONS / OPEN QUESTIONS
--   * D-004 per-person identity / no shared accounts; D-005 #6 PIN session.
--   * D-006 PIN fast session only on a paired+authorized device.
--   * D-011 sensitive mutations (incl. PIN-session establishment) ONLY via a
--     SECURITY DEFINER RPC; no service-role in clients.
--   * D-012 four layers; RLS enabled+forced + deny-by-default on the new table.
--   * D-022 idempotency key = device + local_operation_id (here: device session +
--     local_operation_id, which pins the device).
--   * D-027 Accepted-Open-with-safe-interim (Q-009 below).
--   * Q-009 (Accepted Open): offline PIN/permission validity window. INTERIM
--     ASSUMPTION used here (8 h), centralized + clearly marked; the MECHANISM is
--     implemented + tested, the DURATION is not frozen. Server reconnect
--     re-validation / revocation sweep is RF-061 (out of scope).
--   * ASSUMPTION (no open question governs these): max failed attempts = 5,
--     lockout duration = 15 min. Centralized + marked; changeable in one place.
--   * RISK R-003 (CRITICAL) tenant isolation; RISK R-007 offline staleness.
--
-- SECURITY NOTES
--   * NO plaintext PIN is ever accepted, stored, or logged. The RPC takes a
--     credential VERIFIER (not a typed PIN); the seam compares references only.
--   * Real salted-hash verification + credential provisioning + client-side
--     PIN->verifier derivation are a DEFERRED, NOT-yet-frozen contract — the seam
--     is interim/dev only and MUST NOT be treated as production cryptography.
--
-- OUT OF SCOPE (other tickets): RF-052+ business RPCs; RF-056/057 sync; RF-059
--   full per-command role matrix + the rest of the pin_sessions write lockdown;
--   RF-060 platform-admin; RF-061 revocation sweep / reconnect re-validation; any
--   UI / Dart / config / remote / secrets / service-role.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Centralized interim constants (ASSUMPTION / Q-009). One helper each — never
--    inline the values in SQL/tests; reference these functions.
-- ----------------------------------------------------------------------------
create or replace function app.pin_max_failed_attempts()
  returns integer language sql immutable set search_path = ''
as $$ select 5 $$;  -- ASSUMPTION / Q-009 (no open question governs the count)

create or replace function app.pin_lockout_duration()
  returns interval language sql immutable set search_path = ''
as $$ select interval '15 minutes' $$;  -- ASSUMPTION / Q-009

create or replace function app.pin_session_offline_window()
  returns interval language sql immutable set search_path = ''
as $$ select interval '8 hours' $$;  -- ASSUMPTION / Q-009 (offline validity window)

comment on function app.pin_max_failed_attempts()   is 'RF-051 INTERIM constant (ASSUMPTION / Q-009): consecutive failed PIN attempts before lockout. Centralized; change here only.';
comment on function app.pin_lockout_duration()       is 'RF-051 INTERIM constant (ASSUMPTION / Q-009): PIN lockout duration after the cap is reached. Centralized; change here only.';
comment on function app.pin_session_offline_window() is 'RF-051 INTERIM constant (ASSUMPTION / Q-009): PIN session offline/idle validity window used to set pin_sessions.expires_at. Centralized; change here only. The DURATION is NOT frozen (Q-009); only the mechanism is.';

revoke all on function app.pin_max_failed_attempts()   from public;
revoke all on function app.pin_lockout_duration()       from public;
revoke all on function app.pin_session_offline_window() from public;
grant execute on function app.pin_max_failed_attempts()   to authenticated;
grant execute on function app.pin_lockout_duration()       to authenticated;
grant execute on function app.pin_session_offline_window() to authenticated;

-- ----------------------------------------------------------------------------
-- 2. pin_attempt_states — durable attempt/lockout state per (employee + device).
--    Tenant + BRANCH scoped (D-001/D-002); cross-org/branch refs are structurally
--    impossible via composite same-org FKs (D-012 layer 4). Writes go ONLY through
--    the SECURITY DEFINER RPC (authenticated gets SELECT only).
-- ----------------------------------------------------------------------------
create table pin_attempt_states (
  id                   uuid        not null default gen_random_uuid(),
  organization_id      uuid        not null references organizations (id) on delete restrict,
  restaurant_id        uuid        not null,
  branch_id            uuid        not null,
  employee_profile_id  uuid        not null,
  device_id            uuid        not null,
  failed_attempt_count integer     not null default 0 check (failed_attempt_count >= 0),
  locked_until         timestamptz,
  last_failed_at       timestamptz,
  last_attempt_at      timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  primary key (id),
  -- one attempt/lockout state row per employee+device (the ON CONFLICT target)
  unique (organization_id, employee_profile_id, device_id),
  -- same-branch structural FKs (D-012 layer 4)
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references devices (organization_id, restaurant_id, branch_id, id) on delete restrict,
  -- employee must be in the SAME organization (structural)
  foreign key (organization_id, employee_profile_id)
    references employee_profiles (organization_id, id) on delete restrict
);

comment on table pin_attempt_states is
  'RF-051: durable PIN attempt/lockout state per (employee_profile + device) — SECURITY §9 "locked on that device". Failed attempts precede session creation, so this state cannot live on pin_sessions. Written ONLY by app.start_pin_session (SECURITY DEFINER); authenticated has SELECT only. Thresholds are centralized ASSUMPTION/Q-009 helpers.';

create index pin_attempt_states_branch_device_idx on pin_attempt_states (organization_id, restaurant_id, branch_id, device_id);
create index pin_attempt_states_branch_idx        on pin_attempt_states (organization_id, restaurant_id, branch_id);

create trigger pin_attempt_states_set_updated_at
  before update on pin_attempt_states for each row execute function app.set_updated_at();

-- RLS: enable + force, deny-by-default, membership/branch scoped (reuses the
-- RF-015 resolver/scope helpers UNCHANGED). Satisfies the RF-019 default-deny
-- presence detector (RLS enabled + forced + >= 1 policy).
alter table pin_attempt_states enable row level security;
alter table pin_attempt_states force  row level security;

create policy pin_attempt_states_scoped on pin_attempt_states
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

-- Least privilege: authenticated may READ (scoped) but NEVER directly mutate the
-- lockout counter; all writes go through the SECURITY DEFINER RPC.
grant select on pin_attempt_states to authenticated;

-- ----------------------------------------------------------------------------
-- 3. PIN verifier SEAM (INTERIM / DEV ONLY — NOT production cryptography).
--    Compares the supplied verifier to employee_profiles.pin_credential_ref. The
--    real salted-hash verification, credential provisioning, and client-side
--    PIN->verifier derivation are a DEFERRED, not-yet-frozen contract. No
--    plaintext PIN is stored; the verifier is treated as an opaque reference and
--    is NEVER logged. SECURITY DEFINER (reads RLS-protected employee_profiles).
-- ----------------------------------------------------------------------------
create or replace function app.verify_pin_credential(p_employee_profile_id uuid, p_pin_verifier text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- ASSUMPTION (interim seam): a non-null verifier that exactly matches the stored
  -- reference passes. Replace with real salted-hash verification when the PIN
  -- credential scheme is frozen (separate ticket). Never compare/return plaintext.
  select exists (
    select 1
    from public.employee_profiles ep
    where ep.id = p_employee_profile_id
      and ep.pin_credential_ref is not null
      and p_pin_verifier is not null
      and ep.pin_credential_ref = p_pin_verifier
  )
$$;

comment on function app.verify_pin_credential(uuid, text) is
  'RF-051 INTERIM SEAM (NOT production crypto): true iff the supplied verifier matches employee_profiles.pin_credential_ref. Real salted-hash verification + credential provisioning are DEFERRED/not-frozen. No plaintext PIN; verifier must never be logged.';

revoke all on function app.verify_pin_credential(uuid, text) from public;
-- intentionally NOT granted to authenticated: only the start_pin_session RPC (which
-- runs as the definer) calls it; clients never call the verifier directly.

-- ----------------------------------------------------------------------------
-- 4. Offline-validity MECHANISM. A pin_session is valid iff active, not ended,
--    and within its expires_at window. Expired => invalid (forces re-auth). The
--    DURATION is Q-009 (set via the centralized helper); only the MECHANISM here.
-- ----------------------------------------------------------------------------
create or replace function app.is_pin_session_valid(p_pin_session_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.pin_sessions ps
    where ps.id = p_pin_session_id
      and ps.is_active
      and ps.ended_at is null
      and (ps.expires_at is null or ps.expires_at > now())
  )
$$;

comment on function app.is_pin_session_valid(uuid) is
  'RF-051: offline-validity mechanism — true iff the pin_session is active, not ended, and within its expires_at window; an expired window => false (forces re-auth). The window DURATION is Q-009 (ASSUMPTION); only the mechanism is frozen here.';

revoke all on function app.is_pin_session_valid(uuid) from public;
grant execute on function app.is_pin_session_valid(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. Defense-in-depth lockout guard: an ACTIVE pin_session cannot be created for a
--    currently-locked (employee, device), on ANY insert/update path. Hardened
--    SECURITY DEFINER (reads RLS-protected device_sessions/pin_attempt_states;
--    search_path locked). Trigger-only; not granted to app roles.
-- ----------------------------------------------------------------------------
create or replace function app.enforce_pin_not_locked()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_device_id    uuid;
  v_locked_until timestamptz;
begin
  if NEW.is_active then
    select ds.device_id into v_device_id
      from public.device_sessions ds
      where ds.id = NEW.device_session_id;

    select pas.locked_until into v_locked_until
      from public.pin_attempt_states pas
      where pas.organization_id     = NEW.organization_id
        and pas.employee_profile_id = NEW.employee_profile_id
        and pas.device_id           = v_device_id;

    if v_locked_until is not null and v_locked_until > now() then
      raise exception 'pin_session blocked: employee % is locked on device % until %',
        NEW.employee_profile_id, v_device_id, v_locked_until
        using errcode = '42501';
    end if;
  end if;
  return NEW;
end;
$$;

comment on function app.enforce_pin_not_locked() is
  'RF-051 defense-in-depth guard: rejects an ACTIVE pin_session for a currently-locked (employee, device) regardless of path (42501). Hardened SECURITY DEFINER. Complements the RF-016 backing guard.';

revoke all on function app.enforce_pin_not_locked() from public;

create trigger pin_sessions_enforce_not_locked
  before insert or update on pin_sessions
  for each row execute function app.enforce_pin_not_locked();

-- ----------------------------------------------------------------------------
-- 6. Idempotency surface (D-022). Additive nullable column + partial-unique index
--    on (org, device_session, local_operation_id). NULL allowed (RF-016-era rows
--    have none); the RPC returns the existing session on a repeated key.
-- ----------------------------------------------------------------------------
alter table pin_sessions add column local_operation_id text;

comment on column pin_sessions.local_operation_id is
  'RF-051: client local operation id for idempotent start_pin_session (D-022 key = device session + local_operation_id). Nullable; partial-unique while not null.';

create unique index pin_sessions_idem_key
  on pin_sessions (organization_id, device_session_id, local_operation_id)
  where local_operation_id is not null;

-- ----------------------------------------------------------------------------
-- 7. Direct-insert bypass prevention. After RF-051 a PIN session may be
--    established ONLY through app.start_pin_session (D-011). REVOKE INSERT on
--    pin_sessions from authenticated; the SECURITY DEFINER RPC (owned by the
--    migration runner) retains insert. SELECT/UPDATE/DELETE are unchanged here —
--    the full write lockdown/role matrix is RF-059. (RF-016 tests insert
--    pin_sessions as the connection role / expect 42501 on the cross-scope
--    authenticated insert, so this does not break them.)
-- ----------------------------------------------------------------------------
revoke insert on pin_sessions from authenticated;

-- ----------------------------------------------------------------------------
-- 8. start_pin_session — the API_CONTRACT §4.13 SECURITY DEFINER RPC.
--    NOTE on the wrong-PIN path: raising would roll back the attempt-counter
--    increment (single-statement transaction), making lockout non-functional.
--    Therefore a WRONG verifier PERSISTS the increment and RETURNS NULL (no
--    session, no raise); LOCKED and structural/precondition failures RAISE 42501.
-- ----------------------------------------------------------------------------
create or replace function app.start_pin_session(
  p_device_session_id   uuid,
  p_employee_profile_id uuid,
  p_pin_verifier        text,
  p_local_operation_id  text default null
)
  returns uuid
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_ds_org        uuid;
  v_ds_rest       uuid;
  v_ds_branch     uuid;
  v_device_id     uuid;
  v_ds_active     boolean;
  v_ds_revoked    timestamptz;
  v_pairing_stat  text;
  v_emp_org       uuid;
  v_emp_appuser   uuid;
  v_emp_membership uuid;
  v_emp_status    text;
  v_membership_id uuid;
  v_m_org         uuid;
  v_m_rest        uuid;
  v_m_branch      uuid;
  v_m_status      text;
  v_m_deleted     timestamptz;
  v_count         integer;
  v_locked_until  timestamptz;
  v_existing      uuid;
  v_new_id        uuid;
begin
  -- RF051-B1: idempotency replay is DEFERRED to step 10 — AFTER full validation and
  -- a SUCCESSFUL verifier. It must never return an existing session before
  -- device/pairing/employee/membership/lockout/verifier are validated (otherwise a
  -- caller holding only device_session_id + local_operation_id could retrieve a
  -- session without the verifier, while locked, or after revocation).

  -- (1-4) validate device session: exists, active, not revoked, pairing active
  select ds.organization_id, ds.restaurant_id, ds.branch_id, ds.device_id,
         ds.is_active, ds.revoked_at, dp.status
    into v_ds_org, v_ds_rest, v_ds_branch, v_device_id, v_ds_active, v_ds_revoked, v_pairing_stat
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = p_device_session_id;
  if not found then
    raise exception 'start_pin_session: device session not found' using errcode = '42501';
  end if;
  if not (v_ds_active and v_ds_revoked is null and v_pairing_stat = 'active') then
    raise exception 'start_pin_session: device session is not active/paired' using errcode = '42501';
  end if;

  -- (5) resolve employee profile (same org as the device session, active)
  select ep.organization_id, ep.app_user_id, ep.membership_id, ep.employment_status
    into v_emp_org, v_emp_appuser, v_emp_membership, v_emp_status
    from public.employee_profiles ep
    where ep.id = p_employee_profile_id;
  if not found then
    raise exception 'start_pin_session: employee profile not found' using errcode = '42501';
  end if;
  if v_emp_org <> v_ds_org then
    raise exception 'start_pin_session: employee not in the device session organization' using errcode = '42501';
  end if;
  if v_emp_status <> 'active' then
    raise exception 'start_pin_session: employee profile is not active' using errcode = '42501';
  end if;

  -- (6) membership resolution (DOMAIN_MODEL §1.2 precedence)
  if v_emp_membership is not null then
    v_membership_id := v_emp_membership;                      -- (1) authoritative
  else
    if v_emp_appuser is null then
      raise exception 'start_pin_session: membership resolution empty (no membership_id and no app_user)' using errcode = '42501';
    end if;
    select count(*) into v_count                              -- (2) unambiguous fallback
      from public.memberships m
      where m.app_user_id = v_emp_appuser
        and m.organization_id = v_emp_org
        and m.status = 'active'
        and m.deleted_at is null;
    if v_count = 0 then
      raise exception 'start_pin_session: membership resolution empty (no active membership)' using errcode = '42501';
    end if;
    if v_count > 1 then
      raise exception 'start_pin_session: membership resolution ambiguous (% active memberships)', v_count using errcode = '42501';
    end if;
    -- exactly one active membership: fetch it
    select m.id into v_membership_id
      from public.memberships m
      where m.app_user_id = v_emp_appuser
        and m.organization_id = v_emp_org
        and m.status = 'active'
        and m.deleted_at is null;
  end if;

  -- the resolved membership must be active and cover the device session scope
  select m.organization_id, m.restaurant_id, m.branch_id, m.status, m.deleted_at
    into v_m_org, v_m_rest, v_m_branch, v_m_status, v_m_deleted
    from public.memberships m
    where m.id = v_membership_id;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'start_pin_session: resolved membership is not active' using errcode = '42501';
  end if;
  if v_m_org <> v_ds_org
     or not (v_m_rest is null or v_m_rest = v_ds_rest)
     or not (v_m_branch is null or v_m_branch = v_ds_branch) then
    raise exception 'start_pin_session: resolved membership does not cover the device session scope' using errcode = '42501';
  end if;

  -- (7-8) lockout check for (employee, device); locked => raise
  select pas.locked_until into v_locked_until
    from public.pin_attempt_states pas
    where pas.organization_id = v_ds_org
      and pas.employee_profile_id = p_employee_profile_id
      and pas.device_id = v_device_id;
  if v_locked_until is not null and v_locked_until > now() then
    raise exception 'start_pin_session: PIN locked on this device until %', v_locked_until using errcode = '42501';
  end if;

  -- (9-10) verify PIN via the seam. WRONG verifier => persist increment + lock at
  -- the cap, then RETURN NULL (no raise, so the counter survives; no session).
  if not app.verify_pin_credential(p_employee_profile_id, p_pin_verifier) then
    insert into public.pin_attempt_states as pas
        (organization_id, restaurant_id, branch_id, employee_profile_id, device_id,
         failed_attempt_count, last_failed_at, last_attempt_at)
      values (v_ds_org, v_ds_rest, v_ds_branch, p_employee_profile_id, v_device_id, 1, now(), now())
      on conflict (organization_id, employee_profile_id, device_id) do update
        set failed_attempt_count = pas.failed_attempt_count + 1,
            last_failed_at = now(),
            last_attempt_at = now()
      returning pas.failed_attempt_count into v_count;

    if v_count >= app.pin_max_failed_attempts() then
      update public.pin_attempt_states
        set locked_until = now() + app.pin_lockout_duration()
        where organization_id = v_ds_org
          and employee_profile_id = p_employee_profile_id
          and device_id = v_device_id;
    end if;

    return null;  -- invalid verifier: counter persisted, NO pin_session created
  end if;

  -- (10) verifier SUCCEEDED. Idempotency replay is checked ONLY now (RF051-B1),
  -- scoped to the FULLY VALIDATED operation context: organization + device session
  -- + employee + resolved membership + local_operation_id. A replay therefore can
  -- never bypass the checks above, and — being scoped by employee + resolved
  -- membership — can never return another user's session even though the
  -- partial-unique index is weaker. (A wrong verifier already returned NULL above.)
  if p_local_operation_id is not null then
    select ps.id into v_existing
      from public.pin_sessions ps
      where ps.organization_id        = v_ds_org
        and ps.device_session_id      = p_device_session_id
        and ps.employee_profile_id    = p_employee_profile_id
        and ps.resolved_membership_id = v_membership_id
        and ps.local_operation_id     = p_local_operation_id
      limit 1;
    if v_existing is not null then
      return v_existing;   -- idempotent replay of the SAME validated operation
    end if;
  end if;

  -- (11) new session: reset attempt state, then issue the short-lived session
  insert into public.pin_attempt_states as pas
      (organization_id, restaurant_id, branch_id, employee_profile_id, device_id,
       failed_attempt_count, locked_until, last_attempt_at)
    values (v_ds_org, v_ds_rest, v_ds_branch, p_employee_profile_id, v_device_id, 0, null, now())
    on conflict (organization_id, employee_profile_id, device_id) do update
      set failed_attempt_count = 0,
          locked_until = null,
          last_attempt_at = now();

  insert into public.pin_sessions
      (organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id,
       resolved_membership_id, local_operation_id, is_active, expires_at)
    values (v_ds_org, v_ds_rest, v_ds_branch, p_device_session_id, p_employee_profile_id,
            v_membership_id, p_local_operation_id, true, now() + app.pin_session_offline_window())
    returning id into v_new_id;

  return v_new_id;
end;
$$;

comment on function app.start_pin_session(uuid, uuid, text, text) is
  'RF-051 (API_CONTRACT §4.13, D-006/D-011) SECURITY DEFINER RPC: establishes a PIN session on a paired+authorized device. Validates device session + pairing, resolves membership (DOMAIN_MODEL §1.2; refuses ambiguous/empty), enforces lockout, verifies via the interim seam. Wrong verifier => persist failed-attempt increment + RETURN NULL (raising would roll the increment back); locked/structural => 42501. expires_at = now() + offline window (Q-009 ASSUMPTION). RF051-B1: idempotency replay happens ONLY after full validation + a successful verifier, scoped to (org, device session, employee, resolved membership, local_operation_id) so it never bypasses verification/lockout/revocation and never returns another user''s session. No plaintext PIN; verifier never logged.';

revoke all on function app.start_pin_session(uuid, uuid, text, text) from public;
grant execute on function app.start_pin_session(uuid, uuid, text, text) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop function if exists app.start_pin_session(uuid, uuid, text, text);
-- grant insert on pin_sessions to authenticated;  -- restore RF-016 grant
-- drop index if exists public.pin_sessions_idem_key;
-- alter table pin_sessions drop column if exists local_operation_id;
-- drop trigger if exists pin_sessions_enforce_not_locked on pin_sessions;
-- drop function if exists app.enforce_pin_not_locked();
-- drop function if exists app.is_pin_session_valid(uuid);
-- drop function if exists app.verify_pin_credential(uuid, text);
-- drop table if exists pin_attempt_states;
-- drop function if exists app.pin_session_offline_window();
-- drop function if exists app.pin_lockout_duration();
-- drop function if exists app.pin_max_failed_attempts();
-- ============================================================================
