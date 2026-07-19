-- ============================================================================
-- KITCHEN-MODE-001A — DORMANT backend foundation for the printer-only kitchen
-- workflow (no KDS device; paper kitchen tickets; settlement-alone completion).
--
-- DEPLOY-AHEAD SAFE BY CONSTRUCTION — THIS MIGRATION SHIPS NO ACTIVATION PATH:
--   * `branches.kitchen_workflow_mode` defaults to 'kds' for every existing and
--     future branch; NO setter RPC exists (the owner-controlled,
--     readiness-validated setter ships only in a LATER phase, after the durable
--     POS kitchen spool and fail-closed client behavior exist);
--   * direct writes are impossible for app roles: `branches` UPDATE privilege is
--     revoked from `authenticated` (RF-059 §grants) AND the FORCEd RLS policy
--     `branches_upd_deny` is `using (false)`; every existing branch-update RPC
--     (RF-112 update_branch_settings, RF-113 set_branch_pos_shift_close_enabled,
--     RF-117 set_branch_tax) writes an EXPLICIT column list that cannot touch
--     this column;
--   * therefore every mode-gated body below runs its `kds` branch — which is
--     byte-equivalent to the pre-KITCHEN-MODE behavior — until a later,
--     separately-reviewed phase provides the only write path. `printer_only` is
--     reachable today ONLY via privileged (service-role / test-fixture) SQL.
--
-- Contents (all additive; no table dropped/renamed; no shipped migration edited):
--   1. branches.kitchen_workflow_mode column ('kds' | 'printer_only').
--   2. Read-only RPCs (member + token-proven device) — RF-113 clones. NO setter.
--   3. app.try_auto_complete_order — faithful re-creation of the LIVE PSC-001C
--      body (20260722090000) with ONE mode-gated eligibility branch:
--      printer_only = settlement alone from any ACTIVE state (rounds gate
--      skipped); kds = byte-equivalent served + rounds + settlement gates.
--   4. app.submit_order — faithful re-creation of the LIVE RESTAURANT-OPS-V1
--      body (20260719100000) with a dormant zero-total printer-only completion
--      tail + ADDITIVE envelope keys (auto_completed, order_status).
--   5. app.sync_pull — faithful re-creation of the LIVE PSC-001C body with the
--      authoritative kitchen exclusion for printer_only branches.
--
-- pos_ready_feed is DELIBERATELY untouched: it serves only rows with a
-- non-null ready_at, which is stamped exclusively on the KDS preparing->ready
-- transition — a printer-only order can never enter it (proven by pgTAP).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The branch workflow mode column (default 'kds'; existing rows untouched
--    beyond the metadata-only default/NOT NULL — PostgreSQL 11+ fast path).
-- ----------------------------------------------------------------------------
alter table public.branches
  add column kitchen_workflow_mode text not null default 'kds'
    constraint branches_kitchen_workflow_mode_check
    check (kitchen_workflow_mode in ('kds', 'printer_only'));

comment on column public.branches.kitchen_workflow_mode is
  'KITCHEN-MODE-001A: the branch''s authoritative kitchen workflow. ''kds'' (default) = the shipped KDS-screen lifecycle, byte-identical behavior. ''printer_only'' = no KDS device; kitchen tickets are printed by the POS and orders complete on authoritative full settlement alone (see app.try_auto_complete_order). DORMANT: no setter RPC exists yet — the owner-controlled readiness-validated setter ships in a later KITCHEN-MODE phase; until then only privileged SQL can change this value. Direct app-role writes are blocked by the revoked UPDATE privilege + the branches_upd_deny RLS policy.';

-- ----------------------------------------------------------------------------
-- 2a. Member READ (Dashboard) — clone of app.get_branch_pos_shift_close_enabled.
-- ----------------------------------------------------------------------------
create or replace function app.get_branch_kitchen_workflow_mode(
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
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_mode  text;
begin
  if v_actor is null then
    raise exception 'get_branch_kitchen_workflow_mode: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    -- no membership covering this scope (incl. cross-tenant): reveal nothing.
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  select b.kitchen_workflow_mode into v_mode
    from public.branches b
    where b.id = p_branch_id and b.organization_id = p_organization_id
      and b.restaurant_id = p_restaurant_id and b.deleted_at is null;
  if v_mode is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'branch', 'branch_id', p_branch_id,
                            'kitchen_workflow_mode', v_mode);
end;
$$;

comment on function app.get_branch_kitchen_workflow_mode(uuid, uuid, uuid) is
  'KITCHEN-MODE-001A: member READ of branches.kitchen_workflow_mode. Any active membership covering the branch (rank > 0) may read; no membership / cross-tenant => not_found (no scope leak). READ-ONLY — no setter exists in this phase. A database error propagates (42501/raise) rather than being converted into a silent ''kds'', so a future fail-closed client can distinguish "authoritatively kds" from "could not read".';

create or replace function public.get_branch_kitchen_workflow_mode(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_branch_kitchen_workflow_mode(p_organization_id, p_restaurant_id, p_branch_id); $$;

revoke all on function app.get_branch_kitchen_workflow_mode(uuid, uuid, uuid)    from public;
grant execute on function app.get_branch_kitchen_workflow_mode(uuid, uuid, uuid) to authenticated;
revoke all on function public.get_branch_kitchen_workflow_mode(uuid, uuid, uuid)    from public;
grant execute on function public.get_branch_kitchen_workflow_mode(uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 2b. Device READ (POS/KDS, token-proven) — clone of
--     app.get_device_pos_shift_close_enabled / app.get_device_printer_assignments.
-- ----------------------------------------------------------------------------
create or replace function app.get_device_kitchen_workflow_mode(
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
  v_hash text;
  v_mode text;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_workflow_mode');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  -- token proof EXACTLY like app.get_device_printer_assignments: a live ACTIVE
  -- session on an ACTIVE pairing for THIS device, on a live device + live
  -- branch/restaurant. Read the mode from the device's OWN branch only — the
  -- caller can never choose a branch.
  select b.kitchen_workflow_mode into v_mode
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
  if v_mode is null then
    -- typed failure — NEVER a silent 'kds': the future POS client must be able
    -- to fail closed (block submission) when the mode cannot be read.
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_workflow_mode');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'kitchen_workflow_mode',
                            'kitchen_workflow_mode', v_mode, 'server_ts', now());
end;
$$;

comment on function app.get_device_kitchen_workflow_mode(uuid, text) is
  'KITCHEN-MODE-001A: TOKEN-PROVEN device read of its OWN branch''s kitchen_workflow_mode (auth mirrors app.get_device_printer_assignments; any failure => typed {ok:false, error:invalid_session} — fail closed, no scope leak, and NEVER a fabricated ''kds''). Returns only {ok, kitchen_workflow_mode, server_ts} — no secrets, no money. Callable by anonymous authenticated devices (authorization is the token, not membership). READ-ONLY — no setter exists in this phase.';

create or replace function public.get_device_kitchen_workflow_mode(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_device_kitchen_workflow_mode(p_device_id, p_session_token); $$;

revoke all on function app.get_device_kitchen_workflow_mode(uuid, text)    from public;
grant execute on function app.get_device_kitchen_workflow_mode(uuid, text) to authenticated;
revoke all on function public.get_device_kitchen_workflow_mode(uuid, text)    from public;
grant execute on function public.get_device_kitchen_workflow_mode(uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.try_auto_complete_order — faithful re-creation of the LIVE PSC-001C
--    body (20260722090000 lines 1007-1135) with ONE delta: the mode-gated
--    eligibility branch. Same signature => CREATE OR REPLACE keeps ACLs; the
--    INTERNAL revokes are re-issued below for parity.
-- ----------------------------------------------------------------------------
create or replace function app.try_auto_complete_order(
  p_organization_id           uuid,
  p_restaurant_id             uuid,
  p_branch_id                 uuid,
  p_order_id                  uuid,
  p_trigger                   text,   -- 'order_served' | 'payment_recorded' | 'order_submitted'
  p_actor_app_user_id         uuid,   -- the REAL initiating actor (JWT path)
  p_actor_employee_profile_id uuid,   -- the REAL initiating actor (PIN path)
  p_actor_membership_id       uuid,
  p_actor_role                text,
  p_device_id                 uuid,
  p_local_operation_id        text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_status     text;
  v_rev        integer;
  v_new_rev    integer;
  v_total      bigint;  -- the order's CURRENT total: decides chargeable vs not
  v_err_state  text;    -- fail-soft diagnostics (see the exception handler)
  v_err_msg    text;
  v_order_code text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
  v_kitchen_mode text;  -- KITCHEN-MODE-001A: the branch's authoritative workflow mode
begin
  -- The order row is ALREADY locked by the caller; this re-read is a no-op
  -- re-acquire in the same transaction and gives us the CURRENT committed state.
  select o.status, o.revision, o.grand_total_minor
    into v_status, v_rev, v_total
    from public.orders o
    where o.id              = p_order_id
      and o.organization_id = p_organization_id
      and o.deleted_at is null
    for update;

  -- Terminal orders (completed/cancelled/voided) are NEVER revived, in ANY
  -- workflow mode; a missing/cross-tenant/deleted order is not our case either.
  if not found or v_status in ('completed', 'cancelled', 'voided') then
    return jsonb_build_object('completed', false, 'reason', 'not_eligible');
  end if;

  -- KITCHEN-MODE-001A: the ONE mode read. FAIL-CLOSED to 'kds' — a missing or
  -- soft-deleted branch row can only ever produce the historical behavior,
  -- never the widened printer-only eligibility.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id              = p_branch_id
      and b.organization_id = p_organization_id
      and b.deleted_at is null;
  v_kitchen_mode := coalesce(v_kitchen_mode, 'kds');

  if v_kitchen_mode = 'printer_only' then
    -- PRINTER-ONLY (KITCHEN-MODE-001A, DORMANT until a later phase ships the
    -- owner setter): there is no KDS to walk submitted->...->served, so kitchen
    -- progression is NOT a completion requirement. Any ACTIVE order completes on
    -- authoritative FULL SETTLEMENT alone (the amount-aware predicate below —
    -- never a client flag). The rounds gate is deliberately SKIPPED: a round's
    -- kitchen work has no server-side "served" writer in this mode, and holding
    -- completion on it would strand every added-to order forever. `draft` never
    -- persists server-side and is deliberately NOT eligible.
    if v_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
      return jsonb_build_object('completed', false, 'reason', 'not_eligible');
    end if;
  else
    -- KDS MODE (the default) — BYTE-EQUIVALENT to the pre-KITCHEN-MODE gates:
    -- not served (submitted/accepted/preparing/ready stay put) is not our case.
    if v_status <> 'served' then
      return jsonb_build_object('completed', false, 'reason', 'not_eligible');
    end if;

    -- PSC-001C: EVERY additional service round must itself be `served` before the
    -- parent may complete (app.order_rounds_all_served — zero rounds passes
    -- trivially; a voided round is NOT completion-eligible). An order whose final
    -- round is still with the kitchen stays OPEN even when fully paid; the round's
    -- own served transition re-runs this decision under the same parent lock.
    if not app.order_rounds_all_served(p_organization_id, p_order_id) then
      return jsonb_build_object('completed', false, 'reason', 'rounds_active');
    end if;
  end if;

  -- The authoritative SETTLEMENT test. An unpaid served order stays served and
  -- stays visible in Awaiting close — that is the point.
  if not app.order_is_fully_settled(p_organization_id, p_order_id) then
    return jsonb_build_object('completed', false, 'reason', 'not_fully_paid');
  end if;

  -- The ONLY mutation: status + revision. No payment is created or touched, no
  -- total is recomputed, no table/shift/receipt is affected.
  v_new_rev := v_rev + 1;
  update public.orders
    set status = 'completed', revision = v_new_rev
    where id = p_order_id;

  -- ONE canonical audit event, naming the REAL initiating actor and device, and
  -- proving this was automatic and why. Money-free (T-003).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    p_organization_id, p_restaurant_id, p_branch_id,
    p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
    'order.status_updated', null,
    -- KITCHEN-MODE-001A: old_values names the REAL source status (always
    -- 'served' in kds mode — byte-equivalent — and the actual active state in
    -- printer-only mode; the append-only trail must not claim a serve that
    -- never happened).
    jsonb_build_object('order_id', p_order_id, 'status', v_status, 'revision', v_rev),
    jsonb_build_object(
      'order_id',              p_order_id,
      'order_code',            v_order_code,
      'status',                'completed',
      'revision',              v_new_rev,
      'resolved_membership_id', p_actor_membership_id,
      'role',                  p_actor_role,
      'local_operation_id',    p_local_operation_id,
      -- THE AUDIT MUST NOT LIE (D-013, invariant 8 — this trail is append-only and
      -- can never be corrected). A ZERO-TOTAL order settles with NO payment row, so
      -- writing 'paid' here would assert a payment that was never taken — and the
      -- owner would see the SAME order as `unpaid` in the Orders list, which derives
      -- its payment_status from the existence of a payments row. Say what is true:
      -- there was nothing to pay.
      'payment_status',        case when v_total = 0 then 'not_chargeable' else 'paid' end,
      'completion_mode',       'automatic',
      'completion_trigger',    p_trigger)
    -- KITCHEN-MODE-001A: mode metadata ONLY in printer-only mode, so the kds
    -- audit payload stays byte-identical to the pre-KITCHEN-MODE trail.
    || case when v_kitchen_mode = 'printer_only'
         then jsonb_build_object('kitchen_workflow_mode', 'printer_only')
         else '{}'::jsonb end);

  return jsonb_build_object(
    'completed', true, 'revision', v_new_rev, 'trigger', p_trigger,
    'order_code', v_order_code);
exception
  -- FAIL SOFT, ALWAYS — BUT NEVER SILENTLY.
  --
  --  * FAIL SOFT: a successful payment (or a successful `served` transition) must
  --    never be turned into a client-visible failure by its own SIDE EFFECT. The POS
  --    payment parser is fail-closed and treats any non-`applied` result as a FAILED
  --    payment, so re-raising here would tell a cashier the money was not taken when
  --    it was. We therefore swallow the error instead of propagating it.
  --  * NEVER SILENTLY: an unexpected error here is a real defect, so it is RAISEd as
  --    a WARNING carrying the SQLSTATE and the message. That reaches the PostgreSQL
  --    server log at the default log_min_messages, giving an operator something
  --    diagnosable to find; a WARNING cannot abort the transaction, so the payment
  --    still commits. The SQLSTATE (never the message) is also returned to the caller
  --    in `error_code`.
  --  * NOTHING PARTIAL, NO FAKE SUCCESS: the `update orders` and the audit `insert`
  --    above both run inside THIS block's implicit savepoint, so if either one fails
  --    BOTH are rolled back. The order stays `served`, NO audit row exists, and we
  --    report completed=false. There is no path that can write a SUCCESS audit event
  --    for a completion that did not actually happen.
  when others then
    get stacked diagnostics
      v_err_state = returned_sqlstate,
      v_err_msg   = message_text;
    raise warning
      'ORDER-AUTO-COMPLETION-001 app.try_auto_complete_order FAILED (fail-soft): order_id=% trigger=% sqlstate=% message=%',
      p_order_id, p_trigger, v_err_state, v_err_msg;
    return jsonb_build_object(
      'completed',  false,
      'reason',     'auto_completion_failed',
      'error_code', v_err_state);
end;
$$;

comment on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) is
  'ORDER-AUTO-COMPLETION-001 + PSC-001C + KITCHEN-MODE-001A: the ONE automatic-completion decision, chained by app.apply_order_status_transition (order_served), app.record_payment (payment_recorded) and app.submit_order (order_submitted, zero-total printer-only). KDS-mode branches (the default) keep the BYTE-EQUIVALENT gates: served + all-rounds-served + amount-aware full settlement. printer_only branches (DORMANT — no setter exists yet) complete any ACTIVE order (submitted/accepted/preparing/ready/served) on authoritative FULL SETTLEMENT alone; the rounds gate is skipped because kitchen progression has no writer in that mode. Terminal orders are never revived in any mode; the mode read fail-closes to kds; fail-soft with WARNING diagnostics; idempotent under the caller-held order lock; audits order.status_updated with completion_mode=automatic (+ kitchen_workflow_mode only in printer-only mode). INTERNAL: not granted to any client role.';

revoke all on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) from public;
revoke all on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) from anon;
revoke all on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) from authenticated;

-- ----------------------------------------------------------------------------
-- 4. app.submit_order — faithful re-creation of the LIVE RESTAURANT-OPS-V1 body
--    (20260719100000 lines 84-508) with the dormant KITCHEN-MODE-001A deltas:
--    replay/final envelopes gain ADDITIVE auto_completed + order_status keys,
--    and a zero-total printer-only order completes at the authoritative tail.
--    Signature UNCHANGED; grants re-issued for parity.
-- ----------------------------------------------------------------------------
create or replace function app.submit_order(
  p_pin_session_id              uuid,
  p_order_id                    uuid,
  p_device_id                   uuid,
  p_local_operation_id          text,
  p_order_type                  text,
  p_table_id                    uuid,
  p_shift_id                    uuid,
  p_currency_code               text,
  p_notes                       text,
  p_order_items                 jsonb,
  p_client_subtotal_minor       bigint,
  p_client_discount_total_minor bigint,
  p_client_tax_total_minor      bigint,
  p_client_grand_total_minor    bigint,
  p_client_created_at           timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org           uuid;
  v_rest          uuid;
  v_branch        uuid;
  v_dsid          uuid;
  v_emp           uuid;
  v_membership    uuid;
  v_ds_device     uuid;
  v_ds_active     boolean;
  v_ds_revoked    timestamptz;
  v_pairing_stat  text;
  v_role          text;
  v_m_status      text;
  v_m_deleted     timestamptz;
  v_m_rest        uuid;
  v_m_branch      uuid;
  v_existing_id   uuid;
  v_existing_rev  integer;
  v_item          jsonb;
  v_modifier      jsonb;
  v_item_id       uuid;
  v_qty           bigint;
  v_unit          bigint;
  v_line_disc     bigint;
  v_mod_qty       bigint;
  v_mod_price     bigint;
  v_mod_sum       bigint;
  v_line_total    bigint;
  v_subtotal      bigint := 0;
  v_grand         bigint;
  v_item_count    integer := 0;
  v_mod_count     integer := 0;
  v_unavailable   jsonb;
  v_item_ids      uuid[];
  -- KITCHEN-MODE-001A (all three used ONLY by the additive tail/replay below):
  v_kitchen_mode  text;
  v_auto          jsonb;
  v_existing_status text;
begin
  -- (1-5) PIN session: exists, valid (active/not-ended/not-expired), backing
  -- device session active + not revoked, pairing active. Scope + actor derived here.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found then
    raise exception 'submit_order: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'submit_order: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;

  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing_stat
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing_stat = 'active') then
    raise exception 'submit_order: backing device session/pairing is not active' using errcode = '42501';
  end if;

  -- (6) the caller's claimed device must be the device behind the PIN session
  if v_ds_device <> p_device_id then
    raise exception 'submit_order: device_id does not match the PIN session device' using errcode = '42501';
  end if;

  -- (9-14) membership: active, role permitted, scope covers the derived branch
  select m.role, m.status, m.deleted_at, m.restaurant_id, m.branch_id
    into v_role, v_m_status, v_m_deleted, v_m_rest, v_m_branch
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'submit_order: resolved membership is not active' using errcode = '42501';
  end if;
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    raise exception 'submit_order: role % may not submit orders', v_role using errcode = '42501';
  end if;
  if not (v_m_rest is null or v_m_rest = v_rest) or not (v_m_branch is null or v_m_branch = v_branch) then
    raise exception 'submit_order: membership scope does not cover the order branch' using errcode = '42501';
  end if;
  -- NOTE: org/restaurant/branch are taken from the PIN session (v_org/v_rest/v_branch),
  -- NEVER from client input, so a cross-tenant submit is structurally impossible.

  -- (payload) basic shape + currency + order_type
  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array' or jsonb_array_length(p_order_items) < 1 then
    raise exception 'submit_order: order_items must be a non-empty jsonb array' using errcode = '42501';
  end if;
  if p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'submit_order: invalid order_type %', p_order_type using errcode = '42501';
  end if;
  if p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$' then
    raise exception 'submit_order: currency_code must be a 3-letter ISO code' using errcode = '42501';
  end if;
  if p_client_discount_total_minor < 0 or p_client_tax_total_minor < 0
     or p_client_subtotal_minor < 0 or p_client_grand_total_minor < 0 then
    raise exception 'submit_order: order totals must be non-negative integers (minor units)' using errcode = '42501';
  end if;

  -- (payload+) RESTAURANT-OPERATIONS-V1-001 order-type table SHAPE rules —
  -- payload-stable, so they sit with the shape checks (before the replay
  -- lookup). RETURN-refusals, not raises: sync_push merges them VERBATIM so
  -- the POS can name the rule that fired (§4.35 error contract).
  if p_order_type = 'takeaway' and p_table_id is not null then
    -- takeaway never carries a table; a contradictory payload is refused, not
    -- silently "fixed" (the client's draft state is wrong and must say so).
    return jsonb_build_object('ok', false, 'error', 'table_not_allowed', 'entity', 'order');
  end if;
  if p_order_type = 'dine_in' and p_table_id is null then
    -- NEW dine-in orders require a table. Historical tableless dine-in rows
    -- remain valid (this rule binds acceptance, not stored data).
    return jsonb_build_object('ok', false, 'error', 'table_required', 'entity', 'order');
  end if;

  -- (money recompute) from the SUBMITTED SNAPSHOTS ONLY (never the live menu).
  -- Validate the per-line and order totals; reject any client/snapshot mismatch.
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    -- bound to the integer column range so an absurd quantity yields a clean 42501
    -- rather than a raw 22003 on the ::int insert (and limits qty*price overflow risk).
    if v_qty <= 0 or v_qty > 2147483647 then
      raise exception 'submit_order: order_items[].quantity must be between 1 and 2147483647' using errcode = '42501';
    end if;
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    if (v_item ->> 'menu_item_id') is null then
      raise exception 'submit_order: order_items[].menu_item_id is required' using errcode = '42501';
    end if;
    if (v_item ->> 'menu_item_name_snapshot') is null then
      raise exception 'submit_order: order_items[].menu_item_name_snapshot is required' using errcode = '42501';
    end if;

    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        if v_mod_qty <= 0 or v_mod_qty > 2147483647 then
          raise exception 'submit_order: modifiers[].quantity must be between 1 and 2147483647' using errcode = '42501';
        end if;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;

    v_line_total := v_qty * v_unit + v_mod_sum - v_line_disc;
    if v_line_total < 0 then
      raise exception 'submit_order: computed line_total_minor is negative' using errcode = '42501';
    end if;
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if p_client_subtotal_minor <> v_subtotal then
    raise exception 'submit_order: client subtotal_minor (%) does not match snapshot recompute (%)',
      p_client_subtotal_minor, v_subtotal using errcode = '42501';
  end if;
  v_grand := v_subtotal - p_client_discount_total_minor + p_client_tax_total_minor;
  if v_grand < 0 then
    raise exception 'submit_order: computed grand_total_minor is negative' using errcode = '42501';
  end if;
  if p_client_grand_total_minor <> v_grand then
    raise exception 'submit_order: client grand_total_minor (%) does not match snapshot recompute (%)',
      p_client_grand_total_minor, v_grand using errcode = '42501';
  end if;

  -- (idempotency) ONLY AFTER full validation: replay scoped to the validated
  -- (org, device, local_operation_id). Returns the same order; never re-inserts;
  -- never bypasses validation; never crosses tenants (org is session-derived).
  select o.id, o.revision, o.status into v_existing_id, v_existing_rev, v_existing_status
    from public.orders o
    where o.organization_id = v_org
      and o.device_id = p_device_id
      and o.local_operation_id = p_local_operation_id
    limit 1;
  if found then
    -- KITCHEN-MODE-001A (ADDITIVE keys only; existing keys byte-identical): the
    -- replay reports the CURRENT authoritative status, so a replayed zero-total
    -- printer-only submit consistently reads back `completed`. `auto_completed`
    -- on the replay path means "this order is completed NOW" — clients that
    -- predate the key ignore it.
    return jsonb_build_object(
      'ok', true, 'order_id', v_existing_id, 'revision', v_existing_rev,
      'server_ts', now(), 'idempotency_replay', true,
      'auto_completed', (v_existing_status = 'completed'),
      'order_status', v_existing_status);
  end if;

  -- (accept) RESTAURANT-OPERATIONS-V1-001 TIME-VARYING acceptance checks —
  -- deliberately AFTER the replay lookup (an already-accepted order must keep
  -- replaying even if its table or an item's availability changed since) and
  -- BEFORE any insert (a refusal never leaves a partial order).
  --
  -- (accept-1) the dine-in table must be a LIVE, ACTIVE, IN-SERVICE table of
  -- the SESSION branch. A foreign-branch, tombstoned, deactivated,
  -- out-of-service, or unknown table is the SAME refusal — the device learns
  -- nothing about other branches (R-003). STABILIZATION: out_of_service is a
  -- HARD manual floor state (a broken table); under a stale client list the
  -- picker's block is not enough, so the server refuses it too. reserved/
  -- occupied remain seatable (the reserving party arriving IS the seating).
  if p_order_type = 'dine_in' and not exists (
       select 1 from public.tables t
       where t.id              = p_table_id
         and t.organization_id = v_org
         and t.restaurant_id   = v_rest
         and t.branch_id       = v_branch
         and t.is_active
         and t.status <> 'out_of_service'
         and t.deleted_at is null) then
    return jsonb_build_object('ok', false, 'error', 'table_not_available', 'entity', 'order');
  end if;

  -- (accept-2) REVIEW CORRECTION (A1 + A2): every line item must be a REAL,
  -- SELLABLE item of the session menu — proven, not presumed — and AVAILABLE
  -- in the session branch, evaluated under a SHARED LOCK so an availability
  -- flip can never race past acceptance.
  --
  -- A1 — the CANONICAL sellability predicate, identical to what app.pos_menu
  -- serves the POS (order_items.menu_item_id is deliberately non-FK, so a
  -- stale or manipulated cart could previously submit an unknown, deleted,
  -- inactive, sibling-branch or foreign-scope id and still create an order):
  --   item:     exists in v_org + v_rest, is_active, deleted_at IS NULL,
  --             branch-visible (branch_id IS NULL OR = v_branch);
  --   category: parent exists, is_active, deleted_at IS NULL, branch-visible;
  --   effective availability: no 'unavailable' override for (v_branch, item).
  -- Absence of an override means available ONLY once the item is proven
  -- sellable. ALL non-sellable cases fail closed as ONE indistinguishable
  -- refusal (error item_unavailable, reason 'unavailable') so nothing —
  -- sibling-branch pins included — becomes an existence oracle (R-003).
  -- Explicit overrides keep their structured reason (sold_out|paused). The
  -- name echoed back is the CLIENT'S OWN payload snapshot, never DB data.
  -- D-008 is untouched: nothing here reprices from the live menu.
  --
  -- A2 — the TOCTOU serialization point: lock the CANONICAL menu_items rows
  -- (the same rows app.menu_set_item_availability locks) BEFORE evaluating.
  -- Locking the override row would not work — it may not exist yet. Locks are
  -- taken in one statement in DETERMINISTIC ascending id order, so two carts
  -- sharing items can never deadlock (and the setter locks exactly one row).
  -- Unknown/foreign ids match no row and take no lock — they fail the
  -- sellability check regardless, and there is nothing to serialize with.
  -- If the setter committed 'unavailable' first, this read (under lock) sees
  -- it and refuses; if this submit locked first, the setter WAITS until the
  -- accepted order commits and its change applies to later orders only.
  select array_agg(distinct (e ->> 'menu_item_id')::uuid)
    into v_item_ids
    from jsonb_array_elements(p_order_items) e;
  perform 1
    from public.menu_items i
    where i.organization_id = v_org
      and i.id = any (v_item_ids)
    order by i.id
    for update;

  select jsonb_agg(jsonb_build_object(
           'menu_item_id', blocked.menu_item_id,
           'name',         blocked.name,
           'reason',       blocked.reason)
           order by blocked.menu_item_id)
    into v_unavailable
    from (
      select li.menu_item_id,
             li.name,
             coalesce(a.reason, 'unavailable') as reason
        from (
          select (e ->> 'menu_item_id')::uuid as menu_item_id,
                 min(e ->> 'menu_item_name_snapshot') as name
            from jsonb_array_elements(p_order_items) e
            group by 1
        ) li
        left join public.menu_items i
          on i.id = li.menu_item_id
         and i.organization_id = v_org
         and i.restaurant_id   = v_rest
         and i.is_active
         and i.deleted_at is null
         and (i.branch_id is null or i.branch_id = v_branch)
        left join public.menu_categories c
          on c.id = i.menu_category_id
         -- REVIEW DELTA (HIGH): the category must belong to the EXACT session
         -- scope — org AND restaurant. The schema permits an item of
         -- restaurant A referencing a category of restaurant B in the same
         -- org; without the restaurant predicate such a hybrid item passed as
         -- sellable here while pos_menu's category list is restaurant-scoped.
         and c.organization_id = v_org
         and c.restaurant_id   = v_rest
         and c.is_active
         and c.deleted_at is null
         and (c.branch_id is null or c.branch_id = v_branch)
        left join public.menu_item_branch_availability a
          on a.organization_id = v_org
         and a.branch_id       = v_branch
         and a.menu_item_id    = li.menu_item_id
         and a.availability    = 'unavailable'
        where i.id is null            -- unknown / foreign / inactive / deleted / pinned elsewhere
           or c.id is null            -- category missing / inactive / deleted / not visible here
           or a.menu_item_id is not null  -- explicitly unavailable in this branch
    ) blocked;
  if v_unavailable is not null then
    return jsonb_build_object('ok', false, 'error', 'item_unavailable',
                              'entity', 'order', 'items', v_unavailable);
  end if;

  -- (insert) order header at status 'submitted'
  insert into public.orders (
    id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, table_id, shift_id,
    order_type, status, currency_code,
    subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor,
    notes, local_operation_id, revision, client_created_at)
  values (
    p_order_id, v_org, v_rest, v_branch, p_device_id, p_pin_session_id,
    v_emp, v_membership, p_table_id, p_shift_id,
    p_order_type, 'submitted', p_currency_code,
    v_subtotal, p_client_discount_total_minor, p_client_tax_total_minor, v_grand,
    p_notes, p_local_operation_id, 1, p_client_created_at);

  -- (insert) items at status 'pending' + their modifiers, recomputing line_total
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;
    v_line_total := v_qty * v_unit + v_mod_sum - v_line_disc;

    insert into public.order_items (
      organization_id, restaurant_id, branch_id, order_id, menu_item_id,
      status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor, notes, prep_snapshot)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_item ->> 'menu_item_id')::uuid,
      'pending', v_qty::int, v_item ->> 'menu_item_name_snapshot', v_unit,
      v_item -> 'item_size_snapshot', v_item -> 'item_variant_snapshot', v_line_disc, v_line_total,
      v_item ->> 'notes', v_item -> 'prep_snapshot')
    returning id into v_item_id;

    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        if (v_modifier ->> 'modifier_option_id') is null then
          raise exception 'submit_order: modifiers[].modifier_option_id is required' using errcode = '42501';
        end if;
        if (v_modifier ->> 'option_name_snapshot') is null then
          raise exception 'submit_order: modifiers[].option_name_snapshot is required' using errcode = '42501';
        end if;
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        insert into public.order_item_modifiers (
          organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id,
          modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
        values (
          v_org, v_rest, v_branch, v_item_id, (v_modifier ->> 'modifier_option_id')::uuid,
          v_modifier ->> 'modifier_name_snapshot', v_modifier ->> 'option_name_snapshot', v_mod_price, v_mod_qty::int, v_modifier -> 'meat_snapshot');
        v_mod_count := v_mod_count + 1;
      end loop;
    end if;
    v_item_count := v_item_count + 1;
  end loop;

  -- (audit) append-only order.submitted event (D-013, API_CONTRACT §4.1) in the
  -- SAME transaction. This SECURITY DEFINER RPC writes it as the audit_events
  -- table owner (RF-017 grants app roles NO insert; the append-only trigger
  -- blocks only UPDATE/DELETE/TRUNCATE). The idempotency-replay path returns
  -- earlier, so a replay NEVER writes a second audit row. actor =
  -- employee_profile (RF-017 requires app_user OR employee_profile present).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch,
    null, v_emp, p_device_id,
    'order.submitted', null, null,
    jsonb_build_object(
      'order_id',               p_order_id,
      'status',                 'submitted',
      'revision',               1,
      'currency_code',          p_currency_code,
      'subtotal_minor',         v_subtotal,
      'discount_total_minor',   p_client_discount_total_minor,
      'tax_total_minor',        p_client_tax_total_minor,
      'grand_total_minor',      v_grand,
      'device_id',              p_device_id,
      'local_operation_id',     p_local_operation_id,
      'order_type',             p_order_type,
      'table_id',               p_table_id,
      'shift_id',               p_shift_id,
      'resolved_membership_id', v_membership,
      'item_count',             v_item_count,
      'modifier_count',         v_mod_count));

  -- ---------------------------------------------------------------------------
  -- KITCHEN-MODE-001A (DORMANT, additive tail): a ZERO-TOTAL order submitted in
  -- a `printer_only` branch settles with NOTHING to pay (app.order_is_fully_settled
  -- returns true for grand_total_minor = 0 with NO payment row) and has no
  -- payment.create event to trigger completion — so the SAME auto-completion
  -- helper runs here, at the authoritative tail: grand total is known and
  -- validated, the order + items + audit are durably written, and this
  -- transaction still holds the exclusive lock on the freshly-inserted order
  -- row (satisfying the helper's caller-holds-the-lock contract). The helper
  -- alone decides eligibility: in the default `kds` mode it returns
  -- not_eligible for a `submitted` order, so kds-branch behavior — including
  -- kds zero-total behavior — is byte-identical to before. NO payment row and
  -- NO tender is ever fabricated; the helper is fail-soft, so a completion
  -- side-effect failure can never turn a successful submit into an error.
  -- ---------------------------------------------------------------------------
  if v_grand = 0 then
    select b.kitchen_workflow_mode into v_kitchen_mode
      from public.branches b
      where b.id              = v_branch
        and b.organization_id = v_org
        and b.deleted_at is null;
    if coalesce(v_kitchen_mode, 'kds') = 'printer_only' then
      v_auto := app.try_auto_complete_order(
        v_org, v_rest, v_branch, p_order_id,
        'order_submitted',
        null,          -- no JWT actor on the PIN path
        v_emp, v_membership, v_role,
        p_device_id, p_local_operation_id);
    end if;
  end if;

  -- KITCHEN-MODE-001A: ADDITIVE keys only — `ok`/`order_id`/`server_ts`/
  -- `idempotency_replay` are byte-identical; `revision` still reports the
  -- order's CURRENT revision (1, or 2 when the dormant zero-total completion
  -- just bumped it — reporting 1 for a revision-2 row would poison client
  -- reconciliation). Clients that predate the new keys ignore them.
  return jsonb_build_object(
    'ok', true, 'order_id', p_order_id,
    'revision', coalesce((v_auto ->> 'revision')::integer, 1),
    'server_ts', now(), 'idempotency_replay', false,
    'auto_completed', coalesce((v_auto ->> 'completed')::boolean, false),
    'order_status', case when coalesce((v_auto ->> 'completed')::boolean, false)
                         then 'completed' else 'submitted' end);
end;
$$;

comment on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) is
  'RF-052 SECURITY DEFINER submit_order + KITCHEN-PREP/MEAT snapshots + RESTAURANT-OPERATIONS-V1-001 acceptance rules (review-corrected) + KITCHEN-MODE-001A dormant zero-total completion. Signature UNCHANGED. Shape rules (before replay): takeaway+table -> table_not_allowed; dine_in without table -> table_required. Acceptance rules (after replay, before any insert — no partial order): dine-in table must be live+active+in-service in the SESSION branch -> table_not_available; every line item must be a PROVEN SELLABLE branch-available item under FOR UPDATE menu locks -> item_unavailable. All RETURN through sync_push verbatim (§4.35). KITCHEN-MODE-001A (additive; kds branches byte-identical): the replay and success envelopes carry auto_completed + order_status; a ZERO-TOTAL order in a printer_only branch runs app.try_auto_complete_order at the authoritative tail (order_submitted trigger) — settled-with-nothing-to-pay, NO payment row fabricated, fail-soft, idempotent on replay. Historical rows untouched; money recompute/idempotency/audit byte-unchanged (D-007/D-008).';

revoke all on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) from public;
grant execute on function app.submit_order(uuid, uuid, uuid, text, text, uuid, uuid, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. app.sync_pull — faithful re-creation of the LIVE PSC-001C body
--    (20260722090000 lines 2496-2700) with ONE delta: the authoritative
--    kitchen exclusion for printer_only branches (section (b)). Signature
--    UNCHANGED; grants re-issued for parity.
-- ----------------------------------------------------------------------------
create or replace function app.sync_pull(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_entities       text[]  default null,
  p_cursors        jsonb   default '{}'::jsonb,
  p_limit          integer default 500
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_emp         uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_limit       integer;
  v_allowed     text[];
  v_requested   text[];
  v_include_ops boolean;
  v_entity      text;
  v_cur         jsonb;
  v_c_uat       timestamptz;
  v_c_id        uuid;
  v_changes     jsonb := '{}'::jsonb;
  v_op_rows     jsonb;
  v_op_count    integer;
  v_op_last     jsonb;
  v_op_statuses jsonb;
  v_kitchen_mode text;  -- KITCHEN-MODE-001A: branch workflow mode (kitchen gate)
  c_financial   constant text[] := array['payments', 'shifts', 'cash_drawer_sessions'];
  c_business    constant text[] := array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds', 'payments', 'shifts', 'cash_drawer_sessions'];
  -- RF-109: the six menu reference entities. Price-capable roles only (menu rows carry money, T-003).
  c_menu        constant text[] := array['menu_categories', 'menu_items', 'item_sizes', 'item_variants', 'modifiers', 'modifier_options'];
  -- MVP: the money-free floor entity — EVERY device role may pull it (the KDS
  -- maps orders.table_id -> a human table label through this feed).
  c_floor       constant text[] := array['tables'];
begin
  -- (0) limit validation (A7): default 500, reject <=0 or >1000 (validation-error style).
  v_limit := coalesce(p_limit, 500);
  if v_limit <= 0 or v_limit > 1000 then
    raise exception 'sync_pull: p_limit must be between 1 and 1000 (got %)', v_limit using errcode = '42501';
  end if;
  if p_cursors is null or jsonb_typeof(p_cursors) <> 'object' then
    raise exception 'sync_pull: p_cursors must be a JSON object' using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing active; device match (A8).
  --     Scope (org/restaurant/branch) + actor + role are derived HERE, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'sync_pull: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'sync_pull: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'sync_pull: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_pull: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'sync_pull: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) role-permitted entities (A5): kitchen_staff -> non-financial operational
  --     + the money-free `tables` floor entity (NO menu -- menu rows carry money,
  --     T-003). Price-capable roles -> operational business + RF-109 menu + tables.
  if v_role = 'kitchen_staff' then
    -- KITCHEN-MODE-001A: the AUTHORITATIVE kitchen exclusion. In a
    -- `printer_only` branch there is no kitchen board — the kitchen ticket is
    -- paper — so a kitchen_staff session is served NO actionable order
    -- entities (orders / order_items / order_item_modifiers /
    -- order_service_rounds are all withheld). Only the money-free `tables`
    -- floor entity remains, which is exactly enough for a safe, honest EMPTY
    -- board on any KDS that is (accidentally) paired to such a branch. An
    -- EXPLICIT request for an order entity rejects with the existing
    -- not-permitted-for-role 42501 in (c) below — fail closed, never a
    -- silently truncated feed dressed up as a full one. The mode read
    -- fail-closes to 'kds', so a missing branch row can only ever produce the
    -- historical allow-list. No other role's exposure changes.
    select b.kitchen_workflow_mode into v_kitchen_mode
      from public.branches b
      where b.id              = v_branch
        and b.organization_id = v_org
        and b.deleted_at is null;
    if coalesce(v_kitchen_mode, 'kds') = 'printer_only' then
      v_allowed := c_floor;
    else
      -- KDS MODE (default) — BYTE-EQUIVALENT to the PSC-001C allow-list:
      -- order_service_rounds is MONEY-FREE by schema — the kitchen needs it
      -- to render Addition/Round N tickets with the round's own status.
      v_allowed := array['orders', 'order_items', 'order_item_modifiers', 'order_service_rounds'] || c_floor;
    end if;
  elsif v_role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant') then
    v_allowed := c_business || c_menu || c_floor;
  else
    v_allowed := array[]::text[];
  end if;

  -- (c) resolve the requested set. null -> all role-permitted + operation_statuses.
  --     Otherwise validate each name: unknown -> reject; not-permitted-for-role -> reject.
  if p_entities is null then
    v_requested   := v_allowed;
    v_include_ops := true;
  else
    v_requested   := array[]::text[];
    v_include_ops := false;
    foreach v_entity in array p_entities loop
      if v_entity = 'operation_statuses' then
        v_include_ops := true;
      elsif v_entity = any(c_business) or v_entity = any(c_menu) or v_entity = any(c_floor) then
        if not (v_entity = any(v_allowed)) then
          raise exception 'sync_pull: entity % is not permitted for role %', v_entity, v_role using errcode = '42501';
        end if;
        if not (v_entity = any(v_requested)) then
          v_requested := array_append(v_requested, v_entity);
        end if;
      else
        raise exception 'sync_pull: unknown entity %', v_entity using errcode = '42501';
      end if;
    end loop;
  end if;

  -- (d) page each requested entity by its per-entity (updated_at, id) cursor.
  foreach v_entity in array v_requested loop
    v_cur   := p_cursors -> v_entity;
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    v_changes := v_changes || jsonb_build_object(
      v_entity, app.sync_pull_changes(v_entity, v_org, v_branch, v_c_uat, v_c_id, v_limit));
  end loop;

  -- (d2) KITCHEN MONEY REDACTION (RF-059, A3/T-003): kitchen_staff must receive NO money figure.
  --      Preserved verbatim. (Kitchen never reaches the paging loop for a menu entity -- a menu
  --      request is rejected in (c) -- so this strips money only from the operational rows kitchen
  --      legitimately receives; it remains a defence-in-depth backstop for any *_minor key.
  --      `tables` rows are money-free, so redact_money is a harmless no-op on them.)
  if v_role = 'kitchen_staff' then
    select coalesce(
             jsonb_object_agg(
               ent,
               case when jsonb_typeof(val -> 'rows') = 'array'
                 then jsonb_set(val, '{rows}',
                        coalesce((select jsonb_agg(app.redact_money(r))
                                  from jsonb_array_elements(val -> 'rows') as r), '[]'::jsonb))
                 else val end),
             '{}'::jsonb)
      into v_changes
      from jsonb_each(v_changes) as ec(ent, val);
  end if;

  -- (e) current-device operation-status feed (A4): sync_operations for THIS org + THIS device
  --     only. Projects status/conflict fields; excludes raw payload. Empty when not requested.
  if v_include_ops then
    v_cur   := p_cursors -> 'operation_statuses';
    v_c_uat := nullif(v_cur ->> 'updated_at', '')::timestamptz;
    v_c_id  := nullif(v_cur ->> 'id', '')::uuid;
    with look as (
      select so.id as _id, so.updated_at as _uat,
             jsonb_build_object(
               'id',                 so.id,
               'local_operation_id', so.local_operation_id,
               'operation_type',     so.operation_type,
               'target_entity',      so.target_entity,
               'target_id',          so.target_id,
               'status',             so.status,
               'result',             so.result,
               'last_error_code',    so.last_error_code,
               'last_error_class',   so.last_error_class,
               'conflict_info',      so.conflict_info,
               'rejection_reason',   so.rejection_reason,
               'retry_count',        so.retry_count,
               'updated_at',         so.updated_at,
               'applied_at',         so.applied_at,
               'server_received_at', so.server_received_at) as _row,
             row_number() over (order by so.updated_at asc, so.id asc) as _rn
      from public.sync_operations so
      where so.organization_id = v_org
        and so.device_id = p_device_id
        and (v_c_uat is null or so.updated_at > v_c_uat or (so.updated_at = v_c_uat and so.id > v_c_id))
      order by so.updated_at asc, so.id asc
      limit v_limit + 1
    ),
    page as (
      select _id, _uat, _row from look where _rn <= v_limit
    )
    select coalesce(jsonb_agg(_row order by _uat asc, _id asc), '[]'::jsonb),
           (select count(*) from look)::int,
           (select jsonb_build_object('updated_at', _uat, 'id', _id) from page order by _uat desc, _id desc limit 1)
      into v_op_rows, v_op_count, v_op_last
      from page;
    v_op_statuses := jsonb_build_object(
      'rows', v_op_rows,
      'next_cursor', case when v_op_count > 0 then v_op_last else null end,
      'has_more', (v_op_count > v_limit));
  else
    v_op_statuses := jsonb_build_object('rows', '[]'::jsonb, 'next_cursor', null, 'has_more', false);
  end if;

  return jsonb_build_object(
    'ok', true,
    'server_ts', now(),
    'changes', v_changes,
    'operation_statuses', v_op_statuses);
end;
$$;

comment on function app.sync_pull(uuid, uuid, text[], jsonb, integer) is
  'RF-057 pull RPC, hardened by RF-059 (A3/T-003), extended by RF-109 (menu), the MVP `tables` floor entity, PSC-001C (order_service_rounds) and KITCHEN-MODE-001A. Session/device validation (A8), role-permitted entity set (A5), per-entity (updated_at,id) cursor (A1), tombstones inline (A9), limit default 500/cap 1000, current-device operation_statuses feed (A4), RF057-B1 lookahead, and kitchen money redaction are preserved verbatim. KITCHEN-MODE-001A: a kitchen_staff session in a `printer_only` branch resolves the money-free `tables` floor entity ONLY — no orders/order_items/order_item_modifiers/order_service_rounds — so an (accidentally) paired KDS renders a safe, honest EMPTY board; an explicit order-entity request rejects with the existing not-permitted 42501 (fail closed); the mode read fail-closes to kds; NO other role''s exposure changes; tenant/branch isolation unchanged (R-003). Faithful re-creation of the 20260722090000 body. Read-only; no audit.';

revoke all on function app.sync_pull(uuid, uuid, text[], jsonb, integer) from public;
grant execute on function app.sync_pull(uuid, uuid, text[], jsonb, integer) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   re-create app.sync_pull / app.submit_order / app.try_auto_complete_order
--     from 20260722090000 / 20260719100000 / 20260722090000 respectively;
--   drop function if exists public.get_device_kitchen_workflow_mode(uuid, text);
--   drop function if exists app.get_device_kitchen_workflow_mode(uuid, text);
--   drop function if exists public.get_branch_kitchen_workflow_mode(uuid, uuid, uuid);
--   drop function if exists app.get_branch_kitchen_workflow_mode(uuid, uuid, uuid);
--   alter table public.branches drop column if exists kitchen_workflow_mode;
-- ============================================================================
