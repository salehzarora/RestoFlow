-- ============================================================================
-- RF-139 — PIN session audit events (started + rate-limited failed-attempt)
-- ============================================================================
-- Resolves M7 contract drift D3 (docs/M7_BACKEND_CONTRACT_NOTES.md §3): the
-- API_CONTRACT §4.13/§4.21 promise that app.start_pin_session emits a
-- `pin_session.started` audit event on success and rate-limited failed-attempt
-- events (DECISION D-013), but the RF-051 implementation emitted none.
--
-- This is additive and FORWARD-ONLY: it `create or replace`s app.start_pin_session
-- with the SAME signature, return type, grants, and RETURN CONTRACT (wrong PIN =>
-- NULL; locked/structural => 42501; success => the pin_session uuid; idempotent
-- replay => the same uuid). The ONLY behavioural change is two append-only audit
-- writes into RF-017 audit_events:
--
--   * pin_session.started — written on a genuinely NEW session, AFTER the
--     new-session insert and AFTER the idempotency-replay early return, so an
--     idempotent replay (which returns the existing session) NEVER double-audits.
--   * pin_session.failed  — written on the wrong-verifier path, which RETURNS NULL
--     (does NOT raise) so the row persists; it carries failed_attempt_count and the
--     lock state (locked / locked_until) when the attempt reaches the cap.
--
-- WHY ONLY THESE TWO PATHS
--   app.start_pin_session runs in a single-statement (PostgREST RPC) transaction.
--   The locked / structural / revoked rejections RAISE SQLSTATE 42501; an audit
--   INSERT issued before a RAISE is rolled back together with the rest of the
--   statement (and, per RF-051, the wrong-verifier path deliberately RETURNS NULL
--   precisely so its attempt-counter increment survives). The contract's
--   "failed-attempt events" map to WRONG PIN attempts — exactly the auditable
--   (non-raising) failure path. Precondition rejections that raise are not "failed
--   PIN attempts" and are not in-transaction auditable without breaking the
--   counter/return contract; auditing them is left as a forward item (it needs an
--   autonomous-transaction / out-of-band writer — out of scope here).
--
-- RATE-LIMITED BY CONSTRUCTION
--   At most app.pin_max_failed_attempts() pin_session.failed rows are written per
--   lockout window per (employee, device): once the cap locks the pair, further
--   attempts are rejected (42501) BEFORE reaching the verifier/audit path.
--
-- SECURITY / INVARIANTS
--   * The PIN and the credential verifier are NEVER recorded (D-006,
--     SECURITY_AND_THREAT_MODEL); only non-sensitive operational metadata.
--   * No money / no _minor fields are involved (D-007 — money columns untouched).
--   * Append-only audit trail via RF-017 (D-013): the SECURITY DEFINER RPC, owned
--     by the migration runner, inserts directly (the same path RF-053/RF-056 use);
--     the RF-017 trigger blocks only UPDATE/DELETE/TRUNCATE, never INSERT.
--   * Actor is always present (audit_events_actor_present): the employee profile is
--     always recorded; the resolved app_user (nullable for PIN-only staff) too.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown = `create or
-- replace` app.start_pin_session back to the RF-051 body (no audit writes).
-- ============================================================================

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
  v_locked_set    timestamptz;   -- RF-139: locked_until actually set on the capping failure (NULL otherwise)
  v_existing      uuid;
  v_new_id        uuid;
  v_expires_at    timestamptz;   -- RF-139: the new session's authoritative expiry (audited, never recomputed)
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
          and device_id = v_device_id
        returning locked_until into v_locked_set;   -- RF-139: capture the lock for the audit
    end if;

    -- RF-139 (API_CONTRACT §4.13/§4.21, DECISION D-013): audit the FAILED PIN
    -- attempt. This path RETURNS NULL (does NOT raise), so the row persists;
    -- raising would roll back both the attempt counter AND this audit. The PIN /
    -- verifier is NEVER recorded — only the attempt count and lock state. Bounded
    -- (rate-limited) to <= app.pin_max_failed_attempts() rows per lockout window
    -- per (employee, device), since a locked pair is rejected (42501) before here.
    insert into public.audit_events
        (organization_id, restaurant_id, branch_id,
         actor_app_user_id, actor_employee_profile_id, device_id,
         action, reason, old_values, new_values)
      values (v_ds_org, v_ds_rest, v_ds_branch,
              v_emp_appuser, p_employee_profile_id, v_device_id,
              'pin_session.failed', null, null,
              jsonb_build_object(
                'device_session_id',     p_device_session_id,
                'resolved_membership_id', v_membership_id,
                'failed_attempt_count',  v_count,
                'locked',                (v_locked_set is not null),
                'locked_until',          v_locked_set));

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
      return v_existing;   -- idempotent replay of the SAME validated operation (RF-139: NOT re-audited)
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
    returning id, expires_at into v_new_id, v_expires_at;

  -- RF-139 (API_CONTRACT §4.13/§4.21, DECISION D-013): audit the SUCCESSFUL
  -- PIN-session establishment. Placed AFTER the new-session insert and AFTER the
  -- idempotency-replay early return above, so an idempotent replay NEVER
  -- double-audits. The PIN / verifier is NEVER recorded.
  insert into public.audit_events
      (organization_id, restaurant_id, branch_id,
       actor_app_user_id, actor_employee_profile_id, device_id,
       action, reason, old_values, new_values)
    values (v_ds_org, v_ds_rest, v_ds_branch,
            v_emp_appuser, p_employee_profile_id, v_device_id,
            'pin_session.started', null, null,
            jsonb_build_object(
              'pin_session_id',         v_new_id,
              'device_session_id',      p_device_session_id,
              'resolved_membership_id', v_membership_id,
              'expires_at',             v_expires_at,
              'idempotent_replay',      false));

  return v_new_id;
end;
$$;

comment on function app.start_pin_session(uuid, uuid, text, text) is
  'RF-051 (API_CONTRACT §4.13, D-006/D-011) SECURITY DEFINER RPC, audited under RF-139 (D-013): establishes a PIN session on a paired+authorized device. Validates device session + pairing, resolves membership (DOMAIN_MODEL §1.2; refuses ambiguous/empty), enforces lockout, verifies via the interim seam. Wrong verifier => persist failed-attempt increment + write a pin_session.failed audit event + RETURN NULL (raising would roll the increment AND the audit back); locked/structural => 42501 (NOT in-transaction auditable; left as a forward item). On a genuinely new session writes a pin_session.started audit event AFTER the insert and AFTER the idempotency-replay early return, so a replay never double-audits. Failed-attempt audit is rate-limited by construction (<= app.pin_max_failed_attempts() per lockout window per employee+device). expires_at = now() + offline window (Q-009 ASSUMPTION). No plaintext PIN; the verifier is NEVER logged or audited.';

revoke all on function app.start_pin_session(uuid, uuid, text, text) from public;
grant execute on function app.start_pin_session(uuid, uuid, text, text) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. To revert: `create or replace function
-- app.start_pin_session(uuid, uuid, text, text)` with the RF-051 body (the two
-- audit_events inserts removed; signature/grants unchanged).
-- ============================================================================
