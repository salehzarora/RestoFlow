-- ============================================================================
-- MVP -- Staff + PIN provisioning foundation: server-side bcrypt PIN verifier,
--        staff creation, PIN set/rotate, staff lists (management + device).
-- ============================================================================
-- Replaces the RF-051 INTERIM dev-only PIN verifier seam with PRODUCTION
-- server-side bcrypt verification, and adds the smallest provisioning surface
-- the visible MVP needs: create a PIN-only staff operator, set/rotate their
-- PIN, list staff for the dashboard, and list PIN-pad candidates for a
-- token-proven device. Additive and FORWARD-ONLY: it NEVER edits a prior
-- migration file (functions are evolved via `create or replace`, the
-- RF-139-established pattern).
--
-- DESIGN DECISION -- typed PIN over TLS + SERVER-SIDE bcrypt (supersedes the
-- RF-051 header note "client-side PIN->verifier derivation is deferred" FOR
-- THE MVP):
--   * app.start_pin_session's p_pin_verifier parameter now carries the
--     operator's TYPED PIN, sent over TLS to the RPC. Verification hashes it
--     SERVER-SIDE with bcrypt (extensions.crypt against the stored
--     employee_profiles.pin_credential_ref, which is a bcrypt hash written by
--     app.set_employee_pin via extensions.gen_salt('bf')).
--   * The PIN is NEVER stored, logged, audited, or fingerprinted in plaintext
--     anywhere (SECURITY_AND_THREAT_MODEL §9: salted hash, never plaintext).
--   * Any NON-bcrypt pin_credential_ref (the legacy interim plain-equality
--     refs) now ALWAYS FAILS verification (fail-closed): the interim dev-only
--     equality seam is dead. Legacy rows must be re-provisioned via
--     app.set_employee_pin.
--
-- SYNTHETIC IDENTIFIER EMAIL (D-004 preserved):
--   PIN-only operators (cashier/kitchen staff on a PIN pad) have NO login
--   account and no real email; app_users.email is NOT NULL UNIQUE, so
--   app.create_staff_member mints a synthetic, unique, lowercase identifier
--   'staff-<uuid-hex>@pin.restoflow.invalid'. The RFC-2606 reserved `.invalid`
--   TLD guarantees it can never be routed or registered; it is ONLY an
--   identifier. Each operator still gets their OWN app_user + membership +
--   employee_profile -- per-person identity, no shared accounts (D-004; the
--   six identity concepts of D-005 stay distinct).
--
-- DECISIONS / OPEN QUESTIONS
--   * D-004 per-person identity; roles are membership-scoped, never global.
--   * D-006 PIN fast session only on a paired+authorized device: the device
--     staff list is token-proven exactly like app.restore_device_session
--     (RF-161) -- a device holds ZERO tenant authority beyond its session.
--   * D-011 sensitive mutations ONLY via SECURITY DEFINER RPCs; grants to
--     `authenticated` only (anonymous authenticated devices qualify for the
--     device list); never anon/service_role; search_path locked to ''.
--   * D-013 append-only audit: every mutation writes an audit row via
--     app.management_audit (RF-112); role denials write audited
--     `*_denied` rows; NO row ever carries PIN material.
--   * D-033 GUC-free management authorization (RF-112 pattern): caller =
--     app.current_app_user_id(); authority = app.actor_rank_in_scope over the
--     target scope; rank >= manager(2) manages; staff creation additionally
--     requires the caller to STRICTLY OUTRANK the assigned role (mirrors
--     grant_membership); rank 0 (non-member/cross-org/out-of-scope) => 42501.
--   * Q-009 (Accepted Open): the offline validity window / lockout constants
--     are UNCHANGED (RF-051 centralized helpers); setting a fresh PIN resets
--     the pin_attempt_states counters/lockout for that employee (a manager
--     rotating a PIN is the recovery path for a locked-out operator).
--   * RISK R-003 (CRITICAL) tenant isolation; RISK R-007 offline staleness.
--
-- IDEMPOTENCY: the mutating RPCs reuse the RF-112 management_request_results
-- ledger (per-actor client_request_id; check before authorization, claim
-- before mutation, conflicting reuse => 42501). The set_employee_pin
-- fingerprint hashes a SHA-256 DIGEST of the PIN (never the raw PIN), and no
-- stored result contains the PIN or the bcrypt hash.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PRODUCTION PIN VERIFIER -- replaces the RF-051 interim equality seam.
--    True iff the stored ref is a bcrypt hash ('$2...') AND bcrypt(p_pin, ref)
--    matches. A NULL ref, a NULL pin, or ANY non-bcrypt (legacy interim) ref
--    fails closed. Same signature/volatility/posture as RF-051; `create or
--    replace` preserves the existing ACL (internal: revoked from public, NOT
--    granted to authenticated -- only the SECURITY DEFINER RPCs call it).
-- ----------------------------------------------------------------------------
create or replace function app.verify_pin_credential(p_employee_profile_id uuid, p_pin_verifier text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- PRODUCTION (supersedes the RF-051 interim seam): p_pin_verifier is the
  -- operator's typed PIN (sent over TLS); verification is server-side bcrypt.
  -- The '$2%' guard makes every legacy plain-equality ref fail closed AND
  -- prevents extensions.crypt from being fed a non-bcrypt salt.
  select exists (
    select 1
    from public.employee_profiles ep
    where ep.id = p_employee_profile_id
      and ep.pin_credential_ref is not null
      and ep.pin_credential_ref like '$2%'
      and p_pin_verifier is not null
      and extensions.crypt(p_pin_verifier, ep.pin_credential_ref) = ep.pin_credential_ref
  )
$$;

comment on function app.verify_pin_credential(uuid, text) is
  'MVP staff/PIN provisioning (PRODUCTION; supersedes the RF-051 interim seam): true iff employee_profiles.pin_credential_ref is a bcrypt hash and extensions.crypt(typed PIN, ref) = ref. The typed PIN travels over TLS and is hashed SERVER-SIDE (the RF-051 "client-side derivation deferred" note is superseded for the MVP). Any non-bcrypt (legacy interim) ref ALWAYS fails (fail-closed). No plaintext PIN is ever stored/logged; internal only (not granted to authenticated).';

-- keep the RF-051 exposure: internal only (no new grants).
revoke all on function app.verify_pin_credential(uuid, text) from public;

-- ----------------------------------------------------------------------------
-- 2. app.create_staff_member -- create a PIN-only staff operator in ONE
--    transaction: app_user (synthetic identifier email) + active membership +
--    employee_profile (no PIN yet). Manager+ covering the target scope, and
--    the caller must STRICTLY OUTRANK the assigned role (a manager can create
--    cashier/kitchen_staff but NOT another manager -- mirrors grant_membership).
-- ----------------------------------------------------------------------------
create or replace function app.create_staff_member(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_display_name      text,
  p_role              text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();
  v_rank       integer;
  v_name       text;
  v_fp         text;
  v_replay     jsonb;
  v_app_user   uuid := gen_random_uuid();
  v_membership uuid := gen_random_uuid();
  v_employee   uuid := gen_random_uuid();
  v_email      text;
  v_result     jsonb;
  v_new        jsonb;
begin
  -- (a) authentication + required input
  if v_actor is null then
    raise exception 'create_staff_member: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'create_staff_member: client_request_id is required' using errcode = '42501';
  end if;
  -- staff operators are branch-scoped (they work a PIN pad at a branch)
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'create_staff_member: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;

  -- (b) structural validation
  v_name := btrim(coalesce(p_display_name, ''));
  if length(v_name) = 0 then
    raise exception 'create_staff_member: display_name is required' using errcode = '42501';
  end if;
  -- only operator roles are creatable here (owners are onboarded/granted via
  -- create_organization / grant_membership, never as PIN-only staff).
  if p_role is null or p_role not in ('cashier', 'kitchen_staff', 'manager') then
    raise exception 'create_staff_member: role must be cashier, kitchen_staff or manager' using errcode = '42501';
  end if;
  -- target branch + parent restaurant must exist in the org AND be LIVE (RF-112 rule:
  -- never create authority on a dead scope).
  if not exists (
       select 1 from public.branches b
       join public.restaurants r on r.id = b.restaurant_id and r.organization_id = b.organization_id
       where b.id = p_branch_id and b.organization_id = p_organization_id
         and b.restaurant_id = p_restaurant_id and b.deleted_at is null and r.deleted_at is null) then
    raise exception 'create_staff_member: branch not found in organization/restaurant or scope is soft-deleted' using errcode = '42501';
  end if;

  -- (c) committed idempotent replay (before authorization -> true idempotency;
  --     mirrors grant_membership). Fingerprint carries NO secret (there is none here).
  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'branch', p_branch_id, 'display_name', v_name, 'role', p_role)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'create_staff_member', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (d) authorization (GUC-free + role-rank guard). 0 => no covering membership => 42501.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'create_staff_member: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  -- caller IS a covering member from here -> denials are audited permission_denied:
  -- rank >= manager required AND the caller must STRICTLY outrank the assigned role.
  if v_rank < 2 or v_rank <= app.role_rank(p_role) then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'staff.create_denied', null,
      jsonb_build_object('display_name', v_name, 'role', p_role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'employee_profile');
  end if;

  -- (e) claim idempotency BEFORE mutating (race-safe), then create the three rows + audit.
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'employee_profile',
                'employee_profile_id', v_employee, 'membership_id', v_membership,
                'app_user_id', v_app_user, 'role', p_role);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'create_staff_member', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- synthetic, unique, lowercase identifier email (RFC-2606 .invalid TLD): PIN-only
  -- operators have NO login account; this is ONLY an identifier (D-004 preserved --
  -- each operator is their own person/identity, never a shared account).
  v_email := 'staff-' || replace(gen_random_uuid()::text, '-', '') || '@pin.restoflow.invalid';

  insert into public.app_users (id, email, display_name, is_active)
  values (v_app_user, v_email, v_name, true);

  insert into public.memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, status)
  values (v_membership, v_app_user, p_organization_id, p_restaurant_id, p_branch_id, p_role, 'active');

  insert into public.employee_profiles
    (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id,
     display_name, employment_status, pin_credential_ref)
  values
    (v_employee, p_organization_id, p_restaurant_id, p_branch_id, v_app_user, v_membership,
     v_name, 'active', null);  -- NO PIN yet: provisioned separately via set_employee_pin

  -- audit (D-013): the profile post-image WITHOUT the credential column (defensive --
  -- it is NULL here, but audit must structurally never carry PIN material).
  select to_jsonb(t) - 'pin_credential_ref' into v_new
    from public.employee_profiles t where t.id = v_employee;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'staff.created', null,
    v_new || jsonb_build_object('membership_id', v_membership, 'app_user_id', v_app_user, 'role', p_role));
  return v_result;
end;
$$;

comment on function app.create_staff_member(uuid, uuid, uuid, uuid, text, text) is
  'MVP staff provisioning (D-004/D-011/D-013, RF-112 pattern): creates a PIN-only staff operator in one transaction -- app_user (synthetic unique lowercase ''staff-<hex>@pin.restoflow.invalid'' identifier email, RFC-2606), an ACTIVE branch-scoped membership, and an employee_profile with pin_credential_ref NULL (PIN is provisioned via set_employee_pin). Caller must be manager+ covering the target scope AND strictly outrank the assigned role (cashier/kitchen_staff/manager only). rank 0 => 42501; in-scope rank denial => audited staff.create_denied + permission_denied. Idempotent via management_request_results.';

-- ----------------------------------------------------------------------------
-- 3. app.set_employee_pin -- set/rotate an operator's PIN. Stores ONLY a
--    server-side bcrypt hash; deletes the employee's pin_attempt_states rows
--    (a fresh PIN resets counters/lockout -- the manager recovery path).
--    Authorization is against the EMPLOYEE'S ACTUAL scope, loaded first.
-- ----------------------------------------------------------------------------
create or replace function app.set_employee_pin(
  p_client_request_id   uuid,
  p_employee_profile_id uuid,
  p_pin                 text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor       uuid := app.current_app_user_id();
  v_emp         public.employee_profiles%rowtype;
  v_rank        integer;
  v_target_role text;
  v_fp          text;
  v_replay      jsonb;
  v_result      jsonb;
begin
  if v_actor is null then
    raise exception 'set_employee_pin: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_employee_pin: client_request_id is required' using errcode = '42501';
  end if;
  if p_employee_profile_id is null then
    raise exception 'set_employee_pin: employee_profile_id is required' using errcode = '42501';
  end if;

  -- load the employee FIRST: authorization runs against ITS actual scope, so a
  -- caller can never choose a scope they control to reach a foreign employee.
  select * into v_emp from public.employee_profiles where id = p_employee_profile_id;
  if not found or v_emp.deleted_at is not null then
    raise exception 'set_employee_pin: employee profile not found' using errcode = '42501';
  end if;

  -- authorization against the EMPLOYEE'S scope. 0 => no covering membership
  -- (non-member / cross-org / out-of-scope) => structural 42501.
  v_rank := app.actor_rank_in_scope(v_emp.organization_id, v_emp.restaurant_id, v_emp.branch_id);
  if v_rank = 0 then
    raise exception 'set_employee_pin: caller has no active membership covering the employee scope' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(v_emp.organization_id, v_emp.restaurant_id, v_emp.branch_id,
      'staff.pin_set_denied', null,
      jsonb_build_object('employee_profile_id', p_employee_profile_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'employee_profile');
  end if;

  -- STRICT-OUTRANK guard on the TARGET's own role (review fix; mirrors
  -- create_staff_member/grant_membership): rotating someone's PIN is taking
  -- over their sign-in identity, so a manager may rotate cashier/kitchen PINs
  -- but NEVER a peer manager's or a superior's (D-004 per-person identity;
  -- prevents impersonation + framing the victim in the audit trail).
  select m.role into v_target_role
    from public.memberships m
    where m.id = v_emp.membership_id
      and m.deleted_at is null;
  if v_target_role is null then
    -- No authoritative membership link: not a PIN-capable profile (fail closed).
    raise exception 'set_employee_pin: employee profile has no authoritative membership' using errcode = '42501';
  end if;
  if v_rank <= app.role_rank(v_target_role) then
    perform app.management_audit(v_emp.organization_id, v_emp.restaurant_id, v_emp.branch_id,
      'staff.pin_set_denied', null,
      jsonb_build_object('employee_profile_id', p_employee_profile_id, 'reason', 'target_rank'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'employee_profile');
  end if;

  -- PIN policy: 4-8 digits (soft failure -- the dashboard shows a field error).
  if p_pin is null or p_pin !~ '^[0-9]{4,8}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_pin', 'entity', 'employee_profile');
  end if;

  -- idempotency (RF-112 ledger). The fingerprint carries NO PIN-derived material
  -- of any kind (review fix: a fast digest of a 4-8 digit PIN is brute-forceable,
  -- so persisting one would defeat the bcrypt-at-rest posture). The CLIENT sends
  -- a FRESH client_request_id per submission, so distinct rotations never collide;
  -- a true retry of one submission replays its stored result.
  v_fp := md5(jsonb_build_object('employee', p_employee_profile_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_employee_pin', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'employee_profile',
                'employee_profile_id', p_employee_profile_id, 'pin_set', true);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_employee_pin', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- store ONLY the server-side bcrypt hash (SECURITY §9: salted hash, never
  -- plaintext). Explicit work factor 10 (review fix: pgcrypto's default bf cost
  -- is 6, too weak for a small numeric keyspace).
  update public.employee_profiles
     set pin_credential_ref = extensions.crypt(p_pin, extensions.gen_salt('bf', 10))
     where id = p_employee_profile_id;

  -- a fresh PIN resets the attempt counters/lockout for this employee on EVERY
  -- device (the manager rotating a PIN is the lockout recovery path; Q-009
  -- constants unchanged).
  delete from public.pin_attempt_states
   where organization_id = v_emp.organization_id
     and employee_profile_id = p_employee_profile_id;

  -- audit (D-013): the employee id only -- NEVER the PIN or its hash.
  perform app.management_audit(v_emp.organization_id, v_emp.restaurant_id, v_emp.branch_id,
    'staff.pin_set', null,
    jsonb_build_object('employee_profile_id', p_employee_profile_id, 'pin_set', true));
  return v_result;
end;
$$;

comment on function app.set_employee_pin(uuid, uuid, text) is
  'MVP staff provisioning (D-011/D-013, SECURITY §9): sets/rotates an operator''s PIN as a SERVER-SIDE bcrypt hash (extensions.crypt + gen_salt(''bf'', 10)) on employee_profiles.pin_credential_ref, then deletes the employee''s pin_attempt_states rows (a fresh PIN resets counters/lockout). Authorized manager+ against the EMPLOYEE''S actual scope (rank 0 => 42501; rank 1 => audited staff.pin_set_denied + permission_denied) AND strictly outranking the TARGET''s own membership role (a manager can never rotate a peer manager''s or a superior''s PIN -- D-004 identity takeover guard; denied => audited staff.pin_set_denied reason target_rank). PIN policy ^[0-9]{4,8}$ (else {ok:false, error:invalid_pin}). Idempotent via management_request_results; the fingerprint, stored result, and audit rows carry NO PIN-derived material of any kind (the client sends a fresh client_request_id per submission).';

-- ----------------------------------------------------------------------------
-- 4. app.list_staff -- the dashboard staff list (management read; RF-160
--    list_devices pattern). Returns has_pin as a BOOLEAN only -- the credential
--    ref never leaves the database.
-- ----------------------------------------------------------------------------
create or replace function app.list_staff(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_items jsonb;
begin
  if v_actor is null then
    raise exception 'list_staff: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_staff: organization_id is required' using errcode = '42501';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_staff: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < 2 then     -- cashier/kitchen_staff/accountant cannot list staff
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'employee_profile');
  end if;

  select coalesce(jsonb_agg(item order by (item ->> 'display_name'), (item ->> 'employee_profile_id')), '[]'::jsonb)
    into v_items
  from (
    select jsonb_build_object(
      'employee_profile_id', ep.id,
      'display_name',        ep.display_name,
      'employee_number',     ep.employee_number,
      'role',                m.role,
      'employment_status',   ep.employment_status,
      'has_pin',             (ep.pin_credential_ref is not null),  -- boolean ONLY; never the ref
      'restaurant_id',       ep.restaurant_id,
      'branch_id',           ep.branch_id,
      'created_at',          ep.created_at
    ) as item
    from public.employee_profiles ep
    join public.memberships m
      on m.id = ep.membership_id
     and m.organization_id = ep.organization_id
     and m.status = 'active'
     and m.deleted_at is null
    where ep.organization_id = p_organization_id
      and (p_restaurant_id is null or ep.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or ep.branch_id     = p_branch_id)
      and ep.deleted_at is null
  ) t;

  return jsonb_build_object('ok', true, 'entity', 'employee_profile', 'staff', v_items);
end;
$$;

comment on function app.list_staff(uuid, uuid, uuid) is
  'MVP staff provisioning (RF-160 list pattern, D-033): GUC-free staff LIST for the owner/manager dashboard. Reads live (tombstone-filtered) employee_profiles joined to their LIVE ACTIVE linked membership in the PASSED (org, restaurant?, branch?) scope after app.actor_rank_in_scope >= manager (rank 1 in-scope -> permission_denied; no covering membership -> 42501). Returns has_pin as a BOOLEAN only -- pin_credential_ref NEVER leaves the DB. Read-only, ordered by display_name.';

-- ----------------------------------------------------------------------------
-- 5. app.list_device_staff -- the PIN-pad candidate list for a TOKEN-PROVEN
--    device (RF-161 restore_device_session pattern: an anonymous authenticated
--    device with ZERO tenant authority proves itself with its session token).
--    Returns ONLY what a PIN pad needs: id + display_name + role. NO email,
--    NO employee_number, NO pin data/flags. Any failure => invalid_session
--    (fail closed, no scope leak).
-- ----------------------------------------------------------------------------
create or replace function app.list_device_staff(
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
  v_items  jsonb;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_staff');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- token proof EXACTLY like app.restore_device_session (RF-161): a live ACTIVE
  -- session on an ACTIVE pairing for THIS device, on a live device + live
  -- branch/restaurant (fail closed on a dead/decommissioned scope).
  select ds.id, ds.organization_id, ds.restaurant_id, ds.branch_id
    into v_sid, v_org, v_rest, v_branch
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
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'device_staff');
  end if;

  -- ACTIVE employees whose LIVE ACTIVE linked membership covers the device's
  -- branch: branch-pinned to this branch, OR branch-wide (branch null) at this
  -- restaurant or org-wide. Operator roles only. (Employees relying on the
  -- RF-051 app_user fallback resolution -- membership_id NULL -- are not listed;
  -- create_staff_member always sets the authoritative link.)
  select coalesce(jsonb_agg(item order by (item ->> 'display_name'), (item ->> 'employee_profile_id')), '[]'::jsonb)
    into v_items
  from (
    select jsonb_build_object(
      'employee_profile_id', ep.id,
      'display_name',        ep.display_name,
      'role',                m.role
    ) as item
    from public.employee_profiles ep
    join public.memberships m
      on m.id = ep.membership_id
     and m.organization_id = ep.organization_id
     and m.status = 'active'
     and m.deleted_at is null
    where ep.organization_id = v_org
      and ep.employment_status = 'active'
      and ep.deleted_at is null
      and m.role in ('cashier', 'kitchen_staff', 'manager')
      and (
        m.branch_id = v_branch
        or (m.branch_id is null and (m.restaurant_id = v_rest or m.restaurant_id is null))
      )
  ) t;

  return jsonb_build_object('ok', true, 'entity', 'device_staff', 'staff', v_items);
end;
$$;

comment on function app.list_device_staff(uuid, text) is
  'MVP staff provisioning (D-006/D-011, RF-161 token-proof pattern): the PIN-pad candidate list for a token-proven device. Proves the session token exactly like app.restore_device_session (hash match on a live ACTIVE session on an ACTIVE pairing, live device/branch/restaurant); any failure => {ok:false, error:invalid_session} (fail closed, no scope leak). Returns ONLY employee_profile_id + display_name + role for ACTIVE employees whose live ACTIVE linked membership covers the device''s branch, roles cashier/kitchen_staff/manager, ordered by display_name. NO email, NO employee_number, NO pin data/flags. Callable by anonymous authenticated devices (authorization is the token, not membership).';

-- ----------------------------------------------------------------------------
-- 6. Thin public SECURITY INVOKER wrappers (RF-064 / RF-109 / RF-123 pattern).
--    No logic; delegate verbatim; the caller's EXECUTE on app.* is reused.
-- ----------------------------------------------------------------------------
create or replace function public.create_staff_member(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_display_name text, p_role text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.create_staff_member(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_display_name, p_role); $$;

create or replace function public.set_employee_pin(
  p_client_request_id uuid, p_employee_profile_id uuid, p_pin text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_employee_pin(p_client_request_id, p_employee_profile_id, p_pin); $$;

create or replace function public.list_staff(
  p_organization_id uuid, p_restaurant_id uuid default null, p_branch_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.list_staff(p_organization_id, p_restaurant_id, p_branch_id); $$;

create or replace function public.list_device_staff(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.list_device_staff(p_device_id, p_session_token); $$;

-- ----------------------------------------------------------------------------
-- 7. Grants: authenticated only (never anon/service_role; D-011). Anonymous
--    authenticated devices qualify for list_device_staff (RF-161 posture).
--    app.verify_pin_credential stays internal (section 1; no new grants).
-- ----------------------------------------------------------------------------
revoke all on function app.create_staff_member(uuid, uuid, uuid, uuid, text, text) from public;
revoke all on function app.set_employee_pin(uuid, uuid, text)                      from public;
revoke all on function app.list_staff(uuid, uuid, uuid)                            from public;
revoke all on function app.list_device_staff(uuid, text)                           from public;

grant execute on function app.create_staff_member(uuid, uuid, uuid, uuid, text, text) to authenticated;
grant execute on function app.set_employee_pin(uuid, uuid, text)                      to authenticated;
grant execute on function app.list_staff(uuid, uuid, uuid)                            to authenticated;
grant execute on function app.list_device_staff(uuid, text)                           to authenticated;

revoke all on function public.create_staff_member(uuid, uuid, uuid, uuid, text, text) from public;
revoke all on function public.set_employee_pin(uuid, uuid, text)                      from public;
revoke all on function public.list_staff(uuid, uuid, uuid)                            from public;
revoke all on function public.list_device_staff(uuid, text)                           from public;

grant execute on function public.create_staff_member(uuid, uuid, uuid, uuid, text, text) to authenticated;
grant execute on function public.set_employee_pin(uuid, uuid, text)                      to authenticated;
grant execute on function public.list_staff(uuid, uuid, uuid)                            to authenticated;
grant execute on function public.list_device_staff(uuid, text)                           to authenticated;

-- ============================================================================
-- DOWN (manual) -- Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop function if exists public.list_device_staff(uuid, text);
-- drop function if exists public.list_staff(uuid, uuid, uuid);
-- drop function if exists public.set_employee_pin(uuid, uuid, text);
-- drop function if exists public.create_staff_member(uuid, uuid, uuid, uuid, text, text);
-- drop function if exists app.list_device_staff(uuid, text);
-- drop function if exists app.list_staff(uuid, uuid, uuid);
-- drop function if exists app.set_employee_pin(uuid, uuid, text);
-- drop function if exists app.create_staff_member(uuid, uuid, uuid, uuid, text, text);
-- -- restore the RF-051 interim verifier via `create or replace function
-- -- app.verify_pin_credential(uuid, text)` with the RF-051 body (plain-equality
-- -- seam; same signature/posture) -- see 20260621120000_rf051_pin_session_flow.sql.
-- ============================================================================
