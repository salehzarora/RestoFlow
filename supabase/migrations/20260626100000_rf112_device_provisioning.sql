-- RF-112 Stage 2 -- GUC-free device provisioning forward path (DECISION D-033; API_CONTRACT §4.27).
--
-- Implements the documented device enrollment edges up to `paired`:
--   create_device  -> issue_device_enrollment_code (code_issued)
--   -> redeem_device_enrollment_code (code_issued -> pending)
--   -> approve_device (pending -> paired; the manager-approval edge, STATE_MACHINES §9)
--
-- ============================================================================
-- DEFERRED -- start_device_session + the paired -> active activation (CONTRACT GAP, reported):
--   §4.27 says start_device_session mints a device_sessions row "on an ACTIVE pairing", and
--   STATE_MACHINES §9 makes `active` the prerequisite for opening a device session
--   ("paired -> active ... allowed to open device_session"). But §4.27 defines NO RPC for the
--   `paired -> active` activation, approve_device must STOP at `paired` (pending -> active is
--   FORBIDDEN, STATE_MACHINES §9), and "server" activation has no defined trigger. Implementing
--   start_device_session would therefore require either inventing an undocumented activate_device
--   RPC or weakening start_device_session to accept a non-active (`paired`) pairing -- both
--   explicitly disallowed by the Stage 2 brief and the freeze-before-code method. So this stage
--   STOPS at `paired` and reports the gap: a follow-up docs gate (a D-034-style ADR amending
--   §4.27) must decide the activation surface (add `activate_device` paired->active manager/server,
--   OR define start_device_session's server-driven paired->active) BEFORE start_device_session is
--   built. No forbidden/hidden transition is introduced here.
-- ============================================================================
--
-- GUC-FREE (D-033): caller identity from auth.uid() -> app.current_app_user_id(); scope is the
-- PASSED/derived org/restaurant/branch validated DIRECTLY against memberships via the Stage 1
-- helper app.actor_rank_in_scope (NEVER app.current_org_id()/has_scope()/has_role_in_scope()/
-- menu_guard; NEVER app.is_platform_admin()). Management-authorized: org_owner/restaurant_owner/
-- manager covering the device's scope may provision (rank >= manager); cashier/kitchen_staff/
-- accountant -> permission_denied; non-member/cross-org/out-of-scope -> 42501. No anon/service_role.
--
-- WHY MANAGEMENT-DRIVEN (not device-originated): RF-112 has NO device-auth bridge yet (deferred),
-- so a device cannot authenticate as itself. The enrollment edges are driven by an authenticated
-- management member in the device's scope (a manager enters/redeems the code), so idempotency uses
-- client_request_id (the Stage 1 ledger), NOT device_id+local_operation_id. The device_id+
-- local_operation_id path (D-022) applies once device-auth lands (deferred with start_device_session).
--
-- SECRETS (SECURITY REQUIREMENT, D-033/§4.27): the enrollment code is server-generated, returned to
-- the caller EXACTLY ONCE (only on the first/claiming call), and stored ONLY as a SHA-256 hash in
-- device_pairings.enrollment_code_hash -- NEVER plaintext in the DB or in audit_events. The
-- idempotency ledger stores a NO-CODE result, so a replay NEVER re-returns the one-time code.
-- Code is consume-once (status='code_issued' is the only redeemable state); expired/revoked/
-- suspended pairings fail closed. TTL is a conservative centralized constant (Q-009-aware).
--
-- Reuses Stage 1 (20260626090000): app.actor_rank_in_scope, app.role_rank, app.management_audit,
-- app.management_idem_check, app.management_claim_request, public.management_request_results.
-- Direct DML on devices/device_pairings stays RLS-denied (RF-059); these DEFINER RPCs write as the
-- BYPASSRLS owner. FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.

-- ===========================================================================
-- 1. Conservative enrollment-code TTL (centralized; Q-009-aware, not frozen).
-- ===========================================================================
create or replace function app.device_enrollment_code_ttl()
  returns interval
  language sql
  immutable
  set search_path = ''
as $$ select interval '15 minutes' $$;  -- conservative INTERIM constant (Q-009); change here only.

comment on function app.device_enrollment_code_ttl() is
  'RF-112 (D-033/§4.27): conservative device enrollment-code validity window (INTERIM; Q-009-aware, not frozen). Centralized; change here only.';

revoke all on function app.device_enrollment_code_ttl() from public;

-- ===========================================================================
-- 2. Server-side secret hashing (SHA-256 hex). Stores only the hash; the plaintext
--    code is returned once and never persisted. Internal (revoked from public).
-- ===========================================================================
create or replace function app.hash_provisioning_secret(p_secret text)
  returns text
  language sql
  immutable
  security definer
  set search_path = ''
as $$ select encode(extensions.digest(p_secret, 'sha256'), 'hex') $$;

comment on function app.hash_provisioning_secret(text) is
  'RF-112 (D-033): SHA-256 (hex) of a server-generated provisioning secret (enrollment code). Stored in device_pairings.enrollment_code_hash; the plaintext is returned ONCE and never persisted. Internal to the device-provisioning RPCs.';

revoke all on function app.hash_provisioning_secret(text) from public;

-- ===========================================================================
-- 3. app.create_device -- register a branch-scoped device row (no secret stored).
-- ===========================================================================
create or replace function app.create_device(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_device_type       text,
  p_label             text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   integer;
  v_fp     text;
  v_replay jsonb;
  v_id     uuid := gen_random_uuid();
  v_result jsonb;
  v_new    jsonb;
begin
  if v_actor is null then
    raise exception 'create_device: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'create_device: client_request_id is required' using errcode = '42501';
  end if;
  -- devices are branch-scoped (org/restaurant/branch NOT NULL); there is NO station column.
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'create_device: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;
  if p_device_type is null or p_device_type not in ('pos', 'kds') then
    raise exception 'create_device: device_type must be pos or kds' using errcode = '42501';
  end if;
  -- target branch + parent restaurant must exist in the org AND be LIVE (not soft-deleted).
  if not exists (
       select 1 from public.branches b
       join public.restaurants r on r.id = b.restaurant_id and r.organization_id = b.organization_id
       where b.id = p_branch_id and b.organization_id = p_organization_id
         and b.restaurant_id = p_restaurant_id and b.deleted_at is null and r.deleted_at is null) then
    raise exception 'create_device: branch not found in organization/restaurant or scope is soft-deleted' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id, 'branch', p_branch_id,
              'device_type', p_device_type, 'label', p_label)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'create_device', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'create_device: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  if v_rank < 2 then     -- cashier/kitchen_staff/accountant cannot provision
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'device.create_denied', null,
      jsonb_build_object('device_type', p_device_type));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'device', 'device_id', v_id);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'create_device', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  insert into public.devices (id, organization_id, restaurant_id, branch_id, device_type, label, is_active)
  values (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_device_type, nullif(btrim(coalesce(p_label, '')), ''), true);
  -- device_credential_ref is left NULL: the real device credential is OS-secure-stored on the device
  -- and provisioned later (RF-021); no device secret is minted/returned at create time.

  select to_jsonb(t) into v_new from public.devices t where t.id = v_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'device.created', null, v_new);
  return v_result;
end;
$$;

-- ===========================================================================
-- 4. app.issue_device_enrollment_code -- mint a short-lived enrollment code for a
--    live, in-scope device. Returns the plaintext code ONCE; stores only its hash.
-- ===========================================================================
create or replace function app.issue_device_enrollment_code(
  p_client_request_id uuid,
  p_device_id         uuid,
  p_ttl               interval default null
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
  v_rank    integer;
  v_fp      text;
  v_replay  jsonb;
  v_pairing uuid := gen_random_uuid();
  v_code    text;
  v_hash    text;
  v_expires timestamptz;
  v_stored  jsonb;
begin
  if v_actor is null then
    raise exception 'issue_device_enrollment_code: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'issue_device_enrollment_code: client_request_id is required' using errcode = '42501';
  end if;
  if p_device_id is null then
    raise exception 'issue_device_enrollment_code: device_id is required' using errcode = '42501';
  end if;
  if p_ttl is not null and p_ttl <= interval '0' then
    raise exception 'issue_device_enrollment_code: ttl must be positive' using errcode = '42501';
  end if;

  -- device must exist, be active+live, and sit on a LIVE branch/restaurant (fail closed).
  select d.organization_id, d.restaurant_id, d.branch_id
    into v_org, v_rest, v_branch
    from public.devices d
    join public.branches b on b.id = d.branch_id and b.organization_id = d.organization_id and b.restaurant_id = d.restaurant_id
    join public.restaurants r on r.id = d.restaurant_id and r.organization_id = d.organization_id
    where d.id = p_device_id and d.deleted_at is null and d.is_active
      and b.deleted_at is null and r.deleted_at is null;
  if not found then
    raise exception 'issue_device_enrollment_code: device not found, inactive, or its scope is soft-deleted' using errcode = '42501';
  end if;

  -- fingerprint over the INPUTS only (never the generated code).
  v_fp := md5(jsonb_build_object('device_id', p_device_id,
              'ttl_seconds', extract(epoch from coalesce(p_ttl, app.device_enrollment_code_ttl())))::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'issue_device_enrollment_code', v_fp);
  if v_replay is not null then
    return v_replay;   -- committed replay: NO plaintext code (stored result has none)
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'issue_device_enrollment_code: caller has no active membership covering the device scope' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(v_org, v_rest, v_branch, 'device.enrollment_code_issue_denied', null,
      jsonb_build_object('device_id', p_device_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device_pairing');
  end if;

  -- server-generated high-entropy code; store ONLY its hash; expiry from the conservative TTL.
  v_code    := replace(gen_random_uuid()::text, '-', '');
  v_hash    := app.hash_provisioning_secret(v_code);
  v_expires := now() + coalesce(p_ttl, app.device_enrollment_code_ttl());

  -- the LEDGER stores a NO-CODE result, so a replay can never re-return the one-time code.
  v_stored := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'device_pairing',
                'device_pairing_id', v_pairing, 'device_id', p_device_id, 'status', 'code_issued',
                'code_expires_at', v_expires);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'issue_device_enrollment_code', v_fp, v_stored);
  if v_replay is not null then
    return v_replay;   -- lost the race: replay (no code)
  end if;

  insert into public.device_pairings
    (id, organization_id, restaurant_id, branch_id, device_id, enrollment_code_hash, code_expires_at, status)
  values (v_pairing, v_org, v_rest, v_branch, p_device_id, v_hash, v_expires, 'code_issued');

  -- audit carries NO plaintext code (only the pairing id + expiry).
  perform app.management_audit(v_org, v_rest, v_branch, 'device.enrollment_code_issued', null,
    jsonb_build_object('device_id', p_device_id, 'device_pairing_id', v_pairing, 'code_expires_at', v_expires));

  -- FIRST response ONLY: include the one-time plaintext enrollment code.
  return v_stored || jsonb_build_object('enrollment_code', v_code);
end;
$$;

-- ===========================================================================
-- 5. app.redeem_device_enrollment_code -- consume a code (code_issued -> pending).
--    Verifies by hash; rejects wrong/expired/already-consumed codes and dead scope.
-- ===========================================================================
create or replace function app.redeem_device_enrollment_code(
  p_client_request_id uuid,
  p_device_id         uuid,
  p_enrollment_code   text
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
  v_rank    integer;
  v_hash    text;
  v_fp      text;
  v_replay  jsonb;
  v_pairing uuid;
  v_expires timestamptz;
  v_rows    integer;
  v_result  jsonb;
begin
  if v_actor is null then
    raise exception 'redeem_device_enrollment_code: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'redeem_device_enrollment_code: client_request_id is required' using errcode = '42501';
  end if;
  if p_device_id is null or p_enrollment_code is null or btrim(p_enrollment_code) = '' then
    raise exception 'redeem_device_enrollment_code: device_id and enrollment_code are required' using errcode = '42501';
  end if;

  select d.organization_id, d.restaurant_id, d.branch_id
    into v_org, v_rest, v_branch
    from public.devices d
    join public.branches b on b.id = d.branch_id and b.organization_id = d.organization_id and b.restaurant_id = d.restaurant_id
    join public.restaurants r on r.id = d.restaurant_id and r.organization_id = d.organization_id
    where d.id = p_device_id and d.deleted_at is null and d.is_active
      and b.deleted_at is null and r.deleted_at is null;
  if not found then
    raise exception 'redeem_device_enrollment_code: device not found, inactive, or its scope is soft-deleted' using errcode = '42501';
  end if;

  v_hash := app.hash_provisioning_secret(p_enrollment_code);
  -- fingerprint uses the code HASH (never plaintext) so the ledger stores no secret.
  v_fp := md5(jsonb_build_object('device_id', p_device_id, 'code_hash', v_hash)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'redeem_device_enrollment_code', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'redeem_device_enrollment_code: caller has no active membership covering the device scope' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(v_org, v_rest, v_branch, 'device.enrollment_code_redeem_denied', null,
      jsonb_build_object('device_id', p_device_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device_pairing');
  end if;

  -- find the redeemable pairing: status='code_issued' is the ONLY redeemable state, so a
  -- wrong code OR an already-consumed/revoked/suspended/expired pairing yields no match.
  select dp.id, dp.code_expires_at into v_pairing, v_expires
    from public.device_pairings dp
    where dp.organization_id = v_org and dp.device_id = p_device_id
      and dp.status = 'code_issued' and dp.enrollment_code_hash = v_hash and dp.deleted_at is null
    limit 1;
  if v_pairing is null then
    raise exception 'redeem_device_enrollment_code: invalid, unknown, or already-consumed enrollment code' using errcode = '42501';
  end if;
  if v_expires is not null and v_expires < now() then
    raise exception 'redeem_device_enrollment_code: enrollment code expired' using errcode = '42501';
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'device_pairing',
                'device_pairing_id', v_pairing, 'device_id', p_device_id, 'status', 'pending');
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'redeem_device_enrollment_code', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- consume-once: the guarded UPDATE (status='code_issued') is race-safe (a concurrent redeem
  -- that won leaves 0 rows here). The RF-016 enforce_pairing_code_expiry trigger is a backstop.
  update public.device_pairings
    set status = 'pending'
    where id = v_pairing and status = 'code_issued';
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'redeem_device_enrollment_code: enrollment code already consumed' using errcode = '42501';
  end if;

  -- audit carries NO plaintext code.
  perform app.management_audit(v_org, v_rest, v_branch, 'device.enrollment_code_redeemed', null,
    jsonb_build_object('device_id', p_device_id, 'device_pairing_id', v_pairing, 'status', 'pending'));
  return v_result;
end;
$$;

-- ===========================================================================
-- 6. app.approve_device -- the manager-approval edge pending -> paired (NEVER
--    pending -> active, which STATE_MACHINES §9 marks FORBIDDEN).
-- ===========================================================================
create or replace function app.approve_device(
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
  v_status  text;
  v_rank    integer;
  v_fp      text;
  v_replay  jsonb;
  v_rows    integer;
  v_result  jsonb;
begin
  if v_actor is null then
    raise exception 'approve_device: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'approve_device: client_request_id is required' using errcode = '42501';
  end if;
  if p_device_pairing_id is null then
    raise exception 'approve_device: device_pairing_id is required' using errcode = '42501';
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
    raise exception 'approve_device: pairing not found, or its device/scope is inactive or soft-deleted' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('device_pairing_id', p_device_pairing_id, 'op', 'approve')::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'approve_device', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'approve_device: caller has no active membership covering the device scope' using errcode = '42501';
  end if;
  if v_rank < 2 then     -- approval REQUIRED by manager+; cashier/kitchen/accountant denied
    perform app.management_audit(v_org, v_rest, v_branch, 'device.approve_denied', null,
      jsonb_build_object('device_pairing_id', p_device_pairing_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device_pairing');
  end if;

  -- pending is the ONLY legal source for pending -> paired. This rejects every other state
  -- (code_issued/paired/active/suspended/revoked/code_expired/rejected) -> revoked/suspended/
  -- expired pairings fail closed, and pending -> active can never happen here.
  if v_status <> 'pending' then
    raise exception 'approve_device: pairing is not pending (status=%); only pending -> paired is allowed', v_status using errcode = '42501';
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'device_pairing',
                'device_pairing_id', p_device_pairing_id, 'status', 'paired');
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'approve_device', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- pending -> paired (sets paired_at). Guarded WHERE status='pending' is race-safe.
  update public.device_pairings
    set status = 'paired', paired_at = now()
    where id = p_device_pairing_id and status = 'pending';
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'approve_device: pairing was not pending at approval time' using errcode = '42501';
  end if;

  perform app.management_audit(v_org, v_rest, v_branch, 'device.approved', null,
    jsonb_build_object('device_pairing_id', p_device_pairing_id, 'status', 'paired'));
  return v_result;
end;
$$;

-- ===========================================================================
-- 7. Thin public SECURITY INVOKER wrappers (RF-064 / RF-109 pattern). Data-API
--    reachable; the caller's EXECUTE on app.* is reused; no logic.
--    NOTE: there is intentionally NO public.start_device_session wrapper -- that RPC
--    is DEFERRED pending the paired->active activation contract decision (see header).
-- ===========================================================================
create or replace function public.create_device(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_device_type text, p_label text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.create_device(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_device_type, p_label); $$;

create or replace function public.issue_device_enrollment_code(
  p_client_request_id uuid, p_device_id uuid, p_ttl interval default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.issue_device_enrollment_code(p_client_request_id, p_device_id, p_ttl); $$;

create or replace function public.redeem_device_enrollment_code(
  p_client_request_id uuid, p_device_id uuid, p_enrollment_code text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.redeem_device_enrollment_code(p_client_request_id, p_device_id, p_enrollment_code); $$;

create or replace function public.approve_device(
  p_client_request_id uuid, p_device_pairing_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.approve_device(p_client_request_id, p_device_pairing_id); $$;

-- ===========================================================================
-- 8. Grants: authenticated only (never anon/service_role). The app RPCs + public
--    wrappers go to authenticated; internal helpers stay revoked + ungranted.
-- ===========================================================================
revoke all on function app.create_device(uuid, uuid, uuid, uuid, text, text)            from public;
revoke all on function app.issue_device_enrollment_code(uuid, uuid, interval)           from public;
revoke all on function app.redeem_device_enrollment_code(uuid, uuid, text)              from public;
revoke all on function app.approve_device(uuid, uuid)                                   from public;

grant execute on function app.create_device(uuid, uuid, uuid, uuid, text, text)         to authenticated;
grant execute on function app.issue_device_enrollment_code(uuid, uuid, interval)        to authenticated;
grant execute on function app.redeem_device_enrollment_code(uuid, uuid, text)           to authenticated;
grant execute on function app.approve_device(uuid, uuid)                                to authenticated;

revoke all on function public.create_device(uuid, uuid, uuid, uuid, text, text)         from public;
revoke all on function public.issue_device_enrollment_code(uuid, uuid, interval)        from public;
revoke all on function public.redeem_device_enrollment_code(uuid, uuid, text)           from public;
revoke all on function public.approve_device(uuid, uuid)                                from public;

grant execute on function public.create_device(uuid, uuid, uuid, uuid, text, text)      to authenticated;
grant execute on function public.issue_device_enrollment_code(uuid, uuid, interval)     to authenticated;
grant execute on function public.redeem_device_enrollment_code(uuid, uuid, text)        to authenticated;
grant execute on function public.approve_device(uuid, uuid)                             to authenticated;

-- ===========================================================================
-- DOWN (manual; Supabase is forward-only -- `supabase db reset` replays):
--   drop function if exists public.approve_device(uuid, uuid);
--   drop function if exists public.redeem_device_enrollment_code(uuid, uuid, text);
--   drop function if exists public.issue_device_enrollment_code(uuid, uuid, interval);
--   drop function if exists public.create_device(uuid, uuid, uuid, uuid, text, text);
--   drop function if exists app.approve_device(uuid, uuid);
--   drop function if exists app.redeem_device_enrollment_code(uuid, uuid, text);
--   drop function if exists app.issue_device_enrollment_code(uuid, uuid, interval);
--   drop function if exists app.create_device(uuid, uuid, uuid, uuid, text, text);
--   drop function if exists app.hash_provisioning_secret(text);
--   drop function if exists app.device_enrollment_code_ttl();
-- ===========================================================================
