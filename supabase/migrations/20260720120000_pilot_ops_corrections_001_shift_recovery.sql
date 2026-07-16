-- ============================================================================
-- PILOT-OPERATIONS-CORRECTIONS-001 (4/4) -- server-authoritative open-shift
-- summary (fixes "expected cash shows 0 after restart")
-- ============================================================================
-- During a live shift the POS computes the expected close cash from IN-MEMORY
-- session state (opening float + payments collected this run). After an app
-- restart + same-employee PIN login that in-memory state is gone, so the
-- shift-close UI shows Expected cash 0 -- while app.close_shift still computes the
-- REAL expected from PERSISTED payments and rejects a 0 close (variance<>0, no
-- reason). The UI and the server disagree because the UI derived expected from
-- ephemeral state.
--
-- The fix is a NEW read-only RPC that returns the current OPEN shift for the
-- session's (organization, branch, device) -- the canonical shift-ownership tuple
-- (one non-terminal shift per (org,branch,device), enforced by
-- shifts_one_active_per_device_uidx) that app.close_shift itself validates -- WITH
-- expected_cash_minor computed by the EXACT SAME SQL as app.close_shift
-- (opening_float + sum of COMPLETED CASH payments on the bound drawer). The POS
-- then sources Expected cash from this server value instead of the local
-- aggregation, so the displayed figure matches what close_shift will enforce.
--
--   * NO new money formula in Dart (D-007: money maths lives in SQL). The sum keys
--     on payments.cash_drawer_session_id and filters method='cash' AND
--     status='completed' -- byte-identical to app.close_shift, so the two can never
--     diverge.
--   * READ-ONLY. This is NOT a sync_push op (it mutates nothing) -- it is its own
--     SECURITY INVOKER public wrapper, like get_device_branch_tax /
--     get_device_printer_assignments.
--   * T-003: a kitchen_staff principal never receives a money figure -- the money
--     keys are OMITTED for that role (the KDS is money-free and does not call this
--     RPC, but the redaction is defence in depth).
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- ============================================================================

create function app.get_open_shift_summary(
  p_pin_session_id uuid,
  p_device_id      uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_dsid       uuid;
  v_emp        uuid;
  v_membership uuid;
  v_ds_device  uuid;
  v_ds_active  boolean;
  v_ds_revoked timestamptz;
  v_pairing    text;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_m_perms    jsonb;
  v_authorized boolean;
  v_is_owner   boolean;
  v_shift_id   uuid;
  v_status     text;
  v_rev        integer;
  v_opened_at  timestamptz;
  v_opened_by  uuid;
  v_drawer_id  uuid;
  v_opening    bigint;
  v_cash_sales bigint;
  v_expected   bigint;
begin
  -- (a) canonical PIN-session preamble; scope + actor + role derived HERE, never
  --     from payload. Every failure is one indistinguishable 42501 (no R-003 oracle).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'get_open_shift_summary: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'get_open_shift_summary: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'get_open_shift_summary: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'get_open_shift_summary: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'get_open_shift_summary: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) the current NON-TERMINAL shift for THIS (org, branch, device) -- the
  --     canonical ownership tuple close_shift validates (one active per device).
  select s.id, s.status, s.revision, s.opened_at, s.opened_by_employee_profile_id
    into v_shift_id, v_status, v_rev, v_opened_at, v_opened_by
    from public.shifts s
    where s.organization_id = v_org
      and s.branch_id       = v_branch
      and s.device_id       = p_device_id
      and s.status in ('opening', 'open', 'closing');
  if not found then
    return jsonb_build_object('ok', true, 'entity', 'shift', 'has_open_shift', false);
  end if;

  -- (b2) B1 + Finding 2 (PILOT-OPERATIONS-CORRECTIONS-001): recovery authorization is
  --      the EXACT SAME predicate as app.close_shift (staff_cashier_permissions_001):
  --        manager/restaurant_owner/org_owner may close (recover) ANY shift;
  --        a cashier may close (recover) ONLY their own shift (opened_by = actor) AND
  --        ONLY when the close_shift CAPABILITY is allowed for them.
  --      Mirroring it here stops the summary handing can_close=true + the drawer figure
  --      to someone close_shift would then refuse. Two denials are distinguished
  --      HONESTLY (never money in either):
  --        * a DIFFERENT employee owns the shift  -> shift_owner_mismatch
  --        * the owning cashier lacks the capability -> shift_close_not_allowed
  --      Every denial returns has_open_shift=true, can_close=false, NO money keys.
  v_is_owner   := (v_role = 'cashier' and v_opened_by = v_emp);
  v_authorized := (v_role in ('manager', 'restaurant_owner', 'org_owner'))
                  or (app.cashier_capability_allowed(v_role, v_m_perms, 'close_shift')
                      and v_is_owner);
  if not v_authorized then
    return jsonb_build_object('ok', true, 'entity', 'shift', 'has_open_shift', true,
      'can_close', false,
      -- capability-disabled OWNER is a capability denial, NOT an owner mismatch.
      'error', case when v_is_owner then 'shift_close_not_allowed'
                    else 'shift_owner_mismatch' end,
      'shift_id', v_shift_id, 'status', v_status, 'revision', v_rev,
      'opened_at', v_opened_at, 'opened_by_employee_profile_id', v_opened_by,
      'server_ts', now());
  end if;

  -- (c) the bound cash drawer (1:1). Opening float is on the drawer.
  select cds.id, cds.opening_float_minor
    into v_drawer_id, v_opening
    from public.cash_drawer_sessions cds
    where cds.organization_id = v_org and cds.shift_id = v_shift_id;

  -- (d) CANONICAL expected cash -- byte-identical to app.close_shift's reconciliation
  --     math (opening float + completed CASH payments on the drawer). Integer minor
  --     units only (D-007). A kitchen_staff principal never receives money (T-003):
  --     the money keys are omitted below.
  if found then
    select coalesce(sum(p.amount_minor), 0) into v_cash_sales
      from public.payments p
      where p.organization_id = v_org
        and p.cash_drawer_session_id = v_drawer_id
        and p.method = 'cash'
        and p.status = 'completed';
    v_expected := v_opening + v_cash_sales;
  end if;

  -- Only an actor AUTHORIZED to close this shift (manager+ or the owning cashier)
  -- reaches here -- (b2) already returned the money-free owner-mismatch for anyone
  -- else, so kitchen_staff / accountant never see a drawer figure (T-003 preserved,
  -- defence in depth). can_close=true is explicit so the UI can offer the close form.
  return jsonb_build_object('ok', true, 'entity', 'shift', 'has_open_shift', true,
    'can_close', true,
    'shift_id', v_shift_id, 'cash_drawer_session_id', v_drawer_id,
    'status', v_status, 'revision', v_rev, 'opened_at', v_opened_at,
    'opened_by_employee_profile_id', v_opened_by,
    'opening_float_minor', v_opening,
    'cash_sales_minor', v_cash_sales,
    'expected_cash_minor', v_expected,
    'server_ts', now());
end;
$$;

comment on function app.get_open_shift_summary(uuid, uuid) is
  'PILOT-OPERATIONS-CORRECTIONS-001 (D-011): READ-ONLY current open-shift summary for the session''s (organization, branch, device) -- the canonical shift-ownership tuple app.close_shift validates (one non-terminal shift per (org,branch,device)). Returns has_open_shift=false when none. B1 + Finding 2: authorization is the EXACT SAME predicate as app.close_shift -- manager/restaurant_owner/org_owner may recover any shift; a cashier may recover ONLY their own (opened_by = actor) AND only when the close_shift CAPABILITY is allowed (app.cashier_capability_allowed(role, permissions, ''close_shift'')). A denial returns has_open_shift=true, can_close=false, opened_by_employee_profile_id, and NO money keys, with an HONEST typed reason: a different owner -> shift_owner_mismatch; the owning cashier lacking the capability -> shift_close_not_allowed (never misreported as an owner mismatch). An AUTHORIZED actor gets can_close=true plus expected_cash_minor computed with the EXACT SAME SQL as app.close_shift (opening_float + sum of completed CASH payments on the bound drawer; integer minor units, D-007). kitchen_staff/accountant receive NO money keys (T-003; caught by the authorization guard). Canonical PIN-session preamble; every invalid/expired/revoked/mismatched session collapses to ONE 42501 (no R-003 oracle). Mutates nothing.';

-- Thin public SECURITY INVOKER wrapper (PostgREST entrypoint; the POS reaches it
-- with the anon key + its PIN/device session, like public.sync_pull). No authority
-- of its own. authenticated only; anon + PUBLIC revoked; no service-role.
create function public.get_open_shift_summary(
  p_pin_session_id uuid,
  p_device_id      uuid
)
  returns jsonb language sql stable security invoker set search_path = ''
as $$
  select app.get_open_shift_summary(p_pin_session_id, p_device_id);
$$;

comment on function public.get_open_shift_summary(uuid, uuid) is
  'PILOT-OPERATIONS-CORRECTIONS-001: PUBLIC (PostgREST-reachable) INVOKER wrapper over app.get_open_shift_summary. Carries no authority of its own.';

revoke all on function app.get_open_shift_summary(uuid, uuid) from public;
revoke all on function app.get_open_shift_summary(uuid, uuid) from anon;
grant execute on function app.get_open_shift_summary(uuid, uuid) to authenticated;
revoke all on function public.get_open_shift_summary(uuid, uuid) from public;
revoke all on function public.get_open_shift_summary(uuid, uuid) from anon;
grant execute on function public.get_open_shift_summary(uuid, uuid) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only -- `supabase db reset` replays):
--   drop function if exists public.get_open_shift_summary(uuid, uuid);
--   drop function if exists app.get_open_shift_summary(uuid, uuid);
-- ============================================================================
