-- ============================================================================
-- KITCHEN-MODE-001C3B1A - Stable readiness assignment identity + a
-- configuration-independent POS spool/status report.
--
-- ADDITIVE ONLY. No workflow-mode setter, no ambiguous-hold resolver, no
-- public mode writer, no authenticated mode-write grant. Production
-- printer_only activation remains structurally impossible.
--
--   1. kitchen_printer_readiness_reports.printer_assignment_id (nullable) - a
--      STABLE reference to the exact printer_devices row the report describes,
--      composite-FK ON DELETE SET NULL (a deleted printer fails the report
--      closed, never cascades away readiness history). Old 001C3A reports keep
--      a NULL id and are structurally NON-QUALIFYING.
--   2. app.kitchen_readiness_assignment_valid / _report_qualifies - the ONE
--      canonical qualifying predicate (assignment binding + capability/purpose/
--      80mm/secure-spool/revision), reused by every consumer.
--   3. app.report_kitchen_printer_readiness - a NEW 12-arg canonical signature
--      taking p_printer_assignment_id; the shipped 11-arg signature is
--      re-created to DELEGATE with a NULL assignment (deployed 001C3A clients
--      keep working, their reports non-qualifying). No third overload.
--   4. Qualifying consumers re-created to use the helper: pull's claim gate and
--      the transition-readiness selection + a new
--      'kitchen_printer_assignment_required' diagnostic blocker.
--   5. kitchen_pos_status_reports + app.report_kitchen_pos_status - a
--      configuration-INDEPENDENT device status (spool availability + unresolved
--      count + revision) that stays fresh even with NO kitchen printer, for the
--      future safe printer_only -> kds escape gate. No printer/endpoint/money
--      columns at all.
--
-- FINGERPRINT NOTE (accepted this phase): printer_devices stores the endpoint
-- inside connection_config, but there is NO server-side helper reproducing the
-- client's sha256('network|host|port') canonicalization. Rather than invent an
-- incompatible algorithm or expose an endpoint, the qualifying binding is by
-- assignment ID + scope + transport + role + width; printer_fingerprint stays a
-- client-supplied routing-integrity field. A server-recomputed fingerprint is a
-- later additive concern and is documented as a remaining limitation.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Stable printer-assignment identity on the readiness report.
-- ----------------------------------------------------------------------------
alter table public.kitchen_printer_readiness_reports
  add column printer_assignment_id uuid;

-- Composite FK into the report's OWN (org, restaurant, branch) scope so the
-- assignment can never point at another branch's printer. ON DELETE SET NULL:
-- deleting/retiring a printer_devices row nulls the reference (fail closed to
-- non-qualifying) and never deletes readiness history.
alter table public.kitchen_printer_readiness_reports
  add constraint kitchen_printer_readiness_reports_assignment_fk
  foreign key (organization_id, restaurant_id, branch_id, printer_assignment_id)
  references public.printer_devices (organization_id, restaurant_id, branch_id, id)
  -- PG15 column-restricted SET NULL: ONLY the assignment id is nulled on a
  -- printer delete (org/rest/branch stay; the readiness row + history survive).
  on delete set null (printer_assignment_id);

create index kitchen_printer_readiness_reports_assignment_idx
  on public.kitchen_printer_readiness_reports
     (organization_id, restaurant_id, branch_id, printer_assignment_id)
  where printer_assignment_id is not null;

comment on column public.kitchen_printer_readiness_reports.printer_assignment_id is
  'KITCHEN-MODE-001C3B1A: the STABLE printer_devices identity this report describes (never list position). NULL for a legacy 001C3A report or after the printer is deleted (ON DELETE SET NULL) - either way the report is structurally NON-QUALIFYING for activation.';

-- ----------------------------------------------------------------------------
-- 2. The ONE canonical qualifying predicate (assignment binding + report content).
-- ----------------------------------------------------------------------------
create or replace function app.kitchen_readiness_assignment_valid(
  p_report public.kitchen_printer_readiness_reports)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- The report's pinned assignment must still be a live, enabled, kitchen-
  -- capable 80mm printer whose transport matches the reported transport, in
  -- the report's OWN scope. No endpoint is read or exposed.
  select p_report.printer_assignment_id is not null
     and exists (
       select 1 from public.printer_devices pd
       where pd.organization_id = p_report.organization_id
         and pd.restaurant_id   = p_report.restaurant_id
         and pd.branch_id       = p_report.branch_id
         and pd.id              = p_report.printer_assignment_id
         and pd.deleted_at is null
         and pd.is_enabled
         and pd.role in ('kitchen', 'both')
         and pd.paper_width = '80mm'
         and pd.connection_type = p_report.transport_kind
     );
$$;

comment on function app.kitchen_readiness_assignment_valid(public.kitchen_printer_readiness_reports) is
  'KITCHEN-MODE-001C3B1A: TRUE when the report pins a still-valid kitchen printer assignment (live + enabled + role kitchen/both + 80mm + transport match, same scope). No endpoint read/exposed. INTERNAL.';

revoke all on function app.kitchen_readiness_assignment_valid(public.kitchen_printer_readiness_reports) from public;
revoke all on function app.kitchen_readiness_assignment_valid(public.kitchen_printer_readiness_reports) from anon;
revoke all on function app.kitchen_readiness_assignment_valid(public.kitchen_printer_readiness_reports) from authenticated;

create or replace function app.kitchen_readiness_report_qualifies(
  p_report public.kitchen_printer_readiness_reports,
  p_branch_revision integer)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- The FULL activation-qualifying predicate for ONE report (freshness, device
  -- liveness, pairing and scope are the CALLER's job; this is the report's own
  -- intrinsic content + its stable assignment binding + the mode revision).
  select p_report.capability = 'kitchen_printer_only_v1'
     and p_report.printer_purpose = 'kitchen_ticket'
     and p_report.paper_width = '80mm'
     and p_report.secure_spool_available
     and p_report.mode_revision = p_branch_revision
     and app.kitchen_readiness_assignment_valid(p_report);
$$;

comment on function app.kitchen_readiness_report_qualifies(public.kitchen_printer_readiness_reports, integer) is
  'KITCHEN-MODE-001C3B1A: the ONE canonical activation-qualifying predicate for a readiness report (capability/purpose/80mm/secure-spool/revision + stable assignment binding). Freshness/device-liveness/pairing/scope stay the caller''s responsibility. Reused by pull, transition-readiness and the report RPC so every consumer is identical. INTERNAL.';

revoke all on function app.kitchen_readiness_report_qualifies(public.kitchen_printer_readiness_reports, integer) from public;
revoke all on function app.kitchen_readiness_report_qualifies(public.kitchen_printer_readiness_reports, integer) from anon;
revoke all on function app.kitchen_readiness_report_qualifies(public.kitchen_printer_readiness_reports, integer) from authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.report_kitchen_printer_readiness - NEW 12-arg canonical signature
--    (assignment-aware) + the shipped 11-arg signature re-created to delegate
--    with a NULL assignment. Deployed 001C3A clients keep working; their
--    reports store a NULL assignment and are non-qualifying.
-- ----------------------------------------------------------------------------
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

comment on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer, uuid) is
  'KITCHEN-MODE-001C1 + 001C3B1A: the POS''s kitchen-printing readiness report, NOW assignment-aware (p_printer_assignment_id pins the stable printer_devices identity; a supplied-but-invalid/foreign assignment is a typed invalid_printer_assignment; a NULL assignment is stored but never qualifies). Device-token authenticated (full liveness; KDS denied; scope from the session). activation_ready = 80mm + secure spool + valid pinned assignment. One current report per device, 10-minute server validity. No audit row (device-only path, D-013).';

-- 11-arg legacy signature: re-created to DELEGATE with a NULL assignment so
-- deployed 001C3A clients keep working (their reports are non-qualifying).
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
  p_mode_revision          integer
)
  returns jsonb
  language sql
  security definer
  set search_path = ''
as $$
  select app.report_kitchen_printer_readiness(
    p_device_id, p_session_token, p_capability, p_app_build, p_printer_purpose,
    p_transport_kind, p_paper_width, p_printer_fingerprint,
    p_secure_spool_available, p_unresolved_local_jobs, p_mode_revision, null);
$$;

comment on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) is
  'KITCHEN-MODE-001C3B1A: the LEGACY 11-arg readiness signature, re-created to delegate to the assignment-aware 12-arg canonical function with a NULL assignment. Deployed 001C3A clients keep working; a NULL-assignment report is stored but can never qualify for activation.';

create or replace function public.report_kitchen_printer_readiness(
  p_device_id uuid, p_session_token text, p_capability text, p_app_build text,
  p_printer_purpose text, p_transport_kind text, p_paper_width text,
  p_printer_fingerprint text, p_secure_spool_available boolean,
  p_unresolved_local_jobs integer, p_mode_revision integer,
  p_printer_assignment_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.report_kitchen_printer_readiness(p_device_id, p_session_token, p_capability, p_app_build, p_printer_purpose, p_transport_kind, p_paper_width, p_printer_fingerprint, p_secure_spool_available, p_unresolved_local_jobs, p_mode_revision, p_printer_assignment_id); $$;

-- grants: BOTH signatures, both schemas (11-arg already granted in 001C1; the
-- re-created app 11-arg keeps its ACL; re-issue for parity + the new 12-arg).
revoke all on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from public;
revoke all on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from anon;
grant execute on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) to authenticated;
revoke all on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from public;
revoke all on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) from anon;
grant execute on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer) to authenticated;
revoke all on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer, uuid) from public;
revoke all on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer, uuid) from anon;
grant execute on function app.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer, uuid) to authenticated;
revoke all on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer, uuid) from public;
revoke all on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer, uuid) from anon;
grant execute on function public.report_kitchen_printer_readiness(uuid, text, text, text, text, text, text, text, boolean, integer, integer, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4a. Re-create app.pull_kitchen_print_dispatches (VERBATIM 001C1 body; the ONLY
--     delta is the claim gate now using app.kitchen_readiness_report_qualifies).
-- ----------------------------------------------------------------------------
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


create or replace function public.pull_kitchen_print_dispatches(
  p_device_id uuid, p_session_token text, p_limit integer default 20,
  p_cursor_created_at timestamptz default null, p_cursor_id uuid default null,
  p_cursor_type_rank integer default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.pull_kitchen_print_dispatches(p_device_id, p_session_token, p_limit, p_cursor_created_at, p_cursor_id, p_cursor_type_rank); $$;

revoke all on function app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) from public;
revoke all on function app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) from anon;
grant execute on function app.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) to authenticated;
revoke all on function public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) from public;
revoke all on function public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) from anon;
grant execute on function public.pull_kitchen_print_dispatches(uuid, text, integer, timestamptz, uuid, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 4b. Re-create app.get_kitchen_workflow_transition_readiness (VERBATIM 001C1
--     body; deltas: qualifying selection via the helper + a new diagnostic
--     'kitchen_printer_assignment_required' blocker).
-- ----------------------------------------------------------------------------
create or replace function app.get_kitchen_workflow_transition_readiness(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor          uuid := app.current_app_user_id();
  v_rank           integer;
  v_mode           text;
  v_rev            integer;
  v_active_orders  integer;
  v_ready_orders   integer;
  v_active_rounds  integer;
  v_pending_ops    integer;
  v_unresolved     integer;
  v_pending_voids  integer;
  v_report         public.kitchen_printer_readiness_reports%rowtype;
  v_diag           public.kitchen_printer_readiness_reports%rowtype;
  v_used           public.kitchen_printer_readiness_reports%rowtype;
  v_to_po          jsonb := '[]'::jsonb;
  v_to_kds         jsonb := '[]'::jsonb;
begin
  if v_actor is null then
    raise exception 'get_kitchen_workflow_transition_readiness: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;

  select b.kitchen_workflow_mode, b.kitchen_workflow_mode_revision
    into v_mode, v_rev
    from public.branches b
    where b.id = p_branch_id and b.organization_id = p_organization_id
      and b.restaurant_id = p_restaurant_id and b.deleted_at is null;
  if v_mode is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;

  -- The server RECOMPUTES every server-side blocker itself; the only client
  -- input is the fresh device-session-proven readiness report row.
  select count(*)::int into v_active_orders
    from public.orders o
    where o.organization_id = p_organization_id and o.branch_id = p_branch_id
      and o.deleted_at is null
      and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served');
  select count(*)::int into v_ready_orders
    from public.orders o
    where o.organization_id = p_organization_id and o.branch_id = p_branch_id
      and o.deleted_at is null and o.status = 'ready';
  select count(*)::int into v_active_rounds
    from public.order_service_rounds r
    where r.organization_id = p_organization_id and r.branch_id = p_branch_id
      and r.deleted_at is null
      and r.status in ('submitted', 'accepted', 'preparing', 'ready');
  select count(*)::int into v_pending_ops
    from public.sync_operations so
    where so.organization_id = p_organization_id and so.branch_id = p_branch_id
      and so.status in ('created', 'pending', 'in_flight');
  select count(*)::int into v_unresolved
    from public.kitchen_print_dispatches d
    where d.organization_id = p_organization_id and d.branch_id = p_branch_id
      and d.completed_at is null and d.superseded_by_dispatch_id is null;
  select count(*)::int into v_pending_voids
    from public.kitchen_print_dispatches d
    where d.organization_id = p_organization_id and d.branch_id = p_branch_id
      and d.dispatch_type = 'void'
      and d.completed_at is null and d.superseded_by_dispatch_id is null;
  -- CORRECTION-001 readiness selection: the report that satisfies a blocker
  -- must be a FULLY QUALIFYING one — fresh, activation-capable (80mm + secure
  -- spool), carrying the CURRENT mode revision, and filed by a LIVE,
  -- correctly-scoped, actively-paired POS device. A newer non-qualifying
  -- report (58mm, stale revision, revoked device, ...) can never SHADOW a
  -- valid qualifying report from another compatible POS.
  select rr.* into v_report
    from public.kitchen_printer_readiness_reports rr
    join public.devices d
      on  d.id = rr.device_id
      and d.organization_id = rr.organization_id
      and d.restaurant_id   = rr.restaurant_id
      and d.branch_id       = rr.branch_id
      and d.device_type = 'pos' and d.is_active and d.deleted_at is null
    where rr.organization_id = p_organization_id and rr.branch_id = p_branch_id
      and rr.expires_at > now()
      -- KITCHEN-MODE-001C3B1A: full qualifying predicate incl. the stable
      -- printer-assignment binding (app.kitchen_readiness_report_qualifies).
      and app.kitchen_readiness_report_qualifies(rr, v_rev)
      and exists (select 1 from public.device_pairings dp
                   where dp.device_id = d.id and dp.organization_id = d.organization_id
                     and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null)
    order by rr.reported_at desc
    limit 1;
  if v_report.id is null then
    -- DIAGNOSTIC fallback (still live-device + fresh + capability-matched):
    -- names the SPECIFIC deficiency instead of a generic absence.
    select rr.* into v_diag
      from public.kitchen_printer_readiness_reports rr
      join public.devices d
        on  d.id = rr.device_id
        and d.organization_id = rr.organization_id
        and d.restaurant_id   = rr.restaurant_id
        and d.branch_id       = rr.branch_id
        and d.device_type = 'pos' and d.is_active and d.deleted_at is null
      where rr.organization_id = p_organization_id and rr.branch_id = p_branch_id
        and rr.expires_at > now()
        and rr.capability = 'kitchen_printer_only_v1'
        and rr.printer_purpose = 'kitchen_ticket'
        and exists (select 1 from public.device_pairings dp
                     where dp.device_id = d.id and dp.organization_id = d.organization_id
                       and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null)
      order by rr.reported_at desc
      limit 1;
  end if;
  if v_report.id is not null then
    v_used := v_report;
  else
    v_used := v_diag;
  end if;

  -- kds -> printer_only blockers.
  if v_active_orders > 0 then v_to_po := v_to_po || '"active_orders"'::jsonb; end if;
  if v_active_rounds > 0 then v_to_po := v_to_po || '"active_service_rounds"'::jsonb; end if;
  if v_ready_orders > 0 then v_to_po := v_to_po || '"unresolved_ready_state"'::jsonb; end if;
  if v_pending_ops > 0 then v_to_po := v_to_po || '"unresolved_sync_operations"'::jsonb; end if;
  if v_report.id is not null then
    null; -- a fully qualifying live report exists: no readiness blocker.
  elsif v_diag.id is null then
    v_to_po := v_to_po || '"no_fresh_pos_readiness"'::jsonb;
  else
    if v_diag.paper_width <> '80mm' then v_to_po := v_to_po || '"paper_width_80mm_required"'::jsonb; end if;
    if not v_diag.secure_spool_available then v_to_po := v_to_po || '"secure_spool_unavailable"'::jsonb; end if;
    if v_diag.mode_revision <> v_rev then v_to_po := v_to_po || '"stale_mode_revision"'::jsonb; end if;
    -- KITCHEN-MODE-001C3B1A: a fresh diagnostic report otherwise fine but
    -- lacking a stable, still-valid kitchen printer assignment (a 001C3A
    -- report with a NULL id, or a disabled/deleted/58mm/receipt-only/
    -- transport-mismatched assignment) names the specific deficiency.
    if v_diag.printer_assignment_id is null
       or not app.kitchen_readiness_assignment_valid(v_diag) then
      v_to_po := v_to_po || '"kitchen_printer_assignment_required"'::jsonb;
    end if;
  end if;

  -- printer_only -> kds blockers.
  if v_unresolved > 0 then v_to_kds := v_to_kds || '"unresolved_dispatches"'::jsonb; end if;
  if v_pending_voids > 0 then v_to_kds := v_to_kds || '"pending_void_dispatches"'::jsonb; end if;
  if v_active_orders > 0 then v_to_kds := v_to_kds || '"active_orders"'::jsonb; end if;
  if v_active_rounds > 0 then v_to_kds := v_to_kds || '"active_service_rounds"'::jsonb; end if;
  if v_used.id is null then
    v_to_kds := v_to_kds || '"no_fresh_pos_status_report"'::jsonb;
  elsif v_used.unresolved_local_jobs > 0 then
    v_to_kds := v_to_kds || '"unresolved_local_jobs"'::jsonb;
  end if;

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_workflow_transition_readiness',
    'mode', v_mode,
    'mode_revision', v_rev,
    'to_printer_only', jsonb_build_object(
      'ready', (jsonb_array_length(v_to_po) = 0), 'blockers', v_to_po),
    'to_kds', jsonb_build_object(
      'ready', (jsonb_array_length(v_to_kds) = 0), 'blockers', v_to_kds),
    'counts', jsonb_build_object(
      'active_orders', v_active_orders,
      'active_service_rounds', v_active_rounds,
      'ready_orders', v_ready_orders,
      'pending_sync_operations', v_pending_ops,
      'unresolved_dispatches', v_unresolved,
      'pending_void_dispatches', v_pending_voids,
      'unresolved_local_jobs', coalesce(v_used.unresolved_local_jobs, 0)),
    'readiness_report', case when v_used.id is null then null else jsonb_build_object(
      'reported_at', v_used.reported_at,
      'expires_at', v_used.expires_at,
      'paper_width', v_used.paper_width,
      'transport_kind', v_used.transport_kind,
      'secure_spool_available', v_used.secure_spool_available,
      'app_build', v_used.app_build,
      -- CORRECTION-001: says explicitly whether this is the fully QUALIFYING
      -- live report or only the best diagnostic one.
      'qualifying', (v_report.id is not null)) end,
    'server_ts', now());
end;
$$;


create or replace function public.get_kitchen_workflow_transition_readiness(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_kitchen_workflow_transition_readiness(p_organization_id, p_restaurant_id, p_branch_id); $$;

revoke all on function app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from public;
revoke all on function app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from anon;
grant execute on function app.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) to authenticated;
revoke all on function public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from public;
revoke all on function public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) from anon;
grant execute on function public.get_kitchen_workflow_transition_readiness(uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. kitchen_pos_status_reports - configuration-INDEPENDENT device spool status.
--    Stays fresh with NO kitchen printer; for the future safe printer_only->kds
--    escape gate. NO printer/transport/paper/fingerprint/endpoint/money columns.
-- ----------------------------------------------------------------------------
create table public.kitchen_pos_status_reports (
  id                     uuid        not null default gen_random_uuid(),
  organization_id        uuid        not null references public.organizations (id) on delete restrict,
  restaurant_id          uuid        not null,
  branch_id              uuid        not null,
  device_id              uuid        not null,
  app_build              text        not null check (length(btrim(app_build)) between 1 and 64),
  mode_revision          integer     not null check (mode_revision > 0),
  secure_spool_available boolean     not null,
  unresolved_local_jobs  integer     not null check (unresolved_local_jobs >= 0),
  reported_at            timestamptz not null default now(),
  expires_at             timestamptz not null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  primary key (id),
  unique (organization_id, device_id),
  foreign key (organization_id, restaurant_id, branch_id)
    references public.branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references public.devices (organization_id, restaurant_id, branch_id, id) on delete restrict
);

comment on table public.kitchen_pos_status_reports is
  'KITCHEN-MODE-001C3B1A: a POS device''s configuration-INDEPENDENT spool/status report (secure-spool availability + unresolved local job count + branch mode revision). One current row per device (upsert), authoritative only while unexpired (reported_at + 10 min). Unlike readiness it needs NO printer assignment, transport, paper width, fingerprint or endpoint - it exists so the future printer_only -> kds escape gate can require a fresh authoritative statement that unresolved_local_jobs = 0 even when no kitchen printer is configured. Written only by app.report_kitchen_pos_status; no direct app-role access; no member-read RPC in this phase.';

alter table public.kitchen_pos_status_reports enable row level security;
alter table public.kitchen_pos_status_reports force row level security;
revoke all on table public.kitchen_pos_status_reports from public;
revoke all on table public.kitchen_pos_status_reports from anon;
revoke all on table public.kitchen_pos_status_reports from authenticated;
create policy kitchen_pos_status_reports_sel_deny on public.kitchen_pos_status_reports for select to authenticated using (false);
create policy kitchen_pos_status_reports_ins_deny on public.kitchen_pos_status_reports for insert to authenticated with check (false);
create policy kitchen_pos_status_reports_upd_deny on public.kitchen_pos_status_reports for update to authenticated using (false) with check (false);
create policy kitchen_pos_status_reports_del_deny on public.kitchen_pos_status_reports for delete to authenticated using (false);

-- ----------------------------------------------------------------------------
-- 6. app.report_kitchen_pos_status (+wrapper).
-- ----------------------------------------------------------------------------
create or replace function app.report_kitchen_pos_status(
  p_device_id              uuid,
  p_session_token          text,
  p_app_build              text,
  p_mode_revision          integer,
  p_secure_spool_available boolean,
  p_unresolved_local_jobs  integer
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

  select b.kitchen_workflow_mode_revision into v_rev
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if p_mode_revision is distinct from v_rev then
    return jsonb_build_object('ok', false, 'error', 'stale_mode_revision', 'mode_revision', v_rev);
  end if;

  insert into public.kitchen_pos_status_reports
    (organization_id, restaurant_id, branch_id, device_id, app_build,
     mode_revision, secure_spool_available, unresolved_local_jobs,
     reported_at, expires_at)
  values
    (v_org, v_rest, v_branch, p_device_id, btrim(p_app_build),
     p_mode_revision, p_secure_spool_available, p_unresolved_local_jobs,
     now(), now() + interval '10 minutes')
  on conflict (organization_id, device_id) do update set
     restaurant_id          = excluded.restaurant_id,
     branch_id              = excluded.branch_id,
     app_build              = excluded.app_build,
     mode_revision          = excluded.mode_revision,
     secure_spool_available = excluded.secure_spool_available,
     unresolved_local_jobs  = excluded.unresolved_local_jobs,
     reported_at            = excluded.reported_at,
     expires_at             = excluded.expires_at,
     updated_at             = now();

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_pos_status',
    'expires_at', now() + interval '10 minutes',
    'server_ts', now());
end;
$$;

comment on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) is
  'KITCHEN-MODE-001C3B1A: a POS device''s configuration-INDEPENDENT spool status upsert (device-token authenticated, full liveness, KDS denied, scope from the session; validates app_build/spool/unresolved and the CURRENT branch mode revision - stale returns the authoritative revision). No printer/transport/paper/fingerprint/endpoint/customer/money data. One current row per device, 10-minute server validity. No audit row (device-only path, D-013).';

create or replace function public.report_kitchen_pos_status(
  p_device_id uuid, p_session_token text, p_app_build text,
  p_mode_revision integer, p_secure_spool_available boolean,
  p_unresolved_local_jobs integer)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.report_kitchen_pos_status(p_device_id, p_session_token, p_app_build, p_mode_revision, p_secure_spool_available, p_unresolved_local_jobs); $$;

revoke all on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) from public;
revoke all on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) from anon;
grant execute on function app.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) to authenticated;
revoke all on function public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) from public;
revoke all on function public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) from anon;
grant execute on function public.report_kitchen_pos_status(uuid, text, text, integer, boolean, integer) to authenticated;
