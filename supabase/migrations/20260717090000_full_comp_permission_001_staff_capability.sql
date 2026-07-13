-- ============================================================================
-- FULL-COMP-PERMISSION-001 -- a SEPARATE staff permission for making an order FREE
-- ============================================================================
-- Product change (human-approved): "apply a discount" and "make the order free"
-- become TWO capabilities, not one.
--
--   apply_discount   -- ordinary discounts.   Cashier default: ON  (deny-only)
--   apply_full_comp  -- make the order FREE.  Cashier default: OFF (grant-only)
--
-- WHAT A FULL COMP IS. Any successful discount mutation whose RESULTING
-- AUTHORITATIVE grand_total_minor is EXACTLY 0. The server computes the prospective
-- total from its OWN price snapshots and tests THAT. It is NOT inferred from a UI
-- "100%" preset, from p_discount_type, or from any client-supplied flag -- so a
-- `fixed` discount that happens to cover the whole order is caught identically to a
-- 10000-basis-point `percentage` one.
--
-- WHY A SECOND RESOLVER (the crux of this migration).
-- app.cashier_capability_allowed is structurally DENY-ONLY: its terminal predicate
-- is `not (permissions ? key)`, so ABSENCE GRANTS. It cannot express a default-OFF
-- capability in EITHER direction:
--   * adding 'apply_full_comp' to its hardcoded key list would hand the new right to
--     EVERY existing cashier at once (they all carry permissions '{}') -- the exact
--     inverse of the product decision; and
--   * storing an explicit {"apply_full_comp":"true"} would read there as a DENY,
--     because a PRESENT key always denies.
-- So this migration adds a COMPLEMENTARY, GRANT-ONLY resolver with the opposite
-- polarity (app.cashier_capability_granted): PRESENCE of the canonical JSON string
-- "true" grants; absence -- the state of every cashier alive today -- DENIES. The
-- deny-only resolver is left completely untouched and keeps owning its three keys.
-- No backfill, no data migration, and no cashier silently gains the right to give
-- food away.
--
-- FULL COMP NEVER BYPASSES THE ORDINARY DISCOUNT PERMISSION. The apply_discount gate
-- runs FIRST inside app.apply_discount and refuses on its own, so a cashier granted
-- full-comp but DENIED ordinary discounts never reaches the comp gate. Revoking
-- apply_discount therefore renders a stored full-comp grant INERT without erasing it.
--
-- ROLE DEFAULTS: org_owner / restaurant_owner / manager hold full comp BY ROLE.
-- A cashier is DENIED unless an owner/manager explicitly grants it to that individual.
--
-- WHAT ELSE CHANGES IN app.apply_discount -- this is not merely a rename:
--   * THE GATE MOVES FROM THE DISCOUNT BASE TO THE RESULTING TOTAL. The old test was
--     `v_disc_amount >= v_base`, where v_base is the SUBTOTAL (order scope) or ONE
--     LINE (item scope). Neither is the rule: with tax > 0, zeroing the subtotal
--     still leaves grand = tax > 0 (the guest owes money -- not a comp), and zeroing
--     one line of a multi-line order leaves the order far from free.
--   * THE ITEM SCOPE COMPUTES ITS PROSPECTIVE ROLLUP BEFORE WRITING. The old code
--     updated order_items FIRST and only then learned the new grand total, so it
--     could not refuse without leaving a partial write behind (a RETURN does not
--     unwind it, and a RAISE would roll back the denial audit).
--   * A NEGATIVE PROSPECTIVE TOTAL IS REFUSED, NOT FLOORED. The old item-scope
--     `if v_new_grand < 0 then v_new_grand := 0` silently MANUFACTURED A FREE ORDER
--     that neither gate ever saw (the pre-existing order-level discount is never
--     re-clamped against a shrunken subtotal). That bypass is closed.
--
-- Refusals RETURN a typed envelope, never RAISE: a raise would roll back the denial
-- audit row, and app.sync_push rebuilds a RAISEd envelope and collapses `error` to
-- the literal 'rejected' -- destroying the domain code the POS needs to explain
-- itself. Tokens: permission_denied/full_comp_permission_required and
-- invalid_discount/discount_exceeds_order_total.
--
-- EXPLICITLY NOT CHANGED: the settlement predicate (app.order_is_fully_settled),
-- auto-completion, the discount-after-payment freeze, terminal-order guards, the
-- payment path, receipt numbering, void semantics. NO payment row is ever fabricated
-- for a comped order -- a zero-total order is NON-CHARGEABLE and settles with no
-- payment at all (ORDER-AUTO-COMPLETION-001), which is precisely why "free" has to
-- be a guarded right rather than a discount of convenient size.
--
-- Forward-only, additive. NOT applied to hosted by this migration.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. app.cashier_capability_granted -- the GRANT-ONLY (default-OFF) resolver: the
--    polarity mirror of app.cashier_capability_allowed, which stays untouched.
--    Pure (no table access); returns false for every non-cashier role, so it can
--    only ever ALLOW a cashier and never widen another role. Callers OR it with
--    their owner/manager role grants.
-- ---------------------------------------------------------------------------
create or replace function app.cashier_capability_granted(
  p_role        text,
  p_permissions jsonb,
  p_capability  text
)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  -- FAIL-CLOSED. A default-OFF capability is GRANTED only by the EXPLICIT presence
  -- of the canonical JSON string "true". Absence DENIES (the role default). A JSON
  -- boolean true, the number 1, "TRUE"/"yes", null, an array, an object, a non-object
  -- permissions blob, a SQL NULL, every non-cashier role, and any capability outside
  -- the named grant-only set ALL DENY. There is no coercion anywhere: a malformed
  -- permissions payload can never manufacture the right to give food away.
  --
  -- THE coalesce IS LOAD-BEARING, NOT DEFENSIVE NOISE. `jsonb -> key` on a MISSING
  -- key returns SQL NULL, and `NULL = '"true"'::jsonb` is NULL -- which would poison
  -- the whole AND chain and make this function return NULL (not false) for the single
  -- most common input in the system: a cashier with no override. NULL is NOT false:
  -- the caller's guard reads `if ... and not v_may_comp then`, and `not NULL` is NULL,
  -- so the branch would NEVER FIRE and an UNGRANTED CASHIER COULD COMP THE ORDER --
  -- a fail-OPEN on the one permission that gives food away. coalesce(..., false)
  -- collapses NULL to a hard false. (The deny-only resolver is safe without this only
  -- because the `?` operator returns a strict boolean and never NULL.)
  select coalesce(
           p_role = 'cashier'
           and p_capability in ('apply_full_comp')
           and p_permissions is not null
           and jsonb_typeof(p_permissions) = 'object'
           and p_permissions -> p_capability = '"true"'::jsonb,
         false);
$$;

comment on function app.cashier_capability_granted(text, jsonb, text) is
  'FULL-COMP-PERMISSION-001: FAIL-CLOSED GRANT-ONLY (default-OFF) per-cashier capability resolver -- the polarity MIRROR of app.cashier_capability_allowed (deny-only/default-ON, unchanged). TRUE iff role=cashier AND the capability is one of the named grant-only keys (apply_full_comp) AND permissions is a well-formed JSON object AND the key is PRESENT carrying exactly the canonical JSON string "true". ABSENCE DENIES, so every cashier alive today (permissions ''{}'') is denied by construction with no backfill. Every malformed present value (boolean true, number, "TRUE", null, array, object) DENIES -- a broken payload can never manufacture a grant. Non-object / JSON-null / SQL-NULL permissions, every non-cashier role, and any capability outside the grant-only set all DENY. Callers OR it with their owner/manager role grants, so it never widens another role. It does NOT imply the ordinary discount right: app.apply_discount checks apply_discount FIRST and refuses independently.';

revoke all on function app.cashier_capability_granted(text, jsonb, text) from public;
revoke all on function app.cashier_capability_granted(text, jsonb, text) from anon;
revoke all on function app.cashier_capability_granted(text, jsonb, text) from authenticated;


-- ---------------------------------------------------------------------------
-- 2. app.apply_discount -- faithful re-creation of the MONEY-SETTLEMENT-CONSISTENCY-001
--    body with the full-comp gate REBASED on the RESULTING AUTHORITATIVE TOTAL,
--    extended to the new capability, HOISTED ABOVE the item-scope write, and with the
--    silent negative->0 floor replaced by a fail-closed refusal. Everything else --
--    PIN-session auth, scope checks, the FOR UPDATE lock, the terminal guard, the
--    completed-payment freeze, the discount maths, idempotency, the success audit --
--    is VERBATIM.
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
  -- FULL-COMP-PERMISSION-001
  v_may_comp     boolean;   -- the EFFECTIVE right to make an order FREE
  v_other_lines  bigint;    -- sum of the OTHER live lines (prospective rollup)
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

  -- FULL-COMP-PERMISSION-001 -- THE EFFECTIVE RIGHT TO MAKE AN ORDER FREE.
  -- Resolved ONCE, from the SERVER's own membership row (v_m_perms), never from
  -- anything the client sent. Manager/restaurant_owner/org_owner hold it BY ROLE;
  -- a cashier holds it ONLY via an EXPLICIT, default-OFF grant
  -- (app.cashier_capability_granted -- presence of the canonical JSON string
  -- "true"). This NEVER bypasses the general discount permission: gate (c) above
  -- already refused any actor lacking `apply_discount`, so a cashier granted
  -- full-comp but DENIED ordinary discounts never reaches this line.
  v_may_comp := (v_role in ('manager', 'restaurant_owner', 'org_owner'))
                or app.cashier_capability_granted(v_role, v_m_perms, 'apply_full_comp');

  if p_scope = 'order' then
    -- order-level: base = current subtotal; clamp discount <= subtotal
    v_base := v_subtotal;
    if p_discount_type = 'percentage' then
      v_disc_amount := round(v_base::numeric * p_value / 10000)::bigint;   -- numeric is exact (not float); half-away-from-zero
    else
      v_disc_amount := p_value;
    end if;
    if v_disc_amount > v_base then v_disc_amount := v_base; end if;          -- clamp >= 0 (D-007/§4.4)
    v_new_grand := v_subtotal - v_disc_amount + v_tax;

    -- FULL-COMP-PERMISSION-001 -- THE GATE IS THE RESULTING AUTHORITATIVE TOTAL.
    -- A "full comp" is DEFINED as: this mutation would leave grand_total_minor
    -- EXACTLY 0. It is NOT inferred from a UI "100%" choice, from p_discount_type,
    -- or from a client flag -- the server computes the prospective total from its
    -- OWN snapshots and tests THAT. So a `fixed` discount that happens to cover the
    -- whole order is caught identically to a 10000-bp `percentage` one, and a
    -- percentage that merely zeroes the SUBTOTAL of a TAXED order (leaving
    -- grand = tax > 0) is NOT a comp -- the guest still owes money.
    -- Refusal RETURNS (never raises): a raise would roll back the audit row, and
    -- app.sync_push rebuilds a RAISEd envelope and collapses `error` to the literal
    -- 'rejected', destroying the domain code the POS needs.
    if v_new_grand < 0 then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
        jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id,
                           'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                           'role', v_role, 'scope', p_scope,
                           'discount_type', p_discount_type, 'value', p_value,
                           'denied_reason', 'discount_exceeds_order_total'));
      return jsonb_build_object('ok', false, 'error', 'invalid_discount',
                                'detail', 'discount_exceeds_order_total', 'order_id', p_order_id,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
    if v_new_grand = 0 and not v_may_comp then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
        jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id,
                           'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                           'role', v_role, 'scope', p_scope,
                           'discount_type', p_discount_type, 'value', p_value,
                           'resulting_charge_state', 'not_chargeable',
                           'denied_reason', 'full_comp_permission_required'));
      return jsonb_build_object('ok', false, 'error', 'permission_denied',
                                'detail', 'full_comp_permission_required', 'order_id', p_order_id,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
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
    if v_disc_amount > v_base then v_disc_amount := v_base; end if;
    v_new_line_total := v_base - v_disc_amount;

    -- FULL-COMP-PERMISSION-001 -- THE PROSPECTIVE ORDER TOTAL, COMPUTED BEFORE ANY
    -- WRITE. The old code updated order_items FIRST and only then learned the new
    -- grand total, so an item-scope gate could not refuse without leaving a partial
    -- write behind (a RETURN does not unwind it -- only a RAISE would, and a RAISE
    -- would roll back the denial audit AND lose the domain code through sync_push).
    -- So the rollup is now computed from the OTHER live lines plus THIS line's
    -- prospective total, with nothing written yet.
    select coalesce(sum(oi.line_total_minor), 0) into v_other_lines
      from public.order_items oi
      where oi.order_id = p_order_id and oi.organization_id = v_org
        and oi.id <> p_order_item_id
        and oi.status not in ('voided', 'cancelled');
    v_new_subtotal := v_other_lines + v_new_line_total;
    v_new_grand    := v_new_subtotal - v_discount + v_tax;

    -- A NEGATIVE prospective total is REFUSED, never floored. The old code silently
    -- clamped it to 0 -- which MANUFACTURED A FREE ORDER that neither gate ever saw
    -- (the pre-existing order-level v_discount is not re-clamped against a shrunken
    -- subtotal). Failing closed here removes that bypass. D-007: money stays a
    -- non-negative integer.
    if v_new_grand < 0 then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
        jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id, 'order_item_id', p_order_item_id,
                           'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                           'role', v_role, 'scope', p_scope,
                           'discount_type', p_discount_type, 'value', p_value,
                           'denied_reason', 'discount_exceeds_order_total'));
      return jsonb_build_object('ok', false, 'error', 'invalid_discount',
                                'detail', 'discount_exceeds_order_total', 'order_id', p_order_id,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
    -- The SAME resulting-total rule as the order scope: zeroing ONE line of a
    -- multi-line order is an ordinary discount (the order still owes money); it is a
    -- COMP only when the ORDER's grand total lands on exactly 0.
    if v_new_grand = 0 and not v_may_comp then
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'order.discount_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
        jsonb_build_object('attempted_action', 'apply_discount', 'order_id', p_order_id, 'order_item_id', p_order_item_id,
                           'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                           'role', v_role, 'scope', p_scope,
                           'discount_type', p_discount_type, 'value', p_value,
                           'resulting_charge_state', 'not_chargeable',
                           'denied_reason', 'full_comp_permission_required'));
      return jsonb_build_object('ok', false, 'error', 'permission_denied',
                                'detail', 'full_comp_permission_required', 'order_id', p_order_id,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;

    update public.order_items
      set line_discount_minor = v_disc_amount, line_total_minor = v_new_line_total
      where id = p_order_item_id;
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
  'RF-053 + STAFF-CASHIER-PERMISSIONS-001 + MONEY-SETTLEMENT-CONSISTENCY-001 + FULL-COMP-PERMISSION-001 (API_CONTRACT §4.5, D-007/D-011): SECURITY DEFINER discount RPC (fixed amount_minor or percentage basis points), INTEGER MINOR UNITS only. TWO permissions now gate it. (1) ORDINARY DISCOUNT: manager+ OR a cashier with the default-ON apply_discount capability -- checked FIRST and refusing on its own. (2) FULL COMP (making the order FREE): manager+ OR a cashier with the EXPLICIT, default-OFF apply_full_comp grant (app.cashier_capability_granted). A FULL COMP IS DEFINED AS a mutation whose RESULTING AUTHORITATIVE grand_total_minor is EXACTLY 0 -- computed server-side from its OWN snapshots, NEVER inferred from a UI "100%" preset, from p_discount_type, or from any client flag, so a `fixed` discount covering the whole order is caught identically to a 10000-bp percentage one. Conversely, a discount that merely zeroes the SUBTOTAL of a TAXED order (leaving grand = tax > 0) is NOT a comp: the guest still owes money. FULL COMP NEVER BYPASSES THE ORDINARY DISCOUNT RIGHT (gate 1 runs first), so revoking apply_discount renders a stored full-comp grant INERT. The item scope computes its prospective rollup BEFORE any write, and a NEGATIVE prospective total is REFUSED (invalid_discount / discount_exceeds_order_total) rather than floored to 0 -- the old floor silently manufactured a FREE order that no gate saw. Refusals RETURN {ok:false, error:permission_denied, detail:full_comp_permission_required} and are audited order.discount_denied (never raise: a raise rolls back the denial audit, and app.sync_push collapses a raised error to the literal ''rejected''), with NO order/item write, NO revision bump and NO idempotency-ledger entry. THE FINANCIAL SNAPSHOT STILL FREEZES AT PAYMENT (any live completed payment refuses every discount mutation, D-023). Terminal orders still rejected. The order row is locked FOR UPDATE. Order-bound idempotency (D-022). Writes order.discount_applied (D-013). NO payment is ever fabricated for a comped order: a zero-total order is NON-CHARGEABLE and settles with no payment row (ORDER-AUTO-COMPLETION-001).';


-- ---------------------------------------------------------------------------
-- 3. app.set_staff_capabilities -- 5-arg -> 6-arg. A CHANGED SIGNATURE cannot use
--    CREATE OR REPLACE: Postgres would leave the old 5-arg function in place as a
--    second OVERLOAD and PostgREST would resolve the call ambiguously. So BOTH the
--    public wrapper and the app function are DROPPED and re-created. The DROP also
--    destroys their ACLs, which are re-applied immediately below each.
-- ---------------------------------------------------------------------------
drop function if exists public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean);
drop function if exists app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean);

create function app.set_staff_capabilities(
  p_client_request_id   uuid,
  p_employee_profile_id uuid,
  p_apply_discount      boolean,
  p_void_order          boolean,
  p_close_shift         boolean,
  p_apply_full_comp     boolean default false   -- FULL-COMP-PERMISSION-001 (default OFF)
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_membership uuid;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_perms      jsonb;
  v_new_perms  jsonb;
  v_rank       integer;
  v_fp         text;
  v_replay     jsonb;
  v_result     jsonb;
begin
  -- (a) authentication + required input
  if v_actor is null then
    raise exception 'set_staff_capabilities: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_staff_capabilities: client_request_id is required' using errcode = '42501';
  end if;
  if p_employee_profile_id is null then
    raise exception 'set_staff_capabilities: employee_profile_id is required' using errcode = '42501';
  end if;

  -- (b) idempotent replay FIRST -- BEFORE any target lookup, so the idempotency
  --     ledger cannot become an existence/scope oracle. The fingerprint is derived
  --     ONLY from caller-supplied canonical input; management_idem_check is
  --     actor-scoped (keyed on actor_app_user_id + client_request_id), so a stored
  --     replay result is never exposed to a different actor/membership/org/session.
  -- FULL-COMP-PERMISSION-001: the 4th toggle is PART OF THE FINGERPRINT. Without it,
  -- flipping ONLY full-comp on an otherwise-identical payload would hash to the prior
  -- request and REPLAY its stored result -- silently skipping the write.
  v_fp := md5(jsonb_build_object('emp', p_employee_profile_id,
              'apply_discount', p_apply_discount, 'void_order', p_void_order,
              'close_shift', p_close_shift, 'apply_full_comp', p_apply_full_comp)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_staff_capabilities', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (c) resolve the target: the employee_profile AND its authoritative membership
  --     in ONE coherent lookup, proving they are the SAME person (ep.membership_id
  --     = m.id, same organization, same app_user_id). Authorization AND the UPDATE
  --     both derive from the MEMBERSHIP's OWN scope (the row that will be mutated),
  --     NEVER the profile's -- a profile in branch A pointing at a branch-B
  --     membership can no longer authorize a branch-B mutation. A missing / deleted
  --     / inactive / mismatched (profile<->membership) target, a target outside the
  --     caller's covering scope, and a cross-tenant target ALL collapse to ONE
  --     fail-closed 42501 with an IDENTICAL message (no existence/scope oracle).
  select m.organization_id, m.restaurant_id, m.branch_id, m.id, m.role, m.status, m.deleted_at, m.permissions
    into v_org, v_rest, v_branch, v_membership, v_role, v_m_status, v_m_deleted, v_perms
    from public.employee_profiles ep
    join public.memberships m
      on m.id              = ep.membership_id
     and m.organization_id = ep.organization_id
     and m.app_user_id     = ep.app_user_id
    where ep.id = p_employee_profile_id and ep.deleted_at is null;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'set_staff_capabilities: employee not found or not in caller scope' using errcode = '42501';
  end if;
  -- authority is measured against the MEMBERSHIP scope (downward-only coverage:
  -- an org/restaurant owner legitimately covers a branch; a branch manager does
  -- not cover a sibling branch). 0 => outside coverage => SAME 42501 as not-found.
  v_rank := app.actor_rank_in_scope(v_org, v_rest, v_branch);
  if v_rank = 0 then
    raise exception 'set_staff_capabilities: employee not found or not in caller scope' using errcode = '42501';
  end if;
  -- (d) rank >= manager AND strictly outrank the target. An IN-SCOPE but
  --     insufficient-rank actor gets a DURABLE staff.capabilities_denied audit +
  --     permission_denied (RETURNED, so the audit persists -- see the report note
  --     on why the not-found/cross-tenant RAISE paths cannot be durably audited).
  if v_rank < 2 or v_rank <= app.role_rank(v_role) then
    perform app.management_audit(v_org, v_rest, v_branch,
      'staff.capabilities_denied', null,
      jsonb_build_object('employee_profile_id', p_employee_profile_id, 'membership_id', v_membership, 'target_role', v_role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'employee_profile');
  end if;
  -- these three toggles exist only for the cashier role.
  if v_role <> 'cashier' then
    raise exception 'set_staff_capabilities: capabilities apply only to the cashier role' using errcode = '42501';
  end if;

  -- (e) build the new permissions -- deny-only storage: canonical JSON string
  --     "false" to deny, drop the key to allow (role default ON). Only the three
  --     keys are ever touched; UNRELATED permission keys are preserved verbatim.
  v_new_perms := coalesce(v_perms, '{}'::jsonb);
  v_new_perms := case when p_apply_discount then v_new_perms - 'apply_discount'
                      else jsonb_set(v_new_perms, '{apply_discount}', '"false"'::jsonb) end;
  v_new_perms := case when p_void_order then v_new_perms - 'void_order'
                      else jsonb_set(v_new_perms, '{void_order}', '"false"'::jsonb) end;
  v_new_perms := case when p_close_shift then v_new_perms - 'close_shift'
                      else jsonb_set(v_new_perms, '{close_shift}', '"false"'::jsonb) end;
  -- FULL-COMP-PERMISSION-001 -- INVERTED STORAGE. The three above are DENY-ONLY
  -- (default ON: absence allows, the string "false" denies). Full-comp is the
  -- opposite: DEFAULT OFF, so a GRANT writes the canonical string "true" and a
  -- REVOKE removes the key. Absence therefore DENIES, so every existing cashier
  -- (permissions '{}') stays denied by construction -- no backfill, no migration
  -- of data, and no cashier silently gains the right to give food away.
  v_new_perms := case when p_apply_full_comp
                      then jsonb_set(v_new_perms, '{apply_full_comp}', '"true"'::jsonb)
                      else v_new_perms - 'apply_full_comp' end;

  -- (f) claim idempotency BEFORE mutating (race-safe), then a SCOPE-PREDICATED
  --     update (the predicates re-assert the membership's own scope; the UPDATE
  --     does not rely only on the prior SELECT) + audit with OLD and NEW raw
  --     permissions and effective values.
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false,
                'entity', 'employee_profile', 'employee_profile_id', p_employee_profile_id,
                'membership_id', v_membership,
                'capabilities', jsonb_build_object('apply_discount', p_apply_discount,
                  'void_order', p_void_order, 'close_shift', p_close_shift,
                  'apply_full_comp', p_apply_full_comp));
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_staff_capabilities', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  update public.memberships
     set permissions = v_new_perms, updated_at = now()
   where id = v_membership and organization_id = v_org
     and restaurant_id is not distinct from v_rest
     and branch_id     is not distinct from v_branch;

  perform app.management_audit(v_org, v_rest, v_branch, 'staff.capabilities_updated',
    jsonb_build_object('employee_profile_id', p_employee_profile_id, 'membership_id', v_membership,
      'permissions', v_perms,
      'capabilities', jsonb_build_object(
        'apply_discount',  app.cashier_capability_allowed('cashier', v_perms, 'apply_discount'),
        'void_order',      app.cashier_capability_allowed('cashier', v_perms, 'void_order'),
        'close_shift',     app.cashier_capability_allowed('cashier', v_perms, 'close_shift'),
        'apply_full_comp', app.cashier_capability_granted('cashier', v_perms, 'apply_full_comp'))),
    jsonb_build_object('employee_profile_id', p_employee_profile_id, 'membership_id', v_membership,
      'permissions', v_new_perms,
      'capabilities', jsonb_build_object('apply_discount', p_apply_discount,
        'void_order', p_void_order, 'close_shift', p_close_shift,
        'apply_full_comp', p_apply_full_comp)));

  return v_result;
end;
$$;

comment on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean) is
  'STAFF-CASHIER-PERMISSIONS-001 + FULL-COMP-PERMISSION-001: owner/manager sets a target CASHIER''s capabilities. TWO STORAGE POLARITIES now coexist. The three original toggles stay DENY-ONLY / default-ON: OFF stores the canonical JSON string "false", ON REMOVES the key. The new apply_full_comp is the mirror -- GRANT-ONLY / default-OFF: ON stores the canonical string "true", OFF REMOVES the key, so ABSENCE DENIES and no existing cashier is grandfathered into it. Unrelated permission keys are preserved verbatim. Tenant + branch + role-rank scoped (mirrors create_staff_member): the caller must COVER the target scope AND rank >= manager AND STRICTLY OUTRANK the target -- so a manager cannot edit another manager, nobody reaches a sibling restaurant/branch, and a cross-tenant target and a nonexistent one collapse to ONE indistinguishable 42501 (no R-003 existence oracle). Cashier-role-only. Idempotent, and the 4th toggle IS part of the fingerprint -- flipping only full-comp is a real write, not a stale replay no-op. Audited staff.capabilities_updated with OLD and NEW raw permissions AND effective capabilities; an in-scope but insufficient-rank actor gets a durable staff.capabilities_denied + permission_denied.';

-- The PUBLIC wrapper for the 6-arg function (the 5-arg wrapper was dropped above).
create or replace function public.set_staff_capabilities(
  p_client_request_id   uuid,
  p_employee_profile_id uuid,
  p_apply_discount      boolean,
  p_void_order          boolean,
  p_close_shift         boolean,
  p_apply_full_comp     boolean default false
)
  returns jsonb
  language sql
  volatile
  security invoker
  set search_path = ''
as $$
  select app.set_staff_capabilities(p_client_request_id, p_employee_profile_id,
                                    p_apply_discount, p_void_order, p_close_shift,
                                    p_apply_full_comp);
$$;

comment on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean) is
  'FULL-COMP-PERMISSION-001: PUBLIC (PostgREST-reachable) INVOKER wrapper over the 6-arg app.set_staff_capabilities. Re-created after the arity change -- a CREATE OR REPLACE would have left the 5-arg function behind as a second overload and PostgREST would resolve ambiguously. Carries no authority of its own.';

revoke all on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean) from public;
revoke all on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean) from anon;
grant execute on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean) to authenticated;

revoke all on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean) from public;
revoke all on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean) from anon;
grant execute on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean, boolean) to authenticated;


-- ---------------------------------------------------------------------------
-- 4. app.create_staff_member -- the initial-capabilities validator is now
--    POLARITY-AWARE (deny-only keys may only be denied; the grant-only key may only
--    be granted), and the staff.created audit records the new capability. See §6:
--    staff.created is now PROJECTED, so a grant made at provisioning time is visible
--    in the Activity Log rather than recorded and never shown.
-- ---------------------------------------------------------------------------
create or replace function app.create_staff_member(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_display_name      text,
  p_role              text,
  p_capabilities      jsonb   default null   -- STAFF-CASHIER-PERMISSIONS-001: initial cashier deny overrides (atomic)
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();
  v_rank       integer;
  v_name       text;
  v_fp         text;
  v_replay     jsonb;
  v_app_user   uuid := gen_random_uuid();
  v_membership uuid := gen_random_uuid();
  v_employee   uuid := gen_random_uuid();
  v_email      text;
  v_result     jsonb;
  v_new        jsonb;
  v_perms      jsonb := '{}'::jsonb;
begin
  -- (a) authentication + required input
  if v_actor is null then
    raise exception 'create_staff_member: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'create_staff_member: client_request_id is required' using errcode = '42501';
  end if;
  -- staff operators are branch-scoped (they work a PIN pad at a branch)
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'create_staff_member: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;

  -- (b) structural validation
  v_name := btrim(coalesce(p_display_name, ''));
  if length(v_name) = 0 then
    raise exception 'create_staff_member: display_name is required' using errcode = '42501';
  end if;
  -- only operator roles are creatable here (owners are onboarded/granted via
  -- create_organization / grant_membership, never as PIN-only staff).
  if p_role is null or p_role not in ('cashier', 'kitchen_staff', 'manager') then
    raise exception 'create_staff_member: role must be cashier, kitchen_staff or manager' using errcode = '42501';
  end if;
  -- STAFF-CASHIER-PERMISSIONS-001: OPTIONAL initial cashier capability DENY
  -- overrides, persisted ATOMICALLY with the membership in THIS transaction (no
  -- fail-open create-then-set). Fail-closed + deny-only: only role=cashier, only
  -- the three named keys, only the string 'false' (absence/'true' => role default
  -- ON, so those are never stored). Anything else raises => nothing is created.
  if p_capabilities is not null and p_capabilities <> '{}'::jsonb then
    if jsonb_typeof(p_capabilities) <> 'object' then
      raise exception 'create_staff_member: capabilities must be a JSON object' using errcode = '42501';
    end if;
    if p_role <> 'cashier' then
      raise exception 'create_staff_member: capabilities apply only to the cashier role' using errcode = '42501';
    end if;
    -- STRICT + fail-closed: iterate with jsonb_each (NO text coercion). Every key
    -- must be one of the three canonical keys AND every value must be the exact
    -- JSON STRING "false". Rejects JSON null / boolean false / boolean true /
    -- string "true" / numbers / arrays / nested objects / unknown keys / mixed
    -- payloads (a scalar/array/null ROOT is already rejected by the object check).
    -- FULL-COMP-PERMISSION-001: TWO storage polarities now coexist, and each key is
    -- validated against ITS OWN one. The three default-ON keys may only ever be
    -- DENIED (the JSON string "false"). apply_full_comp is DEFAULT-OFF and may only
    -- ever be GRANTED (the JSON string "true"). Anything else -- a "true" on a
    -- default-ON key, a "false" on full-comp (that is already the default, so
    -- storing it would be meaningless noise), a boolean, a number, null, an array,
    -- an object, or an unknown key -- RAISES, and nothing is created. Fail-closed;
    -- no silent coercion of a malformed grant into a real one.
    if exists (
         select 1 from jsonb_each(p_capabilities) e
         where jsonb_typeof(e.value) <> 'string'
            or e.key not in ('apply_discount', 'void_order', 'close_shift', 'apply_full_comp')
            or (e.key in ('apply_discount', 'void_order', 'close_shift')
                and e.value <> '"false"'::jsonb)
            or (e.key = 'apply_full_comp' and e.value <> '"true"'::jsonb)) then
      raise exception 'create_staff_member: capabilities may only DENY (JSON string "false") apply_discount/void_order/close_shift or GRANT (JSON string "true") apply_full_comp' using errcode = '42501';
    end if;
    v_perms := p_capabilities;
  end if;
  -- target branch + parent restaurant must exist in the org AND be LIVE (RF-112 rule:
  -- never create authority on a dead scope).
  if not exists (
       select 1 from public.branches b
       join public.restaurants r on r.id = b.restaurant_id and r.organization_id = b.organization_id
       where b.id = p_branch_id and b.organization_id = p_organization_id
         and b.restaurant_id = p_restaurant_id and b.deleted_at is null and r.deleted_at is null) then
    raise exception 'create_staff_member: branch not found in organization/restaurant or scope is soft-deleted' using errcode = '42501';
  end if;

  -- (c) committed idempotent replay (before authorization -> true idempotency;
  --     mirrors grant_membership). Fingerprint carries NO secret (there is none here).
  -- STAFF-CASHIER-PERMISSIONS-001 (idempotency legacy compat): with NO initial
  -- denies (p_capabilities NULL/{} -> v_perms {}) compute the EXACT pre-migration
  -- fingerprint (no capabilities component) so a request created before this
  -- migration replays after it. Only when real denies exist do we extend the
  -- fingerprint with a canonical representation -- v_perms is jsonb, so equivalent
  -- deny objects (any key order) share one canonical text (key order is irrelevant).
  if v_perms = '{}'::jsonb then
    v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
                'branch', p_branch_id, 'display_name', v_name, 'role', p_role)::text);
  else
    v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
                'branch', p_branch_id, 'display_name', v_name, 'role', p_role,
                'capabilities', v_perms)::text);
  end if;
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'create_staff_member', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (d) authorization (GUC-free + role-rank guard). 0 => no covering membership => 42501.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'create_staff_member: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  -- caller IS a covering member from here -> denials are audited permission_denied:
  -- rank >= manager required AND the caller must STRICTLY outrank the assigned role.
  if v_rank < 2 or v_rank <= app.role_rank(p_role) then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
      'staff.create_denied', null,
      jsonb_build_object('display_name', v_name, 'role', p_role));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'employee_profile');
  end if;

  -- (e) claim idempotency BEFORE mutating (race-safe), then create the three rows + audit.
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'employee_profile',
                'employee_profile_id', v_employee, 'membership_id', v_membership,
                'app_user_id', v_app_user, 'role', p_role);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'create_staff_member', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- synthetic, unique, lowercase identifier email (RFC-2606 .invalid TLD): PIN-only
  -- operators have NO login account; this is ONLY an identifier (D-004 preserved --
  -- each operator is their own person/identity, never a shared account).
  v_email := 'staff-' || replace(gen_random_uuid()::text, '-', '') || '@pin.restoflow.invalid';

  insert into public.app_users (id, email, display_name, is_active)
  values (v_app_user, v_email, v_name, true);

  insert into public.memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, status, permissions)
  values (v_membership, v_app_user, p_organization_id, p_restaurant_id, p_branch_id, p_role, 'active', v_perms);

  insert into public.employee_profiles
    (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id,
     display_name, employment_status, pin_credential_ref)
  values
    (v_employee, p_organization_id, p_restaurant_id, p_branch_id, v_app_user, v_membership,
     v_name, 'active', null);  -- NO PIN yet: provisioned separately via set_employee_pin

  -- audit (D-013): the profile post-image WITHOUT the credential column (defensive --
  -- it is NULL here, but audit must structurally never carry PIN material).
  select to_jsonb(t) - 'pin_credential_ref' into v_new
    from public.employee_profiles t where t.id = v_employee;
  -- STAFF-CASHIER-PERMISSIONS-001: include the initial canonical deny overrides
  -- (v_perms: {} when none) and the effective capability values for a cashier, so
  -- staff.created records the exact provisioned capabilities. No PIN/secret data.
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'staff.created', null,
    v_new || jsonb_build_object('membership_id', v_membership, 'app_user_id', v_app_user, 'role', p_role,
      'permissions', v_perms,
      'capabilities', case when p_role = 'cashier' then jsonb_build_object(
          'apply_discount',  app.cashier_capability_allowed('cashier', v_perms, 'apply_discount'),
          'void_order',      app.cashier_capability_allowed('cashier', v_perms, 'void_order'),
          'close_shift',     app.cashier_capability_allowed('cashier', v_perms, 'close_shift'),
          'apply_full_comp', app.cashier_capability_granted('cashier', v_perms, 'apply_full_comp'))
        else null end));
  return v_result;
end;
$$;

comment on function app.create_staff_member(uuid, uuid, uuid, uuid, text, text, jsonb) is
  'MVP staff provisioning (RF-160/D-033) + STAFF-CASHIER-PERMISSIONS-001 + FULL-COMP-PERMISSION-001: creates an employee_profile + membership ATOMICALLY, with OPTIONAL initial cashier capabilities persisted in the SAME transaction (no fail-open create-then-set). The validator is fail-closed and now POLARITY-AWARE: apply_discount/void_order/close_shift may only ever be DENIED (the JSON string "false"), while apply_full_comp may only ever be GRANTED (the JSON string "true"). Any unknown key, any non-string value, a "true" on a deny-only key, or a "false" on the grant-only key RAISES 42501 and NOTHING is created -- a malformed payload can never be coerced into a grant. Cashier-role-only. Audited staff.created, which now carries the effective capabilities INCLUDING apply_full_comp and IS projected to the Activity Log: a capability may never be granted invisibly.';


-- ---------------------------------------------------------------------------
-- 5. app.list_staff -- each cashier row's effective capabilities now include
--    apply_full_comp, resolved by the GRANT-only resolver. Using the deny-only one
--    here would report the exact inverse (absent key => "allowed").
-- ---------------------------------------------------------------------------
create or replace function app.list_staff(
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
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_items jsonb;
begin
  if v_actor is null then
    raise exception 'list_staff: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_staff: organization_id is required' using errcode = '42501';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_staff: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < 2 then     -- cashier/kitchen_staff/accountant cannot list staff
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'employee_profile');
  end if;

  select coalesce(jsonb_agg(item order by (item ->> 'display_name'), (item ->> 'employee_profile_id')), '[]'::jsonb)
    into v_items
  from (
    select jsonb_build_object(
      'employee_profile_id', ep.id,
      'display_name',        ep.display_name,
      'employee_number',     ep.employee_number,
      'role',                m.role,
      'employment_status',   ep.employment_status,
      'has_pin',             (ep.pin_credential_ref is not null),  -- boolean ONLY; never the ref
      'restaurant_id',       ep.restaurant_id,
      'branch_id',           ep.branch_id,
      'created_at',          ep.created_at,
      'capabilities',        jsonb_build_object(
        'apply_discount',  app.cashier_capability_allowed(m.role, m.permissions, 'apply_discount'),
        'void_order',      app.cashier_capability_allowed(m.role, m.permissions, 'void_order'),
        'close_shift',     app.cashier_capability_allowed(m.role, m.permissions, 'close_shift'),
        -- FULL-COMP-PERMISSION-001: default-OFF, so it resolves through the GRANT
        -- resolver, not the deny-only one. A cashier with no override reports false.
        'apply_full_comp', app.cashier_capability_granted(m.role, m.permissions, 'apply_full_comp'))
    ) as item
    from public.employee_profiles ep
    join public.memberships m
      on m.id = ep.membership_id
     and m.organization_id = ep.organization_id
     and m.status = 'active'
     and m.deleted_at is null
    where ep.organization_id = p_organization_id
      and (p_restaurant_id is null or ep.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or ep.branch_id     = p_branch_id)
      and ep.deleted_at is null
  ) t;

  return jsonb_build_object('ok', true, 'entity', 'employee_profile', 'staff', v_items);
end;
$$;

comment on function app.list_staff(uuid, uuid, uuid) is
  'MVP staff provisioning list (RF-160/D-033) + STAFF-CASHIER-PERMISSIONS-001 + FULL-COMP-PERMISSION-001: faithful re-creation whose per-row `capabilities` object now carries FOUR effective booleans -- apply_discount/void_order/close_shift via the DENY-ONLY resolver, and apply_full_comp via the GRANT-ONLY resolver (a cashier with no explicit grant reports false; using the deny-only resolver here would report the exact inverse). Non-cashier rows report false for all four: the toggles apply only to the cashier role, and owners/managers hold these rights BY ROLE -- which the Dashboard states honestly rather than rendering as a stored toggle. Owner/manager-only, has_pin remains a boolean, read-only, otherwise verbatim.';


-- ---------------------------------------------------------------------------
-- 6. app.audit_action_has_detail -- staff.created now carries a safe projection, so
--    a capability granted at PROVISIONING time can never be invisible.
-- ---------------------------------------------------------------------------
create or replace function app.audit_action_has_detail(p_action text)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  select coalesce(p_action, '') like 'order.void%'
      or p_action like 'order.discount%'
      or p_action like 'order.status%'
      or p_action =    'order.submitted'
      or p_action like 'staff.capabilities%'
      -- FULL-COMP-PERMISSION-001: staff.created was NOT projected, so the capabilities
      -- a cashier is PROVISIONED with were written to the append-only trail and then
      -- never shown. Granting "make orders free" invisibly is exactly what this ticket
      -- must not do, so the CREATE path is projected too.
      or p_action =    'staff.created'
      or p_action like 'membership.%'
      or p_action like 'shift.%'
      or p_action like 'cash_drawer.%'
      or p_action like 'payment.%'
      or p_action like 'settings.%'
      or p_action =    'pin_session.failed';
$$;

comment on function app.audit_action_has_detail(text) is
  'AUDIT-LOG-DASHBOARD-001 + AUDIT-COVERAGE-002 + FULL-COMP-PERMISSION-001: is p_action a SUPPORTED action that may carry a safe payload projection? Unknown/unsupported actions return NO payload details (metadata + category only). Now includes staff.created, so the capabilities a cashier is PROVISIONED with -- including an apply_full_comp grant -- appear in the Activity Log instead of being written to the append-only trail and never shown. Gates app.audit_safe_detail.';


-- ---------------------------------------------------------------------------
-- 7. app.audit_safe_detail -- allowlist the 4th capability key and the
--    resulting_charge_state token. The allowlist is APPEND-ONLY: a key that is not
--    listed here is never even read, so a new detail is invisible until added.
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
    'denied_reason',
    -- FULL-COMP-PERMISSION-001: WHAT the mutation would have left the order as. A
    -- closed enum of STATE tokens ('not_chargeable') -- never money, never an
    -- identifier (T-003 holds).
    'resulting_charge_state'
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
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp']) as k
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
  'AUDIT-LOG-DASHBOARD-001 + AUDIT-COVERAGE-002 + ORDER-COMPLETION-001 + ORDER-AUTO-COMPLETION-001 + MONEY-SETTLEMENT-CONSISTENCY-001 + FULL-COMP-PERMISSION-001: ALLOWLIST projection of ONE audit payload (old or new) to canonical safe fields. Gated by app.audit_action_has_detail (unsupported action -> ''{}''). Emits only allowlisted SCALAR keys (status/order_status/scope/discount_type/value/attempted_action/order_type/roles/*_minor money/voided_item_count/failed_attempt_count/locked/timezone/name/receipt_prefix/order_code/payment_status/completion_mode/completion_trigger/denied_reason + resulting_charge_state) plus the nested `capabilities` object, now kept to its FOUR canonical boolean keys (apply_discount/void_order/close_shift/apply_full_comp). denied_reason (order_has_completed_payment | full_comp_requires_manager | full_comp_permission_required | discount_exceeds_order_total | order_not_voidable) and resulting_charge_state (not_chargeable) are STATE tokens saying WHY a mutation was refused and WHAT it would have left behind -- never money, never an identifier (T-003 holds). Every un-listed key (secret OR merely unknown) and every other nested structure is DROPPED. Malformed/non-object -> ''{}''; never throws. This is the server-side privacy boundary; the RPC returns NO raw payload JSON.';


-- ---------------------------------------------------------------------------
-- 8. app.pin_session_capabilities (+ its public wrapper) -- the POS's EFFECTIVE
--    capability context.
--
--    The POS previously received NO capability information whatsoever
--    (app.start_pin_session returns a bare uuid), so it could not honestly pre-empt
--    a refusal it already knew was coming: the cashier typed a discount, waited, and
--    was rejected at the end.
--
--    This is ADVISORY ONLY. The server remains the sole authority and re-decides on
--    every mutation inside app.apply_discount; this projection exists purely so the
--    POS can state the rule up front. It returns EFFECTIVE rights (role OR grant),
--    so a MANAGER signed in on a POS is never mistaken for an unprivileged cashier.
-- ---------------------------------------------------------------------------
create or replace function app.pin_session_capabilities(
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
  v_dsid       uuid;
  v_emp        uuid;
  v_ds_device  uuid;
  v_ds_active  boolean;
  v_ds_revoked timestamptz;
  v_pairing    text;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_m_perms    jsonb;
begin
  -- The SAME session validation app.apply_discount performs, in the same order.
  -- Every failure collapses to ONE indistinguishable fail-closed envelope: a caller
  -- must never be able to probe WHICH of session / device / pairing / membership was
  -- wrong (no R-003 oracle).
  select ps.device_session_id, ps.employee_profile_id
    into v_dsid, v_emp
    from public.pin_sessions ps
    where ps.id = p_pin_session_id
      and ps.status = 'active'
      and (ps.expires_at is null or ps.expires_at > now());
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;

  select ds.device_id, (ds.status = 'active'), ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not v_ds_active or v_ds_revoked is not null or v_pairing <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;
  if v_ds_device is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;

  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.employee_profiles ep
    join public.memberships m
      on m.id              = ep.membership_id
     and m.organization_id = ep.organization_id
     and m.app_user_id     = ep.app_user_id
    where ep.id = v_emp and ep.deleted_at is null;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'pin_session');
  end if;

  -- EFFECTIVE rights -- byte-for-byte the predicates app.apply_discount enforces, so
  -- the client can never disagree with the server about what it may do.
  return jsonb_build_object(
    'ok', true, 'entity', 'pin_session', 'role', v_role,
    'capabilities', jsonb_build_object(
      'apply_discount',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_allowed(v_role, v_m_perms, 'apply_discount'),
      'apply_full_comp',
        (v_role in ('manager', 'restaurant_owner', 'org_owner'))
        or app.cashier_capability_granted(v_role, v_m_perms, 'apply_full_comp')));
end;
$$;

comment on function app.pin_session_capabilities(uuid, uuid) is
  'FULL-COMP-PERMISSION-001 (D-006/D-011): READ-ONLY projection of the EFFECTIVE capabilities of the human behind an ACTIVE PIN session on a PAIRED, ACTIVE device. The POS previously received NO capability context at all (app.start_pin_session returns a bare uuid), so it could not pre-empt a refusal it already knew was coming. Returns EFFECTIVE rights -- role OR explicit grant -- computed with byte-for-byte the predicates app.apply_discount enforces, so the client can never disagree with the server: apply_discount (manager+ OR the default-ON cashier capability) and apply_full_comp (manager+ OR the EXPLICIT default-OFF cashier grant). ADVISORY ONLY: the server remains the sole authority and re-decides on every mutation; this exists so the POS can state the rule up front instead of failing the cashier at the end. Every invalid / expired / revoked / device-mismatched / inactive-membership session collapses to ONE indistinguishable invalid_session envelope (no probe oracle). Carries no money, no PIN material, and no identifier beyond the role.';

create or replace function public.pin_session_capabilities(
  p_pin_session_id uuid,
  p_device_id      uuid
)
  returns jsonb
  language sql
  volatile
  security invoker
  set search_path = ''
as $$
  select app.pin_session_capabilities(p_pin_session_id, p_device_id);
$$;

comment on function public.pin_session_capabilities(uuid, uuid) is
  'FULL-COMP-PERMISSION-001: PUBLIC (PostgREST-reachable) INVOKER wrapper over app.pin_session_capabilities -- the POS reaches it with the anon key plus its PIN/device session, exactly like public.sync_push. Carries no authority of its own.';


-- ---------------------------------------------------------------------------
-- 9. ACLs. Every function stays REVOKED from PUBLIC and from anon; only
--    `authenticated` may execute a client entry point, and no service-role grant is
--    added anywhere (D-011). The internal resolver is executable by NO client role.
--    (set_staff_capabilities' grants were re-applied in §3, immediately after the
--    DROP that destroyed them.)
-- ---------------------------------------------------------------------------
revoke all on function app.pin_session_capabilities(uuid, uuid) from public;
revoke all on function app.pin_session_capabilities(uuid, uuid) from anon;
grant execute on function app.pin_session_capabilities(uuid, uuid) to authenticated;

revoke all on function public.pin_session_capabilities(uuid, uuid) from public;
revoke all on function public.pin_session_capabilities(uuid, uuid) from anon;
grant execute on function public.pin_session_capabilities(uuid, uuid) to authenticated;
