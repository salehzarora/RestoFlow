-- ============================================================================
-- MONEY-SETTLEMENT-CONSISTENCY-001 — align discounts, zero-value tender, reports and
-- POS actions with THE ONE canonical settlement rule.
--
-- THE RULE (app.order_is_fully_settled, shipped by ORDER-AUTO-COMPLETION-001 and NOT
-- redefined here — there is exactly ONE definition of "settled" in the system):
--
--     grand_total_minor  < 0  -> FAIL CLOSED (not settled)
--     grand_total_minor  = 0  -> SETTLED. NON-CHARGEABLE: the order owes nothing, so it
--                                settles with NO payment row and none is ever created.
--     grand_total_minor  > 0  -> settled ONLY when a LIVE COMPLETED payment COVERS the
--                                CURRENT total (integer minor units, D-007). D-025 holds.
--     missing / soft-deleted / cross-tenant order -> FAIL CLOSED.
--
-- ORDER-AUTO-COMPLETION-001 made the ORDER LIFECYCLE obey that rule. It did not make the
-- rest of the money surface obey it. This migration closes the four gaps it left open.
--
-- 1. THE DISCOUNT HOLE (the reason the settlement test had to be amount-aware at all).
--    app.apply_discount REPLACES the discount and RECOMPUTES grand_total_minor, guarded
--    ONLY by terminal status. Because app.record_payment deliberately does NOT advance
--    orders.status (D-025), a fully-PAID order is still `submitted`/`served` — NOT
--    terminal — and therefore still discountable. A second, smaller discount raises
--    grand_total_minor back ABOVE the already-frozen payments.amount_minor, silently
--    UN-SETTLING a paid order. The payment row is never falsified; the TARGET moves under
--    it. It also took NO row lock at all, so any guard would have raced record_payment.
--    -> THE FINANCIAL SNAPSHOT NOW FREEZES AT PAYMENT: once an order carries a LIVE
--       COMPLETED payment, ANY discount mutation is refused — including one that would
--       LOWER the total (human decision: the snapshot is frozen, not merely protected
--       from inflation). The order row is locked FOR UPDATE first, matching the global
--       lock order, so a payment can never slip in between the guard and the write.
--
-- 2. ZERO-VALUE TENDER. app.record_payment happily "collected" 0 from a NON-CHARGEABLE
--    (zero-total) order: it minted a 0-amount payments row AND BURNED a per-branch
--    receipt number for money that never moved.
--    -> Refused, BEFORE the shift/drawer locks, BEFORE the receipt allocation and BEFORE
--       the payment insert. A refused zero tender now touches NOTHING.
--
-- 3. REPORT / BOARD CLASSIFICATION. Every paid/unpaid classifier was a MARKER
--    ("a completed payment row exists"), which is wrong in BOTH directions: a zero-total
--    order was reported UNPAID forever (there is no payment row to find), and an
--    UNDER-COVERED order was reported PAID. The board even contradicted the audit log,
--    which already says `not_chargeable`.
--    -> owner_active_orders, owner_order_history, owner_daily_report and
--       owner_report_range now all call app.order_is_fully_settled. The list surfaces
--       additionally report a THIRD honest state, `not_chargeable`, instead of lying with
--       either "paid" (no payment was taken) or "unpaid" (nothing is owed).
--
-- 4. THE DENIAL REASON WAS INVISIBLE. `order.discount_denied` / `order.void_denied` have
--    always carried a `denied_reason`, but it was never on the audit_safe_detail
--    allowlist — so the Activity Log showed THAT a discount was denied and never WHY.
--    -> `denied_reason` is allowlisted (a closed enum of safe state tokens, money-free).
--
-- WHAT THIS MIGRATION DOES NOT DO (deliberately, per the human decisions):
--   * It does NOT change void eligibility. `completed` stays TERMINAL and a completed
--     order — zero-total or not — is NOT voidable. There is no completed -> void path.
--   * It does NOT touch MONETARY ARITHMETIC. Billed money is still summed from the ORDER
--     SNAPSHOT (D-008) and collected money still from payments.status='completed'. A
--     part-payment IS cash in the drawer and MUST stay in collected_minor. Only
--     CLASSIFICATION and COUNTERS move.
--   * No refunds, no split payments, no second completed payment, no fabricated payment.
--
-- Every function below is re-created VERBATIM from its newest shipping definition with
-- only the surgical changes described in its own header. No signature changes, so every
-- public wrapper and every client call site keeps working, and CREATE OR REPLACE
-- preserves the existing ACLs.
--
-- Additive / forward-only. No table, column, CHECK, RLS policy, trigger or index change;
-- no historical order, payment or audit row is rewritten.
-- PENDING: RISK R-003 sign-off. NOT applied to hosted by this migration.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. app.apply_discount — re-created VERBATIM from STAFF-CASHIER-PERMISSIONS-001
--    (20260710110000) with exactly TWO surgical changes:
--      (i)  the order row is now locked FOR UPDATE (it took NO lock before);
--      (ii) a LIVE COMPLETED payment now FREEZES the financial snapshot — any discount
--           mutation is refused, in either direction, audited as order.discount_denied
--           with denied_reason = order_has_completed_payment.
--    The cashier-capability gate, the full-comp manager gate, the integer-minor maths,
--    the clamping, the idempotency ledger and the success audit are UNCHANGED.
-- ---------------------------------------------------------------------------

create or replace function app.apply_discount(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_scope              text,     -- 'order' | 'order_item'
  p_order_item_id      uuid,     -- required when p_scope = 'order_item'
  p_discount_type      text,     -- 'fixed' | 'percentage'
  p_value              bigint,   -- fixed: amount_minor ; percentage: basis points (0..10000)
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
  v_subtotal     bigint;
  v_discount     bigint;
  v_tax          bigint;
  v_qty          integer;
  v_unit         bigint;
  v_mod_sum      bigint;
  v_base         bigint;
  v_disc_amount  bigint;
  v_new_subtotal bigint;
  v_new_grand    bigint;
  v_new_rev      integer;
  v_stored       jsonb;
  v_stored_order uuid;
  v_result       jsonb;
  v_old_line_disc bigint;
  v_new_line_total bigint;
begin
  -- (a) PIN session + backing + actor/scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'apply_discount: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'apply_discount: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'apply_discount: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'apply_discount: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'apply_discount: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load order; it MUST be in the actor's org + branch (no cross-tenant)
  --     MONEY-SETTLEMENT-CONSISTENCY-001: FOR UPDATE. apply_discount previously took NO
  --     row lock, so the completed-payment freeze below would have raced record_payment
  --     (which could commit a payment between the guard's read and the discount's write,
  --     leaving a paid order under-covered). `orders` is the FIRST lock every mutating
  --     path takes (record_payment: orders -> shifts -> drawer -> receipt counter;
  --     void_order: orders; apply_order_status_transition: orders), and apply_discount
  --     takes no other lock — so this adds NO new lock-order edge and cannot deadlock.
  select o.organization_id, o.branch_id, o.status, o.revision,
         o.subtotal_minor, o.discount_total_minor, o.tax_total_minor
    into v_o_org, v_o_branch, v_o_status, v_o_rev, v_subtotal, v_discount, v_tax
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'apply_discount: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'apply_discount: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (A6) — BEFORE the idempotency replay (RF053-B1) so an
  --     unauthorized actor can never replay a prior SUCCESS. A DENIAL is audited
  --     (order.discount_denied) + RETURNED (no raise, so the audit persists) with NO
  --     state change and NO ledger write (the ledger holds only authorized successes;
  --     denials are re-audited as probe attempts, never replayed).
  if not ((v_role in ('manager', 'restaurant_owner', 'org_owner'))
          or app.cashier_capability_allowed(v_role, v_m_perms, 'apply_discount')) then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id,
                         'role', v_role, 'scope', p_scope, 'discount_type', p_discount_type, 'value', p_value));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) input validation (operation shape; independent of mutable post-success state)
  if p_scope not in ('order', 'order_item') then
    raise exception 'apply_discount: invalid scope %', p_scope using errcode = '42501';
  end if;
  if p_discount_type not in ('fixed', 'percentage') then
    raise exception 'apply_discount: invalid discount_type %', p_discount_type using errcode = '42501';
  end if;
  if p_value is null or p_value < 0 then
    raise exception 'apply_discount: value must be a non-negative integer' using errcode = '42501';
  end if;
  if p_discount_type = 'percentage' and p_value > 10000 then
    raise exception 'apply_discount: percentage basis points must be 0..10000' using errcode = '42501';
  end if;
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'apply_discount: a non-empty reason is required' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + input validation,
  --     ORDER-BOUND. Same (org, device, local_operation_id, action) on a DIFFERENT
  --     order is a conflict, not a replay (never leaks the original order's result).
  select oo.result, oo.order_id into v_stored, v_stored_order
    from public.order_operations oo
    where oo.organization_id = v_org and oo.device_id = p_device_id
      and oo.local_operation_id = p_local_operation_id and oo.action = 'apply_discount';
  if found then
    if v_stored_order <> p_order_id then
      raise exception 'apply_discount: idempotency key already used for a different order (%, not %)', v_stored_order, p_order_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) order must be non-terminal; optimistic concurrency
  if v_o_status in ('voided', 'cancelled', 'completed') then
    raise exception 'apply_discount: order status % is terminal; cannot discount', v_o_status using errcode = '42501';
  end if;
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    raise exception 'apply_discount: revision conflict (expected %, got %)', p_expected_revision, v_o_rev using errcode = '40001';
  end if;

  -- (f2) MONEY-SETTLEMENT-CONSISTENCY-001 — THE FINANCIAL SNAPSHOT FREEZES AT PAYMENT.
  --      Once an order carries a LIVE COMPLETED payment, NO discount mutation is allowed,
  --      in EITHER direction. Raising the total obviously breaks settlement (it re-bases
  --      grand_total_minor above the frozen payments.amount_minor and silently un-settles
  --      a paid order). LOWERING it is refused too, by human decision: the customer has
  --      already been charged, so a post-payment price change is a REFUND — and there is
  --      no refund flow in MVP (D-023: a completed payment is TERMINAL). Quietly shrinking
  --      the total would leave the books claiming the guest overpaid, with no money moved
  --      and no reversal recorded. The snapshot is FROZEN, not merely protected.
  --
  --      THE MARKER IS THE RIGHT TEST HERE (not app.order_is_fully_settled): the question
  --      is "has this order been CHARGED yet?", not "does it still owe money?". A
  --      NON-CHARGEABLE zero-total order carries no payment and stays freely discountable
  --      (a comp can still be corrected); an UNDER-COVERED order carries a real payment
  --      and is frozen. This is byte-for-byte the guard app.void_order already uses
  --      (RF-062), so "an order that has been paid" has ONE meaning across the tree.
  --
  --      The order row is locked FOR UPDATE above, and record_payment locks it first too,
  --      so a payment cannot commit between this check and the write below.
  --      RETURNS (never RAISES): a raise would roll back the audit row. NO state change,
  --      NO revision bump, NO order/payment/receipt write, and NO order_operations ledger
  --      entry (the ledger holds only authorized successes; a denial is re-audited as a
  --      probe attempt on every retry, never replayed).
  if exists (
    select 1
    from public.payments p
    where p.organization_id = v_org
      and p.order_id        = p_order_id
      and p.status          = 'completed'
      and p.deleted_at is null
  ) then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'scope', p_scope,
                         'discount_type', p_discount_type, 'value', p_value,
                         'denied_reason', 'order_has_completed_payment'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'detail', 'order_has_completed_payment', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  v_new_rev := v_o_rev + 1;

  if p_scope = 'order' then
    -- order-level: base = current subtotal; clamp discount <= subtotal
    v_base := v_subtotal;
    if p_discount_type = 'percentage' then
      v_disc_amount := round(v_base::numeric * p_value / 10000)::bigint;   -- numeric is exact (not float); half-away-from-zero
    else
      v_disc_amount := p_value;
    end if;
    -- STAFF-CASHIER-PERMISSIONS-001 (MONEY_AND_TAX_SPEC §4.4/§4.5): a FULL COMP
    -- (a discount that reduces a POSITIVE target to zero -- 100% percentage, or a
    -- fixed >= base) requires manager+. A cashier is REJECTED (audited
    -- order.discount_denied + permission_denied, no state change), NEVER silently
    -- clamped into a 100% comp. The gate is the frozen 100%/zero-out threshold
    -- (no configured sub-threshold exists to enforce).
    if v_base > 0 and v_disc_amount >= v_base
       and v_role not in ('manager', 'restaurant_owner', 'org_owner') then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
        jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id, 'role', v_role, 'scope', p_scope,
                           'discount_type', p_discount_type, 'value', p_value, 'denied_reason', 'full_comp_requires_manager'));
      return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                               'server_ts', now(), 'idempotency_replay', false);
    end if;
    if v_disc_amount > v_base then v_disc_amount := v_base; end if;          -- clamp >= 0 (D-007/§4.4)
    v_new_grand := v_subtotal - v_disc_amount + v_tax;
    update public.orders
      set discount_total_minor = v_disc_amount, grand_total_minor = v_new_grand, revision = v_new_rev
      where id = p_order_id;

    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_applied', p_reason,
      jsonb_build_object('scope', 'order', 'revision', v_o_rev, 'discount_total_minor', v_discount, 'grand_total_minor', v_subtotal - v_discount + v_tax),
      jsonb_build_object('scope', 'order', 'discount_type', p_discount_type, 'value', p_value, 'revision', v_new_rev,
                         'discount_total_minor', v_disc_amount, 'grand_total_minor', v_new_grand, 'resolved_membership_id', v_membership));
    v_result := jsonb_build_object('ok', true, 'order_id', p_order_id, 'revision', v_new_rev,
                                   'discount_total_minor', v_disc_amount, 'grand_total_minor', v_new_grand);
  else
    -- item-level: base = qty*unit + sum(modifier price*qty); clamp; recompute order rollup
    select oi.quantity, oi.unit_price_minor_snapshot, oi.line_discount_minor
      into v_qty, v_unit, v_old_line_disc
      from public.order_items oi
      where oi.id = p_order_item_id and oi.order_id = p_order_id and oi.organization_id = v_org
        and oi.status not in ('voided', 'cancelled');
    if not found then
      raise exception 'apply_discount: order_item not found in order (or already voided/cancelled)' using errcode = '42501';
    end if;
    select coalesce(sum(m.price_minor_snapshot * m.quantity), 0) into v_mod_sum
      from public.order_item_modifiers m
      where m.order_item_id = p_order_item_id and m.organization_id = v_org;
    v_base := v_qty * v_unit + v_mod_sum;
    if p_discount_type = 'percentage' then
      v_disc_amount := round(v_base::numeric * p_value / 10000)::bigint;
    else
      v_disc_amount := p_value;
    end if;
    -- STAFF-CASHIER-PERMISSIONS-001 (MONEY_AND_TAX_SPEC §4.4/§4.5): full comp of an
    -- item line (reduce a positive line base to zero) also requires manager+.
    if v_base > 0 and v_disc_amount >= v_base
       and v_role not in ('manager', 'restaurant_owner', 'org_owner') then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
        jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id, 'order_item_id', p_order_item_id, 'role', v_role, 'scope', p_scope,
                           'discount_type', p_discount_type, 'value', p_value, 'denied_reason', 'full_comp_requires_manager'));
      return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                               'server_ts', now(), 'idempotency_replay', false);
    end if;
    if v_disc_amount > v_base then v_disc_amount := v_base; end if;
    v_new_line_total := v_base - v_disc_amount;
    update public.order_items
      set line_discount_minor = v_disc_amount, line_total_minor = v_new_line_total
      where id = p_order_item_id;

    -- re-roll up the order subtotal from non-voided/cancelled line totals
    select coalesce(sum(oi.line_total_minor), 0) into v_new_subtotal
      from public.order_items oi
      where oi.order_id = p_order_id and oi.organization_id = v_org
        and oi.status not in ('voided', 'cancelled');
    v_new_grand := v_new_subtotal - v_discount + v_tax;
    if v_new_grand < 0 then v_new_grand := 0; end if;
    update public.orders
      set subtotal_minor = v_new_subtotal, grand_total_minor = v_new_grand, revision = v_new_rev
      where id = p_order_id;

    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_applied', p_reason,
      jsonb_build_object('scope', 'order_item', 'order_item_id', p_order_item_id, 'revision', v_o_rev,
                         'line_discount_minor', v_old_line_disc, 'subtotal_minor', v_subtotal, 'grand_total_minor', v_subtotal - v_discount + v_tax),
      jsonb_build_object('scope', 'order_item', 'order_item_id', p_order_item_id, 'discount_type', p_discount_type, 'value', p_value, 'revision', v_new_rev,
                         'line_discount_minor', v_disc_amount, 'line_total_minor', v_new_line_total,
                         'subtotal_minor', v_new_subtotal, 'grand_total_minor', v_new_grand, 'resolved_membership_id', v_membership));
    v_result := jsonb_build_object('ok', true, 'order_id', p_order_id, 'revision', v_new_rev,
                                   'order_item_id', p_order_item_id, 'line_discount_minor', v_disc_amount,
                                   'subtotal_minor', v_new_subtotal, 'grand_total_minor', v_new_grand);
  end if;

  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'apply_discount', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;


comment on function app.apply_discount(uuid, uuid, uuid, text, text, uuid, text, bigint, text, integer) is
  'RF-053 + STAFF-CASHIER-PERMISSIONS-001 + MONEY-SETTLEMENT-CONSISTENCY-001 (API_CONTRACT §4.5, D-007/D-011): SECURITY DEFINER RPC applying an order- or item-level discount (fixed amount_minor or percentage basis points), in INTEGER MINOR UNITS only, clamped to the target base and floored at zero. PIN-session auth; manager+ OR a cashier with the apply_discount capability; a FULL COMP (zeroing a positive base) requires manager+. THE FINANCIAL SNAPSHOT FREEZES AT PAYMENT: an order carrying a LIVE COMPLETED payment refuses ANY discount mutation — including one that would LOWER the total, because post-payment price changes are refunds and there is no refund flow (D-023: a completed payment is TERMINAL). Refusal is audited order.discount_denied (denied_reason=order_has_completed_payment) and RETURNED as permission_denied + detail=order_has_completed_payment (never raised — a raise would roll back the audit), with NO order/payment/receipt write, NO revision bump and NO idempotency-ledger entry. The order row is locked FOR UPDATE (orders is the first lock every mutating path takes), so a concurrent record_payment can never slip in between the guard and the write. A NON-CHARGEABLE zero-total order carries no payment and stays discountable (a comp can still be corrected). Terminal orders (voided/cancelled/completed) are rejected as before. Order-bound idempotency (D-022). Writes order.discount_applied (D-013).';


-- ---------------------------------------------------------------------------
-- 2. app.record_payment — re-created VERBATIM from ORDER-AUTO-COMPLETION-001
--    (20260714090000) with exactly ONE surgical change: a NON-CHARGEABLE (zero-total)
--    order is REFUSED before any shift/drawer lock, before the receipt number is
--    allocated and before the payment row is inserted. Everything else — the tender
--    maths, the receipt allocation, the shift/drawer stamping, idempotency, the audits
--    and the ORDER-AUTO-COMPLETION-001 direction-B chain — is UNCHANGED.
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
  if v_grand <= 0 then
    raise exception 'record_payment: order % is not chargeable (grand_total_minor = %) [order_not_chargeable]', p_order_id, v_grand using errcode = '42501';
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
-- 3. app.owner_active_orders — re-created VERBATIM from ACTIVE-ORDERS-002
--    (20260713140000). `is_paid` now means SETTLED (the canonical predicate) rather than
--    "a payment row exists", which fixes the board's unpaid counter, its paid/unpaid
--    filter and its per-row badge in one place; and the badge gains the third honest
--    state `not_chargeable`. The `cash` arm of the filter is a TENDER-METHOD question,
--    not a settlement question, and is left exactly as it was.
-- ---------------------------------------------------------------------------

create or replace function app.owner_active_orders(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_status          text default null,   -- one ACTIVE status (must sit INSIDE p_queue)
  p_order_type      text default null,   -- 'dine_in' | 'takeaway'
  p_payment         text default null,   -- 'paid' | 'unpaid' | 'cash'
  p_search          text default null,   -- order code / customer / table / receipt
  p_limit           int  default 100,
  -- ACTIVE-ORDERS-002 (appended, backward-compatible defaults):
  p_queue           text default 'all_active',  -- in_progress | awaiting_close | all_active
  p_sort            text default 'newest',      -- newest | oldest
  p_cursor          text default null           -- "<sort>|<created_at>|<id>"
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid    := app.current_app_user_id();
  v_rank       integer;
  v_currency   text;
  v_limit      integer := least(greatest(coalesce(p_limit, 100), 1), 200);
  v_search     text    := nullif(btrim(coalesce(p_search, '')), '');
  v_queue      text    := coalesce(nullif(btrim(coalesce(p_queue, '')), ''), 'all_active');
  v_sort       text    := coalesce(nullif(btrim(coalesce(p_sort,  '')), ''), 'newest');
  -- The canonical OPERATIONALLY ACTIVE set (D-018). Terminal states
  -- (completed/cancelled/voided) and the local-only `draft` are excluded.
  v_active     text[]  := array['submitted', 'accepted', 'preparing', 'ready', 'served'];
  -- The QUEUES. These are a PRESENTATION grouping OVER the canonical states —
  -- not a new taxonomy: every member is one of the five canonical active states.
  v_in_prog    text[]  := array['submitted', 'accepted', 'preparing', 'ready'];
  v_awaiting   text[]  := array['served'];
  v_queue_set  text[];
  v_newest     boolean;
  v_cursor_ts  timestamptz;
  v_cursor_id  uuid;
  v_summary    jsonb;
  v_rows       jsonb;
  v_matching   bigint;
  v_fetched    bigint;
  v_more       boolean;
  v_next       text;
begin
  if v_actor is null then
    raise exception 'owner_active_orders: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_active_orders: organization_id is required' using errcode = '42501';
  end if;

  -- ---- ENUM-VALIDATED controls. An unknown token is a BAD REQUEST (22023) —
  --      never a silently-empty board, and NOTHING is interpolated into SQL.
  case v_queue
    when 'in_progress'    then v_queue_set := v_in_prog;
    when 'awaiting_close' then v_queue_set := v_awaiting;
    when 'all_active'     then v_queue_set := v_active;
    else raise exception 'owner_active_orders: unknown queue %', v_queue using errcode = '22023';
  end case;

  if v_sort not in ('newest', 'oldest') then
    raise exception 'owner_active_orders: unknown sort %', v_sort using errcode = '22023';
  end if;
  v_newest := (v_sort = 'newest');

  -- A status filter must be an ACTIVE status AND must sit INSIDE the selected
  -- queue — otherwise the two controls would silently contradict each other.
  if p_status is not null then
    if not (p_status = any (v_active)) then
      raise exception 'owner_active_orders: % is not an active order status', p_status using errcode = '22023';
    end if;
    if not (p_status = any (v_queue_set)) then
      raise exception 'owner_active_orders: status % is not in queue %', p_status, v_queue using errcode = '22023';
    end if;
  end if;

  if p_order_type is not null and p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'owner_active_orders: unknown order_type %', p_order_type using errcode = '22023';
  end if;
  if p_payment is not null and p_payment not in ('paid', 'unpaid', 'cash') then
    raise exception 'owner_active_orders: unknown payment filter %', p_payment using errcode = '22023';
  end if;

  -- ---- The keyset cursor is TAGGED with the sort it was minted under:
  --      "<sort>|<created_at>|<id>". Replaying a cursor under the OTHER direction
  --      would silently skip or duplicate rows, so it is REJECTED outright.
  if p_cursor is not null and btrim(p_cursor) <> '' then
    if split_part(p_cursor, '|', 1) <> v_sort then
      raise exception 'owner_active_orders: cursor was issued for sort % but sort % was requested',
        split_part(p_cursor, '|', 1), v_sort using errcode = '22023';
    end if;
    begin
      v_cursor_ts := split_part(p_cursor, '|', 2)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 3)::uuid;
    exception when others then
      raise exception 'owner_active_orders: invalid cursor' using errcode = '22023';
    end;
  end if;

  -- ---- authority over the PASSED scope (downward-only); 0 => not a member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_active_orders: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free); kitchen_staff DENIED (the board carries totals).
  if not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_active_orders');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_active_orders: organization not found (or deleted)' using errcode = '42501';
  end if;

  with scoped as (
    -- EVERY active order in scope (all five canonical states), regardless of the
    -- selected queue — this is what the SUMMARY counts, so the cards stay stable
    -- while the operator switches queues. Deliberately NO date window: an order
    -- still open across midnight must never vanish from an operations board.
    -- LEFT joins (+ a 'UTC' fallback) so a tz-less or soft-deleted branch can
    -- never silently DROP a live order.
    select o.id,
           o.status,
           o.order_type,
           o.customer_name,
           o.receipt_number,
           o.grand_total_minor,
           o.created_at,
           o.table_id,
           o.opened_by_employee_profile_id,
           coalesce(b.timezone, r.timezone, 'UTC') as zone,
           b.name                                  as branch_name,
           pay.method                              as payment_method,
           pay.amount_minor                        as paid_amount_minor,
           -- MONEY-SETTLEMENT-CONSISTENCY-001: SETTLEMENT, not a marker. `is_paid` now
           -- answers "does this order still owe money?" via THE one canonical predicate,
           -- so a NON-CHARGEABLE zero-total order is settled (it was reported UNPAID
           -- forever before, because there is no payment row to find) and an UNDER-COVERED
           -- order is NOT settled (it was reported PAID before). `payment_method` and
           -- `paid_amount_minor` still come from the payment row: they DISPLAY what was
           -- actually taken, and are legitimately null when nothing was.
           app.order_is_fully_settled(o.organization_id, o.id) as is_paid,
           (o.grand_total_minor > 0)               as is_chargeable
    from public.orders o
    left join public.branches b
      on b.organization_id = o.organization_id
     and b.id              = o.branch_id
     and b.deleted_at is null
    left join public.restaurants r
      on r.organization_id = o.organization_id
     and r.id              = o.restaurant_id
     and r.deleted_at is null
    left join lateral (
      -- the single completed payment for the order (at most one; D-024/D-025).
      select p.method, p.amount_minor
      from public.payments p
      where p.organization_id = o.organization_id
        and p.order_id        = o.id
        and p.deleted_at is null
        and p.status = 'completed'
      order by p.created_at desc, p.id desc
      limit 1
    ) pay on true
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and o.status = any (v_active)
  ),
  matched as (
    -- The QUEUE + the list filters. This is the set `matching` counts and the
    -- page is drawn from.
    select s.*,
           tbl.label                     as table_label,
           ep.display_name               as staff_name,
           coalesce(items.item_count, 0) as item_count
    from scoped s
    left join public.tables tbl
      on tbl.organization_id = p_organization_id
     and tbl.id             = s.table_id
     and tbl.deleted_at is null
    left join public.employee_profiles ep
      on ep.organization_id = p_organization_id
     and ep.id             = s.opened_by_employee_profile_id
    left join lateral (
      select sum(oi.quantity)::bigint as item_count
      from public.order_items oi
      where oi.organization_id = p_organization_id
        and oi.order_id        = s.id
        and oi.deleted_at is null
    ) items on true
    where s.status = any (v_queue_set)
      and (p_status     is null or s.status     = p_status)
      and (p_order_type is null or s.order_type = p_order_type)
      and (
        p_payment is null
        or (p_payment = 'paid'   and s.is_paid)
        or (p_payment = 'unpaid' and not s.is_paid)
        or (p_payment = 'cash'   and s.payment_method = 'cash')
      )
      and (
        v_search is null
        or s.customer_name ilike '%' || v_search || '%'
        or coalesce(s.receipt_number, '') ilike '%' || v_search || '%'
        or coalesce(tbl.label, '') ilike '%' || v_search || '%'
        or upper(right(replace(s.id::text, '-', ''), 6)) like '%' || upper(replace(v_search, '#', '')) || '%'
      )
  ),
  page as (
    -- SERVER-SIDE sort + keyset continuation. `id` breaks ties so equal
    -- timestamps order stably and paginate without duplicates or gaps.
    -- One extra row is fetched to decide has_more without a second count.
    select m.*
    from matched m
    where p_cursor is null
       or v_cursor_ts is null
       or (v_newest and (m.created_at, m.id) < (v_cursor_ts, v_cursor_id))
       or (not v_newest and (m.created_at, m.id) > (v_cursor_ts, v_cursor_id))
    order by
      case when v_newest then m.created_at end desc,
      case when v_newest then m.id         end desc,
      case when not v_newest then m.created_at end asc,
      case when not v_newest then m.id         end asc
    limit v_limit + 1
  ),
  numbered as (
    select p.*,
           row_number() over (
             order by
               case when v_newest then p.created_at end desc,
               case when v_newest then p.id         end desc,
               case when not v_newest then p.created_at end asc,
               case when not v_newest then p.id         end asc
           ) as rn
    from page p
  )
  select
    jsonb_build_object(
      'total',  (select count(*) from scoped),
      'unpaid', (select count(*) from scoped where not is_paid),
      -- The QUEUE counters the cards render — scope-wide, never the page.
      'in_progress',    (select count(*) from scoped where status = any (v_in_prog)),
      'awaiting_close', (select count(*) from scoped where status = any (v_awaiting)),
      'by_status', jsonb_build_object(
        'submitted', (select count(*) from scoped where status = 'submitted'),
        'accepted',  (select count(*) from scoped where status = 'accepted'),
        'preparing', (select count(*) from scoped where status = 'preparing'),
        'ready',     (select count(*) from scoped where status = 'ready'),
        'served',    (select count(*) from scoped where status = 'served'))),
    (select count(*) from matched),
    -- The EXTRA row fetched (limit v_limit + 1) is what decides has_more. It must
    -- NOT be derived from `matching`, which counts the WHOLE filtered set: on the
    -- last page of a paginated read, `matching` still exceeds the page size even
    -- though nothing remains after it.
    (select count(*) from numbered),
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id',          n.id,
               'order_code',        '#' || upper(right(replace(n.id::text, '-', ''), 6)),
               'receipt_number',    n.receipt_number,
               'status',            n.status,
               'order_type',        n.order_type,
               'customer_name',     n.customer_name,
               'table_label',       n.table_label,
               'branch_name',       n.branch_name,
               'staff_name',        n.staff_name,
               -- Branch-local DISPLAY string + the ABSOLUTE instant the client
               -- needs for elapsed time, plus the resolved zone. Storage is UTC.
               'created_at',        to_char(n.created_at at time zone n.zone, 'YYYY-MM-DD HH24:MI'),
               'created_at_utc',    to_char(n.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               'timezone',          n.zone,
               'item_count',        n.item_count,
               'grand_total_minor', n.grand_total_minor,
               'payment_method',    n.payment_method,
               -- THREE honest states. Saying "paid" for an order that was never charged
               -- would be a lie, and "unpaid" would imply money is owed when none is —
               -- the Activity Log already records exactly this as `not_chargeable`.
               'payment_status',    case when not n.is_chargeable then 'not_chargeable'
                                         when n.is_paid           then 'paid'
                                         else                          'unpaid' end,
               'paid_amount_minor', n.paid_amount_minor)
             order by n.rn)
      from numbered n
      where n.rn <= v_limit), '[]'::jsonb),
    -- The continuation, TAGGED with this sort so it can never be replayed under
    -- the other direction.
    (select v_sort || '|' || n.created_at::text || '|' || n.id::text
       from numbered n where n.rn = v_limit)
    into v_summary, v_matching, v_fetched, v_rows, v_next;

  -- More rows exist AFTER this page iff the extra (v_limit + 1)-th row came back.
  v_more := v_fetched > v_limit;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_active_orders',
    'currency_code', v_currency,
    'queue', v_queue,
    'sort', v_sort,
    'limit', v_limit,
    'count', jsonb_array_length(v_rows),
    -- the FULL filtered count — never the loaded page. The client renders the
    -- honest "showing the newest N of M" from it.
    'matching', v_matching,
    'has_more',    v_more,
    'truncated',   v_more,
    'next_cursor', case when v_more then v_next else null end,
    'summary', v_summary,
    'orders', v_rows
  );
end;
$$;

comment on function app.owner_active_orders(uuid, uuid, uuid, text, text, text, text, int, text, text, text) is
  'ACTIVE-ORDERS-001 + ACTIVE-ORDERS-002 (READ-ONLY; D-007/D-008/D-011/D-018/D-020/D-025): the owner/manager Dashboard active-order operations board. Returns orders in the CANONICAL ACTIVE set (submitted/accepted/preparing/ready/served; terminal completed/cancelled/voided and local-only draft excluded) in the caller''s scope, with NO date window. QUEUES (a presentation grouping OVER the canonical states, not a new taxonomy): p_queue = in_progress (submitted/accepted/preparing/ready) | awaiting_close (served) | all_active (default; every existing caller is unchanged). SORT is AUTHORITATIVE and SERVER-SIDE: p_sort = newest (created_at desc, id desc; the Dashboard default) | oldest (asc, asc) — a client can never re-sort a capped page, because the un-fetched rows are not in the payload. KEYSET pagination: p_cursor is TAGGED with its sort ("<sort>|<created_at>|<id>") and is REJECTED (22023) if replayed under the other direction; id breaks ties so equal timestamps paginate stably; has_more/next_cursor page beyond the cap; p_limit CAPPED 1..200. A p_status filter must be an active status AND sit inside p_queue (else 22023). Same authorization as owner_order_history (actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free financial-read allowlist; kitchen_staff -> permission_denied). `summary` (total / unpaid / in_progress / awaiting_close / by_status) covers the SCOPE — never the page and never the filters — so the queue cards stay stable. `matching` is the FULL filtered count, never the loaded page. Money is integer minor units read from the stored snapshot. Payment status is a SEPARATE axis (D-025): a paid order stays active, and an unpaid served order belongs to awaiting_close. Returns created_at (branch-local) + created_at_utc (absolute) + timezone for ELAPSED time; there is NO promised/due field in the schema, so this NEVER reports "late" and ranks by nothing but time. Safe columns only. Scope-safe; no anon/service_role.';

-- ---------------------------------------------------------------------------
-- 4. app.owner_order_history — re-created VERBATIM from ORDERS-HISTORY-001
--    (20260710090000), settlement-based badge + filter, and the `not_chargeable` state.
-- ---------------------------------------------------------------------------

create or replace function app.owner_order_history(
  p_organization_id uuid,
  p_restaurant_id   uuid  default null,
  p_branch_id       uuid  default null,
  p_range           text  default 'today',
  p_search          text  default null,
  p_status          text  default null,
  p_order_type      text  default null,
  p_payment         text  default null,   -- null | 'paid' | 'unpaid' | 'cash'
  p_limit           int   default 25,
  p_cursor          text  default null     -- keyset cursor "<created_at>|<id>"
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid    := app.current_app_user_id();
  v_rank       integer;
  v_currency   text;
  v_span       integer;
  v_end_offset integer;
  v_limit      integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_search     text    := nullif(btrim(coalesce(p_search, '')), '');
  v_cursor_ts  timestamptz;
  v_cursor_id  uuid;
  v_result     jsonb;
begin
  if v_actor is null then
    raise exception 'owner_order_history: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_order_history: organization_id is required' using errcode = '42501';
  end if;

  -- Range -> (span, end_offset). Unknown range is a bad request, not a denial.
  case p_range
    when 'today'     then v_span := 1;  v_end_offset := 0;
    when 'yesterday' then v_span := 1;  v_end_offset := 1;
    when 'last7'     then v_span := 7;  v_end_offset := 0;
    when 'last30'    then v_span := 30; v_end_offset := 0;
    else raise exception 'owner_order_history: unknown range %', p_range using errcode = '22023';
  end case;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_order_history: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE);
  -- kitchen_staff DENIED.
  if not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_order_history');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_order_history: organization not found (or deleted)' using errcode = '42501';
  end if;

  -- Keyset cursor: "<created_at::text>|<id>". A malformed cursor is a bad request.
  if p_cursor is not null and btrim(p_cursor) <> '' then
    begin
      v_cursor_ts := split_part(p_cursor, '|', 1)::timestamptz;
      v_cursor_id := split_part(p_cursor, '|', 2)::uuid;
    exception when others then
      raise exception 'owner_order_history: invalid cursor' using errcode = '22023';
    end;
  end if;

  with branch_tz_base as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant, 'UTC'). UNLIKE the
    -- owner_* REPORTS (which exclude tz-less branches from an aggregate), a
    -- history LIST must never silently DROP an order, so a tz-less branch falls
    -- back to UTC for its day window rather than disappearing. ORG-SCOPED at the
    -- source so an org-wide call's windows are not computed over other tenants'
    -- branches (D-001 / RISK R-003).
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone, 'UTC') as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.organization_id = p_organization_id
      and b.deleted_at is null
  ),
  branch_tz as (
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           (lt.local_today - v_end_offset)                as cur_end,
           (lt.local_today - v_end_offset - (v_span - 1)) as cur_start
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
  ),
  matched as (
    select o.id,
           o.status,
           o.order_type,
           o.customer_name,
           o.receipt_number,
           o.subtotal_minor,
           o.discount_total_minor,
           o.tax_total_minor,
           o.grand_total_minor,
           o.created_at,
           t.zone,
           '#' || upper(right(replace(o.id::text, '-', ''), 6)) as order_code,
           tbl.label                                            as table_label,
           ep.display_name                                      as staff_name,
           coalesce(items.item_count, 0)                        as item_count,
           pay.method                                           as payment_method,
           pay.amount_minor                                     as paid_amount_minor,
           -- MONEY-SETTLEMENT-CONSISTENCY-001: SETTLEMENT, not a marker (see
           -- owner_active_orders). History and the live board must never disagree about
           -- whether the same order owes money.
           app.order_is_fully_settled(o.organization_id, o.id) as is_paid,
           (o.grand_total_minor > 0)                            as is_chargeable
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    left join public.tables tbl
      on tbl.organization_id = o.organization_id
     and tbl.id             = o.table_id
     and tbl.deleted_at is null
    left join public.employee_profiles ep
      on ep.organization_id = o.organization_id
     and ep.id             = o.opened_by_employee_profile_id
    left join lateral (
      select sum(oi.quantity)::bigint as item_count
      from public.order_items oi
      where oi.organization_id = o.organization_id
        and oi.order_id        = o.id
        and oi.deleted_at is null
    ) items on true
    left join lateral (
      -- the single completed payment for the order (at most one; D-024/D-025).
      select p.method, p.amount_minor
      from public.payments p
      where p.organization_id = o.organization_id
        and p.order_id        = o.id
        and p.deleted_at is null
        and p.status = 'completed'
      order by p.created_at desc, p.id desc
      limit 1
    ) pay on true
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and (o.created_at at time zone t.zone)::date between t.cur_start and t.cur_end
      and (p_order_type is null or o.order_type = p_order_type)
      and (p_status     is null or o.status     = p_status)
      and (
        p_payment is null
        -- Settlement, not the marker — the SAME rule the badge renders, so filtering
        -- `unpaid` can never surface an order that owes nothing.
        or (p_payment = 'paid'   and app.order_is_fully_settled(o.organization_id, o.id))
        or (p_payment = 'unpaid' and not app.order_is_fully_settled(o.organization_id, o.id))
        or (p_payment = 'cash'   and pay.method = 'cash')
      )
      and (
        v_search is null
        or o.customer_name ilike '%' || v_search || '%'
        or coalesce(o.receipt_number, '') ilike '%' || v_search || '%'
        or coalesce(tbl.label, '') ilike '%' || v_search || '%'
        or upper(right(replace(o.id::text, '-', ''), 6)) like '%' || upper(replace(v_search, '#', '')) || '%'
      )
      and (
        p_cursor is null
        or v_cursor_ts is null
        or o.created_at < v_cursor_ts
        or (o.created_at = v_cursor_ts and o.id < v_cursor_id)
      )
  ),
  page as (
    select m.*, m.created_at::text || '|' || m.id::text as cursor
    from matched m
    order by m.created_at desc, m.id desc
    limit v_limit + 1
  ),
  numbered as (
    select p.*, row_number() over (order by p.created_at desc, p.id desc) as rn
    from page p
  )
  select jsonb_build_object(
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
               'order_id',             n.id,
               'order_code',           n.order_code,
               'receipt_number',       n.receipt_number,
               'status',               n.status,
               'order_type',           n.order_type,
               'customer_name',        n.customer_name,
               'table_label',          n.table_label,
               'staff_name',           n.staff_name,
               'created_at',           to_char(n.created_at at time zone n.zone, 'YYYY-MM-DD HH24:MI'),
               'item_count',           n.item_count,
               'subtotal_minor',       n.subtotal_minor,
               'discount_total_minor', n.discount_total_minor,
               'tax_total_minor',      n.tax_total_minor,
               'grand_total_minor',    n.grand_total_minor,
               'payment_method',       n.payment_method,
               'payment_status',       case when not n.is_chargeable then 'not_chargeable'
                                             when n.is_paid           then 'paid'
                                             else                          'unpaid' end,
               'paid_amount_minor',    n.paid_amount_minor)
             order by n.rn)
      from numbered n
      where n.rn <= v_limit), '[]'::jsonb),
    'has_more',    (select count(*) from numbered) > v_limit,
    'next_cursor', case when (select count(*) from numbered) > v_limit
                        then (select cursor from numbered where rn = v_limit)
                        else null end,
    'count',       least((select count(*) from numbered), v_limit)
  ) into v_result;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_order_history',
    'currency_code', v_currency,
    'range', p_range,
    'limit', v_limit
  ) || v_result;
end;
$$;

comment on function app.owner_order_history(uuid, uuid, uuid, text, text, text, text, text, int, text) is
  'ORDERS-HISTORY-001 (read-only; D-007/D-008/D-011/D-020): GUC-free paginated order-history LIST for the owner/manager Dashboard. Same authorization as owner_report_range (app.actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free can_read_financials-STYLE allowlist; kitchen_staff -> permission_denied). Branch-local date window (p_range in today/yesterday/last7/last30). Optional filters: p_status, p_order_type, p_payment (paid/unpaid/cash), p_search (order code #hex / customer / table / receipt). Keyset pagination ("<created_at>|<id>", newest first, p_limit clamped 1..100, has_more/next_cursor). Money integer minor, read from stored snapshots (never recomputed). Scope-safe (no GUC trusted); no anon/service_role.';

-- ---------------------------------------------------------------------------
-- 5. app.owner_daily_report — re-created VERBATIM from RF-REPORT-003 (20260706100000).
--    ONLY `unpaid_count` changes: it is now the canonical settlement predicate instead of
--    a day-keyed payment marker. Every MONETARY figure — gross/discount/net (billed, from
--    the order snapshot), collected/cash/tenders (from payments.status='completed'),
--    hourly net, void totals and the RF-055 shift_cash block — is BYTE-FOR-BYTE UNCHANGED.
-- ---------------------------------------------------------------------------

create or replace function app.owner_daily_report(
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
  v_actor    uuid    := app.current_app_user_id();
  v_rank     integer;
  v_currency text;
  v_today    date    := current_date;
  v_prior    date    := current_date - 1;
  v_result   jsonb;
begin
  if v_actor is null then
    raise exception 'owner_daily_report: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_daily_report: organization_id is required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_daily_report: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE): the caller
  -- must hold an ACTIVE membership covering the PASSED scope (downward-only,
  -- mirroring app.actor_rank_in_scope) whose role is a financial-read role —
  -- cashier / manager / restaurant_owner / org_owner / accountant; kitchen_staff
  -- is DENIED.
  if not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_daily_report');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_daily_report: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant); tz-less excluded.
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone) as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.deleted_at is null
  ),
  order_day as (
    select o.id as order_id,
           o.status,
           o.subtotal_minor,
           o.discount_total_minor,
           o.grand_total_minor,
           (o.created_at at time zone t.zone)::date        as business_day,
           -- RF-REPORT-002: branch-local hour (0..23) for the sales-by-hour chart.
           extract(hour from (o.created_at at time zone t.zone))::int as business_hour
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and t.zone is not null
      and (o.created_at at time zone t.zone)::date in (v_today, v_prior)
  ),
  item_rollup as (
    -- per-order pre-discount gross + item-level discount (integer sums).
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
      and oi.order_id in (select od.order_id from order_day od)
    group by oi.order_id
  ),
  payment_day as (
    -- completed payments joined to LIVE non-void/cancel orders, branch-local day.
    select p.id,
           p.method,
           p.amount_minor,
           p.created_at,
           (p.created_at at time zone t.zone)::date as business_day
    from public.payments p
    join branch_tz t
      on t.organization_id = p.organization_id
     and t.branch_id       = p.branch_id
    join public.orders o
      on o.organization_id = p.organization_id
     and o.id              = p.order_id
     and o.deleted_at is null
     and o.status not in ('cancelled', 'voided')  -- defensive belt (RF-062 blocks structurally)
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'
      and t.zone is not null
      and (p.created_at at time zone t.zone)::date in (v_today, v_prior)
  ),
  -- MONEY-SETTLEMENT-CONSISTENCY-001 removed the `paid_orders` CTE. It was a MARKER
  -- ("a completed payment row exists"), and it was DAY-KEYED: it matched the PAYMENT's
  -- branch-local day against the ORDER's branch-local day, so an order billed at 23:50
  -- and paid at 00:10 was counted unpaid forever. Settlement is a property of the ORDER,
  -- not of a calendar day, so unpaid_count now asks the canonical predicate directly.
  sales as (
    -- billed sales = orders NOT voided/cancelled/draft.
    select od.business_day,
           count(*)::bigint                                                                as order_count,
           count(*) filter (where od.status = 'completed')::bigint                         as completed_count,
           -- OUTSTANDING money, the canonical rule. A NON-CHARGEABLE zero-total order owes
           -- nothing and is NOT counted; an UNDER-COVERED order still owes and IS counted.
           count(*) filter (
             where not app.order_is_fully_settled(p_organization_id, od.order_id)
           )::bigint                                                                        as unpaid_count,
           coalesce(sum(ir.gross_minor), 0)::bigint                                         as gross_minor,
           (coalesce(sum(ir.item_discount_minor), 0)
             + coalesce(sum(od.discount_total_minor), 0))::bigint                           as discount_minor,
           coalesce(sum(od.subtotal_minor - od.discount_total_minor), 0)::bigint            as net_minor
    from order_day od
    left join item_rollup ir on ir.order_id = od.order_id
    where od.status not in ('voided', 'cancelled', 'draft')
    group by od.business_day
  ),
  voids as (
    select od.business_day,
           count(*)::bigint                              as void_count,
           coalesce(sum(od.grand_total_minor), 0)::bigint as void_total_minor
    from order_day od
    where od.status = 'voided'
    group by od.business_day
  ),
  collected as (
    select business_day,
           coalesce(sum(amount_minor), 0)::bigint                              as collected_minor,
           coalesce(sum(amount_minor) filter (where method = 'cash'), 0)::bigint as cash_minor
    from payment_day
    group by business_day
  ),
  last_cash as (
    -- the most recent completed cash payment on the day (id desc tiebreak).
    select distinct on (business_day)
           business_day, amount_minor as last_cash_payment_minor
    from payment_day
    where method = 'cash'
    order by business_day, created_at desc, id desc
  ),
  tenders as (
    select business_day,
           jsonb_agg(jsonb_build_object('method', method, 'count', cnt, 'total_minor', total_minor)
                     order by method) as tenders
    from (
      select business_day, method,
             count(*)::bigint                       as cnt,
             coalesce(sum(amount_minor), 0)::bigint as total_minor
      from payment_day
      group by business_day, method
    ) g
    group by business_day
  ),
  hourly_net as (
    -- RF-REPORT-002: TODAY's BILLED net (subtotal - discount) per branch-local
    -- hour, over the SAME billed orders as `sales` (void/cancelled/draft excluded).
    select od.business_hour                                                     as hour,
           coalesce(sum(od.subtotal_minor - od.discount_total_minor), 0)::bigint as net_minor
    from order_day od
    where od.business_day = v_today
      and od.status not in ('voided', 'cancelled', 'draft')
    group by od.business_hour
  ),
  hourly_series as (
    -- 24 zero-filled buckets so the chart axis is stable (honest zeros).
    select h.hour::int                                                                        as hour,
           coalesce((select hn.net_minor from hourly_net hn where hn.hour = h.hour), 0)::bigint as net_minor
    from generate_series(0, 23) as h(hour)
  ),
  closed_shifts_today as (
    -- RF-REPORT-003: CLOSED (or reconciled) shifts whose BRANCH-LOCAL closed_at
    -- day is TODAY (tz-less branches excluded, same as the sales figures). Reads
    -- the RF-055-persisted expected/counted/variance (integer minor). A shift
    -- that spanned midnight is attributed to its CLOSE day (cash-count day).
    select s.id                    as shift_id,
           s.branch_id,
           b.name                  as branch_name,
           ep.display_name         as closed_by_name,
           -- BRANCH-LOCAL display strings (consistent with the closed_at bucketing;
           -- never leak a raw UTC ISO whose calendar date contradicts the bucket).
           to_char((s.opened_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as opened_at,
           to_char((s.closed_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as closed_at,
           s.expected_total_minor,
           s.counted_total_minor,
           s.variance_minor
    from public.shifts s
    join branch_tz t
      on t.organization_id = s.organization_id
     and t.branch_id       = s.branch_id
    join public.branches b
      on b.organization_id = s.organization_id
     and b.id              = s.branch_id
    left join public.employee_profiles ep
      on ep.organization_id = s.organization_id
     and ep.id             = s.closed_by_employee_profile_id
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('closed', 'reconciled')
      and s.closed_at is not null
      and t.zone is not null
      and (s.closed_at at time zone t.zone)::date = v_today
  ),
  open_shifts as (
    -- OPEN shifts NOW in scope (point-in-time count; NOT day/tz bucketed).
    select count(*)::bigint as cnt
    from public.shifts s
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('opening', 'open', 'closing')
  )
  select jsonb_build_object(
    'today', jsonb_build_object(
      'order_count',             coalesce((select s.order_count     from sales s     where s.business_day = v_today), 0),
      'completed_count',         coalesce((select s.completed_count from sales s     where s.business_day = v_today), 0),
      'open_count',              coalesce((select s.order_count - s.completed_count from sales s where s.business_day = v_today), 0),
      'unpaid_count',            coalesce((select s.unpaid_count    from sales s     where s.business_day = v_today), 0),
      'gross_minor',             coalesce((select s.gross_minor     from sales s     where s.business_day = v_today), 0),
      'discount_minor',          coalesce((select s.discount_minor  from sales s     where s.business_day = v_today), 0),
      'net_minor',               coalesce((select s.net_minor       from sales s     where s.business_day = v_today), 0),
      'void_count',              coalesce((select v.void_count      from voids v     where v.business_day = v_today), 0),
      'void_total_minor',        coalesce((select v.void_total_minor from voids v    where v.business_day = v_today), 0),
      'collected_minor',         coalesce((select c.collected_minor from collected c where c.business_day = v_today), 0),
      'cash_minor',              coalesce((select c.cash_minor      from collected c where c.business_day = v_today), 0),
      'last_cash_payment_minor', coalesce((select l.last_cash_payment_minor from last_cash l where l.business_day = v_today), 0),
      'tenders',                 coalesce((select t.tenders         from tenders t   where t.business_day = v_today), '[]'::jsonb)),
    'prior_day', jsonb_build_object(
      'order_count',  coalesce((select s.order_count from sales s     where s.business_day = v_prior), 0),
      'gross_minor',  coalesce((select s.gross_minor from sales s     where s.business_day = v_prior), 0),
      'net_minor',    coalesce((select s.net_minor   from sales s     where s.business_day = v_prior), 0),
      'cash_minor',   coalesce((select c.cash_minor  from collected c where c.business_day = v_prior), 0)),
    -- RF-REPORT-002: TODAY's 24 sales-by-hour buckets (billed net, integer minor).
    'hourly', coalesce(
      (select jsonb_agg(jsonb_build_object('hour', hs.hour, 'net_minor', hs.net_minor) order by hs.hour)
       from hourly_series hs),
      '[]'::jsonb),
    -- RF-REPORT-003: TODAY's shift / cash reconciliation (stored RF-055 values).
    'shift_cash', jsonb_build_object(
      'closed_shift_count',  coalesce((select count(*)::int from closed_shifts_today), 0),
      'open_shift_count',    coalesce((select cnt::int from open_shifts), 0),
      'expected_cash_minor', coalesce((select sum(expected_total_minor)::bigint from closed_shifts_today), 0),
      'counted_cash_minor',  coalesce((select sum(counted_total_minor)::bigint  from closed_shifts_today), 0),
      'cash_variance_minor', coalesce((select sum(variance_minor)::bigint       from closed_shifts_today), 0),
      'last_closed_shift', (
        select jsonb_build_object(
                 'shift_id',            cs.shift_id,
                 'branch_id',           cs.branch_id,
                 'branch_name',         cs.branch_name,
                 'opened_at',           cs.opened_at,
                 'closed_at',           cs.closed_at,
                 'closed_by_name',      cs.closed_by_name,
                 'expected_cash_minor', cs.expected_total_minor,
                 'counted_cash_minor',  cs.counted_total_minor,
                 'cash_variance_minor', cs.variance_minor)
        from closed_shifts_today cs
        order by cs.closed_at desc, cs.shift_id desc
        limit 1),
      'recent_closed_shifts', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'shift_id',            r.shift_id,
                 'branch_id',           r.branch_id,
                 'branch_name',         r.branch_name,
                 'closed_at',           r.closed_at,
                 'closed_by_name',      r.closed_by_name,
                 'expected_cash_minor', r.expected_total_minor,
                 'counted_cash_minor',  r.counted_total_minor,
                 'cash_variance_minor', r.variance_minor)
               order by r.closed_at desc, r.shift_id desc)
        from (select * from closed_shifts_today order by closed_at desc, shift_id desc limit 5) r),
        '[]'::jsonb))
  ) into v_result;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_daily_report',
    'currency_code', v_currency,
    'business_date', v_today
  ) || v_result;
end;
$$;

comment on function app.owner_daily_report(uuid, uuid, uuid) is
  'RF-REPORT-003 (extends RF-REPORT-001/002; D-007/D-011/D-020/D-028): GUC-free real owner daily report for the Dashboard Overview. Same authorization (app.actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free can_read_financials-STYLE allowlist cashier/manager/restaurant_owner/org_owner/accountant; kitchen_staff -> permission_denied). today + prior_day (billed vs collected split) + hourly (24 branch-local buckets, billed net) + shift_cash. shift_cash = TODAY''s CLOSED shifts (status closed/reconciled, bucketed by branch-local closed_at day; tz-less excluded) surfacing the RF-055-STORED expected_total_minor (opening float + completed CASH payments; card NOT included), counted_total_minor (operator count), variance_minor (counted - expected, signed); plus a live open_shift_count and last/recent (cap 5, newest first) closes with branch/closed_by names. Reads stored columns (never recomputes cash). All money integer minor (bigint; SUM cast, never float). LIVE deleted_at IS NULL filters (D-020). Read-only; scope-safe (no GUC trusted); no anon/service_role (D-011).';

-- ---------------------------------------------------------------------------
-- 6. app.owner_report_range — re-created VERBATIM from RF-REPORT-004 (20260706110000).
--    ONLY `unpaid_cur` changes. Sales, voids, collected, tenders, hourly net,
--    closed_shifts and shift_sales are BYTE-FOR-BYTE UNCHANGED. In particular
--    shift_sales.order_count stays PAYMENT-rooted: it counts orders that TOUCHED the
--    drawer during that shift, which a part-paid order genuinely did.
-- ---------------------------------------------------------------------------

create or replace function app.owner_report_range(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null,
  p_range           text default 'today'
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid    := app.current_app_user_id();
  v_rank       integer;
  v_currency   text;
  v_span       integer;  -- number of days in the window (1 / 7 / 30)
  v_end_offset integer;  -- days back from a branch's local_today to cur_end
  v_result     jsonb;
begin
  if v_actor is null then
    raise exception 'owner_report_range: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_report_range: organization_id is required' using errcode = '42501';
  end if;

  -- Range -> (span, end_offset). Unknown range is a bad request, not a denial.
  case p_range
    when 'today'     then v_span := 1;  v_end_offset := 0;
    when 'yesterday' then v_span := 1;  v_end_offset := 1;
    when 'last7'     then v_span := 7;  v_end_offset := 0;
    when 'last30'    then v_span := 30; v_end_offset := 0;
    else raise exception 'owner_report_range: unknown range %', p_range using errcode = '22023';
  end case;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_report_range: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE): an ACTIVE
  -- membership covering the PASSED scope (downward-only) whose role is a financial-
  -- read role — cashier / manager / restaurant_owner / org_owner / accountant;
  -- kitchen_staff is DENIED.
  if not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_report_range');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_report_range: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz_base as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant); tz-less excluded.
    -- ORG-SCOPED at the source (SECURITY DEFINER bypasses RLS): the `win` CTE
    -- reads branch_tz DIRECTLY (not via an org-filtered fact join), so without
    -- this filter an org-wide call's range_start/range_end would be computed over
    -- OTHER tenants' branches (D-001 / RISK R-003). All other consumers already
    -- re-scope via their fact tables; this keeps branch_tz itself single-tenant.
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone) as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.organization_id = p_organization_id
      and b.deleted_at is null
      and coalesce(b.timezone, r.timezone) is not null
  ),
  branch_tz as (
    -- per-branch local today + the current/prior window bounds (branch-local).
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           lt.local_today,
           (lt.local_today - v_end_offset)                        as cur_end,
           (lt.local_today - v_end_offset - (v_span - 1))         as cur_start,
           (lt.local_today - v_end_offset - v_span)               as prev_end,
           (lt.local_today - v_end_offset - v_span - (v_span - 1)) as prev_start
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
  ),
  order_win as (
    -- orders in scope, branch-local day + hour, tagged current ('cur') / prior.
    select o.id as order_id,
           o.status,
           o.subtotal_minor,
           o.discount_total_minor,
           o.grand_total_minor,
           (o.created_at at time zone t.zone)::date        as business_day,
           extract(hour from (o.created_at at time zone t.zone))::int as business_hour,
           case
             when (o.created_at at time zone t.zone)::date between t.cur_start  and t.cur_end  then 'cur'
             when (o.created_at at time zone t.zone)::date between t.prev_start and t.prev_end then 'prev'
           end as bucket
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and (o.created_at at time zone t.zone)::date between t.prev_start and t.cur_end
  ),
  item_rollup as (
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
      and oi.order_id in (select ow.order_id from order_win ow)
    group by oi.order_id
  ),
  payment_win as (
    -- completed payments joined to LIVE non-void/cancel orders, tagged cur/prev.
    select p.id,
           p.method,
           p.amount_minor,
           p.created_at,
           case
             when (p.created_at at time zone t.zone)::date between t.cur_start  and t.cur_end  then 'cur'
             when (p.created_at at time zone t.zone)::date between t.prev_start and t.prev_end then 'prev'
           end as bucket
    from public.payments p
    join branch_tz t
      on t.organization_id = p.organization_id
     and t.branch_id       = p.branch_id
    join public.orders o
      on o.organization_id = p.organization_id
     and o.id              = p.order_id
     and o.deleted_at is null
     and o.status not in ('cancelled', 'voided')
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'
      and (p.created_at at time zone t.zone)::date between t.prev_start and t.cur_end
  ),
  -- MONEY-SETTLEMENT-CONSISTENCY-001 removed the `paid_orders_cur` CTE: a MARKER, and
  -- WINDOW-BOUND (the payment had to land inside the selected range, so an order billed
  -- at a window edge but paid just outside it was reported unpaid). Settlement is a
  -- property of the ORDER, not of the window.
  sales as (
    -- billed sales per bucket = orders NOT voided/cancelled/draft.
    select ow.bucket,
           count(*)::bigint                                                        as order_count,
           count(*) filter (where ow.status = 'completed')::bigint                 as completed_count,
           coalesce(sum(ir.gross_minor), 0)::bigint                                as gross_minor,
           (coalesce(sum(ir.item_discount_minor), 0)
             + coalesce(sum(ow.discount_total_minor), 0))::bigint                  as discount_minor,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint   as net_minor
    from order_win ow
    left join item_rollup ir on ir.order_id = ow.order_id
    where ow.bucket is not null
      and ow.status not in ('voided', 'cancelled', 'draft')
    group by ow.bucket
  ),
  unpaid_cur as (
    -- Current-window billed orders that still OWE MONEY, by the canonical rule: a
    -- NON-CHARGEABLE zero-total order owes nothing and is not counted; an UNDER-COVERED
    -- order still owes and is counted.
    select count(*)::bigint as unpaid_count
    from order_win ow
    where ow.bucket = 'cur'
      and ow.status not in ('voided', 'cancelled', 'draft')
      and not app.order_is_fully_settled(p_organization_id, ow.order_id)
  ),
  voids_cur as (
    select count(*)::bigint                               as void_count,
           coalesce(sum(ow.grand_total_minor), 0)::bigint as void_total_minor
    from order_win ow
    where ow.bucket = 'cur' and ow.status = 'voided'
  ),
  collected as (
    select bucket,
           coalesce(sum(amount_minor), 0)::bigint                                as collected_minor,
           coalesce(sum(amount_minor) filter (where method = 'cash'), 0)::bigint as cash_minor
    from payment_win
    where bucket is not null
    group by bucket
  ),
  last_cash as (
    select amount_minor as last_cash_payment_minor
    from payment_win
    where bucket = 'cur' and method = 'cash'
    order by created_at desc, id desc
    limit 1
  ),
  tenders_cur as (
    select jsonb_agg(jsonb_build_object('method', method, 'count', cnt, 'total_minor', total_minor)
                     order by method) as tenders
    from (
      select method,
             count(*)::bigint                       as cnt,
             coalesce(sum(amount_minor), 0)::bigint as total_minor
      from payment_win
      where bucket = 'cur'
      group by method
    ) g
  ),
  hourly_net as (
    -- single-day ranges only: TODAY/YESTERDAY billed net per branch-local hour.
    select ow.business_hour                                                     as hour,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint as net_minor
    from order_win ow
    where v_span = 1
      and ow.bucket = 'cur'
      and ow.status not in ('voided', 'cancelled', 'draft')
    group by ow.business_hour
  ),
  hourly_series as (
    -- 24 zero-filled buckets for single-day ranges; EMPTY for multi-day.
    select h.hour::int                                                                        as hour,
           coalesce((select hn.net_minor from hourly_net hn where hn.hour = h.hour), 0)::bigint as net_minor
    from generate_series(0, 23) as h(hour)
    where v_span = 1
  ),
  closed_shifts_cur as (
    -- CLOSED/reconciled shifts whose branch-local closed_at day is IN the current
    -- window (tz-less excluded). Reads RF-055 stored expected/counted/variance;
    -- adds opening float (cash_drawer_sessions), opened_by, and duration.
    select s.id                    as shift_id,
           s.branch_id,
           b.name                  as branch_name,
           epc.display_name        as closed_by_name,
           epo.display_name        as opened_by_name,
           coalesce(cds.opening_float_minor, 0)::bigint as opening_float_minor,
           to_char((s.opened_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as opened_at,
           to_char((s.closed_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as closed_at,
           (extract(epoch from (s.closed_at - s.opened_at))::bigint / 60)::int as duration_minutes,
           s.expected_total_minor,
           s.counted_total_minor,
           s.variance_minor
    from public.shifts s
    join branch_tz t
      on t.organization_id = s.organization_id
     and t.branch_id       = s.branch_id
    join public.branches b
      on b.organization_id = s.organization_id
     and b.id              = s.branch_id
    left join public.employee_profiles epc
      on epc.organization_id = s.organization_id
     and epc.id             = s.closed_by_employee_profile_id
    left join public.employee_profiles epo
      on epo.organization_id = s.organization_id
     and epo.id             = s.opened_by_employee_profile_id
    left join public.cash_drawer_sessions cds
      on cds.organization_id = s.organization_id
     and cds.shift_id        = s.id
     and cds.deleted_at is null
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('closed', 'reconciled')
      and s.closed_at is not null
      and (s.closed_at at time zone t.zone)::date between t.cur_start and t.cur_end
  ),
  shift_sales as (
    -- per-shift paid-order metrics from FK-enforced, server-stamped payments.shift_id
    -- (RF-055/RF-117). Reliable: count(distinct order) / collected / cash.
    select p.shift_id,
           count(distinct p.order_id)::bigint                                     as order_count,
           coalesce(sum(p.amount_minor), 0)::bigint                               as collected_minor,
           coalesce(sum(p.amount_minor) filter (where p.method = 'cash'), 0)::bigint as cash_sales_minor
    from public.payments p
    where p.organization_id = p_organization_id
      and p.deleted_at is null
      and p.status = 'completed'
      and p.shift_id in (select shift_id from closed_shifts_cur)
    group by p.shift_id
  ),
  shift_rows as (
    -- closed shifts enriched with per-shift sales, newest first, capped at 8.
    select cs.*,
           coalesce(ss.order_count, 0)::bigint      as order_count,
           coalesce(ss.collected_minor, 0)::bigint  as collected_minor,
           coalesce(ss.cash_sales_minor, 0)::bigint as cash_sales_minor
    from closed_shifts_cur cs
    left join shift_sales ss on ss.shift_id = cs.shift_id
    order by cs.closed_at desc, cs.shift_id desc
    limit 8
  ),
  open_shifts as (
    -- OPEN shifts NOW in scope (point-in-time count; NOT day/tz bucketed).
    select count(*)::bigint as cnt
    from public.shifts s
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('opening', 'open', 'closing')
  ),
  win as (
    -- representative display window over the SCOPED branches (exact for single-tz).
    select min(cur_start) as range_start, max(cur_end) as range_end
    from branch_tz
    where (p_restaurant_id is null or restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or branch_id     = p_branch_id)
  )
  select jsonb_build_object(
    'current', jsonb_build_object(
      'order_count',             coalesce((select order_count     from sales where bucket = 'cur'), 0),
      'completed_count',         coalesce((select completed_count from sales where bucket = 'cur'), 0),
      'open_count',              coalesce((select order_count - completed_count from sales where bucket = 'cur'), 0),
      'unpaid_count',            coalesce((select unpaid_count    from unpaid_cur), 0),
      'gross_minor',             coalesce((select gross_minor     from sales where bucket = 'cur'), 0),
      'discount_minor',          coalesce((select discount_minor  from sales where bucket = 'cur'), 0),
      'net_minor',               coalesce((select net_minor       from sales where bucket = 'cur'), 0),
      'void_count',              coalesce((select void_count      from voids_cur), 0),
      'void_total_minor',        coalesce((select void_total_minor from voids_cur), 0),
      'collected_minor',         coalesce((select collected_minor from collected where bucket = 'cur'), 0),
      'cash_minor',              coalesce((select cash_minor      from collected where bucket = 'cur'), 0),
      'last_cash_payment_minor', coalesce((select last_cash_payment_minor from last_cash), 0),
      'tenders',                 coalesce((select tenders         from tenders_cur), '[]'::jsonb)),
    'comparison', jsonb_build_object(
      'order_count',     coalesce((select order_count     from sales     where bucket = 'prev'), 0),
      'gross_minor',     coalesce((select gross_minor     from sales     where bucket = 'prev'), 0),
      'net_minor',       coalesce((select net_minor       from sales     where bucket = 'prev'), 0),
      'cash_minor',      coalesce((select cash_minor      from collected where bucket = 'prev'), 0),
      'collected_minor', coalesce((select collected_minor from collected where bucket = 'prev'), 0)),
    'hourly', coalesce(
      (select jsonb_agg(jsonb_build_object('hour', hs.hour, 'net_minor', hs.net_minor) order by hs.hour)
       from hourly_series hs),
      '[]'::jsonb),
    'shift_cash', jsonb_build_object(
      'closed_shift_count',  coalesce((select count(*)::int from closed_shifts_cur), 0),
      'open_shift_count',    coalesce((select cnt::int from open_shifts), 0),
      'expected_cash_minor', coalesce((select sum(expected_total_minor)::bigint from closed_shifts_cur), 0),
      'counted_cash_minor',  coalesce((select sum(counted_total_minor)::bigint  from closed_shifts_cur), 0),
      'cash_variance_minor', coalesce((select sum(variance_minor)::bigint       from closed_shifts_cur), 0),
      'last_closed_shift', (
        select jsonb_build_object(
                 'shift_id',            r.shift_id,
                 'branch_id',           r.branch_id,
                 'branch_name',         r.branch_name,
                 'opened_at',           r.opened_at,
                 'closed_at',           r.closed_at,
                 'opened_by_name',      r.opened_by_name,
                 'closed_by_name',      r.closed_by_name,
                 'opening_float_minor', r.opening_float_minor,
                 'duration_minutes',    r.duration_minutes,
                 'order_count',         r.order_count,
                 'collected_minor',     r.collected_minor,
                 'cash_sales_minor',    r.cash_sales_minor,
                 'expected_cash_minor', r.expected_total_minor,
                 'counted_cash_minor',  r.counted_total_minor,
                 'cash_variance_minor', r.variance_minor)
        from shift_rows r
        order by r.closed_at desc, r.shift_id desc
        limit 1),
      'recent_closed_shifts', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'shift_id',            r.shift_id,
                 'branch_id',           r.branch_id,
                 'branch_name',         r.branch_name,
                 'opened_at',           r.opened_at,
                 'closed_at',           r.closed_at,
                 'opened_by_name',      r.opened_by_name,
                 'closed_by_name',      r.closed_by_name,
                 'opening_float_minor', r.opening_float_minor,
                 'duration_minutes',    r.duration_minutes,
                 'order_count',         r.order_count,
                 'collected_minor',     r.collected_minor,
                 'cash_sales_minor',    r.cash_sales_minor,
                 'expected_cash_minor', r.expected_total_minor,
                 'counted_cash_minor',  r.counted_total_minor,
                 'cash_variance_minor', r.variance_minor)
               order by r.closed_at desc, r.shift_id desc)
        from shift_rows r),
        '[]'::jsonb))
  ) || jsonb_build_object(
    'range_start', (select to_char(range_start, 'YYYY-MM-DD') from win),
    'range_end',   (select to_char(range_end,   'YYYY-MM-DD') from win)
  ) into v_result;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_report_range',
    'currency_code', v_currency,
    'range', p_range
  ) || v_result;
end;
$$;

comment on function app.owner_report_range(uuid, uuid, uuid, text) is
  'RF-REPORT-004 (additive to RF-REPORT-001/002/003; D-007/D-011/D-020/D-028): GUC-free range owner report for the Dashboard Overview. Same authorization as owner_daily_report (app.actor_rank_in_scope over the PASSED scope, 0 -> 42501; GUC-free can_read_financials-STYLE allowlist cashier/manager/restaurant_owner/org_owner/accountant; kitchen_staff -> permission_denied). p_range in today/yesterday/last7/last30. Current + prior equal-length window are computed PER BRANCH in the branch-local zone (RF-075) from (now() at time zone COALESCE(branch,restaurant))::date, fixing the UTC "today" drift and handling multi-timezone orgs. Returns current + comparison (billed/collected), hourly (24 branch-local buckets, single-day ranges only; empty for multi-day), and a DEEPER shift_cash (closed shifts in window: RF-055 stored expected/counted/variance + opening float, opened_by, duration, and FK-stamped per-shift order_count/collected/cash from payments.shift_id). Reads stored cash (never recomputes). All money integer minor (bigint; SUM cast, never float). LIVE deleted_at IS NULL filters (D-020). Read-only; scope-safe (no GUC trusted); no anon/service_role (D-011).';

-- ---------------------------------------------------------------------------
-- 7. app.audit_safe_detail — the ONLY change is that `denied_reason` joins the ALLOWLIST,
--    so the owner can finally see WHY a discount or a void was refused. Still an
--    allowlist (not a denylist): every un-listed key is dropped.
-- ---------------------------------------------------------------------------

create or replace function app.audit_safe_detail(p_action text, p_values jsonb)
  returns jsonb
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_out  jsonb := '{}'::jsonb;
  v_caps jsonb;
  v_key  text;
begin
  -- Unknown / unsupported action -> no payload details.
  if not app.audit_action_has_detail(p_action) then
    return '{}'::jsonb;
  end if;
  -- Malformed / missing / non-object payload -> empty safe detail (never throws).
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    return '{}'::jsonb;
  end if;

  -- Canonical SAFE SCALAR allowlist. A key is emitted ONLY when it is on this
  -- list AND its value is a scalar (string/number/boolean) — nested objects,
  -- arrays, and every un-listed key (secret OR merely unknown) are dropped.
  foreach v_key in array array[
    'status','order_status','scope','discount_type','value','attempted_action','order_type',
    'role','from_role','to_role','target_role',
    'discount_total_minor','grand_total_minor','subtotal_minor','line_total_minor','line_discount_minor',
    'amount_minor','tendered_minor','change_minor','opening_float_minor',
    'expected_cash_minor','counted_cash_minor','cash_variance_minor','variance_minor',
    'voided_item_count','failed_attempt_count','locked',
    'timezone','name','receipt_prefix',
    'order_code','payment_status',
    -- ORDER-AUTO-COMPLETION-001: how, and why, an order was completed. Both are
    -- STATES ('automatic'/'manual', 'order_served'/'payment_recorded'), not money
    -- and not identifiers — T-003 still holds.
    'completion_mode','completion_trigger',
    -- MONEY-SETTLEMENT-CONSISTENCY-001: WHY a mutation was denied. order.discount_denied
    -- and order.void_denied have always carried this, but it was never allowlisted — so
    -- the Activity Log showed THAT a discount was refused and never WHY. It is a closed
    -- enum of safe STATE tokens (order_has_completed_payment | full_comp_requires_manager),
    -- never money and never an identifier (T-003 holds).
    'denied_reason'
  ] loop
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;

  -- The ONLY allowlisted nested object: `capabilities`, kept to its three
  -- canonical boolean capability keys (unknown nested keys dropped).
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift']) as k
      where (p_values -> 'capabilities') ? k
        and jsonb_typeof(p_values -> 'capabilities' -> k) in ('string','number','boolean');
    if v_caps is distinct from '{}'::jsonb then
      v_out := v_out || jsonb_build_object('capabilities', v_caps);
    end if;
  end if;

  return v_out;
end;
$$;


comment on function app.audit_safe_detail(text, jsonb) is
  'AUDIT-LOG-DASHBOARD-001 + AUDIT-COVERAGE-002 + ORDER-COMPLETION-001 + ORDER-AUTO-COMPLETION-001 + MONEY-SETTLEMENT-CONSISTENCY-001: ALLOWLIST projection of ONE audit payload (old or new) to canonical safe fields. Gated by app.audit_action_has_detail (unsupported action -> ''{}''). Emits only allowlisted scalar keys (status/scope/discount_type/value/attempted_action/order_type/roles/*_minor money/voided_item_count/failed_attempt_count/locked/timezone/name/receipt_prefix/order_code/payment_status/completion_mode/completion_trigger + denied_reason) plus the nested `capabilities` object. denied_reason (order_has_completed_payment | full_comp_requires_manager) is a STATE explaining WHY a mutation was refused — not money, not an identifier (T-003 holds). Every un-listed key (secret OR unknown) and every other nested structure is DROPPED. Malformed/non-object -> ''{}''; never throws. This is the server-side privacy boundary; the RPC returns NO raw payload JSON.';

-- ---------------------------------------------------------------------------
-- ACL — unchanged. Every function above was re-created with CREATE OR REPLACE and an
-- IDENTICAL signature, so PostgreSQL PRESERVES the existing grants: the internal helpers
-- (app.order_is_fully_settled, app.try_auto_complete_order, app.apply_order_status_transition)
-- remain revoked from public/anon/authenticated, app.apply_discount and app.record_payment
-- remain dispatcher-reachable only (no public wrapper), and the owner_* read RPCs keep
-- their `authenticated`-only grants through their existing public SECURITY INVOKER
-- wrappers. This migration adds NO grant and creates NO new function. pgTAP asserts it.
-- ---------------------------------------------------------------------------

-- ROLLBACK (manual; forward-only migrations are never auto-reverted):
--   Re-apply the previous shipping definitions, in this order:
--     app.apply_discount      <- 20260710110000_staff_cashier_permissions_001_default_capabilities.sql
--     app.record_payment      <- 20260714090000_order_auto_completion_001_served_paid.sql
--     app.owner_active_orders <- 20260713140000_active_orders_002_queues_and_sort.sql
--     app.owner_order_history <- 20260710090000_orders_history_001_owner_order_history.sql
--     app.owner_daily_report  <- 20260706100000_rf_report_003_owner_daily_report_shift_cash.sql
--     app.owner_report_range  <- 20260706110000_rf_report_004_owner_report_range.sql
--     app.audit_safe_detail   <- 20260714090000_order_auto_completion_001_served_paid.sql
--   NO DATA IS MIGRATED by this file, so a rollback loses nothing: it only restores the
--   marker-based classification and re-opens the discount/zero-tender holes. Any audit
--   rows already written with denied_reason simply stop being projected to the Dashboard.
