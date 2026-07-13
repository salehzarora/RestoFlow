-- ============================================================================
-- MONEY-SETTLEMENT-CONSISTENCY-001 (corrective) — PRESERVE THE DOMAIN ERROR CONTRACT
-- THROUGH sync_push.
--
-- THE BUG (independent review, P1). app.sync_push finalizes a dispatched operation in
-- two DIFFERENT ways, and only ONE of them keeps the RPC's own error envelope:
--
--   * The RPC RETURNS {ok:false, ...}  (20260710100000, step (b6), the `else` arm):
--         v_results := v_results || (v_dispatch || jsonb_build_object(... 'status','rejected' ...))
--     -> the RPC's OWN envelope is merged through VERBATIM. `error` and `detail` survive.
--     This is exactly how app.void_order's `order_has_completed_payment` already reaches
--     the POS, and it is the documented contract.
--
--   * The RPC RAISES (same step, the exception arm):
--         jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', v_caught_state,
--                            'detail', case when v_caught_msg ilike '%...%' ...)
--     -> the envelope is REBUILT FROM SCRATCH. The RPC's own result is DISCARDED, `error`
--     collapses to the generic literal 'rejected', and `detail` is populated for exactly
--     ONE legacy message pattern (revoked_employee). EVERY OTHER DOMAIN CODE IS LOST.
--
-- Two refusals were on the RAISE side and therefore unreachable by the client:
--   1. record_payment's `order_not_chargeable` (MONEY-SETTLEMENT-CONSISTENCY-001) — so the
--      POS could not show the localized "nothing to pay" explanation it promises.
--   2. void_order's illegal-source-state refusal — so a TERMINAL order was indistinguishable
--      from a transport failure, a malformed response, or any other rejection. The POS was
--      left inferring "already closed" from a zero total, which could tell an operator an
--      order was closed when the network had simply dropped.
--
-- THE FIX — the smallest one that exists: convert those two refusals from RAISE to RETURN.
-- sync_push then propagates them through the EXISTING, already-tested passthrough contract.
-- **app.sync_push is NOT MODIFIED**, no envelope is invented, no raw SQL text is exposed,
-- and no new error class is added — `status` stays 'rejected' and the sync ledger /
-- sync.operation_rejected audit behave exactly as before.
--
-- WHAT DOES NOT CHANGE (verified):
--   * Zero-total side-effect protections: the guard still sits AFTER authorization/scope/
--     state validation and BEFORE the shift+drawer row locks, the receipt allocation and
--     the payment insert. A RETURN reaches none of them, and record_payment's
--     order_operations ledger row is written only on SUCCESS — so a refusal still writes
--     NO payment, allocates NO receipt number, touches NO shift/cash drawer, bumps NO
--     revision and leaves NO success ledger entry. Identical to the RAISE behaviour.
--   * VOID ELIGIBILITY IS UNTOUCHED. The legal source states are still exactly
--     submitted/accepted/preparing/ready/served; `completed` stays TERMINAL; there is NO
--     completed -> void path. Only the SHAPE of the refusal changes.
--   * record_payment's OTHER preconditions (state legality, double-charge, insufficient
--     tender, no open shift/drawer) still RAISE, unchanged — every existing test holds.
--   * Normal cash / card / bit / external payments, successful envelopes, and
--     idempotent replay are byte-for-byte unchanged.
--
-- AUDIT:
--   * void_order: the new RETURN is audited `order.void_denied` with
--     denied_reason='order_not_voidable' — the SAME convention its two other RETURN-based
--     denials already use (permission_denied, order_has_completed_payment). A RAISE could
--     not have audited at all (it would roll the audit row back). `denied_reason` is
--     already on the audit_safe_detail allowlist. No new action key.
--   * record_payment: NO audit, deliberately. Its refusal policy is that only the
--     AUTHORIZATION denial is audited (payment.denied); every precondition is unaudited.
--     A zero-total order is a precondition, not a denial. sync_push still records the
--     refusal as `sync.operation_rejected` (now carrying the honest
--     error='order_not_chargeable' instead of the generic 'rejected'), so the trail is
--     strictly MORE informative than before, with no new action.
--
-- Additive / forward-only. No table, column, CHECK, RLS policy, trigger or index change;
-- no signature change (CREATE OR REPLACE preserves every ACL); no historical row rewritten.
-- PENDING: RISK R-003 sign-off. NOT applied to hosted by this migration.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. app.record_payment — re-created VERBATIM from MONEY-SETTLEMENT-CONSISTENCY-001
--    (20260715090000) with exactly ONE surgical change: the NON-CHARGEABLE refusal now
--    RETURNS {ok:false, error:'order_not_chargeable'} instead of raising, so sync_push
--    propagates the stable code instead of collapsing it to a generic 'rejected'.
--    The guard's POSITION, and therefore every zero-tender side-effect protection, is
--    unchanged. Every OTHER precondition still raises, exactly as before.
-- ---------------------------------------------------------------------------

create or replace function app.record_payment(
  p_pin_session_id             uuid,
  p_order_id                   uuid,
  p_device_id                  uuid,
  p_local_operation_id         text,
  p_tender_type                text,
  p_amount_tendered_minor      bigint,
  p_provisional_receipt_number text default null,
  p_expected_revision          integer default null
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
  v_pairing       text;
  v_role          text;
  v_m_status      text;
  v_m_deleted     timestamptz;
  v_o_org         uuid;
  v_o_branch      uuid;
  v_o_status      text;
  v_o_rev         integer;
  v_grand         bigint;
  v_currency      text;
  v_o_provisional text;
  v_completed_cnt integer;
  v_payable       bigint;
  v_tendered      bigint;          -- RF-117: effective tendered (cash: as given; non-cash: = payable)
  v_change        bigint;
  v_receipt_seq   bigint;
  v_receipt_no    text;
  v_payment_id    uuid;
  v_new_rev       integer;
  v_stored        jsonb;
  v_stored_order  uuid;
  v_result        jsonb;
  v_shift_id      uuid;
  v_drawer_id     uuid;
  v_auto          jsonb;   -- ORDER-AUTO-COMPLETION-001 (trigger direction B)
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'record_payment: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'record_payment: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'record_payment: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'record_payment: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'record_payment: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the order; it MUST be in the actor's org + branch (no cross-tenant).
  --     RF-062 (A1): FOR UPDATE locks the order row FIRST (before the shift/drawer
  --     locks below), so record_payment and void_order serialize on the same order —
  --     a payment cannot complete between void_order's completed-payment guard and its
  --     void, and a void cannot complete between this check and the payment insert.
  --     Global lock order orders -> shifts -> drawer is preserved (no deadlock).
  select o.organization_id, o.branch_id, o.status, o.revision,
         o.grand_total_minor, o.currency_code, o.receipt_provisional_id
    into v_o_org, v_o_branch, v_o_status, v_o_rev, v_grand, v_currency, v_o_provisional
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'record_payment: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'record_payment: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (A7): cashier+ may record a payment. kitchen_staff/
  --     accountant/other denied -> payment.denied audit + permission_denied (no raise).
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'payment.denied', null, null,
      jsonb_build_object('attempted_action', 'record_payment', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) safe input validation. RF-117: accept cash + non-cash externally-recorded tenders.
  if p_tender_type is null or p_tender_type not in ('cash', 'card', 'bit', 'external') then
    raise exception 'record_payment: unsupported tender type (got %)', coalesce(p_tender_type, '<null>') using errcode = '42501';
  end if;
  if p_amount_tendered_minor is null or p_amount_tendered_minor < 0 then
    raise exception 'record_payment: amount_tendered_minor must be a non-negative integer (minor units)' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + input validation, ORDER-BOUND.
  select oo.result, oo.order_id into v_stored, v_stored_order
    from public.order_operations oo
    where oo.organization_id = v_org and oo.device_id = p_device_id
      and oo.local_operation_id = p_local_operation_id and oo.action = 'record_payment';
  if found then
    if v_stored_order <> p_order_id then
      raise exception 'record_payment: idempotency key already used for a different order (%, not %)', v_stored_order, p_order_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) eligible order states (D-025): pay-first supported. draft/cancelled/voided/completed excluded.
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    raise exception 'record_payment: order status % is not a legal payment source state', v_o_status using errcode = '42501';
  end if;

  -- (f1) MONEY-SETTLEMENT-CONSISTENCY-001 — A NON-CHARGEABLE ORDER TAKES NO PAYMENT.
  --      A ZERO-TOTAL order (comped / 100%-discounted) owes NOTHING: app.order_is_fully_settled
  --      already reports it SETTLED, and ORDER-AUTO-COMPLETION-001 auto-completes it on
  --      `served` WITHOUT a payment row. Recording a "payment" for it would mint a
  --      0-amount payments row and BURN a per-branch receipt number (D-021, a gapless
  --      monotonic sequence) for money that never moved, then permanently block the
  --      double-charge guard at (g).
  --
  --      PLACED HERE ON PURPOSE — after the PIN/device/membership authorization (a-c), the
  --      input validation (d), the idempotency replay (e) and the state legality (f), but
  --      BEFORE the shift/drawer ROW LOCKS (f2), the receipt allocation (j) and the payment
  --      insert (k). A refused zero tender therefore touches NOTHING: no shift, no cash
  --      drawer, no receipt counter, no payment row, no order revision, no ledger entry.
  --
  --      KEYED ON THE ORDER'S grand_total_minor, NEVER ON p_amount_tendered_minor: a
  --      NON-CASH tender (card/bit/external) legitimately passes tendered = 0 (RF-117),
  --      and rejecting on the tendered amount would break every non-cash payment.
  --      `<= 0` also FAILS CLOSED on a negative total (impossible under the orders CHECK
  --      grand_total_minor >= 0, but a money defect must never be charged for).
  --
  --      REFUSAL POLICY: raise, no audit — the SAME convention every other record_payment
  --      precondition uses (state legality, double-charge, insufficient tender). Only the
  --      AUTHORIZATION denial is return-based + audited (payment.denied); this is not an
  --      authorization failure, so it does not borrow that path.
  --      RETURNS the stable domain code (it does NOT raise). app.sync_push rebuilds the
  --      envelope from scratch for a RAISE — collapsing every domain code to the generic
  --      literal 'rejected' — but merges a RETURNED envelope through VERBATIM, so `error`
  --      survives to the client. That is the same contract app.void_order already relies on
  --      for order_has_completed_payment. NOTHING is written on this path: the guard is
  --      before the shift/drawer locks, before the receipt allocation, before the payment
  --      insert, and the order_operations ledger row is only written on success.
  if v_grand <= 0 then
    return jsonb_build_object(
      'ok', false, 'error', 'order_not_chargeable', 'order_id', p_order_id,
      'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (f2) RF-055 precondition + ROW LOCKS: an OPEN shift + ACTIVE bound cash drawer for
  --      (org, branch, device). Non-cash payments still record inside the shift (harmless:
  --      close_shift filters method='cash'), preserving the shift/drawer accounting model.
  select s.id into v_shift_id
    from public.shifts s
    where s.organization_id = v_org and s.branch_id = v_branch and s.device_id = p_device_id
      and s.status = 'open'
    for update
    limit 1;
  if not found then
    raise exception 'record_payment: no open shift for this branch/device (precondition_failed)' using errcode = '42501';
  end if;
  select cds.id into v_drawer_id
    from public.cash_drawer_sessions cds
    where cds.organization_id = v_org and cds.shift_id = v_shift_id and cds.status = 'active'
    for update
    limit 1;
  if not found then
    raise exception 'record_payment: no active cash drawer for the open shift (precondition_failed)' using errcode = '42501';
  end if;

  -- (g) at most one completed payment per order (no double-charge; D-024/D-025)
  select count(*) into v_completed_cnt
    from public.payments p
    where p.organization_id = v_org and p.order_id = p_order_id and p.status = 'completed';
  if v_completed_cnt > 0 then
    raise exception 'record_payment: order % already has a completed payment', p_order_id using errcode = '42501';
  end if;

  -- (h) optimistic concurrency (optional)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    raise exception 'record_payment: revision conflict (expected %, got %)', p_expected_revision, v_o_rev using errcode = '40001';
  end if;

  -- (i) tender + change. payable = the order grand total (never recomputed). RF-117:
  --     CASH keeps physical tender >= payable with change = tendered - payable. A NON-CASH
  --     tender (card/bit/external) has no drawer cash movement: record the exact amount
  --     (tendered = payable, change = 0) so payments_change_balances holds and close_shift
  --     (method='cash' only) is unaffected. No cash rounding (MVP). No float (D-007).
  v_payable := v_grand;
  if p_tender_type = 'cash' then
    if p_amount_tendered_minor < v_payable then
      raise exception 'record_payment: amount_tendered_minor (%) is less than the order total (%)', p_amount_tendered_minor, v_payable using errcode = '42501';
    end if;
    v_tendered := p_amount_tendered_minor;
    v_change   := v_tendered - v_payable;
  else
    v_tendered := v_payable;
    v_change   := 0;
  end if;

  -- (j) allocate the authoritative per-branch receipt number (D-021) under a ROW LOCK.
  insert into public.branch_receipt_counters as brc
      (organization_id, restaurant_id, branch_id, last_issued_value)
    values (v_org, v_rest, v_branch, 1)
    on conflict (organization_id, restaurant_id, branch_id) do update
      set last_issued_value = brc.last_issued_value + 1
    returning brc.last_issued_value into v_receipt_seq;
  v_receipt_no := v_receipt_seq::text;

  -- (k) insert the completed payment, STAMPED with the open shift + active drawer.
  --     RF-117: method = the REAL tender type; non-cash tendered=payable/change=0.
  insert into public.payments (
    organization_id, restaurant_id, branch_id, order_id, device_id,
    taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id,
    method, status, amount_minor, tendered_minor, change_minor, currency_code,
    receipt_number, provisional_receipt_number, local_operation_id, revision)
  values (
    v_org, v_rest, v_branch, p_order_id, p_device_id,
    v_emp, v_membership, v_shift_id, v_drawer_id,
    p_tender_type, 'completed', v_payable, v_tendered, v_change, v_currency,
    v_receipt_no, p_provisional_receipt_number, p_local_operation_id, 1)
  returning id into v_payment_id;

  -- (l) set orders.receipt_number (+ keep any client provisional) and bump revision.
  v_new_rev := v_o_rev + 1;
  update public.orders
    set receipt_number = v_receipt_no,
        receipt_provisional_id = coalesce(v_o_provisional, p_provisional_receipt_number),
        revision = v_new_rev
    where id = p_order_id;

  -- (m) audit: payment.recorded (REAL method) + receipt_number.assigned (D-013).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'payment.recorded', null, null,
    jsonb_build_object(
      'payment_id',             v_payment_id,
      'order_id',               p_order_id,
      'method',                 p_tender_type,
      'status',                 'completed',
      'amount_minor',           v_payable,
      'tendered_minor',         v_tendered,
      'change_minor',           v_change,
      'currency_code',          v_currency,
      'receipt_number',         v_receipt_no,
      'shift_id',               v_shift_id,
      'cash_drawer_session_id', v_drawer_id,
      'resolved_membership_id', v_membership));

  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'receipt_number.assigned', null,
    jsonb_build_object('receipt_number', null),
    jsonb_build_object(
      'order_id',         p_order_id,
      'payment_id',       v_payment_id,
      'branch_id',        v_branch,
      'receipt_number',   v_receipt_no,
      'receipt_sequence', v_receipt_seq,
      'order_revision',   v_new_rev));

  -- (n) TRIGGER DIRECTION B (ORDER-AUTO-COMPLETION-001): the order has just become
  --     FULLY PAID. If it is ALREADY `served`, complete it now — in this same
  --     transaction, under the order row lock this function has held since step (b),
  --     so there is NO new lock and NO new lock order. An order in
  --     submitted/accepted/preparing/ready is left exactly where it is; a terminal
  --     order is never revived. The helper NEVER RAISES: a failure here must never
  --     turn this SUCCESSFUL payment into a client-visible failure (the POS payment
  --     parser is fail-closed and treats any non-`applied` result as a failed
  --     payment). Payment state is NOT changed by this — the payment row is already
  --     written and is never touched again.
  v_auto := app.try_auto_complete_order(
    v_org, v_rest, v_branch, p_order_id,
    'payment_recorded',
    null, v_emp, v_membership, v_role, p_device_id, p_local_operation_id);
  if (v_auto ->> 'completed')::boolean then
    v_new_rev := (v_auto ->> 'revision')::integer;   -- report the FINAL revision
  end if;

  -- (o) record the idempotency ledger result + return
  v_result := jsonb_build_object(
    'ok', true, 'payment_id', v_payment_id, 'order_id', p_order_id,
    'method', p_tender_type, 'receipt_number', v_receipt_no, 'change_due_minor', v_change,
    'shift_id', v_shift_id, 'cash_drawer_session_id', v_drawer_id,
    'payment_revision', 1, 'order_revision', v_new_rev,
    -- Additive keys; existing clients ignore what they do not read.
    'auto_completed', coalesce((v_auto ->> 'completed')::boolean, false),
    'order_status', case when coalesce((v_auto ->> 'completed')::boolean, false)
                         then 'completed' else v_o_status end);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'record_payment', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) is
  'RF-054/RF-055/RF-117 + ORDER-AUTO-COMPLETION-001 (API_CONTRACT §4.7, D-011) SECURITY DEFINER RPC: records a payment + assigns the per-branch receipt number (D-021). Tender cash|card|bit|external; CASH keeps tendered>=grand_total + change=tendered-grand_total; NON-CASH records amount=tendered=grand_total, change=0. Requires an open shift + active bound cash drawer and stamps shift_id/cash_drawer_session_id. PIN-session auth; cashier+ only; order-bound idempotency; at most one completed payment per order. AUTO-COMPLETION (direction B): after the payment is written, if the order is ALREADY `served` and is now fully settled, app.try_auto_complete_order completes it in the SAME transaction under the order row lock this function already holds (no new lock, no new lock order); an order in submitted/accepted/preparing/ready is left untouched, and a terminal order is never revived. The helper NEVER RAISES, so a successful payment can never be surfaced as a failed one. The payment row itself is NEVER modified. It still does NOT advance orders.status by itself (D-025) — the automatic rule does, and only for served+fully-paid. Writes payment.recorded + receipt_number.assigned (D-013), plus ONE order.status_updated (completion_mode=automatic) when it auto-completes.';

-- ---------------------------------------------------------------------------
-- 2. app.void_order — re-created VERBATIM from STAFF-CASHIER-PERMISSIONS-001
--    (20260710110000) with exactly ONE surgical change: the ILLEGAL-SOURCE-STATE refusal
--    now RETURNS {ok:false, error:'invalid_transition', detail:'order_not_voidable'} and
--    audits order.void_denied, instead of raising an untyped 42501 that sync_push
--    flattened into a generic 'rejected'.
--
--    VOID ELIGIBILITY IS NOT CHANGED. The legal source states are still exactly
--    submitted/accepted/preparing/ready/served. `completed` stays TERMINAL (D-024) and a
--    completed order — zero-total or not — is still NOT voidable. The role gate, the
--    mandatory reason, the RF-062 completed-payment guard, the idempotency ledger, the
--    item cascade and the success audit are all UNCHANGED.
-- ---------------------------------------------------------------------------

create or replace function app.void_order(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_reason             text,
  p_expected_revision  integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_org          uuid;
  v_rest         uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_emp          uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_role         text;
  v_m_status     text;
  v_m_deleted    timestamptz;
  v_m_perms      jsonb;
  v_o_org        uuid;
  v_o_branch     uuid;
  v_o_status     text;
  v_o_rev        integer;
  v_authorized   boolean;
  v_new_rev      integer;
  v_voided_items integer;
  v_stored       jsonb;
  v_stored_order uuid;
  v_result       jsonb;
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'void_order: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'void_order: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'void_order: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'void_order: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'void_order: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the order; it MUST be in the actor's org + branch (no cross-tenant).
  --     RF-062 (A4): FOR UPDATE locks the order row so void_order serializes with
  --     record_payment (which now also locks the order row) on the SAME order — a
  --     payment cannot complete between the (g2) guard and the void.
  select o.organization_id, o.branch_id, o.status, o.revision
    into v_o_org, v_o_branch, v_o_status, v_o_rev
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'void_order: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'void_order: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (A1): manager/restaurant_owner/org_owner, OR a cashier with an
  --     explicit memberships.permissions->>'void_order' = 'true' grant. RF053-B1:
  --     authorization runs BEFORE the idempotency replay so an unauthorized actor can
  --     never replay a prior SUCCESS result. A DENIAL is audited (order.void_denied)
  --     + RETURNED (no raise, so the audit persists) with NO state change and NO ledger
  --     write (the ledger holds only authorized successes; denials are always re-audited
  --     as probe attempts, never replayed).
  v_authorized := (v_role in ('manager', 'restaurant_owner', 'org_owner'))
                  or app.cashier_capability_allowed(v_role, v_m_perms, 'void_order');

  if not v_authorized then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) reason mandatory (AC#2)
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'void_order: a non-empty reason is required' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + reason, BEFORE the
  --     voidable-source-state check (the order becomes 'voided' after the first
  --     success). ORDER-BOUND: the stored op MUST be for the same order; the same
  --     (org, device, local_operation_id, action) reused on a DIFFERENT order is a
  --     conflict, not a replay (never leaks the original order's result).
  select oo.result, oo.order_id into v_stored, v_stored_order
    from public.order_operations oo
    where oo.organization_id = v_org and oo.device_id = p_device_id
      and oo.local_operation_id = p_local_operation_id and oo.action = 'void_order';
  if found then
    if v_stored_order <> p_order_id then
      raise exception 'void_order: idempotency key already used for a different order (%, not %)', v_stored_order, p_order_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) optimistic concurrency (optional)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    raise exception 'void_order: revision conflict (expected %, got %)', p_expected_revision, v_o_rev using errcode = '40001';
  end if;

  -- (g) state legality (AC#3, D-024): only pre-completion non-terminal source states.
  --     ELIGIBILITY IS UNCHANGED — the legal set is still exactly
  --     submitted/accepted/preparing/ready/served, `completed` remains TERMINAL, and there
  --     is NO completed -> void path. Only the SHAPE of the refusal changes.
  --
  --     MONEY-SETTLEMENT-CONSISTENCY-001 (corrective): RETURN the stable domain code
  --     instead of raising. app.sync_push REBUILDS the envelope from scratch for a RAISE
  --     (collapsing every domain code to the generic literal 'rejected'), but merges a
  --     RETURNED envelope through VERBATIM. Raising left the POS unable to tell
  --     "this order is already closed" apart from a dropped network, a malformed response
  --     or any other rejection — so it was reduced to GUESSING from the order's total, and
  --     could tell an operator an order was closed when the connection had merely failed.
  --
  --     `error` is the established coarse class for an illegal state change
  --     (`invalid_transition`, as the order state machine already uses) and `detail` is the
  --     established fine-grained safe token (as order_has_completed_payment already is).
  --     `order_status` is a STATE, never an identifier — safe to return.
  --
  --     AUDITED like the other two RETURN-based denials in this function
  --     (order.void_denied + denied_reason). A raise could not have audited at all: it
  --     would have rolled the audit row back. NO state change, NO revision bump, NO
  --     order_operations ledger row (denials are re-audited as probe attempts, never
  --     replayed).
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_not_voidable'));
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'detail', 'order_not_voidable', 'order_id', p_order_id,
                              'order_status', v_o_status,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (g2) RF-062 COMPLETED-PAYMENT GUARD (D-023/D-024; STATE_MACHINES §1; API_CONTRACT
  --      §4.6): an order with a LIVE `completed` payment cannot be voided in MVP — there
  --      is no refund/reversal flow. Checked AFTER authorization, reason, the idempotency
  --      replay, expected_revision, and state legality, BEFORE any mutation, so: a prior
  --      successful void still replays at (e) (a voided order can never acquire a
  --      completed payment afterward — record_payment rejects non-eligible orders); a
  --      genuinely terminal status is still rejected at (g) with 42501; and only a
  --      legal-source order that nonetheless carries settled money reaches here. The
  --      order row is locked FOR UPDATE (b) and record_payment also locks it, so a
  --      concurrent payment cannot slip in. A4/A5/A3 decisions: block ONLY a live
  --      `completed` payment (deleted_at IS NULL; no method filter — any completed
  --      payment blocks); org-scoped to the session-derived v_org (tenant-safe); AUDIT
  --      `order.void_denied` (denied_reason=order_has_completed_payment) + RETURN a
  --      permission_denied envelope (NO raise — a raise would roll back the audit), with
  --      NO state change to order/order_items/payment and NO order_operations ledger row
  --      (denials are re-audited as probe attempts on retry, never replayed).
  if exists (
    select 1
    from public.payments p
    where p.organization_id = v_org
      and p.order_id = p_order_id
      and p.status = 'completed'
      and p.deleted_at is null
  ) then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_has_completed_payment'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'detail', 'order_has_completed_payment', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (h) mutate: order -> voided (+reason, +revision); cascade items -> voided
  v_new_rev := v_o_rev + 1;
  update public.orders
    set status = 'voided', void_reason = p_reason, revision = v_new_rev
    where id = p_order_id;

  update public.order_items
    set status = 'voided', void_reason = p_reason
    where order_id = p_order_id and organization_id = v_org
      and status not in ('voided', 'cancelled');
  get diagnostics v_voided_items = row_count;

  -- (i) audit (order.voided) with old/new values (D-013)
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'order.voided', p_reason,
    jsonb_build_object('status', v_o_status, 'revision', v_o_rev),
    jsonb_build_object('status', 'voided', 'revision', v_new_rev,
                       'void_reason', p_reason, 'voided_item_count', v_voided_items,
                       'resolved_membership_id', v_membership));

  -- (j) record ledger + return
  v_result := jsonb_build_object('ok', true, 'order_id', p_order_id, 'status', 'voided', 'revision', v_new_rev);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'void_order', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;


comment on function app.void_order(uuid, uuid, uuid, text, text, integer) is
  'RF-053 + RF-062 + STAFF-CASHIER-PERMISSIONS-001 + MONEY-SETTLEMENT-CONSISTENCY-001 (API_CONTRACT §4.6, D-011/D-024): SECURITY DEFINER RPC voiding a WRONG, UNPAID order with a MANDATORY reason. PIN-session auth; manager/restaurant_owner/org_owner, or a cashier with an explicit void_order capability. ELIGIBILITY IS UNCHANGED: legal source states are exactly submitted/accepted/preparing/ready/served — `completed` is TERMINAL (D-024) and there is NO completed -> void path, for a zero-total order or any other. A LIVE COMPLETED payment blocks the void (RF-062; no refund flow, D-023). Order row locked FOR UPDATE (serializes with record_payment). ALL THREE refusals are RETURNED, never raised (a raise would roll back the audit row) and are audited order.void_denied with a safe denied_reason: permission_denied (role), permission_denied + detail=order_has_completed_payment (paid), and invalid_transition + detail=order_not_voidable + order_status (terminal / illegal source state). Returning rather than raising is what lets app.sync_push propagate the domain code to the client verbatim — a RAISE is flattened to a generic ''rejected'', which previously left the POS unable to tell an already-closed order apart from a dropped network. Order-bound idempotency (D-022). Success cascades items -> voided and writes order.voided (D-013). MONEY-FREE: creates/deletes NO payment and recomputes NO total.';


-- ---------------------------------------------------------------------------
-- ACL — unchanged. Both functions were re-created with CREATE OR REPLACE and an IDENTICAL
-- signature, so PostgreSQL PRESERVES the existing grants: neither has a public wrapper and
-- both remain dispatcher-reachable only (app.sync_push). This migration creates no
-- function, adds no grant, and does NOT modify app.sync_push. pgTAP asserts it.
-- ---------------------------------------------------------------------------

-- ROLLBACK (manual; forward-only migrations are never auto-reverted):
--   app.record_payment <- 20260715090000_money_settlement_consistency_001.sql
--   app.void_order     <- 20260710110000_staff_cashier_permissions_001_default_capabilities.sql
-- Reverting restores the RAISE shape, which re-collapses both domain codes to a generic
-- `rejected` at the sync boundary. NO DATA is migrated by this file, but note that a
-- rollback of the WHOLE release does NOT undo business effects already applied: orders
-- that auto-completed stay completed. FORWARD-FIX is the preferred production recovery.
