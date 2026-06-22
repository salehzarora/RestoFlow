-- ============================================================================
-- RF-053 — apply_discount / void_order (authorize + audit)
-- ============================================================================
-- Two SECURITY DEFINER mutation RPCs on the RF-052 order tables (API_CONTRACT
-- §4.5 apply_discount, §4.6 void_order). Builds on RF-052 (orders/order_items +
-- submit_order + app.order_parse_minor), RF-017 (append-only audit_events),
-- RF-016/051 (PIN session + app.is_pin_session_valid). Additive, FORWARD-ONLY;
-- never edits a prior migration.
--
-- WHAT THIS DOES
--   1. Adds void_reason (text) to orders + order_items (DOMAIN_MODEL §6.1/§6.2;
--      RF-052 omitted them). Additive ALTER (A5).
--   2. Adds order_operations — a minimal tenant-scoped idempotency ledger for
--      mutation replay (D-022). Unique (org, device, local_operation_id, action)
--      so a replay returns the stored result and never double-applies/double-audits (A4).
--   3. app.void_order(...) — authorize via PIN session, require a non-empty reason,
--      move the order submitted/accepted/preparing/ready/served -> voided (cascade
--      its items -> voided), write an append-only order.voided audit. An UNAUTHORIZED
--      cashier void writes an order.void_denied audit and RETURNS a denial (no raise,
--      so the audit persists), with NO state change (A1/A3, T-006).
--   4. app.apply_discount(...) — order/item-level, fixed (_minor) or percentage
--      (basis points), recompute totals from snapshots only (never the live menu;
--      D-008), integer _minor, round half-away (numeric transient), clamp >= 0,
--      write an order.discount_applied audit (A6).
--
-- DECISIONS: D-007 integer _minor; D-008 snapshot/never-recompute-from-menu;
--   D-011 SECURITY DEFINER RPC; D-012 four layers; D-013 append-only audit
--   (success AND denied); D-022 idempotency; D-024 completed is TERMINAL.
--
-- OUT OF SCOPE: RF-054 payment/receipt numbering (the "no completed payment"
--   precondition is N/A — no payment tables exist; A2); refunds/completed-payment
--   reversal; void_payment; standalone void_item; RF-055 shift; RF-056/057 sync;
--   route_to_kitchen + kitchen tables (the void->kitchen cascade is N/A); RF-059
--   full role matrix; tax computation; discount stacking (§4.3 PROPOSED); any
--   UI/Dart/config/remote/secrets/service-role.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. void_reason columns (additive; A5). Set only when the row is voided.
-- ----------------------------------------------------------------------------
alter table public.orders      add column void_reason text;
alter table public.order_items add column void_reason text;

comment on column public.orders.void_reason      is 'RF-053: reason captured when the order is voided (mandatory at void time; null otherwise). DOMAIN_MODEL §6.1.';
comment on column public.order_items.void_reason is 'RF-053: reason captured when the item is voided (set on cascade from order void). DOMAIN_MODEL §6.2.';

-- ----------------------------------------------------------------------------
-- 2. order_operations — mutation idempotency ledger (D-022). Tenant+branch
--    scoped; one row per (org, device, local_operation_id, action). Stores the
--    result envelope so a replay returns it verbatim. Written ONLY by the RF-053
--    SECURITY DEFINER RPCs; authenticated has SELECT only (writes revoked).
-- ----------------------------------------------------------------------------
create table order_operations (
  id                 uuid        not null default gen_random_uuid(),
  organization_id    uuid        not null references organizations (id) on delete restrict,
  restaurant_id      uuid        not null,
  branch_id          uuid        not null,
  device_id          uuid        not null,
  local_operation_id text        not null,
  action             text        not null check (action in ('void_order', 'apply_discount')),
  order_id           uuid        not null,
  result             jsonb       not null,                 -- stored success/denial envelope, replayed verbatim
  created_at         timestamptz not null default now(),
  primary key (id),
  unique (organization_id, device_id, local_operation_id, action),   -- idempotency key (D-022)
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, order_id)
    references orders (organization_id, id) on delete restrict
);

comment on table order_operations is
  'RF-053: mutation idempotency ledger (D-022). One row per (organization_id, device_id, local_operation_id, action); the RPC returns the stored result on replay so a void/discount is never double-applied and no audit row is duplicated. Written only by the RF-053 SECURITY DEFINER RPCs; authenticated SELECT-only.';

create index order_operations_branch_idx on order_operations (organization_id, restaurant_id, branch_id);
create index order_operations_order_idx  on order_operations (organization_id, order_id);

alter table order_operations enable row level security;
alter table order_operations force  row level security;

create policy order_operations_scoped on order_operations
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

grant select on order_operations to authenticated;
revoke insert, update, delete on order_operations from authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.void_order — authorize + reason + state-legality + cascade + audit.
--    Actor/org/restaurant/branch derived from the PIN session, never client input.
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

  -- (b) load the order; it MUST be in the actor's org + branch (no cross-tenant)
  select o.organization_id, o.branch_id, o.status, o.revision
    into v_o_org, v_o_branch, v_o_status, v_o_rev
    from public.orders o where o.id = p_order_id;
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
  'RF-053 (API_CONTRACT §4.6, D-011) SECURITY DEFINER RPC: voids a pre-completion order. Actor/scope from the PIN session (never client). Authorized for manager/restaurant_owner/org_owner or a cashier with permissions.void_order=true; an unauthorized cashier gets an order.void_denied audit + a returned permission_denied (no raise, so the audit persists) with NO state change (A1/A3/T-006). Requires a non-empty reason; legal sources submitted/accepted/preparing/ready/served (completed/cancelled/voided/draft rejected, D-024). Cascades items -> voided; writes order.voided audit (D-013). Idempotent via order_operations (D-022).';

revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from public;
grant execute on function app.void_order(uuid, uuid, uuid, text, text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. app.apply_discount — order/item-level, fixed (_minor) or percentage (bp).
--    Recompute from snapshots only; integer _minor; round half-away; clamp >= 0.
-- ----------------------------------------------------------------------------
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
          or (v_role = 'cashier' and coalesce(v_m_perms ->> 'apply_discount', '') = 'true')) then
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
  'RF-053 (API_CONTRACT §4.5, D-011) SECURITY DEFINER RPC: applies an order/item-level discount (fixed _minor or percentage basis points). Actor/scope from the PIN session; manager+/cashier-with-permissions.apply_discount=true (A6). Requires a non-empty reason; non-terminal orders only. Recomputes totals from persisted snapshots ONLY (never the live menu; D-008), integer _minor, half-away rounding (round(numeric) is half-away-from-zero — numeric, not float8 banker''s), clamped >= 0. A denied caller gets an order.discount_denied audit + a returned permission_denied (no raise) with NO state change. Writes order.discount_applied audit (D-013). Idempotent via order_operations (D-022).';

revoke all on function app.apply_discount(uuid, uuid, uuid, text, text, uuid, text, bigint, text, integer) from public;
grant execute on function app.apply_discount(uuid, uuid, uuid, text, text, uuid, text, bigint, text, integer) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop function if exists app.apply_discount(uuid, uuid, uuid, text, text, uuid, text, bigint, text, integer);
-- drop function if exists app.void_order(uuid, uuid, uuid, text, text, integer);
-- drop table if exists order_operations;
-- alter table public.order_items drop column if exists void_reason;
-- alter table public.orders      drop column if exists void_reason;
-- ============================================================================
