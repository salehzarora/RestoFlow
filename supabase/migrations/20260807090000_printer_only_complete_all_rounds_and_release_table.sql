-- ============================================================================
-- PRINTER-ONLY-CLOSE-ALL-ROUNDS-AND-RELEASE-TABLE-008
-- Close every confirmed service round when a printer-only order completes,
-- and make printer-only mode REACHABLE.
-- ============================================================================
-- THE DEFECT, proven from the shipped source outwards:
--
--   1. `app.add_order_items` opens each amendment as a NEW service round at
--      status 'submitted' (20260722090000).
--   2. `app.update_round_status` admits a KDS DEVICE ONLY for
--      submitted->accepted->preparing->ready; a POS may only do ready->served.
--      On a one-device / printer-only site NO KDS device exists, so NOTHING can
--      ever walk that round forward.
--   3. `app.order_rounds_all_served` is therefore permanently FALSE for any
--      order that took Add-items.
--   4. 20260804090000 unblocked the ORDER by SKIPPING that gate on a
--      printer_only branch - explicitly "WITHOUT writing any round status". The
--      order completes; the ROUND ROW STAYS LIVE FOR EVER.
--
-- So a completed order kept a non-served round, `app.order_rounds_all_served`
-- stayed false for a TERMINAL order, and every round-aware read model kept the
-- fragment. This migration closes those rounds as part of the SAME transaction
-- that completes the order.
--
-- TABLE RELEASE needs NO code and NO table write. Occupancy is DERIVED:
-- `app.pos_tables` / `app.list_tables` count live DINE-IN orders whose status is
-- in (submitted..served) (20260719100000). Completing the order IS the release.
-- Nothing here writes `public.tables`, and the historical `orders.table_id`
-- record is preserved exactly as the schema keeps it.
--
-- WHY THE SETTER SHIPS HERE. `branches.kitchen_workflow_mode` is
-- `not null default 'kds'` and NOTHING in the 107 shipped migrations ever wrote
-- it - 20260723090000 says so ("DORMANT: no setter RPC exists yet") and
-- 20260725090000 repeats it ("bumped ONLY by the future owner setter"). Only
-- pgTAP fixtures ever set it. Every production branch is therefore 'kds', which
-- means the whole printer-only path - including the fix above - would be
-- unreachable. The guarded owner setter below makes it configurable, so this
-- migration is a complete fix rather than dormant code. Approved by the human
-- owner before implementation.
--
-- CONTENTS
--   1. app.terminalize_printer_only_rounds - INTERNAL helper; the ONE writer.
--   2. app.apply_order_status_transition   - forward re-emission of the
--      20260804090000 body + the helper call (manual completion path).
--   3. app.try_auto_complete_order         - forward re-emission of the
--      20260723090000 body + the helper call (automatic completion path).
--   4. app.set_kitchen_workflow_mode (+ public wrapper) - guarded owner setter.
--
-- SAFETY
--   * Additive and forward-only. No existing migration is edited.
--   * NO row is ever deleted; a round is CLOSED, never removed.
--   * NO money, price, modifier, payment or receipt is touched anywhere.
--   * A `voided` round is NEVER rewritten - it stays voided, so history and the
--     "voided is not completion-eligible" rule are both preserved.
--   * kds branches are byte-equivalent: their gate returns before the new call.
--   * The mode is read SERVER-side from `public.branches` in both paths; no
--     client flag can reach it.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.terminalize_printer_only_rounds - the ONE writer that closes rounds a
--    printer-only completion is allowed to skip.
--
--    The parent order row is already locked FOR UPDATE by both callers, so this
--    runs under that lock and cannot interleave with another completion of the
--    same order. IDEMPOTENT: rows already `served` are not selected, so a repeat
--    completion (or a replayed op) updates nothing and writes no audit row.
--
--    `served` is used because that is EXACTLY what the completion predicate,
--    the active-order queries and the reporting contracts already expect - no
--    new status is invented. The table CHECK requires `ready_at` on a served
--    row, so a round that never had one is stamped now (write-once semantics:
--    an existing stamp is preserved). In printer_only the PSC-001A ready feed
--    returns an empty collection by design, so this creates no ready banner.
-- ----------------------------------------------------------------------------
create or replace function app.terminalize_printer_only_rounds(
  p_organization_id           uuid,
  p_restaurant_id             uuid,
  p_branch_id                 uuid,
  p_order_id                  uuid,
  p_actor_app_user_id         uuid,
  p_actor_employee_profile_id uuid,
  p_device_id                 uuid
)
  returns integer
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_rounds jsonb;
  v_n      integer := 0;
begin
  -- Snapshot the rounds about to be closed (RETURNING cannot report the OLD
  -- status on this server version, and the audit must record what they were).
  -- `voided` is deliberately excluded: it is a real historical outcome, it only
  -- ever exists on a voided parent, and rewriting it would destroy history.
  select coalesce(jsonb_agg(jsonb_build_object(
           'round_id',     r.id,
           'round_number', r.round_number,
           'from_status',  r.status) order by r.round_number), '[]'::jsonb)
    into v_rounds
    from public.order_service_rounds r
   where r.organization_id = p_organization_id
     and r.order_id        = p_order_id
     and r.deleted_at is null
     and r.status not in ('served', 'voided');

  if v_rounds = '[]'::jsonb then
    return 0;
  end if;

  update public.order_service_rounds r
     set status   = 'served',
         ready_at = coalesce(r.ready_at, now()),
         revision = r.revision + 1
   where r.organization_id = p_organization_id
     and r.order_id        = p_order_id
     and r.deleted_at is null
     and r.status not in ('served', 'voided');
  get diagnostics v_n = row_count;

  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    p_organization_id, p_restaurant_id, p_branch_id,
    p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
    'order.rounds_closed_printer_only',
    'printer_only completion: no KDS writer exists for these rounds',
    jsonb_build_object('order_id', p_order_id, 'rounds', v_rounds),
    jsonb_build_object('order_id', p_order_id, 'rounds_closed', v_n,
                       'to_status', 'served',
                       'kitchen_workflow_mode', 'printer_only'));
  return v_n;
end;
$$;

comment on function app.terminalize_printer_only_rounds(uuid, uuid, uuid, uuid, uuid, uuid, uuid) is
  'PRINTER-ONLY-CLOSE-ALL-ROUNDS-AND-RELEASE-TABLE-008: closes every LIVE, non-voided service round of an order to `served` when a printer_only branch completes it, in the caller''s transaction and under the caller''s order lock. printer_only has no KDS writer for a round (app.update_round_status is KDS-device-only for submitted->..->ready), so without this a completed order kept a live round for ever and app.order_rounds_all_served stayed false for a TERMINAL order. Uses the EXISTING terminal status - no new status is invented; stamps the CHECK-required ready_at only when absent (write-once); NEVER touches a voided round; deletes nothing; touches no money, payment, table or receipt. Idempotent (already-served rounds are not selected, and a no-op writes no audit). Audits order.rounds_closed_printer_only once per sweep with the prior per-round statuses. INTERNAL: granted to no client role - the mode decision belongs to the two completion paths that call it.';

revoke all on function app.terminalize_printer_only_rounds(uuid, uuid, uuid, uuid, uuid, uuid, uuid) from public;
revoke all on function app.terminalize_printer_only_rounds(uuid, uuid, uuid, uuid, uuid, uuid, uuid) from anon;
revoke all on function app.terminalize_printer_only_rounds(uuid, uuid, uuid, uuid, uuid, uuid, uuid) from authenticated;

-- ----------------------------------------------------------------------------
-- 2. app.apply_order_status_transition - FORWARD RE-EMISSION of the live
--    20260804090000 body, byte-identical except for the printer-only round
--    closure added inside the `completed` gate. Extracted from that migration
--    mechanically, not retyped.
-- ----------------------------------------------------------------------------
create or replace function app.apply_order_status_transition(
  p_order_id                  uuid,
  p_new_status                text,
  p_actor_org                 uuid,
  p_actor_restaurant          uuid,
  p_actor_branch              uuid,
  p_actor_role                text,
  p_actor_app_user_id         uuid,      -- JWT actor  (null on the device path)
  p_actor_employee_profile_id uuid,      -- PIN actor  (null on the JWT path)
  p_actor_membership_id       uuid,
  p_device_id                 uuid,      -- null on the JWT path
  p_local_operation_id        text,      -- null on the JWT path
  p_expected_revision         integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_o_org      uuid;
  v_o_branch   uuid;
  v_o_status   text;
  v_o_rev      integer;
  v_legal      boolean;
  v_new_rev    integer;
  v_paid       boolean;
  v_o_total    bigint;   -- the order's CURRENT total: chargeable vs not_chargeable
  v_auto       jsonb;
  v_kitchen_mode text;   -- DEFERRED-ORDER-AMENDMENTS-001: authoritative branch mode
  v_order_code text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- (a) load the order FOR UPDATE (serializes concurrent status pushes); it MUST
  --     be in the actor's organization AND branch. Cross-tenant -> fail-closed
  --     raise, no write.
  select o.organization_id, o.branch_id, o.status, o.revision, o.grand_total_minor
    into v_o_org, v_o_branch, v_o_status, v_o_rev, v_o_total
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'update_order_status: order not found' using errcode = '42501';
  end if;
  if v_o_org <> p_actor_org or v_o_branch <> p_actor_branch then
    raise exception 'update_order_status: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (b) OPTIMISTIC CONCURRENCY (opt-in; the PIN front passes null, preserving its
  --     exact behaviour). A stale client that read revision N cannot overwrite a
  --     newer state: it gets the documented `revision_mismatch` with the server's
  --     revision so it can re-read. (API_CONTRACT §2 error model.)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    return jsonb_build_object('ok', false, 'error', 'revision_mismatch',
                              'order_id', p_order_id, 'status', v_o_status,
                              'server_revision', v_o_rev,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (c) transition legality: SINGLE-STEP forward only over the FROZEN states
  --     (D-018, STATE_MACHINES §1.1). Skips, backwards, terminal sources
  --     (completed/cancelled/voided), unknown targets, and from==to are all
  --     invalid_transition (returned, not raised — a permanent per-op rejection
  --     through sync_push; no state change). The client can NEVER choose an
  --     arbitrary next status: only these five (from, to) pairs exist.
  v_legal := case
    when v_o_status = 'submitted' and p_new_status = 'accepted'  then true
    when v_o_status = 'accepted'  and p_new_status = 'preparing' then true
    when v_o_status = 'preparing' and p_new_status = 'ready'     then true
    when v_o_status = 'ready'     and p_new_status = 'served'    then true
    when v_o_status = 'served'    and p_new_status = 'completed' then true
    else false end;
  if not v_legal then
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'from', v_o_status, 'to', p_new_status, 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) role authorization: the production + service steps (->accepted/->preparing/
  --     ->ready/->served — the last is the KDS "bump") allow kitchen_staff + cashier
  --     + manager + restaurant_owner + org_owner; the settlement step (->completed)
  --     EXCLUDES kitchen_staff. A denial is audited (order.status_update_denied —
  --     NO money fields) and RETURNED (no raise, so the audit persists), with NO
  --     state change.
  if p_actor_role not in ('kitchen_staff', 'cashier', 'manager', 'restaurant_owner', 'org_owner')
     or (p_actor_role = 'kitchen_staff' and p_new_status = 'completed') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (p_actor_org, p_actor_restaurant, p_actor_branch, p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
            'order.status_update_denied', null, null,
            jsonb_build_object('attempted_action', 'update_order_status', 'order_id', p_order_id,
                               'order_code', v_order_code,
                               'role', p_actor_role, 'from', v_o_status, 'to', p_new_status,
                               'local_operation_id', p_local_operation_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (e) D-025 PAYMENT GATE (ORDER-COMPLETION-001) — an order reaches `completed`
  --     only when payment is `completed`. Derived, never fabricated: "paid" is the
  --     existence of a completed, live payments row (the SAME derivation the
  --     reports and owner_active_orders use). This creates NO payment and changes
  --     NO payments row. A business rejection, NOT an authorization denial, so —
  --     like invalid_transition — it is RETURNED and deliberately NOT audited (the
  --     denied-attempt audit is reserved for authorization failures).
  if p_new_status = 'completed' then
    -- ORDER-AUTO-COMPLETION-001: the ONE authoritative settlement test (integer
    -- minor units). Replaces the bare exists()-a-completed-payment MARKER test:
    -- app.apply_discount can re-base grand_total_minor after a payment is taken, so
    -- a marker could report a partially-settled order as paid. Identical to the old
    -- test in every normal case (the stored amount IS the order total).
    v_paid := app.order_is_fully_settled(v_o_org, p_order_id);
    if not v_paid then
      return jsonb_build_object('ok', false, 'error', 'order_not_paid',
                                'order_id', p_order_id, 'from', v_o_status, 'to', p_new_status,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
    -- PSC-001C: the MANUAL completion gate additionally requires EVERY
    -- additional service round to be served (app.order_rounds_all_served —
    -- zero rounds passes trivially). A business rejection like order_not_paid:
    -- RETURNED, deliberately not audited (the denied-attempt audit is reserved
    -- for authorization failures).
    -- DEFERRED-ORDER-AMENDMENTS-001: the rounds gate is KDS-MODE ONLY.
    -- The ONE mode read, FAIL-CLOSED to 'kds' exactly as
    -- app.try_auto_complete_order does it (a missing or soft-deleted branch row
    -- can only ever produce the historical behaviour, never the widened
    -- printer-only path). The branch is the ORDER's own authoritative
    -- branch_id, already proven equal to the caller scope in (a).
    select b.kitchen_workflow_mode into v_kitchen_mode
      from public.branches b
      where b.id              = v_o_branch
        and b.organization_id = v_o_org
        and b.deleted_at is null;
    v_kitchen_mode := coalesce(v_kitchen_mode, 'kds');
    -- printer_only: there is no KDS to walk a round to `served`, so holding
    -- manual completion on it would strand every added-to order forever. The
    -- gate is SKIPPED — never satisfied by fabricating a round status.
    -- kds: byte-equivalent to the pre-DEFERRED-ORDER-AMENDMENTS-001 behaviour.
    if v_kitchen_mode <> 'printer_only'
       and not app.order_rounds_all_served(v_o_org, p_order_id) then
      return jsonb_build_object('ok', false, 'error', 'rounds_not_served',
                                'order_id', p_order_id, 'from', v_o_status, 'to', p_new_status,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
    -- PRINTER-ONLY-CLOSE-ALL-ROUNDS-AND-RELEASE-TABLE-008. Skipping the gate
    -- (above) let the ORDER complete but left every amendment round LIVE for
    -- ever: `app.add_order_items` opens a round at `submitted`, and the
    -- transition matrix admits a KDS DEVICE ONLY for submitted->..->ready, so on
    -- a one-device site NOTHING can walk it forward. The result was a
    -- non-served round hanging off a TERMINAL order, with
    -- app.order_rounds_all_served permanently false for a COMPLETED order.
    --
    -- The rounds are closed HERE, in the SAME transaction and BEFORE the order
    -- row moves, so the two can never disagree: either every eligible round is
    -- terminal and the order is completed, or nothing commits. Every refusal
    -- above returns before this point, so a refused completion still closes
    -- nothing. kds mode never reaches this line (the gate returned).
    if v_kitchen_mode = 'printer_only' then
      perform app.terminalize_printer_only_rounds(
        v_o_org, p_actor_restaurant, v_o_branch, p_order_id,
        p_actor_app_user_id, p_actor_employee_profile_id, p_device_id);
    end if;
  end if;

  -- (f) mutate: status forward one step; bump revision (updated_at bumps via the
  --     RF-052 set_updated_at trigger, feeding the sync_pull change cursor).
  --     orders.status + orders.revision are the ONLY columns written. No payment,
  --     no shift, no table, no receipt, no total is touched.
  v_new_rev := v_o_rev + 1;
  update public.orders
    set status   = p_new_status,
        revision = v_new_rev,
        -- PSC-001C: the WRITE-ONCE durable ready stamp for the INITIAL kitchen
        -- work unit (the ready-feed source). Stamped exactly when a transition
        -- lands on `ready`; never cleared or re-stamped afterwards (the
        -- single-step matrix makes `ready` reachable once, and the case-guard
        -- keeps the stamp idempotent regardless).
        ready_at = case when p_new_status = 'ready' and ready_at is null then now() else ready_at end
    where id = p_order_id;

  -- (g) audit order.status_updated (D-013) — old/new STATUS + revision + actor
  --     linkage + the SAFE order_code, plus the derived payment_status on a
  --     completion. Deliberately NO money fields: a kitchen actor drives the
  --     production steps of this path and must never put a money figure on the
  --     wire or in its audit (T-003).
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (p_actor_org, p_actor_restaurant, p_actor_branch, p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
          'order.status_updated', null,
          jsonb_build_object('order_id', p_order_id, 'status', v_o_status, 'revision', v_o_rev),
          jsonb_build_object('order_id', p_order_id, 'order_code', v_order_code,
                             'status', p_new_status, 'revision', v_new_rev,
                             'resolved_membership_id', p_actor_membership_id, 'role', p_actor_role,
                             'local_operation_id', p_local_operation_id)
          -- THE AUDIT MUST NOT LIE (D-013): a ZERO-TOTAL order is completed WITHOUT a
          -- payment row, so 'paid' would assert a payment that was never taken. State
          -- the truth — there was nothing to pay.
          || case when p_new_status = 'completed'
                  then jsonb_build_object('payment_status',
                                          case when v_o_total = 0 then 'not_chargeable'
                                               else 'paid' end,
                                          'completion_mode', 'manual')
                  else '{}'::jsonb end);

  -- (h) TRIGGER DIRECTION A (ORDER-AUTO-COMPLETION-001): the order just reached
  --     `served`. If it is ALREADY fully paid, complete it now — in this same
  --     transaction, under the order row lock we already hold. The `served`
  --     transition above stands on its own and is NEVER failed by this: an unpaid
  --     order simply stays served (and stays visible in Awaiting close). The helper
  --     never raises, and it does not re-run the role gate — the kitchen actor was
  --     already authorized to make THIS transition, and the completion is a
  --     system-rule consequence of it, not a second human decision.
  if p_new_status = 'served' then
    v_auto := app.try_auto_complete_order(
      p_actor_org, p_actor_restaurant, p_actor_branch, p_order_id,
      'order_served',
      p_actor_app_user_id, p_actor_employee_profile_id, p_actor_membership_id,
      p_actor_role, p_device_id, p_local_operation_id);
    if (v_auto ->> 'completed')::boolean then
      -- Report the FINAL state, so the caller (and the sync ledger) never records a
      -- status the order is no longer in.
      return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                                'order_code', v_order_code,
                                'status', 'completed',
                                'revision', (v_auto ->> 'revision')::integer,
                                'auto_completed', true,
                                'completion_trigger', 'order_served',
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                            'order_code', v_order_code,
                            'status', p_new_status, 'revision', v_new_rev,
                            'auto_completed', false,
                            'server_ts', now(), 'idempotency_replay', false);
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. app.try_auto_complete_order - FORWARD RE-EMISSION of the live
--    20260723090000 body, byte-identical except for the same printer-only round
--    closure before the status write. The AUTOMATIC path completes a
--    printer_only order on settlement alone, so it stranded rounds too.
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

  -- PRINTER-ONLY-CLOSE-ALL-ROUNDS-AND-RELEASE-TABLE-008: the printer-only
  -- eligibility branch above deliberately SKIPS the rounds gate, so this path
  -- strands amendment rounds exactly as the manual one did. Close them in the
  -- same transaction, before the order moves. kds mode cannot reach this with a
  -- live round (its gate returned `rounds_active`), so the call is confined to
  -- printer_only and the KDS workflow is byte-unchanged.
  if v_kitchen_mode = 'printer_only' then
    perform app.terminalize_printer_only_rounds(
      p_organization_id, p_restaurant_id, p_branch_id, p_order_id,
      p_actor_app_user_id, p_actor_employee_profile_id, p_device_id);
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

-- ----------------------------------------------------------------------------
-- 4. app.set_kitchen_workflow_mode - the guarded owner setter that makes
--    printer_only reachable at last.
--
--    Authority: an ACTIVE membership covering the branch with rank >= 3
--    (restaurant_owner / org_owner). A manager or cashier may not reshape the
--    branch's kitchen workflow. No membership at all (including cross-tenant)
--    gets `not_found`, never `permission_denied` - the same no-scope-leak
--    contract app.get_branch_kitchen_workflow_mode already uses.
--
--    The branch row is taken FOR NO KEY UPDATE, which is exactly the lock the
--    20260803090000 dispatch guard documents as conflicting with the FOR SHARE
--    an in-flight direct_print acceptance holds - so a mode change cannot commit
--    underneath one, and vice versa.
--
--    Bumps kitchen_workflow_mode_revision on a real change (20260725090000
--    reserved it for precisely this setter) so stale client caches and stale
--    mode-change requests stay rejectable. A no-op set returns ok with
--    changed=false and writes NO audit row and NO revision bump.
-- ----------------------------------------------------------------------------
create or replace function app.set_kitchen_workflow_mode(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_branch_id       uuid,
  p_mode            text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_old   text;
  v_rev   integer;
begin
  if v_actor is null then
    raise exception 'set_kitchen_workflow_mode: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;

  -- SCOPE FIRST: never reveal anything about a branch the caller cannot see.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  if v_rank < 3 then
    return jsonb_build_object('ok', false, 'error', 'permission_denied');
  end if;

  -- The value space is the table's own CHECK; reject anything else BEFORE
  -- touching the row so a bad request cannot even take the lock.
  if p_mode is null or p_mode not in ('kds', 'printer_only') then
    return jsonb_build_object('ok', false, 'error', 'invalid_mode');
  end if;

  select b.kitchen_workflow_mode, b.kitchen_workflow_mode_revision
    into v_old, v_rev
    from public.branches b
   where b.id              = p_branch_id
     and b.organization_id = p_organization_id
     and b.restaurant_id   = p_restaurant_id
     and b.deleted_at is null
   for no key update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;

  if v_old = p_mode then
    return jsonb_build_object('ok', true, 'entity', 'branch', 'branch_id', p_branch_id,
                              'kitchen_workflow_mode', v_old,
                              'kitchen_workflow_mode_revision', v_rev,
                              'changed', false);
  end if;

  update public.branches
     set kitchen_workflow_mode          = p_mode,
         kitchen_workflow_mode_revision = v_rev + 1
   where id              = p_branch_id
     and organization_id = p_organization_id;

  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    p_organization_id, p_restaurant_id, p_branch_id,
    v_actor, null, null,
    'branch.kitchen_workflow_mode_updated', null,
    jsonb_build_object('kitchen_workflow_mode', v_old,
                       'kitchen_workflow_mode_revision', v_rev),
    jsonb_build_object('kitchen_workflow_mode', p_mode,
                       'kitchen_workflow_mode_revision', v_rev + 1));

  return jsonb_build_object('ok', true, 'entity', 'branch', 'branch_id', p_branch_id,
                            'kitchen_workflow_mode', p_mode,
                            'kitchen_workflow_mode_revision', v_rev + 1,
                            'changed', true);
end;
$$;

comment on function app.set_kitchen_workflow_mode(uuid, uuid, uuid, text) is
  'PRINTER-ONLY-CLOSE-ALL-ROUNDS-AND-RELEASE-TABLE-008: the guarded owner setter for branches.kitchen_workflow_mode, which had NO writer in any shipped migration (20260723090000 "DORMANT: no setter RPC exists yet") - so every branch was stuck on the ''kds'' default and the entire printer-only path was unreachable. Requires an ACTIVE membership covering the branch with rank >= 3 (restaurant_owner/org_owner); rank 1-2 => permission_denied; no membership or cross-tenant => not_found (no scope leak). Validates against the column''s own CHECK value space. Takes the branch FOR NO KEY UPDATE, the lock the 20260803090000 dispatch guard relies on, so a mode change cannot commit underneath an in-flight direct_print acceptance. Bumps kitchen_workflow_mode_revision on a real change (reserved for this setter by 20260725090000) so stale client caches stay rejectable; a no-op returns changed=false and writes neither an audit row nor a bump. Audits branch.kitchen_workflow_mode_updated with old/new mode + revision. Touches NOTHING else on the branch.';

create or replace function public.set_kitchen_workflow_mode(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_mode text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_kitchen_workflow_mode(p_organization_id, p_restaurant_id, p_branch_id, p_mode); $$;

comment on function public.set_kitchen_workflow_mode(uuid, uuid, uuid, text) is
  'PRINTER-ONLY-CLOSE-ALL-ROUNDS-AND-RELEASE-TABLE-008: public wrapper (security invoker) over app.set_kitchen_workflow_mode, mirroring the get_branch_kitchen_workflow_mode pair. authenticated-only.';

revoke all on function app.set_kitchen_workflow_mode(uuid, uuid, uuid, text)       from public;
revoke all on function app.set_kitchen_workflow_mode(uuid, uuid, uuid, text)       from anon;
grant execute on function app.set_kitchen_workflow_mode(uuid, uuid, uuid, text)    to authenticated;
revoke all on function public.set_kitchen_workflow_mode(uuid, uuid, uuid, text)    from public;
revoke all on function public.set_kitchen_workflow_mode(uuid, uuid, uuid, text)    from anon;
grant execute on function public.set_kitchen_workflow_mode(uuid, uuid, uuid, text) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only - `supabase db reset` replays):
--   restore app.apply_order_status_transition from 20260804090000;
--   restore app.try_auto_complete_order       from 20260723090000;
--   drop function if exists public.set_kitchen_workflow_mode(uuid, uuid, uuid, text);
--   drop function if exists app.set_kitchen_workflow_mode(uuid, uuid, uuid, text);
--   drop function if exists app.terminalize_printer_only_rounds(uuid, uuid, uuid, uuid, uuid, uuid, uuid);
-- Rounds already closed by this migration stay closed - they are authoritative
-- history, not a cache.
-- ============================================================================
