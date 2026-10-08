-- ORDER-EDIT-001B — the ORDER-EDIT read surface of app.pos_order_detail
-- (API_CONTRACT §4.45.10, §4.30c parity, §4.46 voided-order rule; migration
-- 20261008190000_order_edit_001b_read_surface.sql), driven through the
-- public wrapper and real edits / acks / voids (public.sync_push, app.void_order):
--   A. per item: unit_status (order status for the original ticket, round
--      status for a round line), legacy (app.order_item_is_legacy_priced),
--      edit_id (NULL for original lines, the writing edit's id otherwise)
--   B. per order: dispatch_mode, kitchen_channel, edit_count, has_active_round
--      (+ parity with app.pos_order_snapshots in targeted mode)
--   C. edits[]: ordering, exact money-free / identifier-free key set,
--      kitchen_ack_pending (required+unacked / acked / not required / voided)
--   D. branch_features mirrors the branch switches; printer_only -> 'paper';
--      a soft-deleted session branch -> kitchen_channel NULL, switches FALSE
--   E. unchanged behaviour: retired lines excluded, totals / order_code /
--      status, order_not_found, invalid_device_type, permission_denied, no audit
begin;
set local search_path to extensions, public, pg_catalog;

select plan(38);

-- ===== fixture ==============================================================
-- Org B1D0: one KDS-mode branch with order editing ON (finished-food switch
-- OFF); one POS + one KDS device. PIN sessions: cashier (9a), manager (9b) and
-- kitchen_staff (9d) on the POS; kitchen_staff (9c) and cashier (9e) on the KDS.
insert into organizations (id, name, slug, default_currency) values
  ('b1d00000-0000-0000-0000-0000000000a0', 'Org Edit Detail', 'org-edit-detail-001b', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000a0', 'Rest Edit Detail');
insert into branches (id, organization_id, restaurant_id, name, order_edit_enabled) values
  ('b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'Branch Edit Detail', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('b1d00000-0000-0000-0000-0000000000d1', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'pos'),
  ('b1d00000-0000-0000-0000-0000000000d2', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('b1d00000-0000-0000-0000-0000000000f1', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-0000000000d1', 'active'),
  ('b1d00000-0000-0000-0000-0000000000f2', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-0000000000d2', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('b1d00000-0000-0000-0000-00000000005a', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-0000000000d1', 'b1d00000-0000-0000-0000-0000000000f1'),
  ('b1d00000-0000-0000-0000-00000000005b', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-0000000000d2', 'b1d00000-0000-0000-0000-0000000000f2');
insert into app_users (id, email) values
  ('b1d00000-0000-0000-0000-00000000006a', 'detail-cashier@example.test'),
  ('b1d00000-0000-0000-0000-00000000006b', 'detail-manager@example.test'),
  ('b1d00000-0000-0000-0000-00000000006c', 'detail-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('b1d00000-0000-0000-0000-00000000007a', 'b1d00000-0000-0000-0000-00000000006a', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('b1d00000-0000-0000-0000-00000000007b', 'b1d00000-0000-0000-0000-00000000006b', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb),
  ('b1d00000-0000-0000-0000-00000000007c', 'b1d00000-0000-0000-0000-00000000006c', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'kitchen_staff', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('b1d00000-0000-0000-0000-00000000008a', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-00000000006a', 'b1d00000-0000-0000-0000-00000000007a', 'Dina Cashier'),
  ('b1d00000-0000-0000-0000-00000000008b', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-00000000006b', 'b1d00000-0000-0000-0000-00000000007b', 'Eli Manager'),
  ('b1d00000-0000-0000-0000-00000000008c', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-00000000006c', 'b1d00000-0000-0000-0000-00000000007c', 'Fay Kitchen');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  -- POS: cashier (9a), manager (9b), kitchen_staff (9d)
  ('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-00000000005a', 'b1d00000-0000-0000-0000-00000000008a', 'b1d00000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('b1d00000-0000-0000-0000-00000000009b', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-00000000005a', 'b1d00000-0000-0000-0000-00000000008b', 'b1d00000-0000-0000-0000-00000000007b', now() + interval '1 hour'),
  ('b1d00000-0000-0000-0000-00000000009d', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-00000000005a', 'b1d00000-0000-0000-0000-00000000008c', 'b1d00000-0000-0000-0000-00000000007c', now() + interval '1 hour'),
  -- KDS: kitchen_staff (9c), cashier (9e)
  ('b1d00000-0000-0000-0000-00000000009c', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-00000000005b', 'b1d00000-0000-0000-0000-00000000008c', 'b1d00000-0000-0000-0000-00000000007c', now() + interval '1 hour'),
  ('b1d00000-0000-0000-0000-00000000009e', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', 'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-00000000005b', 'b1d00000-0000-0000-0000-00000000008a', 'b1d00000-0000-0000-0000-00000000007a', now() + interval '1 hour');

-- Menu: Burger 4000, Fries 1500, Cola 800 (no menu modifiers; the stored
-- order_item_modifiers rows below carry their own price snapshots).
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('b1d00000-0000-0000-0000-0000000000c1', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('b1d00000-0000-0000-0000-000000001001', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', null, 'b1d00000-0000-0000-0000-0000000000c1', 'Burger', 4000, 'ILS', 1),
  ('b1d00000-0000-0000-0000-000000001002', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', null, 'b1d00000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 2),
  ('b1d00000-0000-0000-0000-000000001003', 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1', null, 'b1d00000-0000-0000-0000-0000000000c1', 'Cola', 800, 'ILS', 3);

-- Builders (direct inserts as the fixture role; the line-position and
-- display-order insert triggers still fire).
create function pg_temp.mk_order(p_id uuid, p_status text, p_dispatch text default 'kds') returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, ready_at, dispatch_mode)
  values (p_id, 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1',
    'b1d00000-0000-0000-0000-0000000000ab', 'b1d00000-0000-0000-0000-0000000000d1',
    'b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000008a',
    'b1d00000-0000-0000-0000-00000000007a', 'dine_in', 'ILS', 0, 0, 'submit-' || p_id::text, p_status,
    case when p_status in ('ready', 'served') then now() - interval '5 minutes' end, p_dispatch);
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_total bigint, p_round uuid default null) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor, service_round_id)
  values (p_id, 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1',
    'b1d00000-0000-0000-0000-0000000000ab', p_order, p_menu, p_qty, p_name, p_unit, 0, p_total, p_round);
$$;
create function pg_temp.mk_mod(p_item uuid, p_name text, p_price bigint) returns void
language sql as $$
  insert into order_item_modifiers (organization_id, restaurant_id, branch_id, order_item_id,
    modifier_option_id, modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity)
  values ('b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1',
    'b1d00000-0000-0000-0000-0000000000ab', p_item, 'b1d00000-0000-0000-0000-00000000e003',
    'Extras', p_name, p_price, 1);
$$;
create function pg_temp.mk_round(p_id uuid, p_order uuid, p_no int, p_status text,
  p_deleted boolean default false) returns void
language sql as $$
  insert into order_service_rounds (id, organization_id, restaurant_id, branch_id, order_id, round_number,
    status, device_id, opened_by_employee_profile_id, ready_at, deleted_at)
  values (p_id, 'b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000000a1',
    'b1d00000-0000-0000-0000-0000000000ab', p_order, p_no, p_status,
    'b1d00000-0000-0000-0000-0000000000d1', 'b1d00000-0000-0000-0000-00000000008a',
    case when p_status in ('ready', 'served') then now() - interval '1 minute' end,
    case when p_deleted then now() end);
$$;
-- re-roll an order's stored totals from its live lines (tax off, no discount)
create function pg_temp.settle_totals(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, grand_total_minor = s.t - o.discount_total_minor
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- one order.edit through public.sync_push (default: the POS)
create function pg_temp.edit(p_pin uuid, p_op text, p_order uuid, p_payload jsonb,
  p_dev uuid default 'b1d00000-0000-0000-0000-0000000000d1') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
    'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;
-- one order.edit_ack (up to edit N) through public.sync_push (default: the KDS)
create function pg_temp.ack(p_pin uuid, p_op text, p_order uuid, p_n int,
  p_dev uuid default 'b1d00000-0000-0000-0000-0000000000d2') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit_ack', 'target_entity', 'order',
    'target_id', p_order, 'payload', jsonb_build_object('order_id', p_order, 'up_to_edit_number', p_n)))) -> 'results' -> 0;
$$;
-- the id of edit N of an order
create function pg_temp.eid(p_order uuid, p_n int) returns uuid
language sql stable as $$
  select id from order_edits where order_id = p_order and edit_number = p_n;
$$;
-- the detail read through the public wrapper (default: the POS)
create function pg_temp.det(p_pin uuid, p_order uuid,
  p_dev uuid default 'b1d00000-0000-0000-0000-0000000000d1') returns jsonb
language sql as $$
  select public.pos_order_detail(p_pin, p_dev, p_order);
$$;
-- stored detail reads, by label
create temp table t_det (k text primary key, r jsonb);
create function pg_temp.r(p_k text) returns jsonb
language sql as $$ select r from t_det where k = p_k; $$;
-- one item of a stored read, by order_item_id
create function pg_temp.it(p_k text, p_item uuid) returns jsonb
language sql as $$
  select x from t_det d, jsonb_array_elements(d.r -> 'items') x
   where d.k = p_k and x ->> 'order_item_id' = p_item::text;
$$;

-- Orders:
--   O1 (a001) served; original Cola + a round 2 in PREPARING holding Fries
--   O2 (a002) preparing; legacy Burger 2 x (4000 + 300) stored 8300, per-unit
--             Burger 2 x (4000 + 300) = 8600, Cola 800 (no rounds)
--   O3 (a003) preparing; Fries 1500 + Cola 800 -> three edits -> ack up to 1
--   O4 (a004) preparing; Cola 800 -> one required edit -> voided
--   O5 (a005) served; rounds: 2 served, 3 voided, 4 preparing but TOMBSTONED
--   O6 (a006) served; a round 2 in READY holding Fries
--   O7 (a007) direct_print, served; Cola 800
select pg_temp.mk_order('b1d00000-0000-0000-0000-00000000a001', 'served');
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a1001', 'b1d00000-0000-0000-0000-00000000a001', 'b1d00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_round('b1d00000-0000-0000-0000-0000000a1e02', 'b1d00000-0000-0000-0000-00000000a001', 2, 'preparing');
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a1002', 'b1d00000-0000-0000-0000-00000000a001', 'b1d00000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500, 'b1d00000-0000-0000-0000-0000000a1e02');
select pg_temp.settle_totals('b1d00000-0000-0000-0000-00000000a001');

select pg_temp.mk_order('b1d00000-0000-0000-0000-00000000a002', 'preparing');
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a2001', 'b1d00000-0000-0000-0000-00000000a002', 'b1d00000-0000-0000-0000-000000001001', 'Burger', 2, 4000, 8300);
select pg_temp.mk_mod('b1d00000-0000-0000-0000-0000000a2001', 'cheese', 300);
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a2002', 'b1d00000-0000-0000-0000-00000000a002', 'b1d00000-0000-0000-0000-000000001001', 'Burger', 2, 4000, 8600);
select pg_temp.mk_mod('b1d00000-0000-0000-0000-0000000a2002', 'cheese', 300);
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a2003', 'b1d00000-0000-0000-0000-00000000a002', 'b1d00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1d00000-0000-0000-0000-00000000a002');

select pg_temp.mk_order('b1d00000-0000-0000-0000-00000000a003', 'preparing');
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a3001', 'b1d00000-0000-0000-0000-00000000a003', 'b1d00000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a3002', 'b1d00000-0000-0000-0000-00000000a003', 'b1d00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1d00000-0000-0000-0000-00000000a003');

select pg_temp.mk_order('b1d00000-0000-0000-0000-00000000a004', 'preparing');
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a4001', 'b1d00000-0000-0000-0000-00000000a004', 'b1d00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1d00000-0000-0000-0000-00000000a004');

select pg_temp.mk_order('b1d00000-0000-0000-0000-00000000a005', 'served');
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a5001', 'b1d00000-0000-0000-0000-00000000a005', 'b1d00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_round('b1d00000-0000-0000-0000-0000000a5e02', 'b1d00000-0000-0000-0000-00000000a005', 2, 'served');
select pg_temp.mk_round('b1d00000-0000-0000-0000-0000000a5e03', 'b1d00000-0000-0000-0000-00000000a005', 3, 'voided');
select pg_temp.mk_round('b1d00000-0000-0000-0000-0000000a5e04', 'b1d00000-0000-0000-0000-00000000a005', 4, 'preparing', true);
select pg_temp.settle_totals('b1d00000-0000-0000-0000-00000000a005');

select pg_temp.mk_order('b1d00000-0000-0000-0000-00000000a006', 'served');
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a6001', 'b1d00000-0000-0000-0000-00000000a006', 'b1d00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_round('b1d00000-0000-0000-0000-0000000a6e02', 'b1d00000-0000-0000-0000-00000000a006', 2, 'ready');
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a6002', 'b1d00000-0000-0000-0000-00000000a006', 'b1d00000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500, 'b1d00000-0000-0000-0000-0000000a6e02');
select pg_temp.settle_totals('b1d00000-0000-0000-0000-00000000a006');

select pg_temp.mk_order('b1d00000-0000-0000-0000-00000000a007', 'served', 'direct_print');
select pg_temp.mk_item('b1d00000-0000-0000-0000-0000000a7001', 'b1d00000-0000-0000-0000-00000000a007', 'b1d00000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('b1d00000-0000-0000-0000-00000000a007');

-- O3 before any edit (its own statement, before the writers)
insert into t_det select 'o3_pre', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a003');

-- Every fixture edit, through public.sync_push (order.edit), each its own statement.
create temp table t_w (k text, r jsonb);
-- O3 edit 1: Cola 1 -> 2 (a +1 delta in place on the In-kitchen unit: confirmation required)
insert into t_w select 'o3e1', pg_temp.edit('b1d00000-0000-0000-0000-00000000009a', 'b1d-o3-e1', 'b1d00000-0000-0000-0000-00000000a003',
  '{"expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "set_quantity", "order_item_id": "b1d00000-0000-0000-0000-0000000a3002", "quantity": 2}]}'::jsonb);
-- O3 edit 2: add Fries (lands in the edit's NEW round only: no confirmation)
insert into t_w select 'o3e2', pg_temp.edit('b1d00000-0000-0000-0000-00000000009a', 'b1d-o3-e2', 'b1d00000-0000-0000-0000-00000000a003',
  '{"expected": {"subtotal_minor": 4600, "tax_total_minor": 0, "grand_total_minor": 4600},
    "changes": [{"op": "add", "item": {"menu_item_id": "b1d00000-0000-0000-0000-000000001002", "quantity": 1,
      "unit_price_minor_snapshot": 1500, "menu_item_name_snapshot": "Fries"}}]}'::jsonb);
-- O3 edit 3: remove the ORIGINAL Fries (retired from the In-kitchen unit: confirmation required)
insert into t_w select 'o3e3', pg_temp.edit('b1d00000-0000-0000-0000-00000000009a', 'b1d-o3-e3', 'b1d00000-0000-0000-0000-00000000a003',
  '{"reason_code": "other", "reason_text": "Guest allergy",
    "expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "remove", "order_item_id": "b1d00000-0000-0000-0000-0000000a3001"}]}'::jsonb);
-- O4 edit 1: Cola 1 -> 2 (confirmation required; never acknowledged)
insert into t_w select 'o4e1', pg_temp.edit('b1d00000-0000-0000-0000-00000000009a', 'b1d-o4-e1', 'b1d00000-0000-0000-0000-00000000a004',
  '{"expected": {"subtotal_minor": 1600, "tax_total_minor": 0, "grand_total_minor": 1600},
    "changes": [{"op": "set_quantity", "order_item_id": "b1d00000-0000-0000-0000-0000000a4001", "quantity": 2}]}'::jsonb);

select is((select string_agg(k || '=' || coalesce(r ->> 'status', 'null'), ',' order by k) from t_w),
  'o3e1=applied,o3e2=applied,o3e3=applied,o4e1=applied',
  '01 every fixture edit is applied through sync_push (order.edit)');

-- Reads after the edits, before the ack / void (each its own statement).
insert into t_det select 'o1', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a001');
insert into t_det select 'o2', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a002');
insert into t_det select 'o3_post', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a003');
insert into t_det select 'o3_post_mgr', pg_temp.det('b1d00000-0000-0000-0000-00000000009b', 'b1d00000-0000-0000-0000-00000000a003');
insert into t_det select 'o4_pre_void', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a004');
insert into t_det select 'o5', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a005');
insert into t_det select 'o6', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a006');
insert into t_det select 'o7', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a007');
create temp table t_snap_pre as
  select public.pos_order_snapshots(p_pin_session_id => 'b1d00000-0000-0000-0000-00000000009a',
                                    p_device_id      => 'b1d00000-0000-0000-0000-0000000000d1',
                                    p_order_ids      => array['b1d00000-0000-0000-0000-00000000a004']::uuid[]) as r;

-- The kitchen confirms O3 up to edit 1 (KDS kitchen_staff); then a manager
-- voids O4 with its edit still pending.
insert into t_w select 'o3ack1', pg_temp.ack('b1d00000-0000-0000-0000-00000000009c', 'b1d-o3-ack1', 'b1d00000-0000-0000-0000-00000000a003', 1);
insert into t_w select 'o4void', app.void_order('b1d00000-0000-0000-0000-00000000009b', 'b1d00000-0000-0000-0000-00000000a004',
  'b1d00000-0000-0000-0000-0000000000d1', 'b1d-o4-void', 'b1d detail void');
select ok((select r ->> 'status' = 'applied' and (r ->> 'acknowledged_count')::int = 1 from t_w where k = 'o3ack1')
      and (select (r ->> 'ok')::boolean from t_w where k = 'o4void')
      and (select status = 'voided' and kitchen_ack_required from orders where id = 'b1d00000-0000-0000-0000-00000000a004'),
  '02 the ack (O3 up to 1) is applied and O4 is voided with its edit still unacknowledged');

create temp table t_audit0 as select count(*) as n from audit_events where organization_id = 'b1d00000-0000-0000-0000-0000000000a0';
insert into t_det select 'o3_acked', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a003');
insert into t_det select 'o4_voided', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a004');
create temp table t_snap as
  select s from jsonb_array_elements(public.pos_order_snapshots(
    p_pin_session_id => 'b1d00000-0000-0000-0000-00000000009a',
    p_device_id      => 'b1d00000-0000-0000-0000-0000000000d1',
    p_order_ids      => array['b1d00000-0000-0000-0000-00000000a001', 'b1d00000-0000-0000-0000-00000000a002',
                              'b1d00000-0000-0000-0000-00000000a003', 'b1d00000-0000-0000-0000-00000000a004',
                              'b1d00000-0000-0000-0000-00000000a005', 'b1d00000-0000-0000-0000-00000000a006',
                              'b1d00000-0000-0000-0000-00000000a007']::uuid[]) -> 'orders') s;
-- the same seven orders read through the detail NOW (same state as t_snap)
create temp table t_det_now as
  select u.id, pg_temp.det('b1d00000-0000-0000-0000-00000000009a', u.id) as r
    from unnest(array['b1d00000-0000-0000-0000-00000000a001', 'b1d00000-0000-0000-0000-00000000a002',
                      'b1d00000-0000-0000-0000-00000000a003', 'b1d00000-0000-0000-0000-00000000a004',
                      'b1d00000-0000-0000-0000-00000000a005', 'b1d00000-0000-0000-0000-00000000a006',
                      'b1d00000-0000-0000-0000-00000000a007']::uuid[]) as u(id);

-- ===== A. per item: unit_status / legacy / edit_id ==========================
select ok((select it ->> 'unit_status' = 'served' and it ->> 'status' = 'pending' and it -> 'service_round_id' = 'null'::jsonb
             from pg_temp.it('o1', 'b1d00000-0000-0000-0000-0000000a1001') it)
      and (select it ->> 'unit_status' = 'preparing' and it ->> 'service_round_id' = 'b1d00000-0000-0000-0000-0000000a1e02'
                  and (it ->> 'round_number')::int = 2
             from pg_temp.it('o1', 'b1d00000-0000-0000-0000-0000000a1002') it),
  '03 unit_status: the original-ticket line carries the ORDER status (served), the round line its ROUND status (preparing)');
select ok((select it ->> 'unit_status' = 'ready' from pg_temp.it('o6', 'b1d00000-0000-0000-0000-0000000a6002') it)
      and (select it ->> 'unit_status' = 'served' from pg_temp.it('o6', 'b1d00000-0000-0000-0000-0000000a6001') it)
      and (select bool_and(x ->> 'unit_status' = 'preparing') from t_det d, jsonb_array_elements(d.r -> 'items') x where d.k = 'o2'),
  '04 unit_status is the raw stage of the line''s work unit (a ready round on a served order; a preparing order)');
select ok((select (it ->> 'legacy')::boolean from pg_temp.it('o2', 'b1d00000-0000-0000-0000-0000000a2001') it)
      and app.order_item_is_legacy_priced('b1d00000-0000-0000-0000-0000000000a0', 'b1d00000-0000-0000-0000-0000000a2001'),
  '05 legacy TRUE for a stored pre-002A row: 2 x (4000 + cheese 300) stored as 8300');
select ok((select jsonb_typeof(it -> 'legacy') = 'boolean' and not (it ->> 'legacy')::boolean
             from pg_temp.it('o2', 'b1d00000-0000-0000-0000-0000000a2002') it)
      and (select not (it ->> 'legacy')::boolean from pg_temp.it('o2', 'b1d00000-0000-0000-0000-0000000a2003') it)
      and (select not (it ->> 'legacy')::boolean from pg_temp.it('o1', 'b1d00000-0000-0000-0000-0000000a1001') it),
  '06 legacy FALSE for per-unit rows: 2 x (4000 + 300) = 8600, a plain Cola, an original O1 line');
select ok((select count(*) = 3 and bool_and(x -> 'edit_id' = 'null'::jsonb) from t_det d, jsonb_array_elements(d.r -> 'items') x where d.k = 'o2')
      and (select count(*) = 2 and bool_and(x -> 'edit_id' = 'null'::jsonb) from t_det d, jsonb_array_elements(d.r -> 'items') x where d.k = 'o1'),
  '07 edit_id is NULL on every original line of an unedited order');
select ok((select it -> 'edit_id' = 'null'::jsonb and (it ->> 'quantity')::int = 1 and it ->> 'unit_status' = 'preparing'
             from pg_temp.it('o3_post', 'b1d00000-0000-0000-0000-0000000a3002') it)
      and (select count(*) = 1
                  and bool_and((x ->> 'quantity')::int = 1 and x -> 'service_round_id' = 'null'::jsonb
                               and x ->> 'unit_status' = 'preparing' and x ->> 'menu_item_name_snapshot' = 'Cola'
                               and not (x ->> 'legacy')::boolean)
             from t_det d, jsonb_array_elements(d.r -> 'items') x
            where d.k = 'o3_post' and x ->> 'edit_id' = pg_temp.eid('b1d00000-0000-0000-0000-00000000a003', 1)::text),
  '08 set_quantity increase: the kept original Cola has edit_id NULL; the +1 delta row carries edit 1''s id (in place, unit preparing, not legacy)');
select ok((select count(*) = 1
                  and bool_and(x ->> 'service_round_id' = (select r.id::text from order_service_rounds r
                                                            where r.edit_id = pg_temp.eid('b1d00000-0000-0000-0000-00000000a003', 2))
                               and x ->> 'unit_status' = 'submitted' and (x ->> 'round_number')::int = 2
                               and x ->> 'menu_item_name_snapshot' = 'Fries' and not (x ->> 'legacy')::boolean)
             from t_det d, jsonb_array_elements(d.r -> 'items') x
            where d.k = 'o3_post' and x ->> 'edit_id' = pg_temp.eid('b1d00000-0000-0000-0000-00000000a003', 2)::text),
  '09 add: the new line carries edit 2''s id and the edit round''s status (submitted) as unit_status');
select ok((select status = 'voided' and removed_by_edit_id = pg_temp.eid('b1d00000-0000-0000-0000-00000000a003', 3)
             from order_items where id = 'b1d00000-0000-0000-0000-0000000a3001')
      and pg_temp.it('o3_post', 'b1d00000-0000-0000-0000-0000000a3001') is null
      and (select jsonb_array_length(r -> 'items') = 3 from t_det where k = 'o3_post'),
  '10 the line retired by edit 3 is NOT in items (3 live lines remain; unchanged exclusion)');

-- ===== B. per order: dispatch_mode / kitchen_channel / edit_count / has_active_round
select ok((select r #>> '{order,dispatch_mode}' = 'kds' and r #>> '{order,kitchen_channel}' = 'kds'
                  and (r #>> '{order,edit_count}')::int = 0 and (r #>> '{order,has_active_round}')::boolean
             from t_det where k = 'o1'),
  '11 O1 (kds order, kds branch): dispatch_mode kds, kitchen_channel kds, edit_count 0, has_active_round TRUE (round preparing)');
select ok((select (r #>> '{order,edit_count}')::int = 0 and not (r #>> '{order,has_active_round}')::boolean
                  and r -> 'edits' = '[]'::jsonb
             from t_det where k = 'o3_pre'),
  '12 O3 before any edit: edit_count 0, has_active_round FALSE (no round), edits []');
select ok((select (r #>> '{order,edit_count}')::int = 3 and (r #>> '{order,has_active_round}')::boolean
             from t_det where k = 'o3_post')
      and (select edit_count = 3 from orders where id = 'b1d00000-0000-0000-0000-00000000a003'),
  '13 O3 after three edits: edit_count 3 (= orders.edit_count), has_active_round TRUE (the edit''s submitted round)');
select ok((select not (r #>> '{order,has_active_round}')::boolean from t_det where k = 'o5')
      and (select not (r #>> '{order,has_active_round}')::boolean from t_det where k = 'o2'),
  '14 has_active_round FALSE: a served round + a voided round + a TOMBSTONED preparing round; and no round at all');
select ok((select (r #>> '{order,has_active_round}')::boolean from t_det where k = 'o6'),
  '15 has_active_round TRUE for a round in ready (the upper bound of submitted..ready)');
select ok((select r #>> '{order,dispatch_mode}' = 'direct_print'
                  and (r -> 'order') ? 'kitchen_channel' and r #> '{order,kitchen_channel}' = 'null'::jsonb
                  and (r ->> 'ok')::boolean
             from t_det where k = 'o7'),
  '16 a direct_print order on a kds branch: dispatch_mode direct_print, kitchen_channel NULL (key present)');
select is((select count(*)::int from t_det_now d
             join t_snap s on s.s ->> 'order_id' = d.id::text
            where (d.r #> '{order,has_active_round}') = (s.s -> 'has_active_round')),
  7, '17 parity: has_active_round of pos_order_detail = pos_order_snapshots (targeted) for all 7 orders');
select ok((select count(distinct (r #>> '{order,has_active_round}')) = 2 from t_det_now)
      and (select count(*) = 7 from t_snap),
  '18 the parity set covers both values (TRUE and FALSE) and the snapshot returned all 7 orders');
select is((select count(*)::int from t_det_now d
             join t_snap s on s.s ->> 'order_id' = d.id::text
            where (d.r #> '{order,edit_count}') = (s.s -> 'edit_count')
              and (s.s ->> 'kitchen_edit_ack_pending')::boolean
                  = coalesce((select bool_or((e ->> 'kitchen_ack_pending')::boolean)
                                from jsonb_array_elements(d.r -> 'edits') e), false)),
  7, '19 parity: edit_count and kitchen_edit_ack_pending (= any edits[].kitchen_ack_pending) agree with the snapshot');

-- ===== C. edits[] ===========================================================
select ok((select jsonb_path_query_array(r, '$.edits[*].edit_number') = '[1, 2, 3]'::jsonb
                  and jsonb_path_query_array(r, '$.edits[*].order_edit_id')
                      = jsonb_build_array(pg_temp.eid('b1d00000-0000-0000-0000-00000000a003', 1),
                                          pg_temp.eid('b1d00000-0000-0000-0000-00000000a003', 2),
                                          pg_temp.eid('b1d00000-0000-0000-0000-00000000a003', 3))
             from t_det where k = 'o3_post'),
  '20 edits[] is ordered by edit_number (1, 2, 3) and carries each edit''s id');
select is((select count(*)::int from t_det d, jsonb_array_elements(d.r -> 'edits') e
            where d.k in ('o3_post', 'o3_acked', 'o4_voided')
              and (select array_agg(kk order by kk) from jsonb_object_keys(e) kk)
                  = array['created_at', 'edit_number', 'kitchen_ack_at', 'kitchen_ack_pending', 'kitchen_ack_required',
                          'kitchen_channel', 'order_edit_id', 'reason_code', 'reason_text']),
  7, '21 every edits[] element has EXACTLY the nine contract keys');
select ok((select count(*) = 0 from t_det d, jsonb_array_elements(d.r -> 'edits') e, jsonb_object_keys(e) kk
            where d.k in ('o3_post', 'o3_acked', 'o4_voided') and kk like '%\_minor' escape '\')
      and (select bool_and(strpos((d.r -> 'edits')::text, x) = 0)
             from t_det d,
                  unnest(array['b1d00000-0000-0000-0000-00000000008a', 'b1d00000-0000-0000-0000-00000000008b',
                               'b1d00000-0000-0000-0000-00000000008c', 'b1d00000-0000-0000-0000-00000000007a',
                               'b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000009c',
                               'b1d00000-0000-0000-0000-0000000000d1', 'b1d00000-0000-0000-0000-0000000000d2',
                               'b1d00000-0000-0000-0000-00000000005a']) x
            where d.k in ('o3_post', 'o3_acked', 'o4_voided')),
  '22 edits[] carry no *_minor key and no staff / membership / PIN / device / session id (even once acknowledged)');
select ok((select bool_and(e ->> 'kitchen_channel' = 'kds' and e -> 'kitchen_ack_at' = 'null'::jsonb
                           and (e ->> 'created_at')::timestamptz = oe.created_at)
             from t_det d, jsonb_array_elements(d.r -> 'edits') e
             join order_edits oe on oe.id = (e ->> 'order_edit_id')::uuid
            where d.k = 'o3_post')
      and (select jsonb_path_query_array(r, '$.edits[*].kitchen_ack_required') = '[true, false, true]'::jsonb
                  and jsonb_path_query_array(r, '$.edits[*].reason_code') = '[null, null, "other"]'::jsonb
                  and jsonb_path_query_array(r, '$.edits[*].reason_text') = '[null, null, "Guest allergy"]'::jsonb
             from t_det where k = 'o3_post'),
  '23 edits[] values are the stored ones: channel kds, created_at, ack_required (T,F,T), reason_code / reason_text');
select is((select jsonb_path_query_array(r, '$.edits[*].kitchen_ack_pending') from t_det where k = 'o3_post'),
  '[true, false, true]'::jsonb,
  '24 kitchen_ack_pending before any ack: TRUE for the two required edits, FALSE for the add-only edit');
select ok((select jsonb_path_query_array(r, '$.edits[*].kitchen_ack_pending') = '[false, false, true]'::jsonb
                  and (r #>> '{edits,0,kitchen_ack_at}')::timestamptz
                      = (select kitchen_ack_at from order_edits where id = pg_temp.eid('b1d00000-0000-0000-0000-00000000a003', 1))
                  and r #> '{edits,2,kitchen_ack_at}' = 'null'::jsonb
             from t_det where k = 'o3_acked'),
  '25 after order.edit_ack up to 1: edit 1 FALSE (its kitchen_ack_at shown), edit 3 still TRUE');
select ok((select r #>> '{order,status}' = 'preparing' and (r #>> '{edits,0,kitchen_ack_pending}')::boolean
             from t_det where k = 'o4_pre_void')
      and (select (r -> 'orders' -> 0 ->> 'kitchen_edit_ack_pending')::boolean from t_snap_pre),
  '26 O4 before the void: its required, unacknowledged edit is pending (detail and snapshot)');
select ok((select r #>> '{order,status}' = 'voided'
                  and jsonb_array_length(r -> 'edits') = 1
                  and (r #>> '{edits,0,kitchen_ack_required}')::boolean
                  and r #> '{edits,0,kitchen_ack_at}' = 'null'::jsonb
                  and jsonb_typeof(r #> '{edits,0,kitchen_ack_pending}') = 'boolean'
                  and not (r #>> '{edits,0,kitchen_ack_pending}')::boolean
             from t_det where k = 'o4_voided')
      and (select not (s.s ->> 'kitchen_edit_ack_pending')::boolean from t_snap s
            where s.s ->> 'order_id' = 'b1d00000-0000-0000-0000-00000000a004'),
  '27 a VOIDED order: the required, unacknowledged edit reads kitchen_ack_pending FALSE (and the snapshot agrees)');

-- ===== E. unchanged behaviour ================================================
select ok((select r #>> '{order,order_code}' = '#' || upper(right(replace('b1d00000-0000-0000-0000-00000000a003', '-', ''), 6))
                  and r #>> '{order,status}' = 'preparing'
                  and (r #>> '{order,subtotal_minor}')::bigint = 3100
                  and (r #>> '{order,grand_total_minor}')::bigint = 3100
                  and (r #>> '{order,tax_total_minor}')::bigint = 0
                  and (r #>> '{order,discount_total_minor}')::bigint = 0
                  and r #>> '{order,order_id}' = 'b1d00000-0000-0000-0000-00000000a003'
             from t_det where k = 'o3_post'),
  '28 the order header still carries order_code, status and the stored totals (3100 after the edits)');
select is((select array_agg(kk order by kk) from t_det d, jsonb_object_keys(d.r) kk where d.k = 'o3_post'),
  array['branch_features', 'edits', 'entity', 'items', 'ok', 'order', 'payment', 'rounds', 'server_ts'],
  '29 the envelope keys are the shipped keys + exactly edits and branch_features');
select ok((select (a.r - 'server_ts') = (b.r - 'server_ts') from t_det a, t_det b
            where a.k = 'o3_post' and b.k = 'o3_post_mgr'),
  '30 a manager PIN reads the identical detail (role does not change the projection)');
select ok((select jsonb_path_query_array(r, '$.rounds[*].round_number') = '[2, 3]'::jsonb
                  and jsonb_path_query_array(r, '$.rounds[*].status') = '["served", "voided"]'::jsonb
             from t_det where k = 'o5'),
  '31 rounds[] unchanged: voided rounds listed (status says so), tombstoned rounds not');
select is(pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000dead'),
  '{"ok": false, "error": "order_not_found", "entity": "order_detail"}'::jsonb,
  '32 an unknown order id still returns order_not_found');
select is(pg_temp.det('b1d00000-0000-0000-0000-00000000009e', 'b1d00000-0000-0000-0000-00000000a003',
                      'b1d00000-0000-0000-0000-0000000000d2'),
  '{"ok": false, "error": "invalid_device_type", "entity": "order_detail"}'::jsonb,
  '33 a KDS device (cashier PIN on the KDS) still gets invalid_device_type');
select is(pg_temp.det('b1d00000-0000-0000-0000-00000000009d', 'b1d00000-0000-0000-0000-00000000a003'),
  '{"ok": false, "error": "permission_denied", "entity": "order_detail"}'::jsonb,
  '34 a kitchen_staff PIN on the POS still gets permission_denied');
select ok((select count(*) from audit_events where organization_id = 'b1d00000-0000-0000-0000-0000000000a0')
          = (select n from t_audit0),
  '35 the reads wrote no audit event');

-- ===== D. branch_features / kitchen_channel against the branch row ===========
-- (every read below runs AFTER the reads stored above)
select ok((select r -> 'branch_features'
                  = '{"order_edit_enabled": true, "order_edit_finished_food_manager_only": false}'::jsonb
             from t_det where k = 'o1')
      and (select (r -> 'branch_features') = (select r -> 'branch_features' from t_det where k = 'o1') from t_det where k = 'o4_voided'),
  '36 branch_features mirrors the branch switches (enabled TRUE, finished-food FALSE)');
update branches set order_edit_enabled = false, order_edit_finished_food_manager_only = true
 where id = 'b1d00000-0000-0000-0000-0000000000ab';
insert into t_det select 'o1_flipped', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a001');
update branches set kitchen_workflow_mode = 'printer_only' where id = 'b1d00000-0000-0000-0000-0000000000ab';
insert into t_det select 'o1_paper', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a001');
insert into t_det select 'o7_paper', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a007');
update branches set deleted_at = now() where id = 'b1d00000-0000-0000-0000-0000000000ab';
insert into t_det select 'o1_gone', pg_temp.det('b1d00000-0000-0000-0000-00000000009a', 'b1d00000-0000-0000-0000-00000000a001');
select ok((select r -> 'branch_features'
                  = '{"order_edit_enabled": false, "order_edit_finished_food_manager_only": true}'::jsonb
                  and r #>> '{order,kitchen_channel}' = 'kds'
             from t_det where k = 'o1_flipped'),
  '37 flipped switches are mirrored (enabled FALSE, finished-food TRUE)');
select ok((select r #>> '{order,kitchen_channel}' = 'paper' and r #>> '{order,dispatch_mode}' = 'kds' from t_det where k = 'o1_paper')
      and (select r #>> '{order,kitchen_channel}' = 'paper' and r #>> '{order,dispatch_mode}' = 'direct_print' from t_det where k = 'o7_paper')
      and (select (r ->> 'ok')::boolean and (r #>> '{order,has_active_round}')::boolean
                  and r #>> '{order,order_id}' = 'b1d00000-0000-0000-0000-00000000a001'
                  and r #> '{order,kitchen_channel}' = 'null'::jsonb
                  and r -> 'branch_features'
                      = '{"order_edit_enabled": false, "order_edit_finished_food_manager_only": false}'::jsonb
                  and jsonb_array_length(r -> 'items') = 2
             from t_det where k = 'o1_gone'),
  '38 printer_only branch: kitchen_channel paper (kds and direct_print orders); a soft-deleted session branch: still ok with the order, kitchen_channel NULL, both switches FALSE');

select * from finish();
rollback;
