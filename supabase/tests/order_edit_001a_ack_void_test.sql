-- ORDER-EDIT-001A — the kitchen's "Got it" (order.edit_ack -> app.kitchen_ack_order_edit,
-- API_CONTRACT §4.46), the app.void_order acknowledgement widening (§4.45.3 /
-- ORDER_EDIT_DESIGN §8.5), and the append-only / write-once guards on
-- order_edits, the order_items edit provenance and order_service_rounds
-- (DOMAIN_MODEL §6.4; schema migration 20261008170000).
begin;
set local search_path to extensions, public, pg_catalog;

select plan(55);

-- ===== fixture ==============================================================
-- Org A: one KDS-mode branch with order editing ON; one POS + one KDS device.
-- PIN sessions: cashier + manager on the POS; kitchen_staff, cashier and
-- manager on the KDS.
insert into organizations (id, name, slug, default_currency) values
  ('e2ed0000-0000-0000-0000-0000000000a0', 'Org Edit Ack', 'org-edit-ack-001a', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000a0', 'Rest Edit Ack');
insert into branches (id, organization_id, restaurant_id, name, order_edit_enabled) values
  ('e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'Branch Edit Ack', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('e2ed0000-0000-0000-0000-0000000000d1', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'pos'),
  ('e2ed0000-0000-0000-0000-0000000000d2', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('e2ed0000-0000-0000-0000-0000000000f1', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-0000000000d1', 'active'),
  ('e2ed0000-0000-0000-0000-0000000000f2', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-0000000000d2', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('e2ed0000-0000-0000-0000-00000000005a', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-0000000000d1', 'e2ed0000-0000-0000-0000-0000000000f1'),
  ('e2ed0000-0000-0000-0000-00000000005b', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-0000000000d2', 'e2ed0000-0000-0000-0000-0000000000f2');
insert into app_users (id, email) values
  ('e2ed0000-0000-0000-0000-00000000006a', 'ack-cashier@example.test'),
  ('e2ed0000-0000-0000-0000-00000000006b', 'ack-manager@example.test'),
  ('e2ed0000-0000-0000-0000-00000000006c', 'ack-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e2ed0000-0000-0000-0000-00000000007a', 'e2ed0000-0000-0000-0000-00000000006a', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'cashier', '{}'::jsonb),
  ('e2ed0000-0000-0000-0000-00000000007b', 'e2ed0000-0000-0000-0000-00000000006b', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'manager', '{}'::jsonb),
  ('e2ed0000-0000-0000-0000-00000000007c', 'e2ed0000-0000-0000-0000-00000000006c', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'kitchen_staff', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('e2ed0000-0000-0000-0000-00000000008a', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-00000000006a', 'e2ed0000-0000-0000-0000-00000000007a', 'Ada Cashier'),
  ('e2ed0000-0000-0000-0000-00000000008b', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-00000000006b', 'e2ed0000-0000-0000-0000-00000000007b', 'Ben Manager'),
  ('e2ed0000-0000-0000-0000-00000000008c', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-00000000006c', 'e2ed0000-0000-0000-0000-00000000007c', 'Cy Kitchen');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  -- POS: cashier (9a), manager (9b)
  ('e2ed0000-0000-0000-0000-00000000009a', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-00000000005a', 'e2ed0000-0000-0000-0000-00000000008a', 'e2ed0000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('e2ed0000-0000-0000-0000-00000000009b', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-00000000005a', 'e2ed0000-0000-0000-0000-00000000008b', 'e2ed0000-0000-0000-0000-00000000007b', now() + interval '1 hour'),
  -- KDS: kitchen_staff (9c), cashier (9e), manager (9f)
  ('e2ed0000-0000-0000-0000-00000000009c', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-00000000005b', 'e2ed0000-0000-0000-0000-00000000008c', 'e2ed0000-0000-0000-0000-00000000007c', now() + interval '1 hour'),
  ('e2ed0000-0000-0000-0000-00000000009e', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-00000000005b', 'e2ed0000-0000-0000-0000-00000000008a', 'e2ed0000-0000-0000-0000-00000000007a', now() + interval '1 hour'),
  ('e2ed0000-0000-0000-0000-00000000009f', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-00000000005b', 'e2ed0000-0000-0000-0000-00000000008b', 'e2ed0000-0000-0000-0000-00000000007b', now() + interval '1 hour');

-- Menu: Fries 1500, Cola 800, Lemonade 900 (no modifiers).
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('e2ed0000-0000-0000-0000-0000000000c1', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', null, 'Mains', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('e2ed0000-0000-0000-0000-000000001002', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', null, 'e2ed0000-0000-0000-0000-0000000000c1', 'Fries', 1500, 'ILS', 1),
  ('e2ed0000-0000-0000-0000-000000001003', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', null, 'e2ed0000-0000-0000-0000-0000000000c1', 'Cola', 800, 'ILS', 2),
  ('e2ed0000-0000-0000-0000-000000001004', 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1', null, 'e2ed0000-0000-0000-0000-0000000000c1', 'Lemonade', 900, 'ILS', 3);

-- Org B: a second tenant with its own KDS-mode branch (editing ON), POS,
-- cashier PIN, menu and order.
insert into organizations (id, name, slug, default_currency) values
  ('e2ed0000-0000-0000-0000-0000000000b0', 'Org Edit Ack B', 'org-edit-ack-001a-b', 'ILS');
insert into restaurants (id, organization_id, name) values
  ('e2ed0000-0000-0000-0000-0000000000b1', 'e2ed0000-0000-0000-0000-0000000000b0', 'Rest Edit Ack B');
insert into branches (id, organization_id, restaurant_id, name, order_edit_enabled) values
  ('e2ed0000-0000-0000-0000-0000000000bb', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1', 'Branch Edit Ack B', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('e2ed0000-0000-0000-0000-0000000000bd', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1', 'e2ed0000-0000-0000-0000-0000000000bb', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('e2ed0000-0000-0000-0000-0000000000bf', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1', 'e2ed0000-0000-0000-0000-0000000000bb', 'e2ed0000-0000-0000-0000-0000000000bd', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('e2ed0000-0000-0000-0000-0000000000b5', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1', 'e2ed0000-0000-0000-0000-0000000000bb', 'e2ed0000-0000-0000-0000-0000000000bd', 'e2ed0000-0000-0000-0000-0000000000bf');
insert into app_users (id, email) values
  ('e2ed0000-0000-0000-0000-0000000000b6', 'ack-cashier-b@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('e2ed0000-0000-0000-0000-0000000000b7', 'e2ed0000-0000-0000-0000-0000000000b6', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1', 'e2ed0000-0000-0000-0000-0000000000bb', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id, display_name) values
  ('e2ed0000-0000-0000-0000-0000000000b8', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1', 'e2ed0000-0000-0000-0000-0000000000bb', 'e2ed0000-0000-0000-0000-0000000000b6', 'e2ed0000-0000-0000-0000-0000000000b7', 'Bea Cashier');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('e2ed0000-0000-0000-0000-0000000000b9', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1', 'e2ed0000-0000-0000-0000-0000000000bb', 'e2ed0000-0000-0000-0000-0000000000b5', 'e2ed0000-0000-0000-0000-0000000000b8', 'e2ed0000-0000-0000-0000-0000000000b7', now() + interval '1 hour');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('e2ed0000-0000-0000-0000-0000000000bc', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1', null, 'Drinks', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('e2ed0000-0000-0000-0000-00000000b003', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1', null, 'e2ed0000-0000-0000-0000-0000000000bc', 'Cola', 800, 'ILS', 1);
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
  opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
  subtotal_minor, grand_total_minor, local_operation_id, status) values
  ('e2ed0000-0000-0000-0000-00000000b0b1', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1',
   'e2ed0000-0000-0000-0000-0000000000bb', 'e2ed0000-0000-0000-0000-0000000000bd', 'e2ed0000-0000-0000-0000-0000000000b9',
   'e2ed0000-0000-0000-0000-0000000000b8', 'e2ed0000-0000-0000-0000-0000000000b7', 'dine_in', 'ILS', 800, 800,
   'submit-org-b-1', 'preparing');
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
  quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor) values
  ('e2ed0000-0000-0000-0000-0000000b1001', 'e2ed0000-0000-0000-0000-0000000000b0', 'e2ed0000-0000-0000-0000-0000000000b1',
   'e2ed0000-0000-0000-0000-0000000000bb', 'e2ed0000-0000-0000-0000-00000000b0b1', 'e2ed0000-0000-0000-0000-00000000b003',
   1, 'Cola', 800, 0, 800);

-- Org A builders (direct inserts as the fixture role; the line-position and
-- display-order insert triggers still fire).
create function pg_temp.mk_order(p_id uuid, p_status text) returns void
language sql as $$
  insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, order_type, currency_code,
    subtotal_minor, grand_total_minor, local_operation_id, status, ready_at)
  values (p_id, 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1',
    'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-0000000000d1',
    'e2ed0000-0000-0000-0000-00000000009a', 'e2ed0000-0000-0000-0000-00000000008a',
    'e2ed0000-0000-0000-0000-00000000007a', 'dine_in', 'ILS', 0, 0, 'submit-' || p_id::text, p_status,
    case when p_status in ('ready', 'served') then now() - interval '5 minutes' end);
$$;
create function pg_temp.mk_item(p_id uuid, p_order uuid, p_menu uuid, p_name text, p_qty int,
  p_unit bigint, p_total bigint, p_round uuid default null) returns void
language sql as $$
  insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
    quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor, service_round_id)
  values (p_id, 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1',
    'e2ed0000-0000-0000-0000-0000000000ab', p_order, p_menu, p_qty, p_name, p_unit, 0, p_total, p_round);
$$;
create function pg_temp.mk_round(p_id uuid, p_order uuid, p_no int, p_status text) returns void
language sql as $$
  insert into order_service_rounds (id, organization_id, restaurant_id, branch_id, order_id, round_number,
    status, device_id, opened_by_employee_profile_id, ready_at)
  values (p_id, 'e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1',
    'e2ed0000-0000-0000-0000-0000000000ab', p_order, p_no, p_status,
    'e2ed0000-0000-0000-0000-0000000000d1', 'e2ed0000-0000-0000-0000-00000000008a',
    case when p_status in ('ready', 'served') then now() - interval '1 minute' end);
$$;
-- re-roll an order's stored totals from its live lines (tax off, no discount)
create function pg_temp.settle_totals(p_order uuid) returns void
language sql as $$
  update orders o set subtotal_minor = s.t, grand_total_minor = s.t - o.discount_total_minor
    from (select coalesce(sum(line_total_minor), 0) as t from order_items
           where order_id = p_order and status not in ('voided', 'cancelled')) s
   where o.id = p_order;
$$;
-- one order.edit through public.sync_push (default: the org A POS)
create function pg_temp.edit(p_pin uuid, p_op text, p_order uuid, p_payload jsonb,
  p_dev uuid default 'e2ed0000-0000-0000-0000-0000000000d1') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit', 'target_entity', 'order',
    'target_id', p_order, 'payload', p_payload || jsonb_build_object('order_id', p_order)))) -> 'results' -> 0;
$$;
-- one order.edit_ack through public.sync_push (default: the org A KDS); the
-- payload is {order_id} || p_extra
create function pg_temp.ack(p_pin uuid, p_op text, p_order uuid, p_extra jsonb,
  p_dev uuid default 'e2ed0000-0000-0000-0000-0000000000d2') returns jsonb
language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.edit_ack', 'target_entity', 'order',
    'target_id', p_order, 'payload', jsonb_build_object('order_id', p_order) || p_extra))) -> 'results' -> 0;
$$;
create function pg_temp.ackn(p_pin uuid, p_op text, p_order uuid, p_n int,
  p_dev uuid default 'e2ed0000-0000-0000-0000-0000000000d2') returns jsonb
language sql as $$
  select pg_temp.ack(p_pin, p_op, p_order, jsonb_build_object('up_to_edit_number', p_n), p_dev);
$$;
-- the id of edit N of an order
create function pg_temp.eid(p_order uuid, p_n int) returns uuid
language sql stable as $$
  select id from order_edits where order_id = p_order and edit_number = p_n;
$$;

-- Orders (org A):
--   A  (a001) preparing: Fries x2 3000, Cola x1 800, Lemonade x1 900 = 4700
--   S  (a002) preparing -> one edit -> later served
--   C  (a003) preparing -> one edit -> later completed
--   Va (ca01) served, a live service round in preparing (void case a)
--   Vb (cb01) preparing -> edit removes from the live unit -> served (void case b)
--   Vc (cc01) preparing -> edit -> acknowledged -> served round -> served (void case c)
--   Vd (cd01) preparing, no edit (void case d)
select pg_temp.mk_order('e2ed0000-0000-0000-0000-00000000a001', 'preparing');
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000a1001', 'e2ed0000-0000-0000-0000-00000000a001', 'e2ed0000-0000-0000-0000-000000001002', 'Fries', 2, 1500, 3000);
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000a1002', 'e2ed0000-0000-0000-0000-00000000a001', 'e2ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000a1003', 'e2ed0000-0000-0000-0000-00000000a001', 'e2ed0000-0000-0000-0000-000000001004', 'Lemonade', 1, 900, 900);
select pg_temp.settle_totals('e2ed0000-0000-0000-0000-00000000a001');

select pg_temp.mk_order('e2ed0000-0000-0000-0000-00000000a002', 'preparing');
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000a2001', 'e2ed0000-0000-0000-0000-00000000a002', 'e2ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000a2002', 'e2ed0000-0000-0000-0000-00000000a002', 'e2ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e2ed0000-0000-0000-0000-00000000a002');

select pg_temp.mk_order('e2ed0000-0000-0000-0000-00000000a003', 'preparing');
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000a3001', 'e2ed0000-0000-0000-0000-00000000a003', 'e2ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000a3002', 'e2ed0000-0000-0000-0000-00000000a003', 'e2ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e2ed0000-0000-0000-0000-00000000a003');

select pg_temp.mk_order('e2ed0000-0000-0000-0000-00000000ca01', 'served');
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000ca101', 'e2ed0000-0000-0000-0000-00000000ca01', 'e2ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.mk_round('e2ed0000-0000-0000-0000-0000000ca1e2', 'e2ed0000-0000-0000-0000-00000000ca01', 2, 'preparing');
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000ca102', 'e2ed0000-0000-0000-0000-00000000ca01', 'e2ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500, 'e2ed0000-0000-0000-0000-0000000ca1e2');
select pg_temp.settle_totals('e2ed0000-0000-0000-0000-00000000ca01');

select pg_temp.mk_order('e2ed0000-0000-0000-0000-00000000cb01', 'preparing');
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000cb101', 'e2ed0000-0000-0000-0000-00000000cb01', 'e2ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000cb102', 'e2ed0000-0000-0000-0000-00000000cb01', 'e2ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e2ed0000-0000-0000-0000-00000000cb01');

select pg_temp.mk_order('e2ed0000-0000-0000-0000-00000000cc01', 'preparing');
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000cc101', 'e2ed0000-0000-0000-0000-00000000cc01', 'e2ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000cc102', 'e2ed0000-0000-0000-0000-00000000cc01', 'e2ed0000-0000-0000-0000-000000001003', 'Cola', 1, 800, 800);
select pg_temp.settle_totals('e2ed0000-0000-0000-0000-00000000cc01');

select pg_temp.mk_order('e2ed0000-0000-0000-0000-00000000cd01', 'preparing');
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000cd101', 'e2ed0000-0000-0000-0000-00000000cd01', 'e2ed0000-0000-0000-0000-000000001002', 'Fries', 1, 1500, 1500);
select pg_temp.settle_totals('e2ed0000-0000-0000-0000-00000000cd01');

-- Every fixture edit, through public.sync_push (order.edit), in this order.
create temp table t_edits (k text, r jsonb);
-- A edit 1: Cola 1 -> 2 (a +1 delta in place on the In-kitchen unit: confirmation required)
insert into t_edits select 'a1', pg_temp.edit('e2ed0000-0000-0000-0000-00000000009a', 'a-e1', 'e2ed0000-0000-0000-0000-00000000a001',
  '{"expected": {"subtotal_minor": 5500, "tax_total_minor": 0, "grand_total_minor": 5500},
    "changes": [{"op": "set_quantity", "order_item_id": "e2ed0000-0000-0000-0000-0000000a1002", "quantity": 2}]}'::jsonb);
-- A edit 2: remove Lemonade + Fries 2 -> 1 (retired from the In-kitchen unit: confirmation required)
insert into t_edits select 'a2', pg_temp.edit('e2ed0000-0000-0000-0000-00000000009a', 'a-e2', 'e2ed0000-0000-0000-0000-00000000a001',
  '{"reason_code": "customer_changed_mind",
    "expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "remove", "order_item_id": "e2ed0000-0000-0000-0000-0000000a1003"},
                {"op": "set_quantity", "order_item_id": "e2ed0000-0000-0000-0000-0000000a1001", "quantity": 1}]}'::jsonb);
-- A edit 3: add Fries (lands in the edit's NEW round only: no confirmation)
insert into t_edits select 'a3', pg_temp.edit('e2ed0000-0000-0000-0000-00000000009a', 'a-e3', 'e2ed0000-0000-0000-0000-00000000a001',
  '{"expected": {"subtotal_minor": 4600, "tax_total_minor": 0, "grand_total_minor": 4600},
    "changes": [{"op": "add", "item": {"menu_item_id": "e2ed0000-0000-0000-0000-000000001002", "quantity": 1,
      "unit_price_minor_snapshot": 1500, "menu_item_name_snapshot": "Fries"}}]}'::jsonb);
insert into t_edits select 's1', pg_temp.edit('e2ed0000-0000-0000-0000-00000000009a', 's-e1', 'e2ed0000-0000-0000-0000-00000000a002',
  '{"expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "set_quantity", "order_item_id": "e2ed0000-0000-0000-0000-0000000a2002", "quantity": 2}]}'::jsonb);
insert into t_edits select 'c1', pg_temp.edit('e2ed0000-0000-0000-0000-00000000009a', 'c-e1', 'e2ed0000-0000-0000-0000-00000000a003',
  '{"expected": {"subtotal_minor": 3100, "tax_total_minor": 0, "grand_total_minor": 3100},
    "changes": [{"op": "set_quantity", "order_item_id": "e2ed0000-0000-0000-0000-0000000a3002", "quantity": 2}]}'::jsonb);
insert into t_edits select 'vb1', pg_temp.edit('e2ed0000-0000-0000-0000-00000000009a', 'vb-e1', 'e2ed0000-0000-0000-0000-00000000cb01',
  '{"reason_code": "item_unavailable",
    "expected": {"subtotal_minor": 1500, "tax_total_minor": 0, "grand_total_minor": 1500},
    "changes": [{"op": "remove", "order_item_id": "e2ed0000-0000-0000-0000-0000000cb102"}]}'::jsonb);
insert into t_edits select 'vc1', pg_temp.edit('e2ed0000-0000-0000-0000-00000000009a', 'vc-e1', 'e2ed0000-0000-0000-0000-00000000cc01',
  '{"reason_code": "item_unavailable",
    "expected": {"subtotal_minor": 1500, "tax_total_minor": 0, "grand_total_minor": 1500},
    "changes": [{"op": "remove", "order_item_id": "e2ed0000-0000-0000-0000-0000000cc102"}]}'::jsonb);
-- org B's own edit on its own order (its own POS + cashier): confirmation required
insert into t_edits select 'b1', pg_temp.edit('e2ed0000-0000-0000-0000-0000000000b9', 'b-e1', 'e2ed0000-0000-0000-0000-00000000b0b1',
  '{"expected": {"subtotal_minor": 1600, "tax_total_minor": 0, "grand_total_minor": 1600},
    "changes": [{"op": "set_quantity", "order_item_id": "e2ed0000-0000-0000-0000-0000000b1001", "quantity": 2}]}'::jsonb,
  'e2ed0000-0000-0000-0000-0000000000bd');

select is((select string_agg(k || '=' || coalesce(r ->> 'status', 'null'), ',' order by k) from t_edits),
  'a1=applied,a2=applied,a3=applied,b1=applied,c1=applied,s1=applied,vb1=applied,vc1=applied',
  '01 every fixture edit is applied through sync_push (order.edit)');
select is((select string_agg(edit_number || ':' || kitchen_ack_required, ',' order by edit_number)
             from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000a001'),
  '1:true,2:true,3:false',
  '02 order A: edits 1 and 2 need the kitchen''s confirmation, edit 3 (a new ticket only) does not');

create temp table t_snap_a as select to_jsonb(o) as row from orders o where o.id = 'e2ed0000-0000-0000-0000-00000000a001';
select ok((select (row ->> 'revision')::int = 4 and (row ->> 'edit_count')::int = 3 and row ->> 'status' = 'preparing' from t_snap_a),
  '03 order A before any acknowledgement: revision 4, edit_count 3, still preparing');

-- ===== B. refusals (RETURNed, audited order.edit_ack_denied) =================
create temp table t_ref (k text, r jsonb);
insert into t_ref select 'pos', pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009a', 'ref-pos', 'e2ed0000-0000-0000-0000-00000000a001', 1,
  'e2ed0000-0000-0000-0000-0000000000d1');
insert into t_ref select 'cashier', pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009e', 'ref-cashier', 'e2ed0000-0000-0000-0000-00000000a001', 1);
insert into t_ref select 'n4', pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'ref-n4', 'e2ed0000-0000-0000-0000-00000000a001', 4);
insert into t_ref select 'n0', pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'ref-n0', 'e2ed0000-0000-0000-0000-00000000a001', 0);
insert into t_ref select 'missing', pg_temp.ack('e2ed0000-0000-0000-0000-00000000009c', 'ref-missing', 'e2ed0000-0000-0000-0000-00000000a001', '{}'::jsonb);
insert into t_ref select 'frac', pg_temp.ack('e2ed0000-0000-0000-0000-00000000009c', 'ref-frac', 'e2ed0000-0000-0000-0000-00000000a001', '{"up_to_edit_number": 1.5}'::jsonb);
insert into t_ref select 'str', pg_temp.ack('e2ed0000-0000-0000-0000-00000000009c', 'ref-str', 'e2ed0000-0000-0000-0000-00000000a001', '{"up_to_edit_number": "1"}'::jsonb);
insert into t_ref select 'neg', pg_temp.ack('e2ed0000-0000-0000-0000-00000000009c', 'ref-neg', 'e2ed0000-0000-0000-0000-00000000a001', '{"up_to_edit_number": -1}'::jsonb);

-- a RETURNed (typed, not raised) refusal for order A, passed through verbatim
create function pg_temp.refused(p_k text, p_error text) returns boolean
language sql as $$
  select r ->> 'status' = 'rejected' and r ->> 'ok' = 'false' and r ->> 'error' = p_error
         and r ->> 'sqlstate' is null and r ->> 'order_id' = 'e2ed0000-0000-0000-0000-00000000a001'
    from t_ref where k = p_k;
$$;

select ok(pg_temp.refused('pos', 'invalid_device_type'),
  '04 a POS device cannot confirm (invalid_device_type)');
select ok(pg_temp.refused('cashier', 'permission_denied'),
  '05 a cashier PIN on the KDS cannot confirm (permission_denied)');
select ok(pg_temp.refused('n4', 'invalid_edit_number'),
  '06 up_to_edit_number above edit_count (4 > 3) is invalid_edit_number');
select ok(pg_temp.refused('n0', 'invalid_edit_number'),
  '07 up_to_edit_number 0 is invalid_edit_number');
select ok(pg_temp.refused('missing', 'invalid_edit_number'),
  '08 a missing up_to_edit_number is invalid_edit_number');
select ok(pg_temp.refused('frac', 'invalid_edit_number') and pg_temp.refused('str', 'invalid_edit_number')
          and pg_temp.refused('neg', 'invalid_edit_number'),
  '09 a non-integer (1.5, "1") or negative up_to_edit_number is invalid_edit_number');
select is((select string_agg(x.reason || '=' || x.n, ',' order by x.reason)
             from (select new_values ->> 'denied_reason' as reason, count(*) as n from audit_events
                    where action = 'order.edit_ack_denied'
                      and new_values ->> 'order_id' = 'e2ed0000-0000-0000-0000-00000000a001'
                    group by 1) x),
  'invalid_device_type=1,invalid_edit_number=6,permission_denied=1',
  '10 every refusal is audited order.edit_ack_denied with its denied_reason');
select ok((select count(*) = 1 from audit_events
            where action = 'order.edit_ack_denied' and new_values ->> 'denied_reason' = 'invalid_device_type'
              and actor_employee_profile_id = 'e2ed0000-0000-0000-0000-00000000008a'
              and device_id = 'e2ed0000-0000-0000-0000-0000000000d1'
              and new_values ->> 'device_type' = 'pos'
              and new_values ->> 'attempted_action' = 'kitchen_ack_order_edit'
              and new_values ->> 'order_code' = '#' || upper(right(replace('e2ed0000-0000-0000-0000-00000000a001', '-', ''), 6)))
      and (select count(*) = 1 from audit_events
            where action = 'order.edit_ack_denied' and new_values ->> 'denied_reason' = 'permission_denied'
              and actor_employee_profile_id = 'e2ed0000-0000-0000-0000-00000000008a'
              and device_id = 'e2ed0000-0000-0000-0000-0000000000d2'
              and new_values ->> 'role' = 'cashier'),
  '11 the denial audit carries the PIN actor, the device, role / device type and the order code');
select ok((select count(*) = 0 from order_edits
            where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and kitchen_ack_at is not null)
      and (select o.row = (select to_jsonb(x) from orders x where x.id = 'e2ed0000-0000-0000-0000-00000000a001') from t_snap_a o),
  '12 the refusals stamped nothing and did not touch the order row');
select is((select count(*)::int from sync_operations
            where local_operation_id like 'ref-%' and operation_type = 'order.edit_ack'
              and status = 'rejected' and device_id in ('e2ed0000-0000-0000-0000-0000000000d1', 'e2ed0000-0000-0000-0000-0000000000d2')),
  8, '13 each refusal is ledgered once as a rejected order.edit_ack operation');

-- ===== C. the happy path: one tap covers every change up to N ================
create temp table t_ack1 as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'ack-1', 'e2ed0000-0000-0000-0000-00000000a001', 1) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'ok')::boolean and (r ->> 'acknowledged_count')::int = 1
                  and (r ->> 'up_to_edit_number')::int = 1 and r ->> 'order_id' = 'e2ed0000-0000-0000-0000-00000000a001'
             from t_ack1),
  '14 order.edit_ack up to 1 from the KDS kitchen_staff: ok, acknowledged_count 1');
select ok((select kitchen_ack_at = now() and kitchen_ack_by_employee_profile_id = 'e2ed0000-0000-0000-0000-00000000008c'
                  and kitchen_ack_device_id = 'e2ed0000-0000-0000-0000-0000000000d2'
             from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and edit_number = 1)
      and (select kitchen_ack_at is null and kitchen_ack_by_employee_profile_id is null and kitchen_ack_device_id is null
             from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and edit_number = 2),
  '15 only edit 1 is stamped (time = now(), the kitchen employee, the KDS); edit 2 is still pending');
create temp table t_ack2 as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'ack-2', 'e2ed0000-0000-0000-0000-00000000a001', 2) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'acknowledged_count')::int = 1 from t_ack2)
      and (select kitchen_ack_at = now() and kitchen_ack_by_employee_profile_id = 'e2ed0000-0000-0000-0000-00000000008c'
                  and kitchen_ack_device_id = 'e2ed0000-0000-0000-0000-0000000000d2'
             from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and edit_number = 2),
  '16 up to 2: acknowledged_count 1 (edit 1 is not re-stamped), edit 2 now stamped');
create temp table t_ack3 as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'ack-3', 'e2ed0000-0000-0000-0000-00000000a001', 3) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'ok')::boolean and (r ->> 'acknowledged_count')::int = 0 from t_ack3),
  '17 up to 3: ok with acknowledged_count 0 (edit 3 never required a confirmation)');
create temp table t_ack4 as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'ack-4', 'e2ed0000-0000-0000-0000-00000000a001', 2) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'ok')::boolean and (r ->> 'acknowledged_count')::int = 0 from t_ack4),
  '18 again up to 2: idempotent, ok with acknowledged_count 0');
select is((select count(*)::int from audit_events
            where action = 'order.edit_acknowledged' and new_values ->> 'order_id' = 'e2ed0000-0000-0000-0000-00000000a001'),
  2, '19 only the two stamping acks are audited (no order.edit_acknowledged for a zero count)');
select ok((select string_agg((new_values ->> 'up_to_edit_number') || ':' || (new_values ->> 'acknowledged_count'), ','
                             order by (new_values ->> 'up_to_edit_number')::int) = '1:1,2:1'
                  and bool_and(actor_employee_profile_id = 'e2ed0000-0000-0000-0000-00000000008c'
                               and device_id = 'e2ed0000-0000-0000-0000-0000000000d2'
                               and new_values ->> 'role' = 'kitchen_staff' and new_values ->> 'device_type' = 'kds')
             from audit_events
            where action = 'order.edit_acknowledged' and new_values ->> 'order_id' = 'e2ed0000-0000-0000-0000-00000000a001'),
  '20 order.edit_acknowledged carries up_to_edit_number and acknowledged_count (1:1, 2:1) and the actor/device');
select ok((select kitchen_ack_at is null and kitchen_ack_by_employee_profile_id is null and kitchen_ack_device_id is null
                  and not kitchen_ack_required
             from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and edit_number = 3),
  '21 the edit that did not require confirmation is never stamped');
select ok((select o.row = (select to_jsonb(x) from orders x where x.id = 'e2ed0000-0000-0000-0000-00000000a001')
                  and (o.row ->> 'revision')::int = 4 from t_snap_a o),
  '22 no write to orders: the order row (revision 4) is unchanged by every ack');
create temp table t_ack1r as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'ack-1', 'e2ed0000-0000-0000-0000-00000000a001', 1) as r;
select ok((select (r ->> 'idempotency_replay')::boolean and r ->> 'status' = 'applied' and (r ->> 'acknowledged_count')::int = 1 from t_ack1r)
      and (select count(*) = 2 from audit_events
            where action = 'order.edit_acknowledged' and new_values ->> 'order_id' = 'e2ed0000-0000-0000-0000-00000000a001'),
  '23 a transport replay of ack-1 returns its stored result and writes nothing');
select is((select count(*)::int from sync_operations
            where local_operation_id in ('ack-1', 'ack-2', 'ack-3', 'ack-4') and operation_type = 'order.edit_ack'
              and status = 'applied' and target_id = 'e2ed0000-0000-0000-0000-00000000a001'
              and device_id = 'e2ed0000-0000-0000-0000-0000000000d2'),
  4, '24 the four acks are ledgered applied, bound to the order');

-- ===== D. served and completed orders are ACCEPTED ===========================
update orders set status = 'served', ready_at = now() - interval '1 minute' where id = 'e2ed0000-0000-0000-0000-00000000a002';
update orders set status = 'completed', ready_at = now() - interval '1 minute' where id = 'e2ed0000-0000-0000-0000-00000000a003';
create temp table t_snap_sc as select id, revision from orders
  where id in ('e2ed0000-0000-0000-0000-00000000a002', 'e2ed0000-0000-0000-0000-00000000a003');
create temp table t_ack_s as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'ack-s', 'e2ed0000-0000-0000-0000-00000000a002', 1) as r;
create temp table t_ack_c as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009f', 'ack-c', 'e2ed0000-0000-0000-0000-00000000a003', 1) as r;
select ok((select r ->> 'status' = 'applied' and (r ->> 'acknowledged_count')::int = 1 from t_ack_s)
      and (select kitchen_ack_at = now() and kitchen_ack_by_employee_profile_id = 'e2ed0000-0000-0000-0000-00000000008c'
             from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000a002' and edit_number = 1)
      and (select o.revision = s.revision and o.status = 'served' from orders o join t_snap_sc s on s.id = o.id
            where o.id = 'e2ed0000-0000-0000-0000-00000000a002'),
  '25 a SERVED order is accepted: the pending edit is stamped, revision unchanged');
select ok((select r ->> 'status' = 'applied' and (r ->> 'acknowledged_count')::int = 1 from t_ack_c)
      and (select kitchen_ack_at = now() and kitchen_ack_by_employee_profile_id = 'e2ed0000-0000-0000-0000-00000000008b'
                  and kitchen_ack_device_id = 'e2ed0000-0000-0000-0000-0000000000d2'
             from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000a003' and edit_number = 1)
      and (select o.revision = s.revision and o.status = 'completed' from orders o join t_snap_sc s on s.id = o.id
            where o.id = 'e2ed0000-0000-0000-0000-00000000a003'),
  '26 a COMPLETED order is accepted (a manager on the KDS may confirm), revision unchanged');

-- ===== E. anti-oracle (RISK R-003) ===========================================
create temp table t_or1 as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'oracle-none', 'e2ed0000-0000-0000-0000-00000000dead', 1) as r;
create temp table t_or2 as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'oracle-foreign', 'e2ed0000-0000-0000-0000-00000000b0b1', 1) as r;
select ok((select r ->> 'status' = 'rejected' and r ->> 'sqlstate' = '42501' and r ->> 'error' = 'rejected' from t_or1),
  '27 a nonexistent order id is rejected with sqlstate 42501 (raised, never a typed refusal)');
select ok((select r ->> 'status' = 'rejected' and r ->> 'sqlstate' = '42501' from t_or2)
      and (select (a.r - 'local_operation_id') = (b.r - 'local_operation_id') from t_or1 a, t_or2 b),
  '28 another organization''s order is rejected with the SAME 42501 envelope (indistinguishable)');
select ok((select kitchen_ack_required and kitchen_ack_at is null
             from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000b0b1' and edit_number = 1)
      and not exists (select 1 from audit_events
                       where action in ('order.edit_acknowledged', 'order.edit_ack_denied')
                         and new_values ->> 'order_id' in ('e2ed0000-0000-0000-0000-00000000b0b1',
                                                          'e2ed0000-0000-0000-0000-00000000dead')),
  '29 the foreign edit stays pending and neither probe wrote an ack / ack-denied audit');

-- ===== F. identity hardening in sync_push ====================================
create temp table t_id1 as select public.sync_push('e2ed0000-0000-0000-0000-00000000009c', 'e2ed0000-0000-0000-0000-0000000000d2',
  jsonb_build_array(jsonb_build_object('local_operation_id', 'idh-ack-1', 'operation_type', 'order.edit_ack',
    'target_entity', 'order', 'target_id', 'e2ed0000-0000-0000-0000-00000000a002',
    'payload', jsonb_build_object('order_id', 'e2ed0000-0000-0000-0000-00000000a001', 'up_to_edit_number', 1)))) -> 'results' -> 0 as r;
create temp table t_id2 as select public.sync_push('e2ed0000-0000-0000-0000-00000000009c', 'e2ed0000-0000-0000-0000-0000000000d2',
  jsonb_build_array(jsonb_build_object('local_operation_id', 'idh-ack-2', 'operation_type', 'order.edit_ack',
    'target_entity', 'order',
    'payload', jsonb_build_object('order_id', 'e2ed0000-0000-0000-0000-00000000a001', 'up_to_edit_number', 1)))) -> 'results' -> 0 as r;
create temp table t_id3 as select public.sync_push('e2ed0000-0000-0000-0000-00000000009a', 'e2ed0000-0000-0000-0000-0000000000d1',
  jsonb_build_array(jsonb_build_object('local_operation_id', 'idh-edit-1', 'operation_type', 'order.edit',
    'target_entity', 'order', 'target_id', 'e2ed0000-0000-0000-0000-00000000a002',
    'payload', '{"order_id": "e2ed0000-0000-0000-0000-00000000a001",
                 "expected": {"subtotal_minor": 5400, "tax_total_minor": 0, "grand_total_minor": 5400},
                 "changes": [{"op": "add", "item": {"menu_item_id": "e2ed0000-0000-0000-0000-000000001003", "quantity": 1,
                   "unit_price_minor_snapshot": 800, "menu_item_name_snapshot": "Cola"}}]}'::jsonb))) -> 'results' -> 0 as r;
select ok((select r ->> 'status' = 'rejected' and r ->> 'error' = 'invalid_payload' from t_id1)
      and not exists (select 1 from sync_operations where local_operation_id = 'idh-ack-1'),
  '30 order.edit_ack whose target_id differs from payload.order_id: invalid_payload, NO ledger row');
select ok((select r ->> 'status' = 'rejected' and r ->> 'error' = 'invalid_payload' from t_id2)
      and not exists (select 1 from sync_operations where local_operation_id = 'idh-ack-2'),
  '31 order.edit_ack without a target_id: invalid_payload, NO ledger row');
select ok((select r ->> 'status' = 'rejected' and r ->> 'error' = 'invalid_payload' from t_id3)
      and not exists (select 1 from sync_operations where local_operation_id = 'idh-edit-1')
      and (select edit_count = 3 from orders where id = 'e2ed0000-0000-0000-0000-00000000a001')
      and (select edit_count = 1 from orders where id = 'e2ed0000-0000-0000-0000-00000000a002'),
  '32 order.edit whose target_id differs from payload.order_id: invalid_payload, NO ledger row, no edit');

-- ===== G. app.void_order — the widened kitchen acknowledgement ==============
-- (a) served parent + a live service round in preparing -> TRUE
create temp table t_va as select app.void_order('e2ed0000-0000-0000-0000-00000000009b', 'e2ed0000-0000-0000-0000-00000000ca01',
  'e2ed0000-0000-0000-0000-0000000000d1', 'void-va', 'ackvoid case a') as r;
select ok((select (r ->> 'ok')::boolean from t_va)
      and (select status = 'voided' and voided_from_status = 'served' and kitchen_ack_required
             from orders where id = 'e2ed0000-0000-0000-0000-00000000ca01')
      and (select count(*) = 1 and bool_and((new_values ->> 'kitchen_ack_required')::boolean)
             from audit_events where action = 'order.voided' and reason = 'ackvoid case a'),
  '33 (a) a served order with a live round in preparing: kitchen_ack_required TRUE (column and order.voided audit)');
-- (b) an edit removed from the live unit, then the unit was served -> TRUE
update orders set status = 'served', ready_at = now() - interval '1 minute' where id = 'e2ed0000-0000-0000-0000-00000000cb01';
create temp table t_vb_pre as select
  (select count(*) from order_service_rounds where order_id = 'e2ed0000-0000-0000-0000-00000000cb01') as rounds,
  (select count(*) from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000cb01'
      and kitchen_ack_required and kitchen_ack_at is null) as pending;
create temp table t_vb as select app.void_order('e2ed0000-0000-0000-0000-00000000009b', 'e2ed0000-0000-0000-0000-00000000cb01',
  'e2ed0000-0000-0000-0000-0000000000d1', 'void-vb', 'ackvoid case b') as r;
select ok((select rounds = 0 and pending = 1 from t_vb_pre)
      and (select (r ->> 'ok')::boolean from t_vb)
      and (select status = 'voided' and voided_from_status = 'served' and kitchen_ack_required
             from orders where id = 'e2ed0000-0000-0000-0000-00000000cb01')
      and (select count(*) = 1 and bool_and((new_values ->> 'kitchen_ack_required')::boolean)
             from audit_events where action = 'order.voided' and reason = 'ackvoid case b'),
  '34 (b) a served order (no round) with a PENDING edit confirmation: kitchen_ack_required TRUE');
create temp table t_vb_ack as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'ack-vb', 'e2ed0000-0000-0000-0000-00000000cb01', 1) as r;
select ok((select r ->> 'status' = 'rejected' and r ->> 'error' = 'order_voided' and r ->> 'order_status' = 'voided'
                  and r ->> 'sqlstate' is null from t_vb_ack)
      and (select kitchen_ack_at is null from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000cb01' and edit_number = 1)
      and (select count(*) = 1 from audit_events where action = 'order.edit_ack_denied'
            and new_values ->> 'order_id' = 'e2ed0000-0000-0000-0000-00000000cb01'
            and new_values ->> 'denied_reason' = 'order_voided'),
  '35 (b) the edit_ack on the voided order: order_voided, nothing stamped, audited');
-- (c) served, the edit already confirmed, only a served round -> FALSE
create temp table t_vc_ack as select pg_temp.ackn('e2ed0000-0000-0000-0000-00000000009c', 'ack-vc', 'e2ed0000-0000-0000-0000-00000000cc01', 1) as r;
select pg_temp.mk_round('e2ed0000-0000-0000-0000-0000000cc1e2', 'e2ed0000-0000-0000-0000-00000000cc01', 2, 'served');
select pg_temp.mk_item('e2ed0000-0000-0000-0000-0000000cc103', 'e2ed0000-0000-0000-0000-00000000cc01', 'e2ed0000-0000-0000-0000-000000001004', 'Lemonade', 1, 900, 900, 'e2ed0000-0000-0000-0000-0000000cc1e2');
select pg_temp.settle_totals('e2ed0000-0000-0000-0000-00000000cc01');
update orders set status = 'served', ready_at = now() - interval '1 minute' where id = 'e2ed0000-0000-0000-0000-00000000cc01';
create temp table t_vc as select app.void_order('e2ed0000-0000-0000-0000-00000000009b', 'e2ed0000-0000-0000-0000-00000000cc01',
  'e2ed0000-0000-0000-0000-0000000000d1', 'void-vc', 'ackvoid case c') as r;
select ok((select (r ->> 'acknowledged_count')::int = 1 from t_vc_ack)
      and (select (r ->> 'ok')::boolean from t_vc)
      and (select status = 'voided' and voided_from_status = 'served' and not kitchen_ack_required
             from orders where id = 'e2ed0000-0000-0000-0000-00000000cc01')
      and (select count(*) = 1 and bool_and(not (new_values ->> 'kitchen_ack_required')::boolean)
             from audit_events where action = 'order.voided' and reason = 'ackvoid case c'),
  '36 (c) a served order, no live round, no pending confirmation: kitchen_ack_required FALSE (unchanged)');
-- (d) preparing -> TRUE (unchanged)
create temp table t_vd as select app.void_order('e2ed0000-0000-0000-0000-00000000009b', 'e2ed0000-0000-0000-0000-00000000cd01',
  'e2ed0000-0000-0000-0000-0000000000d1', 'void-vd', 'ackvoid case d') as r;
select ok((select (r ->> 'ok')::boolean from t_vd)
      and (select status = 'voided' and voided_from_status = 'preparing' and kitchen_ack_required
             from orders where id = 'e2ed0000-0000-0000-0000-00000000cd01')
      and (select count(*) = 1 and bool_and((new_values ->> 'kitchen_ack_required')::boolean)
             from audit_events where action = 'order.voided' and reason = 'ackvoid case d'),
  '37 (d) a preparing order: kitchen_ack_required TRUE (unchanged)');

-- ===== H. order_edits is append-only; the acknowledgement is write-once =====
select throws_ok($$update order_edits set reason_code = 'entry_mistake'
                    where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and edit_number = 2$$,
  '23514', 'order_edits: only the one-time kitchen acknowledgement may change after insert',
  '38 UPDATE of reason_code RAISES 23514');
select throws_ok($$update order_edits set edit_number = 9
                    where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and edit_number = 3$$,
  '23514', 'order_edits: only the one-time kitchen acknowledgement may change after insert',
  '39 UPDATE of edit_number RAISES 23514');
select throws_ok($$update order_edits set kitchen_ack_at = now() + interval '1 minute',
                         kitchen_ack_by_employee_profile_id = 'e2ed0000-0000-0000-0000-00000000008b'
                    where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and edit_number = 1$$,
  '23514', 'order_edits: the kitchen acknowledgement is write-once',
  '40 a second acknowledgement overwrite RAISES 23514');
select throws_ok($$update order_edits set kitchen_ack_at = null, kitchen_ack_by_employee_profile_id = null,
                         kitchen_ack_device_id = null
                    where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and edit_number = 2$$,
  '23514', 'order_edits: the kitchen acknowledgement is write-once',
  '41 clearing a stamped acknowledgement RAISES 23514');
select throws_ok($$delete from order_edits where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and edit_number = 3$$,
  '23514', 'order_edits: rows are append-only and can never be deleted',
  '42 DELETE RAISES 23514');
select throws_ok($$update order_edits set kitchen_ack_at = now()
                    where order_id = 'e2ed0000-0000-0000-0000-00000000cb01' and edit_number = 1$$,
  '23514', 'new row for relation "order_edits" violates check constraint "order_edits_kitchen_ack_state_check"',
  '43 a partial acknowledgement triple RAISES 23514 (CHECK)');
select throws_ok($$update order_edits set kitchen_ack_at = now(),
                         kitchen_ack_by_employee_profile_id = 'e2ed0000-0000-0000-0000-00000000008c',
                         kitchen_ack_device_id = 'e2ed0000-0000-0000-0000-0000000000d2'
                    where order_id = 'e2ed0000-0000-0000-0000-00000000a001' and edit_number = 3$$,
  '23514', 'new row for relation "order_edits" violates check constraint "order_edits_kitchen_ack_state_check"',
  '44 an edit that did not require confirmation cannot be stamped (CHECK)');
select throws_ok($$insert into order_edits (organization_id, restaurant_id, branch_id, order_id, edit_number,
                      device_id, local_operation_id, pin_session_id, employee_profile_id, membership_id,
                      kitchen_channel, kitchen_ack_required)
                    values ('e2ed0000-0000-0000-0000-0000000000a0', 'e2ed0000-0000-0000-0000-0000000000a1',
                      'e2ed0000-0000-0000-0000-0000000000ab', 'e2ed0000-0000-0000-0000-00000000a001', 99,
                      'e2ed0000-0000-0000-0000-0000000000d1', 'paper-ack-1', 'e2ed0000-0000-0000-0000-00000000009a',
                      'e2ed0000-0000-0000-0000-00000000008a', 'e2ed0000-0000-0000-0000-00000000007a',
                      'paper', true)$$,
  '23514', 'new row for relation "order_edits" violates check constraint "order_edits_paper_no_ack_check"',
  '45 a paper-channel row can never require a kitchen acknowledgement (CHECK)');

-- ===== I. order_items edit provenance is write-once ==========================
select throws_ok($$update order_items set edit_id = pg_temp.eid('e2ed0000-0000-0000-0000-00000000a001', 2)
                    where order_id = 'e2ed0000-0000-0000-0000-00000000a001'
                      and edit_id = pg_temp.eid('e2ed0000-0000-0000-0000-00000000a001', 1)$$,
  '23514', 'order_items: edit_id / replaces_order_item_id are fixed at insert',
  '46 changing edit_id after insert RAISES 23514');
select throws_ok($$update order_items set edit_id = pg_temp.eid('e2ed0000-0000-0000-0000-00000000a001', 1)
                    where id = 'e2ed0000-0000-0000-0000-0000000a1002'$$,
  '23514', 'order_items: edit_id / replaces_order_item_id are fixed at insert',
  '47 setting edit_id on a row inserted without one RAISES 23514');
select throws_ok($$update order_items set replaces_order_item_id = 'e2ed0000-0000-0000-0000-0000000a1002'
                    where replaces_order_item_id = 'e2ed0000-0000-0000-0000-0000000a1001'$$,
  '23514', 'order_items: edit_id / replaces_order_item_id are fixed at insert',
  '48 changing replaces_order_item_id after insert RAISES 23514');
select throws_ok($$update order_items set removed_by_edit_id = pg_temp.eid('e2ed0000-0000-0000-0000-00000000a001', 1)
                    where id = 'e2ed0000-0000-0000-0000-0000000a1003'$$,
  '23514', 'order_items: removed_by_edit_id / removed_kitchen_stage are write-once',
  '49 changing an already-set removed_by_edit_id RAISES 23514');
select throws_ok($$update order_items set removed_kitchen_stage = 'ready'
                    where id = 'e2ed0000-0000-0000-0000-0000000a1003'$$,
  '23514', 'order_items: removed_by_edit_id / removed_kitchen_stage are write-once',
  '50 changing an already-set removed_kitchen_stage RAISES 23514');
select throws_ok($$update order_items set removed_by_edit_id = pg_temp.eid('e2ed0000-0000-0000-0000-00000000a001', 1),
                         removed_kitchen_stage = 'preparing'
                    where id = 'e2ed0000-0000-0000-0000-0000000a1002'$$,
  '23514', 'new row for relation "order_items" violates check constraint "order_items_removed_status_check"',
  '51 removed_by_edit_id on a LIVE line RAISES 23514 (CHECK)');
select throws_ok($$update order_items set removed_by_edit_id = pg_temp.eid('e2ed0000-0000-0000-0000-00000000cb01', 1)
                    where id = 'e2ed0000-0000-0000-0000-0000000cb101'$$,
  '23514', 'new row for relation "order_items" violates check constraint "order_items_removed_stage_pair_check"',
  '52 removed_by_edit_id without removed_kitchen_stage RAISES 23514 (CHECK)');
select throws_ok($$insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
                      quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor,
                      replaces_order_item_id)
                    values ('e2ed0000-0000-0000-0000-0000000ee001', 'e2ed0000-0000-0000-0000-0000000000a0',
                      'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab',
                      'e2ed0000-0000-0000-0000-00000000a001', 'e2ed0000-0000-0000-0000-000000001003',
                      1, 'Cola', 800, 0, 800, 'e2ed0000-0000-0000-0000-0000000a1002')$$,
  '23514', 'new row for relation "order_items" violates check constraint "order_items_replaces_requires_edit_check"',
  '53 replaces_order_item_id without edit_id RAISES 23514 (CHECK)');
select throws_ok($$insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id,
                      quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor,
                      edit_id)
                    values ('e2ed0000-0000-0000-0000-0000000ee002', 'e2ed0000-0000-0000-0000-0000000000a0',
                      'e2ed0000-0000-0000-0000-0000000000a1', 'e2ed0000-0000-0000-0000-0000000000ab',
                      'e2ed0000-0000-0000-0000-00000000a002', 'e2ed0000-0000-0000-0000-000000001003',
                      1, 'Cola', 800, 0, 800, pg_temp.eid('e2ed0000-0000-0000-0000-00000000a001', 1))$$,
  '23503', 'insert or update on table "order_items" violates foreign key constraint "order_items_edit_fkey"',
  '54 an edit_id of ANOTHER order is rejected by the composite FK (23503)');

-- ===== J. order_service_rounds.voided_by_edit_id needs a voided round ========
select throws_ok($$update order_service_rounds set voided_by_edit_id = pg_temp.eid('e2ed0000-0000-0000-0000-00000000a001', 3)
                    where edit_id = pg_temp.eid('e2ed0000-0000-0000-0000-00000000a001', 3)$$,
  '23514', 'new row for relation "order_service_rounds" violates check constraint "order_service_rounds_voided_by_edit_check"',
  '55 voided_by_edit_id on a non-voided round RAISES 23514 (CHECK)');

select * from finish();
rollback;
