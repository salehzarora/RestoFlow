-- ============================================================================
-- STAFF-CASHIER-PERMISSIONS-001 -- Default-on cashier capabilities with explicit
-- deny overrides.
--
-- Product change (human-approved): the three routine cashier capabilities
--   * apply_discount   (order/item discount)
--   * void_order       (cancel/void an UNPAID order)
--   * close_shift      (close the cashier's OWN/current shift)
-- become ENABLED BY DEFAULT for the `cashier` role, with an explicit per-cashier
-- DENY override (memberships.permissions ->> key = 'false'). This is a default-ON
-- preset with explicit deny overrides. It flips the prior "explicit grant
-- required" model for cashier discount + void (rf053/rf062); own-shift close was
-- already cashier-allowed by ownership (D-028) and now also honours an explicit
-- deny. PAID-order void stays BLOCKED/deferred (rf062 completed-payment guard is
-- reproduced verbatim). Managers/owners keep their role grants unchanged; other
-- roles are unaffected (the resolver returns false for every non-cashier role, so
-- it never widens any authorization). Missing permission data => role default
-- (ON) ONLY for these three named cashier capabilities.
--
-- Effective rule (single source of truth): app.cashier_capability_allowed(role,
-- permissions, capability) = (role='cashier') AND (capability in the three named)
-- AND (permissions->>capability <> 'false'). Enforcement is SERVER-SIDE in the RPCs below
-- (button visibility is not relied upon). Authorization reads permissions LIVE
-- from the membership row at action time, so a Dashboard change takes effect on
-- the NEXT action / next PIN session; no snapshot to invalidate.
--
-- Dashboard write/read: app.set_staff_capabilities updates the deny overrides for
-- a target cashier (owner/manager, tenant+branch+role-rank scoped, audited,
-- idempotent); app.list_staff now returns each staff row's effective capabilities.
--
-- Faithful re-creation: app.apply_discount (rf053), app.void_order (rf062),
-- app.close_shift (rf055) and app.list_staff (mvp_staff_pin_provisioning) are
-- reproduced verbatim from their newest bodies with ONLY the authorization
-- expression (+ close_shift's membership SELECT/decl, + list_staff's row) changed.
-- SECURITY DEFINER + search_path='' preserved; grants re-asserted (revoke PUBLIC,
-- grant authenticated). Forward-only, additive, non-destructive. NOT hosted here.
-- Updates frozen mandatory test T-006 wording (see SECURITY_AND_THREAT_MODEL.md).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. Centralised effective-permission resolver for the three default-ON cashier
--    capabilities. Pure (no table access); returns false for every non-cashier
--    role so it can only ever ALLOW a cashier -- never widen another role. Only
--    an explicit 'false' deny turns a cashier capability off; absence/'true' =>
--    the role default (ON). Missing/unrelated keys never grant anything.
-- ----------------------------------------------------------------------------
create or replace function app.cashier_capability_allowed(
  p_role        text,
  p_permissions jsonb,
  p_capability  text
)
  returns boolean
  language sql
  immutable
  set search_path = ''
as $$
  -- FAIL-CLOSED effective resolver. A named cashier capability is ALLOWED (role
  -- default ON) ONLY when the deny key is ABSENT from a well-formed JSON object.
  -- Deny-only storage writes exactly {"key":"false"} to deny and REMOVES the key
  -- to allow, so a PRESENT key always means a deny was intended; any present value
  -- (the canonical string "false", or a malformed "true"/boolean/null/number/
  -- array/object) therefore DENIES. Non-object / JSON-null / SQL-NULL permissions,
  -- every non-cashier role, and any capability outside the three named ones all
  -- DENY. Never a universal missing-value allow: absence allows ONLY a named cap.
  select p_role = 'cashier'
         and p_capability in ('apply_discount', 'void_order', 'close_shift')
         and p_permissions is not null
         and jsonb_typeof(p_permissions) = 'object'
         and not (p_permissions ? p_capability);
$$;

comment on function app.cashier_capability_allowed(text, jsonb, text) is
  'STAFF-CASHIER-PERMISSIONS-001: FAIL-CLOSED effective per-cashier capability resolver (pure SECURITY INVOKER helper, immutable) for the three default-ON capabilities (apply_discount, void_order, close_shift). TRUE iff role=cashier AND the capability is one of those three AND permissions is a well-formed JSON object AND the deny key is ABSENT (role default ON). Deny-only storage removes the key to allow and writes {"key":"false"} to deny, so a PRESENT key ALWAYS denies -- the canonical string "false" and every malformed present value (boolean/null/number/array/object/"true") DENY. Non-object / JSON-null / SQL-NULL permissions, every non-cashier role, and any capability outside the three named ones all DENY. Never a universal missing-value allow: absence allows ONLY a named cashier capability. Callers OR it with their owner/manager role grants, so it never widens another role.';

revoke all on function app.cashier_capability_allowed(text, jsonb, text) from public;

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
  select o.organization_id, o.branch_id, o.status, o.revision,
         o.subtotal_minor, o.discount_total_minor, o.tax_total_minor
    into v_o_org, v_o_branch, v_o_status, v_o_rev, v_subtotal, v_discount, v_tax
    from public.orders o where o.id = p_order_id;
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
create or replace function app.close_shift(
  p_pin_session_id       uuid,
  p_shift_id             uuid,
  p_device_id            uuid,
  p_local_operation_id   text,
  p_counted_amount_minor bigint,                 -- API naming; maps to counted_total_minor (A4)
  p_reason               text default null,
  p_expected_revision    integer default null
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
  v_s_org        uuid;
  v_s_branch     uuid;
  v_s_status     text;
  v_s_rev        integer;
  v_s_opened_by  uuid;
  v_drawer_id    uuid;
  v_drawer_status text;
  v_drawer_rev   integer;
  v_opening      bigint;
  v_cash_sales   bigint;
  v_expected     bigint;
  v_counted      bigint;
  v_variance     bigint;
  v_authorized   boolean;
  v_new_rev      integer;
  v_stored       jsonb;
  v_stored_shift uuid;
  v_result       jsonb;
begin
  -- (a) PIN session + backing + actor/scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'close_shift: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'close_shift: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'close_shift: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'close_shift: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'close_shift: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the shift; it MUST be in the actor's org + branch (no cross-tenant)
  select s.organization_id, s.branch_id, s.status, s.revision, s.opened_by_employee_profile_id
    into v_s_org, v_s_branch, v_s_status, v_s_rev, v_s_opened_by
    from public.shifts s where s.id = p_shift_id;
  if not found then
    raise exception 'close_shift: shift not found' using errcode = '42501';
  end if;
  if v_s_org <> v_org or v_s_branch <> v_branch then
    raise exception 'close_shift: shift is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (D-028): manager/restaurant_owner/org_owner may close any shift;
  --     a cashier may close ONLY their OWN shift (opened_by = actor). kitchen_staff/
  --     accountant/other denied -> shift.close_denied audit + permission_denied (no raise).
  v_authorized := (v_role in ('manager', 'restaurant_owner', 'org_owner'))
                  or (app.cashier_capability_allowed(v_role, v_m_perms, 'close_shift')
                      and v_s_opened_by = v_emp);
  if not v_authorized then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'shift.close_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'close_shift', 'shift_id', p_shift_id,
                         'role', v_role, 'shift_status', v_s_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'shift_id', p_shift_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) safe input validation
  if p_counted_amount_minor is null or p_counted_amount_minor < 0 then
    raise exception 'close_shift: counted amount must be a non-negative integer (minor units)' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + input validation,
  --     SHIFT-BOUND. Same key/action on a DIFFERENT shift is a conflict (40001).
  select so.result, so.shift_id into v_stored, v_stored_shift
    from public.shift_operations so
    where so.organization_id = v_org and so.device_id = p_device_id
      and so.local_operation_id = p_local_operation_id and so.action = 'close_shift';
  if found then
    if v_stored_shift <> p_shift_id then
      raise exception 'close_shift: idempotency key already used for a different shift (%, not %)', v_stored_shift, p_shift_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) ROW LOCKS (RF055-B1/B2): lock the target shift, then its bound cash drawer,
  --     with FOR UPDATE in a CONSISTENT order (shift -> drawer) shared by record_payment
  --     and reconcile_shift. State is RE-READ under the locks and validated only after
  --     they are held, so (B1) two concurrent transactions with different
  --     local_operation_ids cannot both pass the guard and double-close, and (B2) a
  --     concurrent record_payment cannot insert a cash sale between the sum and the
  --     close — it must take the same shift lock first, so it either commits before this
  --     sum (and is counted) or blocks until COMMIT and then sees a non-active drawer.
  --     Locks are released at COMMIT. The unlocked load at (b) gave the immutable
  --     opened_by for authorization; status/revision are now the authoritative locked values.
  select s.status, s.revision into v_s_status, v_s_rev
    from public.shifts s where s.id = p_shift_id for update;
  select cds.id, cds.status, cds.revision, cds.opening_float_minor
    into v_drawer_id, v_drawer_status, v_drawer_rev, v_opening
    from public.cash_drawer_sessions cds
    where cds.organization_id = v_org and cds.shift_id = p_shift_id
    for update;
  if not found then
    raise exception 'close_shift: no cash drawer session bound to the shift' using errcode = '42501';
  end if;

  -- (f2) state legality (validated UNDER the locks): shift open, drawer active
  if v_s_status <> 'open' then
    raise exception 'close_shift: shift status % is not a legal close source state (expected open)', v_s_status using errcode = '42501';
  end if;
  if v_drawer_status <> 'active' then
    raise exception 'close_shift: cash drawer status % is not a legal close source state (expected active)', v_drawer_status using errcode = '42501';
  end if;

  -- (g) optimistic concurrency (optional)
  if p_expected_revision is not null and p_expected_revision <> v_s_rev then
    raise exception 'close_shift: revision conflict (expected %, got %)', p_expected_revision, v_s_rev using errcode = '40001';
  end if;

  -- (h) reconciliation math (MONEY §14; A6). expected = opening float + completed
  --     cash sales for this drawer. No refunds/pay-ins/pay-outs in MVP. All _minor.
  select coalesce(sum(p.amount_minor), 0) into v_cash_sales
    from public.payments p
    where p.organization_id = v_org and p.cash_drawer_session_id = v_drawer_id
      and p.method = 'cash' and p.status = 'completed';
  v_expected := v_opening + v_cash_sales;
  v_counted  := p_counted_amount_minor;
  v_variance := v_counted - v_expected;            -- signed: negative = shortage, positive = overage

  -- (i) reason mandatory when variance is non-zero (A7)
  if v_variance <> 0 and btrim(coalesce(p_reason, '')) = '' then
    raise exception 'close_shift: a non-empty reason is required when the variance is non-zero (variance=%)', v_variance using errcode = '42501';
  end if;

  -- (j) mutate: shift open->closed, drawer active->closed; persist amounts on both
  v_new_rev := v_s_rev + 1;
  update public.shifts
    set status = 'closed', expected_total_minor = v_expected, counted_total_minor = v_counted,
        variance_minor = v_variance, close_reason = nullif(btrim(coalesce(p_reason, '')), ''),
        closed_at = now(), closed_by_employee_profile_id = v_emp, revision = v_new_rev
    where id = p_shift_id;
  update public.cash_drawer_sessions
    set status = 'closed', expected_total_minor = v_expected, counted_total_minor = v_counted,
        variance_minor = v_variance, closed_at = now(), revision = v_drawer_rev + 1
    where id = v_drawer_id;

  -- (k) audit: shift.closed + cash_drawer.closed (D-013) with old/new + amounts
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'shift.closed', nullif(btrim(coalesce(p_reason, '')), ''),
    jsonb_build_object('status', 'open', 'revision', v_s_rev),
    jsonb_build_object('shift_id', p_shift_id, 'status', 'closed', 'revision', v_new_rev,
                       'opening_float_minor', v_opening, 'cash_sales_minor', v_cash_sales,
                       'expected_total_minor', v_expected, 'counted_total_minor', v_counted,
                       'variance_minor', v_variance, 'resolved_membership_id', v_membership));
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'cash_drawer.closed', nullif(btrim(coalesce(p_reason, '')), ''),
    jsonb_build_object('status', 'active', 'revision', v_drawer_rev),
    jsonb_build_object('cash_drawer_session_id', v_drawer_id, 'shift_id', p_shift_id, 'status', 'closed',
                       'opening_float_minor', v_opening, 'expected_total_minor', v_expected,
                       'counted_total_minor', v_counted, 'variance_minor', v_variance));

  -- (l) record ledger + return
  v_result := jsonb_build_object(
    'ok', true, 'shift_id', p_shift_id, 'cash_drawer_session_id', v_drawer_id, 'status', 'closed',
    'opening_float_minor', v_opening, 'cash_sales_minor', v_cash_sales,
    'expected_total_minor', v_expected, 'counted_total_minor', v_counted,
    'variance_minor', v_variance, 'revision', v_new_rev);
  insert into public.shift_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, shift_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'close_shift', p_shift_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;
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
        'apply_discount', app.cashier_capability_allowed(m.role, m.permissions, 'apply_discount'),
        'void_order',     app.cashier_capability_allowed(m.role, m.permissions, 'void_order'),
        'close_shift',    app.cashier_capability_allowed(m.role, m.permissions, 'close_shift'))
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

comment on function app.apply_discount(uuid, uuid, uuid, text, text, uuid, text, bigint, text, integer) is
  'RF-053 (API_CONTRACT §4.5, D-011) SECURITY DEFINER discount RPC. STAFF-CASHIER-PERMISSIONS-001: faithful re-creation of the RF-053 body with ONLY the cashier authorization changed -- a cashier may now apply discounts BY DEFAULT (app.cashier_capability_allowed) unless permissions->>''apply_discount''=''false''; manager/restaurant_owner/org_owner grants, discount math (integer minor units, clamp/round), reason, order-state/scope checks, denial audit (order.discount_denied) and idempotency are otherwise verbatim. Aligns with MONEY_AND_TAX_SPEC §4.5 (a cashier may apply discounts).';

comment on function app.void_order(uuid, uuid, uuid, text, text, integer) is
  'RF-053/RF-062 (API_CONTRACT §4.6, D-011/D-023/D-024) SECURITY DEFINER void RPC. STAFF-CASHIER-PERMISSIONS-001: faithful re-creation of the RF-062 body with ONLY the cashier authorization changed -- a cashier may now void an UNPAID order BY DEFAULT (app.cashier_capability_allowed) unless permissions->>''void_order''=''false''. The RF-062 completed-payment guard is reproduced verbatim: a PAID order is still refused (order.void_denied + {ok:false,error:permission_denied,detail:order_has_completed_payment}); paid void/refund stays deferred. FOR UPDATE lock, mandatory reason, order.voided audit and idempotency are verbatim. Updates the UNPAID-void clause of mandatory test T-006 (SECURITY_AND_THREAT_MODEL.md); the PAID-void protection is preserved.';

comment on function app.close_shift(uuid, uuid, uuid, text, bigint, text, integer) is
  'RF-055 (D-028, API_CONTRACT) SECURITY DEFINER shift close/count RPC. STAFF-CASHIER-PERMISSIONS-001: faithful re-creation of the RF-055 body with ONLY the cashier authorization changed -- a cashier may close their OWN shift (opened_by = actor, D-028) unless permissions->>''close_shift''=''false''; managers/owners still close any shift; reconciliation stays separate. The membership SELECT now also loads permissions. Ownership, variance/cash-count, state-machine legality, shift.close_denied audit and idempotency are verbatim. A cashier still cannot close another person''s / another branch''s shift.';

comment on function app.list_staff(uuid, uuid, uuid) is
  'MVP staff provisioning list (RF-160/D-033). STAFF-CASHIER-PERMISSIONS-001: faithful re-creation adding a per-row ''capabilities'' object {apply_discount, void_order, close_shift} = app.cashier_capability_allowed(...) so the owner/manager Dashboard can show a cashier''s EFFECTIVE capability switches. Non-cashier rows report false (the toggles apply only to cashiers). Owner/manager-only, has_pin remains a boolean, read-only, otherwise verbatim.';

-- ----------------------------------------------------------------------------
-- app.set_staff_capabilities -- owner/manager sets a target CASHIER's deny
-- overrides for the three default-ON capabilities. Deny-only storage: a disabled
-- switch stores permissions->>key='false'; an enabled switch REMOVES the key
-- (back to the role default ON). Tenant+branch+role-rank scoped (mirrors
-- create_staff_member): the caller must cover the target scope AND rank >=
-- manager AND strictly outrank the target. Cross-tenant / not-found merge into
-- one indistinguishable 42501 (no R-003 oracle). Audited + idempotent.
-- ----------------------------------------------------------------------------
create or replace function app.set_staff_capabilities(
  p_client_request_id   uuid,
  p_employee_profile_id uuid,
  p_apply_discount      boolean,
  p_void_order          boolean,
  p_close_shift         boolean
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
  v_fp := md5(jsonb_build_object('emp', p_employee_profile_id,
              'apply_discount', p_apply_discount, 'void_order', p_void_order,
              'close_shift', p_close_shift)::text);
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

  -- (f) claim idempotency BEFORE mutating (race-safe), then a SCOPE-PREDICATED
  --     update (the predicates re-assert the membership's own scope; the UPDATE
  --     does not rely only on the prior SELECT) + audit with OLD and NEW raw
  --     permissions and effective values.
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false,
                'entity', 'employee_profile', 'employee_profile_id', p_employee_profile_id,
                'membership_id', v_membership,
                'capabilities', jsonb_build_object('apply_discount', p_apply_discount,
                  'void_order', p_void_order, 'close_shift', p_close_shift));
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
        'apply_discount', app.cashier_capability_allowed('cashier', v_perms, 'apply_discount'),
        'void_order',     app.cashier_capability_allowed('cashier', v_perms, 'void_order'),
        'close_shift',    app.cashier_capability_allowed('cashier', v_perms, 'close_shift'))),
    jsonb_build_object('employee_profile_id', p_employee_profile_id, 'membership_id', v_membership,
      'permissions', v_new_perms,
      'capabilities', jsonb_build_object('apply_discount', p_apply_discount,
        'void_order', p_void_order, 'close_shift', p_close_shift)));

  return v_result;
end;
$$;

comment on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean) is
  'STAFF-CASHIER-PERMISSIONS-001 SECURITY DEFINER RPC: owner/manager sets a target CASHIER''s deny overrides for the three default-ON capabilities. Deny-only storage (false to deny, key removed to allow/default). Tenant+branch+role-rank scoped (mirrors create_staff_member: covering membership AND rank>=manager AND strictly outrank the target); cross-tenant/not-found collapse to one 42501 (no oracle). Refuses non-cashier targets. Audited (staff.capabilities_updated / staff.capabilities_denied) + idempotent (management_request_results).';

-- Thin public SECURITY INVOKER wrapper (RF-064/RF-123 pattern; the caller's
-- EXECUTE on app.* is reused).
create or replace function public.set_staff_capabilities(
  p_client_request_id uuid, p_employee_profile_id uuid,
  p_apply_discount boolean, p_void_order boolean, p_close_shift boolean)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_staff_capabilities(p_client_request_id, p_employee_profile_id, p_apply_discount, p_void_order, p_close_shift); $$;

-- ----------------------------------------------------------------------------
-- STAFF-CASHIER-PERMISSIONS-001: ATOMIC cashier creation with initial capability
-- deny overrides. Extends app.create_staff_member with an OPTIONAL p_capabilities
-- jsonb (deny-only, cashier-only, fail-closed) written in the SAME transaction as
-- the app_user + membership + employee_profile -- so a restricted cashier can
-- NEVER exist with broader-than-requested permissions (no fail-open create-then-
-- set). Faithful re-creation of the mvp_staff_pin_provisioning body with ONLY the
-- signature, the capability validation, the fingerprint and the membership INSERT
-- changed. Drop the 6-arg overload (public first -> app) so the single 7-arg
-- function (p_capabilities default null) serves ALL callers: a 6-arg call uses the
-- default => current behavior (backward compatible).
-- ----------------------------------------------------------------------------
drop function if exists public.create_staff_member(uuid, uuid, uuid, uuid, text, text);
drop function if exists app.create_staff_member(uuid, uuid, uuid, uuid, text, text);

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
    if exists (
         select 1 from jsonb_each(p_capabilities) e
         where e.key not in ('apply_discount', 'void_order', 'close_shift')
            or jsonb_typeof(e.value) <> 'string'
            or e.value <> '"false"'::jsonb) then
      raise exception 'create_staff_member: capabilities may only DENY (JSON string "false") the keys apply_discount/void_order/close_shift' using errcode = '42501';
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
          'apply_discount', app.cashier_capability_allowed('cashier', v_perms, 'apply_discount'),
          'void_order',     app.cashier_capability_allowed('cashier', v_perms, 'void_order'),
          'close_shift',    app.cashier_capability_allowed('cashier', v_perms, 'close_shift'))
        else null end));
  return v_result;
end;
$$;

comment on function app.create_staff_member(uuid, uuid, uuid, uuid, text, text, jsonb) is
  'MVP staff provisioning (D-004/D-011/D-013, RF-112 pattern), STAFF-CASHIER-PERMISSIONS-001: creates a PIN-only staff operator in ONE transaction -- app_user (synthetic identifier email) + ACTIVE branch-scoped membership + employee_profile (pin NULL). Caller must be manager+ covering the target scope AND strictly outrank the assigned role (cashier/kitchen_staff/manager). OPTIONAL p_capabilities jsonb persists initial CASHIER deny overrides ATOMICALLY on the membership (deny-only: only role=cashier, only keys apply_discount/void_order/close_shift, only value ''false''; anything else => 42501 and NOTHING is created -- no fail-open create-then-set). p_capabilities null/{} => permissions {} (all default ON). rank 0 => 42501; in-scope rank denial => audited staff.create_denied + permission_denied. Idempotent via management_request_results (fingerprint includes capabilities).';

-- Thin public SECURITY INVOKER wrapper (7-arg; p_capabilities default null keeps
-- 6-arg callers working).
create or replace function public.create_staff_member(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_display_name text, p_role text, p_capabilities jsonb default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.create_staff_member(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_display_name, p_role, p_capabilities); $$;

-- ----------------------------------------------------------------------------
-- Grants (D-011): authenticated only; never anon/service_role. CREATE OR REPLACE
-- preserves existing ACLs, but the re-asserted revoke/grant keep this migration
-- self-describing for the re-created functions, and provision the new ones.
-- ----------------------------------------------------------------------------
revoke all on function app.apply_discount(uuid, uuid, uuid, text, text, uuid, text, bigint, text, integer) from public;
revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer)                                from public;
revoke all on function app.close_shift(uuid, uuid, uuid, text, bigint, text, integer)                       from public;
revoke all on function app.list_staff(uuid, uuid, uuid)                                                     from public;
revoke all on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean)                    from public;
revoke all on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean)                 from public;
revoke all on function app.create_staff_member(uuid, uuid, uuid, uuid, text, text, jsonb)                    from public;
revoke all on function public.create_staff_member(uuid, uuid, uuid, uuid, text, text, jsonb)                 from public;

grant execute on function app.apply_discount(uuid, uuid, uuid, text, text, uuid, text, bigint, text, integer) to authenticated;
grant execute on function app.void_order(uuid, uuid, uuid, text, text, integer)                                to authenticated;
grant execute on function app.close_shift(uuid, uuid, uuid, text, bigint, text, integer)                       to authenticated;
grant execute on function app.list_staff(uuid, uuid, uuid)                                                     to authenticated;
grant execute on function app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean)                    to authenticated;
grant execute on function public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean)                 to authenticated;
grant execute on function app.create_staff_member(uuid, uuid, uuid, uuid, text, text, jsonb)                    to authenticated;
grant execute on function public.create_staff_member(uuid, uuid, uuid, uuid, text, text, jsonb)                 to authenticated;

-- ============================================================================
-- DOWN (manual; migrations are forward-only, cleanliness gate = `supabase db reset`):
--   drop function if exists public.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean);
--   drop function if exists app.set_staff_capabilities(uuid, uuid, boolean, boolean, boolean);
--   -- app.apply_discount / app.void_order / app.close_shift / app.list_staff revert by
--   -- re-running their prior migrations; app.cashier_capability_allowed:
--   drop function if exists app.cashier_capability_allowed(text, jsonb, text);
-- ============================================================================
