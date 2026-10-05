-- BIZBOT-DEVICE-SESSION-FIX-001: token-proven, sliding 30-day device sessions.
-- Owner-approved policy: no absolute cap; expired/revoked credentials never revive.
-- Only this new migration changes the schema. PIN/offline authority, token values,
-- storage/realtime STABLE predicates, and the deferred gate-parity RPCs are untouched.
-- There is deliberately no existing-row backfill. An expired device re-pairs once.

create or replace function app.device_session_idle_window()
  returns interval language sql immutable set search_path = ''
as $$ select interval '30 days' $$;
revoke all on function app.device_session_idle_window() from public, anon;
grant execute on function app.device_session_idle_window() to authenticated;

-- Preserve the existing minting entry point used by redeem_device_pairing.
create or replace function app.device_session_max_age()
  returns interval language sql immutable set search_path = ''
as $$ select app.device_session_idle_window() $$;
comment on function app.device_session_max_age() is
  'BIZBOT-DEVICE-SESSION-FIX-001: compatibility name for the 30-day sliding idle window; no absolute lifetime cap. Existing redeem_device_pairing uses this when minting.';

-- No caller can renew with a session id alone. This INTERNAL function requires
-- the device id plus raw token, proves the hash, derives every scope id, and
-- grants no employee authority. App RPCs call it as their SECURITY DEFINER owner.
create or replace function app.renew_device_session(
  p_device_id uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_hash text;
  v_sid uuid;
  v_session public.device_sessions%rowtype;
  v_device public.devices%rowtype;
  v_pairing public.device_pairings%rowtype;
  v_branch public.branches%rowtype;
  v_restaurant public.restaurants%rowtype;
  v_organization public.organizations%rowtype;
  v_now timestamptz := now();
  v_invalid jsonb := jsonb_build_object('ok', false, 'error', 'invalid_session',
                                       'entity', 'device_session', 'reason', 'invalid');
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return v_invalid;
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- Token proof BEFORE reason disclosure or locks on caller-selected devices.
  select ds.* into v_session
    from public.device_sessions ds
    where ds.device_id = p_device_id and ds.session_token_ref = v_hash
    order by ds.started_at desc, ds.id desc limit 1;
  if not found then return v_invalid; end if;
  v_sid := v_session.id;

  -- Lock hierarchy before device -> pairing -> session. Scope SHARE locks permit
  -- peer heartbeats but serialize tombstone/suspension. NO KEY UPDATE on the
  -- identity rows avoids conflicting with FK KEY SHARE locks during redemption.
  -- Owner revoke orders device -> pairing -> session; PIN revoke pairing ->
  -- session; self-unpair session only. Recheck AFTER waiting, never revive flags.
  select o.* into v_organization from public.organizations o
    where o.id = v_session.organization_id for share;
  if not found or v_organization.deleted_at is not null or v_organization.status <> 'active' then
    return v_invalid;
  end if;
  select r.* into v_restaurant from public.restaurants r
    where r.id = v_session.restaurant_id and r.organization_id = v_organization.id for share;
  if not found or v_restaurant.deleted_at is not null or v_restaurant.status <> 'active' then
    return v_invalid;
  end if;
  select b.* into v_branch from public.branches b
    where b.id = v_session.branch_id and b.organization_id = v_organization.id
      and b.restaurant_id = v_restaurant.id for share;
  if not found or v_branch.deleted_at is not null or v_branch.status <> 'active' then
    return v_invalid;
  end if;
  select d.* into v_device from public.devices d
    where d.id = p_device_id and d.organization_id = v_organization.id
      and d.restaurant_id = v_restaurant.id and d.branch_id = v_branch.id
    for no key update;
  if not found then return v_invalid; end if;
  select dp.* into v_pairing from public.device_pairings dp
    where dp.id = v_session.device_pairing_id and dp.device_id = v_device.id
      and dp.organization_id = v_organization.id and dp.restaurant_id = v_restaurant.id
      and dp.branch_id = v_branch.id
    for no key update;
  if not found then return v_invalid; end if;
  select ds.* into v_session from public.device_sessions ds
    where ds.id = v_sid and ds.device_id = p_device_id and ds.session_token_ref = v_hash
      and ds.organization_id = v_organization.id and ds.restaurant_id = v_restaurant.id
      and ds.branch_id = v_branch.id and ds.device_pairing_id = v_pairing.id
    for no key update;
  if not found then return v_invalid; end if;

  if v_session.revoked_at is not null or v_pairing.revoked_at is not null
     or v_pairing.status = 'revoked' then
    return v_invalid || jsonb_build_object('reason', 'revoked');
  end if;
  if not v_session.is_active or not v_device.is_active or v_device.deleted_at is not null
     or v_pairing.status <> 'active' or v_pairing.deleted_at is not null then
    return v_invalid;
  end if;
  if v_session.expires_at is not null and v_session.expires_at <= v_now then
    return v_invalid || jsonb_build_object('reason', 'expired');
  end if;

  -- Strict threshold: equality does NOT write. NULL legacy sessions adopt the
  -- sliding window on their first proven activity. Never shorten a later expiry.
  if v_session.expires_at is null
     or v_session.expires_at < v_now + app.device_session_idle_window() - interval '1 hour' then
    update public.device_sessions
      set expires_at = v_now + app.device_session_idle_window()
      where id = v_sid;
    update public.devices set last_seen_at = v_now where id = p_device_id;
    v_session.expires_at := v_now + app.device_session_idle_window();
  end if;

  return jsonb_build_object('ok', true, 'entity', 'device_session',
    'device_session_id', v_sid, 'organization_id', v_organization.id,
    'restaurant_id', v_restaurant.id, 'branch_id', v_branch.id,
    'device_id', p_device_id, 'device_type', v_device.device_type,
    'session_expires_at', v_session.expires_at, 'server_now', v_now);
end;
$$;
revoke all on function app.renew_device_session(uuid, text) from public, anon, authenticated;
comment on function app.renew_device_session(uuid, text) is
  'BIZBOT-DEVICE-SESSION-FIX-001 internal token-proven renewal. Full live scope, device, pairing and session validation; serialized against revocation. NULL or a deadline strictly below now()+30d-1h renews to now()+30d and updates devices.last_seen_at. Expired/revoked/inactive never revive. No token rotation, employee authority, absolute cap, or direct client grant.';

create or replace function app.restore_device_session(
  p_device_id uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_result jsonb;
begin
  v_result := app.renew_device_session(p_device_id, p_session_token);
  if not (v_result ->> 'ok')::boolean then return v_result; end if;
  -- Preserve the token-proven anonymous-principal storage binding. The helper
  -- retains the session lock until this transaction ends, including this write.
  if auth.uid() is not null then
    update public.device_sessions set auth_user_id = auth.uid()
      where id = (v_result ->> 'device_session_id')::uuid
        and auth_user_id is distinct from auth.uid();
  end if;
  return v_result;
end;
$$;
revoke all on function app.restore_device_session(uuid, text) from public, anon;
grant execute on function app.restore_device_session(uuid, text) to authenticated;
comment on function app.restore_device_session(uuid, text) is
  'BIZBOT-DEVICE-SESSION-FIX-001: existing token-proven restore context and invalid_session error preserved. Additive failure reason is expired/revoked/invalid only after token proof (wrong token => invalid). Successful proof renews the 30-day idle window when due, preserves the auth.uid storage binding, and adds session_expires_at/server_now. No absolute cap or token rotation.';

create or replace function app.heartbeat_device_session(
  p_device_id uuid,
  p_session_token text
)
  returns jsonb language sql volatile security definer set search_path = ''
as $$ select app.restore_device_session(p_device_id, p_session_token); $$;
create or replace function public.heartbeat_device_session(
  p_device_id uuid,
  p_session_token text
)
  returns jsonb language sql volatile security invoker set search_path = ''
as $$ select app.heartbeat_device_session(p_device_id, p_session_token); $$;
revoke all on function app.heartbeat_device_session(uuid, text) from public, anon;
revoke all on function public.heartbeat_device_session(uuid, text) from public, anon;
grant execute on function app.heartbeat_device_session(uuid, text) to authenticated;
grant execute on function public.heartbeat_device_session(uuid, text) to authenticated;
comment on function public.heartbeat_device_session(uuid, text) is
  'BIZBOT-DEVICE-SESSION-FIX-001: authenticated-only token-proven foreground heartbeat. Same success context/timestamps and explicit invalid_session reason as restore; no PIN authority, token rotation, or credential returned.';


-- Legacy management mint: latest RF112 body, only initial deadline changed.
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

  -- BIZBOT-DEVICE-SESSION-FIX-001: the legacy management mint now uses the
  -- same 30-day idle window as code redemption. Token/audit/idempotency unchanged.
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
    (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, expires_at)
  values (v_session, v_org, v_rest, v_branch, v_device, p_device_pairing_id, v_hash, true, now() + app.device_session_idle_window());

  -- audit carries NO plaintext token (only the session/pairing ids).
  perform app.management_audit(v_org, v_rest, v_branch, 'device.session_started', null,
    jsonb_build_object('device_session_id', v_session, 'device_pairing_id', p_device_pairing_id));

  -- FIRST response ONLY: include the one-time plaintext session token.
  return v_stored || jsonb_build_object('session_token', v_token);
end;
$$;

-- Latest effective app.report_kitchen_printer_readiness from 20260727090000_kitchen_mode_001c3b1a_stable_readiness_status.sql; business contract preserved.
create or replace function app.report_kitchen_printer_readiness(
  p_device_id              uuid,
  p_session_token          text,
  p_capability             text,
  p_app_build              text,
  p_printer_purpose        text,
  p_transport_kind         text,
  p_paper_width            text,
  p_printer_fingerprint    text,
  p_secure_spool_available boolean,
  p_unresolved_local_jobs  integer,
  p_mode_revision          integer,
  p_printer_assignment_id  uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash             text;
  v_org              uuid;
  v_rest             uuid;
  v_branch           uuid;
  v_dtype            text;
  v_rev              integer;
  v_assignment_ok    boolean;
  v_activation_ready boolean;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_printer_readiness');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- FULL device-liveness contract (the 001A-corrected template); scope comes
  -- EXCLUSIVELY from the proven session.
  select ds.organization_id, ds.restaurant_id, ds.branch_id, d.device_type
    into v_org, v_rest, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_printer_readiness');
  end if;
  if v_dtype <> 'pos' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_printer_readiness');
  end if;

  -- BIZBOT-DEVICE-SESSION-FIX-001: renew only after this RPC proves its device role.
  if not (app.renew_device_session(p_device_id, p_session_token) ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_printer_readiness');
  end if;

  -- Typed validation (closed vocabularies; the CHECKs re-prove at the row).
  if p_capability is distinct from 'kitchen_printer_only_v1' then
    return jsonb_build_object('ok', false, 'error', 'unsupported_capability');
  end if;
  if p_printer_purpose is distinct from 'kitchen_ticket' then
    return jsonb_build_object('ok', false, 'error', 'unsupported_purpose');
  end if;
  if p_transport_kind is null or p_transport_kind not in ('network', 'bluetooth') then
    return jsonb_build_object('ok', false, 'error', 'unsupported_transport');
  end if;
  if p_paper_width is null or p_paper_width not in ('58mm', '80mm') then
    return jsonb_build_object('ok', false, 'error', 'unsupported_paper_width');
  end if;
  if p_app_build is null or length(btrim(p_app_build)) not between 1 and 64 then
    return jsonb_build_object('ok', false, 'error', 'invalid_app_build');
  end if;
  if p_printer_fingerprint is null or p_printer_fingerprint !~ '^[0-9a-f]{16,128}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_fingerprint');
  end if;
  if p_secure_spool_available is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_spool_state');
  end if;
  if p_unresolved_local_jobs is null or p_unresolved_local_jobs < 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_unresolved_count');
  end if;

  select b.kitchen_workflow_mode_revision into v_rev
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if p_mode_revision is distinct from v_rev then
    return jsonb_build_object('ok', false, 'error', 'stale_mode_revision', 'mode_revision', v_rev);
  end if;

  -- KITCHEN-MODE-001C3B1A: the pinned assignment (when supplied) must belong to
  -- THIS scope and still be a live, enabled, kitchen-capable 80mm printer whose
  -- transport matches. A mismatched/foreign assignment is a typed rejection
  -- rather than a silently non-qualifying stored row. A NULL assignment
  -- (legacy 001C3A client) is accepted and stored, but is never qualifying.
  if p_printer_assignment_id is not null then
    select exists (
      select 1 from public.printer_devices pd
      where pd.organization_id = v_org
        and pd.restaurant_id   = v_rest
        and pd.branch_id       = v_branch
        and pd.id              = p_printer_assignment_id
        and pd.deleted_at is null
        and pd.is_enabled
        and pd.role in ('kitchen', 'both')
        and pd.paper_width = '80mm'
        and pd.connection_type = p_transport_kind
    ) into v_assignment_ok;
    if not v_assignment_ok then
      return jsonb_build_object('ok', false, 'error', 'invalid_printer_assignment', 'entity', 'kitchen_printer_readiness');
    end if;
  end if;

  -- ONE current report per device (upsert; the server owns the clock).
  insert into public.kitchen_printer_readiness_reports
    (organization_id, restaurant_id, branch_id, device_id, capability,
     app_build, printer_purpose, transport_kind, paper_width,
     printer_fingerprint, secure_spool_available, unresolved_local_jobs,
     mode_revision, printer_assignment_id, reported_at, expires_at)
  values
    (v_org, v_rest, v_branch, p_device_id, p_capability,
     btrim(p_app_build), p_printer_purpose, p_transport_kind, p_paper_width,
     p_printer_fingerprint, p_secure_spool_available, p_unresolved_local_jobs,
     p_mode_revision, p_printer_assignment_id, now(), now() + interval '10 minutes')
  on conflict (organization_id, device_id) do update set
     restaurant_id          = excluded.restaurant_id,
     branch_id              = excluded.branch_id,
     capability             = excluded.capability,
     app_build              = excluded.app_build,
     printer_purpose        = excluded.printer_purpose,
     transport_kind         = excluded.transport_kind,
     paper_width            = excluded.paper_width,
     printer_fingerprint    = excluded.printer_fingerprint,
     secure_spool_available = excluded.secure_spool_available,
     unresolved_local_jobs  = excluded.unresolved_local_jobs,
     mode_revision          = excluded.mode_revision,
     printer_assignment_id  = excluded.printer_assignment_id,
     reported_at            = excluded.reported_at,
     expires_at             = excluded.expires_at,
     updated_at             = now();

  -- activation_ready reflects whether THIS report would qualify: 80mm + secure
  -- spool + a valid pinned assignment (never a paper claim).
  v_activation_ready := (p_paper_width = '80mm' and p_secure_spool_available
                         and coalesce(v_assignment_ok, false));

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_printer_readiness',
    'meaning', 'transport_accepted_not_paper_confirmed',
    'activation_ready', v_activation_ready,
    'expires_at', now() + interval '10 minutes',
    'server_ts', now());
end;
$$;

-- Latest effective app.report_kitchen_pos_status from 20260728090000_kitchen_mode_001c3b1a2_spool_count_certainty.sql; business contract preserved.
create or replace function app.report_kitchen_pos_status(
  p_device_id              uuid,
  p_session_token          text,
  p_app_build              text,
  p_mode_revision          integer,
  p_secure_spool_available boolean,
  p_unresolved_local_jobs  integer,
  p_spool_count_state      text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash   text;
  v_org    uuid;
  v_rest   uuid;
  v_branch uuid;
  v_dtype  text;
  v_rev    integer;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_pos_status');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- FULL device-liveness contract; scope EXCLUSIVELY from the proven session.
  select ds.organization_id, ds.restaurant_id, ds.branch_id, d.device_type
    into v_org, v_rest, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_pos_status');
  end if;
  if v_dtype <> 'pos' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_pos_status');
  end if;

  -- BIZBOT-DEVICE-SESSION-FIX-001: renew only after this RPC proves its device role.
  if not (app.renew_device_session(p_device_id, p_session_token) ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_pos_status');
  end if;

  if p_app_build is null or length(btrim(p_app_build)) not between 1 and 64 then
    return jsonb_build_object('ok', false, 'error', 'invalid_app_build');
  end if;
  if p_secure_spool_available is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_spool_state');
  end if;
  if p_unresolved_local_jobs is null or p_unresolved_local_jobs < 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_unresolved_count');
  end if;
  -- KITCHEN-MODE-001C3B1A2: the count-certainty state (closed vocab) + the
  -- cross-field invariant (absent => proven-empty). The CHECK constraints
  -- re-prove both at the row; validate here for a typed envelope.
  if p_spool_count_state is null or p_spool_count_state not in ('counted', 'absent', 'unknown') then
    return jsonb_build_object('ok', false, 'error', 'invalid_spool_count_state');
  end if;
  if p_spool_count_state = 'absent' and p_unresolved_local_jobs <> 0 then
    return jsonb_build_object('ok', false, 'error', 'invalid_spool_count_state');
  end if;

  select b.kitchen_workflow_mode_revision into v_rev
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if p_mode_revision is distinct from v_rev then
    return jsonb_build_object('ok', false, 'error', 'stale_mode_revision', 'mode_revision', v_rev);
  end if;

  insert into public.kitchen_pos_status_reports
    (organization_id, restaurant_id, branch_id, device_id, app_build,
     mode_revision, secure_spool_available, unresolved_local_jobs,
     spool_count_state, reported_at, expires_at)
  values
    (v_org, v_rest, v_branch, p_device_id, btrim(p_app_build),
     p_mode_revision, p_secure_spool_available, p_unresolved_local_jobs,
     p_spool_count_state, now(), now() + interval '10 minutes')
  on conflict (organization_id, device_id) do update set
     restaurant_id          = excluded.restaurant_id,
     branch_id              = excluded.branch_id,
     app_build              = excluded.app_build,
     mode_revision          = excluded.mode_revision,
     secure_spool_available = excluded.secure_spool_available,
     unresolved_local_jobs  = excluded.unresolved_local_jobs,
     spool_count_state      = excluded.spool_count_state,
     reported_at            = excluded.reported_at,
     expires_at             = excluded.expires_at,
     updated_at             = now();

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_pos_status',
    'expires_at', now() + interval '10 minutes',
    'server_ts', now());
end;
$$;

-- Latest effective app.pull_kitchen_print_dispatches from 20260727090000_kitchen_mode_001c3b1a_stable_readiness_status.sql; business contract preserved.
create or replace function app.pull_kitchen_print_dispatches(
  p_device_id         uuid,
  p_session_token     text,
  p_limit             integer default 20,
  p_cursor_created_at timestamptz default null,
  p_cursor_id         uuid default null,
  -- CORRECTION-001: the cursor carries the FULL ordering tuple. No 001C
  -- client exists yet, so adding the component is a safe contract change;
  -- it is LAST with a default, so cursorless recovery calls are unchanged.
  p_cursor_type_rank  integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash      text;
  v_org       uuid;
  v_rest      uuid;
  v_branch    uuid;
  v_dtype     text;
  v_mode      text;
  v_brev      integer;
  v_limit     integer;
  v_rows      jsonb;
  v_count     integer;
  v_last_at   timestamptz;
  v_last_rank integer;
  v_last_id   uuid;
  v_has_more  boolean;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    return jsonb_build_object('ok', false, 'error', 'invalid_limit', 'entity', 'kitchen_print_dispatches');
  end if;
  -- CORRECTION-001: the cursor is ALL-OR-NOTHING across its three components
  -- and the rank must be a real rank; a malformed cursor is rejected, never
  -- guessed around.
  if not ((p_cursor_created_at is null and p_cursor_id is null and p_cursor_type_rank is null)
          or (p_cursor_created_at is not null and p_cursor_id is not null and p_cursor_type_rank is not null)) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'kitchen_print_dispatches');
  end if;
  if p_cursor_type_rank is not null and p_cursor_type_rank not in (0, 1, 2) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'kitchen_print_dispatches');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  select ds.organization_id, ds.restaurant_id, ds.branch_id, d.device_type
    into v_org, v_rest, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;
  if v_dtype <> 'pos' then
    -- KDS is explicitly denied: printer-only dispatch payloads never reach a
    -- KDS client through any channel.
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;

  -- BIZBOT-DEVICE-SESSION-FIX-001: renew only after this RPC proves its device role.
  if not (app.renew_device_session(p_device_id, p_session_token) ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;

  select b.kitchen_workflow_mode, b.kitchen_workflow_mode_revision
    into v_mode, v_brev
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if coalesce(v_mode, 'kds') <> 'printer_only' then
    return jsonb_build_object('ok', false, 'error', 'branch_not_printer_only', 'entity', 'kitchen_print_dispatches');
  end if;

  -- The deploy-ahead compatibility guard: only a device with a FRESH,
  -- activation-capable readiness report may claim. No deployed client reports
  -- the capability, so production claims are impossible today.
  -- CORRECTION-001: the report must also carry the CURRENT branch mode
  -- revision — a device whose cached mode view is stale may not claim.
  if not exists (
    select 1 from public.kitchen_printer_readiness_reports rr
    where rr.organization_id = v_org
      and rr.device_id = p_device_id
      and rr.branch_id = v_branch
      and rr.expires_at > now()
      -- KITCHEN-MODE-001C3B1A: the qualifying predicate now REQUIRES a stable,
      -- still-valid kitchen printer assignment. A NULL-assignment 001C3A
      -- report can never unlock the claim. Centralized in the helper so every
      -- consumer stays in exact sync.
      and app.kitchen_readiness_report_qualifies(rr, v_brev)
  ) then
    return jsonb_build_object('ok', false, 'error', 'readiness_required', 'entity', 'kitchen_print_dispatches');
  end if;

  v_limit := p_limit;

  -- ATOMIC CLAIM (CORRECTION-001 tuple contract): ORDER BY and the keyset
  -- cursor use the SAME stable tuple (created_at, type_rank, id), so tied
  -- timestamps can never skip or duplicate a row across a drain loop. The
  -- inner FOR UPDATE serializes concurrent pullers; the outer WHERE re-proves
  -- claimability AFTER the lock wait, so two devices can never claim the
  -- same row. Stale claims (expired) and this device's own claims are
  -- reclaimable; possibly_printed rows are NEVER served; superseded rows are
  -- gone from this feed forever; an UNRESOLVED row never ages out — there is
  -- deliberately NO time window here (CORRECTION-001 retention contract).
  with candidates as (
    select d.id
      from public.kitchen_print_dispatches d
      where d.organization_id = v_org
        and d.branch_id = v_branch
        and d.completed_at is null
        and d.superseded_by_dispatch_id is null
        and d.last_client_status is distinct from 'possibly_printed'
        and (d.claimed_at is null
             or d.claim_expires_at < now()
             or d.claimed_by_device_id = p_device_id)
        and (p_cursor_created_at is null
             or (d.created_at,
                 case d.dispatch_type when 'initial_order' then 0
                                      when 'service_round' then 1 else 2 end,
                 d.id)
                > (p_cursor_created_at, p_cursor_type_rank, p_cursor_id))
      order by d.created_at,
               case d.dispatch_type when 'initial_order' then 0
                                    when 'service_round' then 1 else 2 end,
               d.id
      limit v_limit
      for update of d
  )
  update public.kitchen_print_dispatches d
    set claimed_at = now(),
        claimed_by_device_id = p_device_id,
        claim_expires_at = now() + interval '10 minutes',
        updated_at = now()
    from candidates c
    where d.id = c.id
      and d.completed_at is null
      and d.superseded_by_dispatch_id is null
      and (d.claimed_at is null
           or d.claim_expires_at < now()
           or d.claimed_by_device_id = p_device_id);

  -- The returned page: this device's LIVE claims in tuple order, HARD-capped
  -- at p_limit — own pre-existing active claims can never inflate the page
  -- beyond the requested limit (CORRECTION-001).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'dispatch_type', p.dispatch_type,
           'order_id', p.order_id,
           'service_round_id', p.service_round_id,
           'payload_version', p.payload_version,
           'payload', p.money_free_payload,
           'created_at', p.created_at,
           'claim_expires_at', p.claim_expires_at)
         order by p.created_at, p.type_rank, p.id), '[]'::jsonb),
         count(*)::int,
         (array_agg(p.created_at order by p.created_at desc, p.type_rank desc, p.id desc))[1],
         (array_agg(p.type_rank  order by p.created_at desc, p.type_rank desc, p.id desc))[1],
         (array_agg(p.id         order by p.created_at desc, p.type_rank desc, p.id desc))[1]
    into v_rows, v_count, v_last_at, v_last_rank, v_last_id
    from (
      select d.*,
             case d.dispatch_type when 'initial_order' then 0
                                  when 'service_round' then 1 else 2 end as type_rank
        from public.kitchen_print_dispatches d
        where d.organization_id = v_org
          and d.branch_id = v_branch
          and d.claimed_by_device_id = p_device_id
          and d.claim_expires_at > now()
          and d.completed_at is null
          and d.superseded_by_dispatch_id is null
          and d.last_client_status is distinct from 'possibly_printed'
          and (p_cursor_created_at is null
               or (d.created_at,
                   case d.dispatch_type when 'initial_order' then 0
                                        when 'service_round' then 1 else 2 end,
                   d.id)
                  > (p_cursor_created_at, p_cursor_type_rank, p_cursor_id))
        order by d.created_at,
                 case d.dispatch_type when 'initial_order' then 0
                                      when 'service_round' then 1 else 2 end,
                 d.id
        limit v_limit
    ) p;

  -- TRUTHFUL has_more (CORRECTION-001): true iff a row SERVABLE TO THIS
  -- DEVICE (its own live claim, or still claimable by anyone) exists beyond
  -- the returned page's last tuple.
  if v_count = 0 then
    v_has_more := false;
  else
    select exists (
      select 1 from public.kitchen_print_dispatches d
      where d.organization_id = v_org
        and d.branch_id = v_branch
        and d.completed_at is null
        and d.superseded_by_dispatch_id is null
        and d.last_client_status is distinct from 'possibly_printed'
        and ((d.claimed_by_device_id = p_device_id and d.claim_expires_at > now())
             or d.claimed_at is null
             or d.claim_expires_at < now())
        and (d.created_at,
             case d.dispatch_type when 'initial_order' then 0
                                  when 'service_round' then 1 else 2 end,
             d.id) > (v_last_at, v_last_rank, v_last_id))
      into v_has_more;
  end if;

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_print_dispatches',
    'dispatches', v_rows,
    'has_more', v_has_more,
    'next_cursor', case when v_count > 0
                        then jsonb_build_object('created_at', v_last_at, 'type_rank', v_last_rank, 'id', v_last_id)
                        else null end,
    'server_ts', now());
end;
$$;

-- Latest effective app.acknowledge_kitchen_print_dispatch from 20260825090001_kiosk_kitchen_dispatch_claim_114b2.sql; business contract preserved.
create or replace function app.acknowledge_kitchen_print_dispatch(
  p_device_id      uuid,
  p_session_token  text,
  p_dispatch_id    uuid,
  p_client_status  text,
  p_error_code     text default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash    text;
  v_org     uuid;
  v_branch  uuid;
  v_dtype   text;
  v_row     public.kitchen_print_dispatches%rowtype;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatch');
  end if;
  if p_client_status is null or p_client_status not in
     ('imported', 'transport_accepted', 'possibly_printed', 'failed_retryable', 'blocked_configuration') then
    -- NEVER a physical claim: 'printed'/'paper_printed' are not a vocabulary.
    return jsonb_build_object('ok', false, 'error', 'invalid_status', 'entity', 'kitchen_print_dispatch');
  end if;
  if p_error_code is not null and p_error_code !~ '^[a-z0-9_.\-]{1,64}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_error_code', 'entity', 'kitchen_print_dispatch');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  select ds.organization_id, ds.branch_id, d.device_type
    into v_org, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null or v_dtype not in ('pos', 'kiosk') then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatch');
  end if;
  -- (114B.1) the kiosk principal gets the NARROWEST honest vocabulary: it
  -- imports nothing into a durable spool and configures nothing through
  -- this path, so only the three physical-outcome statuses are meaningful.
  -- Ownership stays the existing claim-holder rule below -- the only way a
  -- kiosk ever holds a claim is the claim-at-submit on its OWN order.
  if v_dtype = 'kiosk' and p_client_status not in
     ('transport_accepted', 'failed_retryable', 'possibly_printed') then
    return jsonb_build_object('ok', false, 'error', 'invalid_status', 'entity', 'kitchen_print_dispatch');
  end if;

  -- BIZBOT-DEVICE-SESSION-FIX-001: renew only after this RPC proves its device role.
  if not (app.renew_device_session(p_device_id, p_session_token) ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatch');
  end if;

  select * into v_row from public.kitchen_print_dispatches d
    where d.id = p_dispatch_id and d.organization_id = v_org and d.branch_id = v_branch
    for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'kitchen_print_dispatch');
  end if;

  -- Idempotent replay: already completed BY THIS DEVICE.
  if v_row.completed_at is not null then
    if v_row.claimed_by_device_id = p_device_id and p_client_status = 'transport_accepted' then
      return jsonb_build_object('ok', true, 'entity', 'kitchen_print_dispatch',
        'dispatch_id', v_row.id, 'completed', true, 'idempotency_replay', true, 'server_ts', now());
    end if;
    return jsonb_build_object('ok', false, 'error', 'conflict', 'entity', 'kitchen_print_dispatch');
  end if;

  -- Claim ownership: the current claim holder while valid, PLUS the designed
  -- stale-recovery path — the device that HELD the claim may still finish its
  -- slow print after expiry, as long as nobody else claimed meanwhile.
  if v_row.claimed_by_device_id is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'not_claim_owner', 'entity', 'kitchen_print_dispatch');
  end if;

  -- CORRECTION-001 STICKY HOLD: once possibly_printed, the ambiguity can
  -- never be resolved by the machine — paper may or may not exist. The ONLY
  -- allowed acknowledgement is an idempotent possibly_printed replay by the
  -- owner; every other status (imported / failed_retryable /
  -- blocked_configuration / transport_accepted) is refused with a typed
  -- conflict, the permanent no-lease hold stays, and nothing ever becomes
  -- automatically pullable again. Resolution is a future explicit
  -- operator-facing RPC, deliberately NOT part of 001C1.
  if v_row.last_client_status = 'possibly_printed' then
    if p_client_status = 'possibly_printed' then
      return jsonb_build_object('ok', true, 'entity', 'kitchen_print_dispatch',
        'dispatch_id', v_row.id, 'completed', false, 'idempotency_replay', true, 'server_ts', now());
    end if;
    return jsonb_build_object('ok', false, 'error', 'ambiguous_print_hold', 'entity', 'kitchen_print_dispatch');
  end if;

  if p_client_status = 'transport_accepted' then
    update public.kitchen_print_dispatches
      set completed_at = now(), last_client_status = p_client_status,
          last_error_code = null, updated_at = now()
      where id = v_row.id;
  elsif p_client_status = 'possibly_printed' then
    -- Permanent hold: NEVER auto-re-served (a blind retry could duplicate
    -- paper). Stays visible/unresolved until an operator acts (001C2 UX).
    update public.kitchen_print_dispatches
      set last_client_status = p_client_status,
          last_error_code = p_error_code,
          claim_expires_at = null, updated_at = now()
      where id = v_row.id;
  elsif p_client_status = 'imported' then
    update public.kitchen_print_dispatches
      set last_client_status = p_client_status,
          claim_expires_at = now() + interval '10 minutes', updated_at = now()
      where id = v_row.id;
  else
    -- failed_retryable / blocked_configuration: recorded; the claim keeps its
    -- natural expiry so the SAME or another POS can retry after it lapses.
    update public.kitchen_print_dispatches
      set last_client_status = p_client_status,
          last_error_code = p_error_code, updated_at = now()
      where id = v_row.id;
  end if;

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_print_dispatch',
    'dispatch_id', v_row.id,
    'completed', (p_client_status = 'transport_accepted'),
    'idempotency_replay', false,
    'server_ts', now());
end;
$$;

create or replace function app.kiosk_session_context(
  p_device_id     uuid,
  p_session_token text,
  out o_session   uuid,
  out o_org       uuid,
  out o_rest      uuid,
  out o_branch    uuid
)
  language plpgsql
  volatile
  security definer
  set search_path = ''
as $$
declare
  v_hash text;
begin
  o_session := null; o_org := null; o_rest := null; o_branch := null;
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return;
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));
  select ds.id, ds.organization_id, ds.restaurant_id, ds.branch_id
    into o_session, o_org, o_rest, o_branch
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
      and (ds.expires_at is null or ds.expires_at > now())  -- RF-118: expired = refused
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null
      and d.device_type = 'kiosk';                          -- kiosk-only capability gate
  -- BIZBOT-DEVICE-SESSION-FIX-001: context consumers are VOLATILE below.
  if o_session is not null
     and not (app.renew_device_session(p_device_id, p_session_token) ->> 'ok')::boolean then
    o_session := null; o_org := null; o_rest := null; o_branch := null;
  end if;
end;
$$;

-- Both app read bodies call kiosk_session_context; the public wrappers must
-- also permit its renewal write. kiosk_submit_order already is VOLATILE.
alter function app.kiosk_menu(uuid, text) volatile;
alter function public.kiosk_menu(uuid, text) volatile;
alter function app.kiosk_tables(uuid, text) volatile;
alter function public.kiosk_tables(uuid, text) volatile;
comment on function app.kiosk_session_context(uuid, text) is
  'BIZBOT-DEVICE-SESSION-FIX-001: internal kiosk-only token context and throttled 30-day renewal. NULL outputs remain the invalid-session contract. VOLATILE through kiosk_menu/kiosk_tables/submit; no direct client grant. Wrong-role, expired, inactive, revoked, or dead-scope sessions never renew.';


-- Latest support-aware list_devices body; actor_read_rank_in_scope is preserved.
create or replace function app.list_devices(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_items jsonb;
begin
  if v_actor is null then
    raise exception 'list_devices: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_devices: organization_id is required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_devices: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < 2 then     -- cashier/kitchen_staff/accountant cannot manage/list devices
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device');
  end if;

  select coalesce(jsonb_agg(item order by (item ->> 'label'), (item ->> 'device_id')), '[]'::jsonb)
    into v_items
  from (
    select jsonb_build_object(
      'device_id',         d.id,
      'label',             d.label,
      'device_type',       d.device_type,
      'branch_id',         d.branch_id,
      'branch_label',      b.name,
      'status',            coalesce(lp.status, 'none'),
      'device_pairing_id', lp.id,
      'has_open_session',  coalesce(ls.is_valid, false),
      'session_expires_at', ls.expires_at,
      'last_seen_at',      d.last_seen_at
    ) as item
    from public.devices d
    join public.branches b on b.id = d.branch_id
    left join lateral (
      select p.id, p.status
      from public.device_pairings p
      where p.device_id = d.id and p.deleted_at is null
      order by p.created_at desc
      limit 1
    ) lp on true
    -- Prefer the newest usable session; otherwise expose the newest historical
    -- deadline. The flag and expiry describe the SAME row even for legacy
    -- devices with multiple sessions. NULL expiry remains valid until activity.
    left join lateral (
      select ds.expires_at,
        (ds.is_active and ds.revoked_at is null
          and (ds.expires_at is null or ds.expires_at > now())
          and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
          and d.is_active
          and ds.organization_id = d.organization_id
          and ds.restaurant_id = d.restaurant_id and ds.branch_id = d.branch_id
          and b.status = 'active' and b.deleted_at is null
          and r.status = 'active' and r.deleted_at is null
          and org.status = 'active' and org.deleted_at is null) as is_valid
      from public.device_sessions ds
      join public.device_pairings dp on dp.id = ds.device_pairing_id
        and dp.device_id = ds.device_id and dp.organization_id = ds.organization_id
        and dp.restaurant_id = ds.restaurant_id and dp.branch_id = ds.branch_id
      join public.restaurants r on r.id = ds.restaurant_id and r.organization_id = ds.organization_id
      join public.organizations org on org.id = ds.organization_id
      where ds.device_id = d.id
      order by is_valid desc, ds.started_at desc, ds.id desc
      limit 1
    ) ls on true
    where d.organization_id = p_organization_id
      and (p_restaurant_id is null or d.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or d.branch_id     = p_branch_id)
      and d.deleted_at is null
  ) t;

  return jsonb_build_object('ok', true, 'entity', 'device', 'devices', v_items, 'server_now', now());
end;
$function$;

-- New functions never broaden either global public surface. These assertions
-- deliberately match STOREFRONT-READ-001 and pending #288 in either apply order.
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
    raise exception 'BIZBOT-DEVICE-SESSION-FIX-001: unexpected anon public surface [%]', v_anon_set;
  end if;
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public\.', ''), ', '
    order by regexp_replace(p.oid::regprocedure::text, '^public\.', '')), '')
    into v_defs from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef;
  if v_defs <> 'storefront_menu(text)' then
    raise exception 'BIZBOT-DEVICE-SESSION-FIX-001: unexpected public DEFINER surface [%]', v_defs;
  end if;
  if has_schema_privilege('anon', 'app', 'USAGE') then
    raise exception 'BIZBOT-DEVICE-SESSION-FIX-001: anon has app schema usage';
  end if;
  if has_function_privilege('authenticated', 'app.renew_device_session(uuid,text)', 'EXECUTE') then
    raise exception 'BIZBOT-DEVICE-SESSION-FIX-001: internal renewal directly executable';
  end if;
end;
$$;
