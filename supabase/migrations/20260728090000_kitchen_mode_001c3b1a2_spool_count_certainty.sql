-- ============================================================================
-- KITCHEN-MODE-001C3B1A2 - Authoritative POS spool-COUNT CERTAINTY.
--
-- ADDITIVE ONLY. No workflow-mode setter, no resolver, no public mode writer,
-- no authenticated mode-write grant, no branch conversion. Production
-- printer_only activation remains structurally impossible.
--
-- WHY: the 001C3B1A status contract (secure_spool_available + unresolved_
-- local_jobs) cannot distinguish a PROVEN-empty spool from one whose count
-- could not be determined - both surface as unresolved_local_jobs = 0. The
-- future printer_only -> kds escape gate (001C3B1B) must NEVER read an unknown
-- count as empty, so this phase adds an explicit, authoritative
-- count-certainty state BEFORE the setter exists.
--
--   1. kitchen_pos_status_reports.spool_count_state text NOT NULL DEFAULT
--      'unknown' CHECK in ('counted','absent','unknown'); a table CHECK also
--      enforces the cross-field invariant absent => unresolved_local_jobs = 0.
--      Legacy 001C3B1A rows / old-client reports carry 'unknown' (fail-closed
--      for the future escape; never fabricated as counted/absent).
--   2. app.report_kitchen_pos_status - a NEW 7-arg canonical signature taking
--      p_spool_count_state (validated closed vocabulary + cross-field); the
--      shipped 6-arg signature is re-created to DELEGATE with 'unknown', so
--      deployed 001C3B1A clients keep working, their reports non-escapable.
--      Exactly two overloads per schema; no stale third.
--
-- NOTE: spool_count_state (was the count determinable?) is INDEPENDENT of
-- secure_spool_available (is the spool usable for encrypted printing?). A
-- readable DB with a missing/corrupt key is 'counted' + secure_spool=false:
-- the count is authoritative even though the spool cannot print. The value is
-- deliberately NOT named 'available' to avoid confusion with that field.
--
-- FUTURE 001C3B1B ESCAPE RULE (DOCUMENTED HERE, NOT IMPLEMENTED IN THIS PHASE).
-- When the printer_only -> kds mode setter is finally built, its drain-safety
-- precondition for a given POS device MUST be, for a FRESH (non-expired) status
-- row belonging to the CURRENT mode revision:
--     spool_count_state IN ('counted','absent')  AND  unresolved_local_jobs = 0
-- i.e. the empty spool must be PROVEN. spool_count_state = 'unknown' (an old
-- 6-arg client, or a device whose DB could not be opened/counted) is NEVER
-- escape-eligible, even when unresolved_local_jobs happens to read 0 -- that 0
-- is not a claim. This phase exists so that gate has a truthful signal to read;
-- it adds NO setter, NO resolver, NO writer, and NO such gate.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Count-certainty column + cross-field invariant.
-- ----------------------------------------------------------------------------
alter table public.kitchen_pos_status_reports
  add column spool_count_state text not null default 'unknown'
    constraint kitchen_pos_status_reports_spool_count_state_check
    check (spool_count_state in ('counted', 'absent', 'unknown'));

-- Cross-field invariant: an ABSENT spool has authoritatively ZERO unresolved
-- jobs (nothing was ever spooled). 'counted' may carry any >= 0; 'unknown'
-- may carry any >= 0 but the value is NON-authoritative (the escape gate
-- rejects 'unknown' regardless of the count).
alter table public.kitchen_pos_status_reports
  add constraint kitchen_pos_status_reports_absent_zero_check
  check (spool_count_state <> 'absent' or unresolved_local_jobs = 0);

comment on column public.kitchen_pos_status_reports.spool_count_state is
  'KITCHEN-MODE-001C3B1A2: whether unresolved_local_jobs is AUTHORITATIVE. counted = the spool DB opened and the count is exact; absent = no spool DB file, count proven 0; unknown = the DB could not be opened/counted (or an old client) - the count is NON-authoritative and the future escape gate must never treat it as empty. INDEPENDENT of secure_spool_available (printability). Legacy rows default ''unknown'' (fail closed).';

-- ----------------------------------------------------------------------------
-- 2. app.report_kitchen_pos_status - NEW 7-arg canonical signature (count-state
--    aware) + the shipped 6-arg signature re-created to delegate with
--    'unknown'. Deployed 001C3B1A clients keep working; their reports carry a
--    non-authoritative count (never escape-eligible).
-- ----------------------------------------------------------------------------
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

comment on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer, text) is
  'KITCHEN-MODE-001C3B1A + 001C3B1A2: a POS device''s configuration-INDEPENDENT spool status upsert, NOW with the authoritative spool_count_state (counted | absent | unknown). Device-token authenticated (full liveness, KDS denied, scope from the session); validates app_build/spool/unresolved, the closed count-state vocabulary, the cross-field invariant (absent => 0), and the CURRENT branch mode revision (stale returns the authoritative revision). No printer/transport/paper/fingerprint/endpoint/customer/money data. One current row per device, 10-minute server validity. No audit row (device-only path, D-013).';

-- 6-arg legacy signature: re-created to DELEGATE with an UNKNOWN count state so
-- deployed 001C3B1A clients keep working; their reports are stored with a
-- non-authoritative count (never escape-eligible in the future 001C3B1B gate).
create or replace function app.report_kitchen_pos_status(
  p_device_id              uuid,
  p_session_token          text,
  p_app_build              text,
  p_mode_revision          integer,
  p_secure_spool_available boolean,
  p_unresolved_local_jobs  integer
)
  returns jsonb
  language sql
  security definer
  set search_path = ''
as $$
  select app.report_kitchen_pos_status(
    p_device_id, p_session_token, p_app_build, p_mode_revision,
    p_secure_spool_available, p_unresolved_local_jobs, 'unknown');
$$;

comment on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) is
  'KITCHEN-MODE-001C3B1A2: the LEGACY 6-arg POS status signature, re-created to delegate to the count-state-aware 7-arg canonical function with spool_count_state=''unknown''. Deployed 001C3B1A clients keep working; their reports carry a NON-authoritative count and are never escape-eligible.';

create or replace function public.report_kitchen_pos_status(
  p_device_id uuid, p_session_token text, p_app_build text,
  p_mode_revision integer, p_secure_spool_available boolean,
  p_unresolved_local_jobs integer, p_spool_count_state text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.report_kitchen_pos_status(p_device_id, p_session_token, p_app_build, p_mode_revision, p_secure_spool_available, p_unresolved_local_jobs, p_spool_count_state); $$;

-- grants: BOTH signatures, both schemas (the 6-arg pair already granted in
-- 001C3B1A; re-issue for parity + the new 7-arg).
revoke all on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) from public;
revoke all on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) from anon;
grant execute on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) to authenticated;
revoke all on function public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) from public;
revoke all on function public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) from anon;
grant execute on function public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) to authenticated;
revoke all on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer, text) from public;
revoke all on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer, text) from anon;
grant execute on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer, text) to authenticated;
revoke all on function public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer, text) from public;
revoke all on function public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer, text) from anon;
grant execute on function public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer, text) to authenticated;
