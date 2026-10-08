-- ============================================================================
-- POS-ORDER-DETAIL-IDS-001 — pos_order_detail exposes each modifier's option
-- id and order-time display-order ranks (ADDITIVE keys only).
-- ORDER-EDIT slice 2 (API_CONTRACT §4.45.10; ORDER_EDIT_DESIGN §8.6 / §10).
--
-- WHY. Editing a sent order (ORDER-EDIT-001E) must rebuild each cart line from
-- the AUTHORITATIVE detail: which option rows are selected (to diff old against
-- new and to keep the order-time price of every kept option) and in which order
-- they print. The detail already carries order_item_id, menu_item_id, status and
-- line_discount_minor per item, but per modifier it carries only names, price,
-- quantity and meat — not the option id, and not the MENU-ORDER-001 ranks it
-- already sorts by.
--
-- WHAT (byte-faithful re-emit of the 20260826090000 (114B.5B) body plus):
--   items[].modifiers[].modifier_option_id                     = m.modifier_option_id
--   items[].modifiers[].modifier_group_display_order_snapshot  = m.modifier_group_display_order_snapshot
--   items[].modifiers[].modifier_option_display_order_snapshot = m.modifier_option_display_order_snapshot
--
-- CONTRACT:
--   * ADDITIVE — every existing key, value and ordering is byte-unchanged; old
--     POS builds ignore the new keys;
--   * NON-MONEY — an opaque reference uuid (NOT NULL, non-FK, RF-052) and two
--     integer ranks (NOT NULL DEFAULT 0, captured at submit by the MENU-ORDER-001
--     trigger as coalesce(display_order, 0)). 0 means only that no non-zero rank
--     was captured: the option / group was missing at submit, the row predates
--     MENU-ORDER-001, or the option / group still had the default display_order
--     0 (never drag-reordered). The ranks are a SORT KEY only, never a liveness
--     signal — whether an option still exists is decided by modifier_option_id
--     against the menu. Nothing is re-derived from the live menu (D-008);
--   * the session-scoped auth envelopes (invalid_session / invalid_device_type
--     / permission_denied / order_not_found, R-003), SECURITY DEFINER +
--     search_path='' + STABLE, the public wrapper and the grants are UNCHANGED.
--     No table/column/index/policy change. No new RPC.
-- ============================================================================

create or replace function app.pos_order_detail(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_order_id       uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_dsid        uuid;
  v_membership  uuid;
  v_ds_device   uuid;
  v_ds_active   boolean;
  v_ds_revoked  timestamptz;
  v_pairing     text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_device_type text;
  v_order       jsonb;
  v_items       jsonb;
  v_rounds      jsonb;
  v_payment     jsonb;
begin
  -- (a) THE CANONICAL PIN-SESSION PREAMBLE (pos_order_snapshots parity):
  --     every structural failure collapses to ONE indistinguishable envelope.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found or not app.is_pin_session_valid(p_pin_session_id) then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found
     or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active')
     or v_ds_device is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_detail');
  end if;

  -- (b) POS-class device + price-capable POS role (this read carries money).
  select d.device_type into v_device_type
    from public.devices d
    where d.id = p_device_id and d.organization_id = v_org;
  if v_device_type is distinct from 'pos' then
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'entity', 'order_detail');
  end if;
  if v_role not in ('cashier', 'manager', 'restaurant_owner', 'org_owner') then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'order_detail');
  end if;

  -- (c) the order — SESSION org+branch scope only. A nonexistent and a
  --     foreign-scope order collapse to the SAME envelope (no oracle, R-003).
  select jsonb_build_object(
           'order_id',             o.id,
           'order_code',           '#' || upper(right(replace(o.id::text, '-', ''), 6)),
           'order_type',           o.order_type,
           'status',               o.status,
           'revision',             o.revision,
           'table_label',          tbl.label,
           'customer_name',        o.customer_name,
           'customer_phone',       o.customer_phone,
           'currency_code',        o.currency_code,
           'subtotal_minor',       o.subtotal_minor,
           'discount_total_minor', o.discount_total_minor,
           'tax_total_minor',      o.tax_total_minor,
           'grand_total_minor',    o.grand_total_minor,
           'receipt_number',       o.receipt_number,
           'created_at',           o.created_at,
           'updated_at',           o.updated_at)
    into v_order
    from public.orders o
    left join public.tables tbl
      on  tbl.organization_id = o.organization_id
      and tbl.id              = o.table_id
    where o.id              = p_order_id
      and o.organization_id = v_org
      and o.branch_id       = v_branch
      and o.deleted_at is null;
  if v_order is null then
    return jsonb_build_object('ok', false, 'error', 'order_not_found', 'entity', 'order_detail');
  end if;

  -- (d) every ACTIVE customer-visible item, with modifiers and round
  --     membership (NULL service_round_id = the original submission).
  --     MENU-ORDER-001: carries + orders by the menu-configured print snapshots.
  --     KIOSK-PRINT-114B.5B: + the ALLOWLISTED order-time kitchen snapshots
  --     (per unit; NULL when never stored; nothing re-derived).
  select coalesce(jsonb_agg(jsonb_build_object(
           'order_item_id',             oi.id,
           'menu_item_id',              oi.menu_item_id,
           'menu_item_name_snapshot',   oi.menu_item_name_snapshot,
           'quantity',                  oi.quantity,
           'unit_price_minor_snapshot', oi.unit_price_minor_snapshot,
           'line_discount_minor',       oi.line_discount_minor,
           'line_total_minor',          oi.line_total_minor,
           -- MENU-ORDER-001: the menu-configured print-order snapshots so a
           -- cross-device reprint matches the live receipt (the client sorts too).
           'category_display_order_snapshot', oi.category_display_order_snapshot,
           'item_display_order_snapshot',     oi.item_display_order_snapshot,
           'line_position',             oi.line_position,
           'status',                    oi.status,
           'notes',                     oi.notes,
           'item_size_snapshot',        oi.item_size_snapshot,
           'item_variant_snapshot',     oi.item_variant_snapshot,
           'service_round_id',          oi.service_round_id,
           'round_number',              r.round_number,
           -- 114B.5B: the item's PER-UNIT prep snapshot through the 017
           -- allowlist (the SAME projection the dispatch payload carries).
           'prep_snapshot',             app.kitchen_prep_projection(oi.prep_snapshot),
           'modifiers',                 coalesce(mods.list, '[]'::jsonb)
         ) order by oi.category_display_order_snapshot asc,
                    oi.item_display_order_snapshot asc,
                    oi.line_position asc,
                    oi.created_at asc, oi.id asc), '[]'::jsonb)
    into v_items
    from public.order_items oi
    left join public.order_service_rounds r
      on  r.organization_id = oi.organization_id
      and r.id              = oi.service_round_id
    left join lateral (
      select jsonb_agg(jsonb_build_object(
               'modifier_name_snapshot', m.modifier_name_snapshot,
               'option_name_snapshot',   m.option_name_snapshot,
               'price_minor_snapshot',   m.price_minor_snapshot,
               'quantity',               m.quantity,
               -- 114B.5B: the option's PER-MODIFIER-UNIT meat contribution
               -- through the 019 allowlist (the SAME projection the dispatch
               -- payload carries); NULL when the option contributes nothing.
               'meat_snapshot',          app.kitchen_modifier_prep_projection(m.meat_snapshot),
               -- POS-ORDER-DETAIL-IDS-001 (ORDER-EDIT slice 2): the option's
               -- non-FK reference id and its order-time display-order ranks
               -- (MENU-ORDER-001 trigger-stamped; until now used only in the
               -- ORDER BY below), so a POS can rebuild the line faithfully.
               'modifier_option_id',                     m.modifier_option_id,
               'modifier_group_display_order_snapshot',  m.modifier_group_display_order_snapshot,
               'modifier_option_display_order_snapshot', m.modifier_option_display_order_snapshot
             ) order by m.modifier_group_display_order_snapshot asc,
                        m.modifier_option_display_order_snapshot asc,
                        m.line_position asc,
                        m.created_at asc, m.id asc) as list
        from public.order_item_modifiers m
        where m.organization_id = oi.organization_id
          and m.order_item_id   = oi.id
          and m.deleted_at is null
    ) mods on true
    where oi.organization_id = v_org
      and oi.order_id        = p_order_id
      and oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled');

  -- (e) the round list (voided rounds included — status says so).
  select coalesce(jsonb_agg(jsonb_build_object(
           'round_id',     r.id,
           'round_number', r.round_number,
           'status',       r.status,
           'ready_at',     r.ready_at,
           'created_at',   r.created_at
         ) order by r.round_number asc), '[]'::jsonb)
    into v_rounds
    from public.order_service_rounds r
    where r.organization_id = v_org
      and r.order_id        = p_order_id
      and r.deleted_at is null;

  -- (f) the (at most one) completed payment — enough for a faithful reprint.
  select jsonb_build_object(
           'payment_id',     p.id,
           'payment_status', p.status,
           'method',         p.method,
           'amount_minor',   p.amount_minor,
           'tendered_minor', p.tendered_minor,
           'change_minor',   p.change_minor,
           'receipt_number', p.receipt_number,
           'created_at',     p.created_at)
    into v_payment
    from public.payments p
    where p.organization_id = v_org
      and p.order_id        = p_order_id
      and p.status          = 'completed'
      and p.deleted_at is null
    limit 1;

  return jsonb_build_object(
    'ok', true, 'entity', 'order_detail', 'server_ts', now(),
    'order',   v_order,
    'items',   v_items,
    'rounds',  v_rounds,
    'payment', v_payment);
end;
$$;

comment on function app.pos_order_detail(uuid, uuid, uuid) is
  'PSC-001C + POS-CUSTOMER-PHONE-DINEIN-CLOSE-001 + KIOSK-PRINT-114B.5B (read-only): the AUTHORITATIVE POS order detail. Byte-faithful re-emit of the 20260802090000 body plus two ADDITIVE money-free keys: items[].prep_snapshot (app.kitchen_prep_projection of the PER-UNIT order-time prep) and items[].modifiers[].meat_snapshot (app.kitchen_modifier_prep_projection of the PER-MODIFIER-UNIT meat) — the same allowlists the dispatch payload uses; NULL when never stored, never re-derived (D-008). SESSION org+branch scope; a nonexistent and a foreign-scope order collapse to the same order_not_found envelope (R-003). No anon/service_role. POS-ORDER-DETAIL-IDS-001: + three ADDITIVE non-money keys per modifier — modifiers[].modifier_option_id (the non-FK option reference) and modifiers[].modifier_group_display_order_snapshot / modifier_option_display_order_snapshot (the MENU-ORDER-001 order-time ranks the ORDER BY already uses); nothing else changed.';

-- ACL parity (CREATE OR REPLACE preserves grants; re-issued explicitly to
-- match the shipped grant exactly). The public wrapper is untouched.
revoke all on function app.pos_order_detail(uuid, uuid, uuid) from public;
revoke all on function app.pos_order_detail(uuid, uuid, uuid) from anon;
grant execute on function app.pos_order_detail(uuid, uuid, uuid) to authenticated;
