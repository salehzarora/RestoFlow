-- ============================================================================
-- RF-062 — Prevent voiding an order that has a completed payment
-- ============================================================================
-- RF-060 planning surfaced a real behavior gap: app.void_order (RF-053) checked only
-- order STATUS legality and never looked at payments, while app.record_payment
-- (RF-054/RF-055) settles a cash payment WITHOUT advancing order status (D-025). So a
-- paid order stayed in a legal void-source state (e.g. 'submitted') and an authorized
-- actor could void it, orphaning a terminal `completed` payment with no refund path —
-- violating the documented invariant (STATE_MACHINES §1 `served → voided` "rejected if
-- any completed payment exists"; API_CONTRACT §4.6 + error table "an order with a
-- completed payment cannot be voided at all in MVP"; DECISION D-023/D-024; refunds are
-- DEFERRED). This is a server-side authorization/state-integrity fix ONLY.
--
-- WHAT THIS DOES (forward-only; CREATE OR REPLACE two SECURITY DEFINER RPCs)
--   1. app.void_order — IDENTICAL to RF-053 EXCEPT (A4) it loads the order FOR UPDATE
--      and (A5) adds a COMPLETED-PAYMENT GUARD after the idempotency replay + state
--      legality and BEFORE any mutation: if any live `completed` payment exists for the
--      order, it writes an `order.void_denied` audit row and RETURNS
--      {ok:false, error:'permission_denied', detail:'order_has_completed_payment'} with
--      NO state change and NO order_operations ledger write (mirrors the existing
--      authorization-denial path; a raise would roll back the audit).
--   2. app.record_payment — IDENTICAL to RF-055 EXCEPT (A1) its order load now uses
--      FOR UPDATE, so record_payment and void_order serialize on the SAME order row and
--      a payment cannot complete in the window between void_order's guard and its void.
--
-- LOCK ORDERING (no deadlock): the global acquisition order is orders → shifts → drawer.
--   void_order locks only {orders}. record_payment locks {orders (new, first) → shifts →
--   drawer}. close_shift/reconcile_shift lock {shifts → drawer} and NEVER orders. Since
--   orders is always acquired before shifts/drawer and the shift→drawer sub-order is
--   unchanged, no lock-order inversion is introduced.
--
-- DECISIONS: D-011 SECURITY DEFINER RPC; D-013 append-only audit (denied sensitive
--   attempt audited); D-023/D-024 completed payment/order terminal, refunds DEFERRED;
--   D-025 payment does NOT advance order fulfillment status (unchanged here).
--
-- OUT OF SCOPE (unchanged): refunds / payment reversal / void_payment / void_item;
--   advancing order status on payment (D-025); state-machine changes; RLS/policy
--   changes; record_payment business logic (auth/idempotency/receipt/insert/status/
--   shift-drawer/audit/one-completed-per-order all verbatim); any client/Dart work.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. app.void_order — CREATE OR REPLACE. RF-053 body verbatim EXCEPT:
--      (A4) the order load at (b) is now `... for update`;
--      (g2) the RF-062 completed-payment guard is inserted after state legality.
-- ----------------------------------------------------------------------------
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
                  or (v_role = 'cashier' and coalesce(v_m_perms ->> 'void_order', '') = 'true');

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

  -- (g) state legality (AC#3, D-024): only pre-completion non-terminal source states
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    raise exception 'void_order: order status % is not a legal void source state', v_o_status using errcode = '42501';
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
  'RF-053 (API_CONTRACT §4.6, D-011) SECURITY DEFINER RPC, hardened by RF-062: voids a pre-completion order. Actor/scope from the PIN session (never client). Authorized for manager/restaurant_owner/org_owner or a cashier with permissions.void_order=true; an unauthorized cashier gets an order.void_denied audit + a returned permission_denied (no raise) with NO state change (A1/A3/T-006). Requires a non-empty reason; legal sources submitted/accepted/preparing/ready/served (completed/cancelled/voided/draft rejected, D-024). RF-062: loads the order FOR UPDATE and, after state legality, REJECTS the void of an order with a live completed payment (D-023/D-024; no refund in MVP) — order.void_denied audit + {ok:false,error:permission_denied,detail:order_has_completed_payment}, no mutation, no ledger. Cascades items -> voided on success; writes order.voided audit (D-013). Idempotent via order_operations (D-022).';

revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from public;
grant execute on function app.void_order(uuid, uuid, uuid, text, text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 2. app.record_payment — CREATE OR REPLACE. RF-055 body verbatim EXCEPT (A1):
--      the order load at (b) is now `... for update`, so record_payment serializes
--      with void_order on the SAME order row. NO business-logic change (auth,
--      idempotency, receipt numbering, payment insertion/status, shift/drawer logic,
--      audit, order-status behavior, and one-completed-per-order are all verbatim).
-- ----------------------------------------------------------------------------
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
  v_change        bigint;
  v_receipt_seq   bigint;
  v_receipt_no    text;
  v_payment_id    uuid;
  v_new_rev       integer;
  v_stored        jsonb;
  v_stored_order  uuid;
  v_result        jsonb;
  v_shift_id      uuid;            -- RF-055: open shift for (org, branch, device)
  v_drawer_id     uuid;            -- RF-055: its active bound cash drawer
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

  -- (c) authorization (A7): cashier+ may record a cash payment. kitchen_staff/
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

  -- (d) safe input validation
  if p_tender_type is null or p_tender_type <> 'cash' then
    raise exception 'record_payment: only cash tender is supported (got %)', coalesce(p_tender_type, '<null>') using errcode = '42501';
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

  -- (f2) RF-055 precondition + ROW LOCKS (A2/B2): there MUST be an open shift with an
  --      active bound cash drawer for this (org, branch, device). Lock the shift, then
  --      its active drawer, with FOR UPDATE in the SAME order as close_shift, so cash
  --      cannot be recorded against a drawer that closes underneath it. If close_shift
  --      holds the shift lock, this SELECT waits and then re-qualifies status (the shift
  --      is no longer 'open' / the drawer no longer 'active') -> precondition_failed; if
  --      this payment holds the lock first, close_shift waits and its expected-cash sum
  --      includes this sale (never stale). Checked AFTER the order-bound idempotency
  --      replay, so a replay after the shift closed still returns the stored payment
  --      (the lock/precondition is never reached on replay).
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

  -- (i) tender + change. payable = the order grand total (never recomputed). No cash rounding (MVP).
  v_payable := v_grand;
  if p_amount_tendered_minor < v_payable then
    raise exception 'record_payment: amount_tendered_minor (%) is less than the order total (%)', p_amount_tendered_minor, v_payable using errcode = '42501';
  end if;
  v_change := p_amount_tendered_minor - v_payable;

  -- (j) allocate the authoritative per-branch receipt number (D-021) under a ROW LOCK.
  insert into public.branch_receipt_counters as brc
      (organization_id, restaurant_id, branch_id, last_issued_value)
    values (v_org, v_rest, v_branch, 1)
    on conflict (organization_id, restaurant_id, branch_id) do update
      set last_issued_value = brc.last_issued_value + 1
    returning brc.last_issued_value into v_receipt_seq;
  v_receipt_no := v_receipt_seq::text;

  -- (k) insert the completed cash payment, STAMPED with the open shift + active drawer (A2)
  insert into public.payments (
    organization_id, restaurant_id, branch_id, order_id, device_id,
    taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id,
    method, status, amount_minor, tendered_minor, change_minor, currency_code,
    receipt_number, provisional_receipt_number, local_operation_id, revision)
  values (
    v_org, v_rest, v_branch, p_order_id, p_device_id,
    v_emp, v_membership, v_shift_id, v_drawer_id,
    'cash', 'completed', v_payable, p_amount_tendered_minor, v_change, v_currency,
    v_receipt_no, p_provisional_receipt_number, p_local_operation_id, 1)
  returning id into v_payment_id;

  -- (l) set orders.receipt_number (+ keep any client provisional) and bump revision.
  --     DOES NOT change orders.status (D-025; A6 of RF-054).
  v_new_rev := v_o_rev + 1;
  update public.orders
    set receipt_number = v_receipt_no,
        receipt_provisional_id = coalesce(v_o_provisional, p_provisional_receipt_number),
        revision = v_new_rev
    where id = p_order_id;

  -- (m) audit: payment.recorded + receipt_number.assigned (A8/D-013). Replay returns earlier.
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
      'method',                 'cash',
      'status',                 'completed',
      'amount_minor',           v_payable,
      'tendered_minor',         p_amount_tendered_minor,
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

  -- (n) record the idempotency ledger result + return
  v_result := jsonb_build_object(
    'ok', true, 'payment_id', v_payment_id, 'order_id', p_order_id,
    'receipt_number', v_receipt_no, 'change_due_minor', v_change,
    'shift_id', v_shift_id, 'cash_drawer_session_id', v_drawer_id,
    'payment_revision', 1, 'order_revision', v_new_rev);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'record_payment', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) is
  'RF-054/RF-055 (API_CONTRACT §4.7, D-011) SECURITY DEFINER RPC, hardened by RF-062: records a cash payment + assigns the per-branch receipt number (D-021). RF-062 (A1): the order load now uses FOR UPDATE so record_payment and void_order serialize on the same order row (orders -> shifts -> drawer global lock order; no deadlock); NO business-logic change. RF-055 (A2): REQUIRES an open shift + active bound cash drawer for (org, branch, device) and STAMPS payments.shift_id/cash_drawer_session_id. All RF-054 behavior preserved: PIN-session auth (cross-tenant impossible); cashier+ only (kitchen_staff/accountant denied -> payment.denied + permission_denied); cash only; change = tendered - grand_total (>=0); order-bound idempotency (replay returns same payment_id + receipt_number, no dup audit); receipt allocated under row lock; at most one completed payment per order; does NOT advance orders.status; writes payment.recorded + receipt_number.assigned (D-013).';

revoke all on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) from public;
grant execute on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. To undo by hand: re-run the RF-053 app.void_order body
-- (without the FOR UPDATE + completed-payment guard) and the RF-055 app.record_payment
-- body (without the order-row FOR UPDATE) via their CREATE OR REPLACE statements.
-- No tables, columns, policies, or grants are added/removed by this migration.
-- ============================================================================
