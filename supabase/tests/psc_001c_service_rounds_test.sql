-- ============================================================================
-- PSC-001C — pgTAP: service rounds, order additions, POS order detail,
--            completion integration and the ready feed.
-- ============================================================================
-- Proves the whole contract end-to-end through public.sync_push /
-- public.pos_order_detail / public.pos_ready_feed:
--   * order_service_rounds schema: defaults, CHECKs, same-parent FK, unique
--     never-reused round numbers;
--   * app.add_order_items (op #14): POS-only + cashier+ device/role gates,
--     eligibility (dine_in, open status, payment freeze), submit_order-parity
--     pricing/sellability, no-addition-line-discount, round allocation,
--     idempotent replay, PSC-001D-grade identity hardening, anti-oracle;
--   * app.update_round_status (op #15): the LOCKED device/role matrix,
--     single-step legality, parent guards, write-once ready_at, item
--     non-mutation, replay/race convergence, hardening;
--   * completion: both race directions, manual rounds_not_served, zero-round
--     regression, exactly-once automatic audit;
--   * whole-order void: round cascade, post-void refusal, PSC-001D ack intact;
--   * pos_ready_feed: derived durable rows, frozen-clock keyset pagination
--     (equal ready_at cannot skip), historical preservation, no money;
--   * pos_order_detail: combined authoritative items (cross-device), payment;
--   * sync_pull: rounds reach the kitchen; old clients unaffected;
--   * revoked-device path hardening for the two new operations.
-- Fixtures inserted as the BYPASSRLS connection role (RF-056/RF-057 convention).
-- NOTE: inside this single transaction now() is FROZEN — every ready_at stamp
-- shares one timestamp, which deliberately makes the feed's equal-timestamp
-- keyset paging a REQUIRED behavior here, not an edge case.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(98);

-- ===== fixtures: Org A (2 POS + 2 KDS devices) + Org B (1 POS) ===============
insert into organizations (id, name, slug, default_currency) values
  ('c0000000-0000-0000-0000-000000000c01', 'Org RC', 'rc-a', 'USD'),
  ('f0000000-0000-0000-0000-000000000c01', 'Org RB', 'rc-b', 'USD');
insert into restaurants (id, organization_id, name) values
  ('c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c01', 'Rest RC'),
  ('f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c01', 'Rest RB');
insert into branches (id, organization_id, restaurant_id, name) values
  ('c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'Branch RC'),
  ('f0000000-0000-0000-0000-000000000c03', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'Branch RB');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('c0000000-0000-0000-0000-0000000000d1', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'pos'),
  ('c0000000-0000-0000-0000-0000000000d2', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'kds'),
  ('c0000000-0000-0000-0000-0000000000d3', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'kds'),
  ('c0000000-0000-0000-0000-0000000000d4', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'pos'),
  ('f0000000-0000-0000-0000-0000000000d1', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d1', 'active'),
  ('c0000000-0000-0000-0000-0000000000a2', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d2', 'active'),
  ('c0000000-0000-0000-0000-0000000000a3', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d3', 'active'),
  ('c0000000-0000-0000-0000-0000000000a4', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d4', 'active'),
  ('f0000000-0000-0000-0000-0000000000a1', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'f0000000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('c0000000-0000-0000-0000-0000000000e1', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d1', 'c0000000-0000-0000-0000-0000000000a1'),
  ('c0000000-0000-0000-0000-0000000000e2', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d2', 'c0000000-0000-0000-0000-0000000000a2'),
  ('c0000000-0000-0000-0000-0000000000e3', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d3', 'c0000000-0000-0000-0000-0000000000a3'),
  ('c0000000-0000-0000-0000-0000000000e4', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000d4', 'c0000000-0000-0000-0000-0000000000a4'),
  ('f0000000-0000-0000-0000-0000000000e1', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'f0000000-0000-0000-0000-0000000000d1', 'f0000000-0000-0000-0000-0000000000a1');
insert into app_users (id, email) values
  ('c0000000-0000-0000-0000-0000000ae001', 'rc-mgr@example.test'),
  ('c0000000-0000-0000-0000-0000000ae002', 'rc-cash@example.test'),
  ('c0000000-0000-0000-0000-0000000ae003', 'rc-kitchen@example.test'),
  ('f0000000-0000-0000-0000-0000000be001', 'rb-mgr@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('c0000000-0000-0000-0000-0000000ab001', 'c0000000-0000-0000-0000-0000000ae001', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'manager', '{}'::jsonb),
  ('c0000000-0000-0000-0000-0000000ab002', 'c0000000-0000-0000-0000-0000000ae002', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'cashier', '{}'::jsonb),
  ('c0000000-0000-0000-0000-0000000ab003', 'c0000000-0000-0000-0000-0000000ae003', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'kitchen_staff', '{}'::jsonb),
  ('f0000000-0000-0000-0000-0000000bb001', 'f0000000-0000-0000-0000-0000000be001', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'manager', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('c0000000-0000-0000-0000-0000000ac001', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000ae001', 'c0000000-0000-0000-0000-0000000ab001'),
  ('c0000000-0000-0000-0000-0000000ac002', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000ae002', 'c0000000-0000-0000-0000-0000000ab002'),
  ('c0000000-0000-0000-0000-0000000ac003', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000ae003', 'c0000000-0000-0000-0000-0000000ab003'),
  ('f0000000-0000-0000-0000-0000000bc001', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'f0000000-0000-0000-0000-0000000be001', 'f0000000-0000-0000-0000-0000000bb001');
-- PIN sessions: mgr/cashier/kitchen on POS-1; kitchen/mgr/cashier on KDS-1;
-- kitchen on KDS-2; cashier on POS-2; Org B mgr on B's POS.
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e1', 'c0000000-0000-0000-0000-0000000ac001', 'c0000000-0000-0000-0000-0000000ab001', now() + interval '1 hour'),
  ('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e1', 'c0000000-0000-0000-0000-0000000ac002', 'c0000000-0000-0000-0000-0000000ab002', now() + interval '1 hour'),
  ('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e2', 'c0000000-0000-0000-0000-0000000ac003', 'c0000000-0000-0000-0000-0000000ab003', now() + interval '1 hour'),
  ('c0000000-0000-0000-0000-0000000ad004', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e2', 'c0000000-0000-0000-0000-0000000ac002', 'c0000000-0000-0000-0000-0000000ab002', now() + interval '1 hour'),
  ('c0000000-0000-0000-0000-0000000ad005', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e1', 'c0000000-0000-0000-0000-0000000ac003', 'c0000000-0000-0000-0000-0000000ab003', now() + interval '1 hour'),
  ('c0000000-0000-0000-0000-0000000ad007', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e3', 'c0000000-0000-0000-0000-0000000ac003', 'c0000000-0000-0000-0000-0000000ab003', now() + interval '1 hour'),
  ('c0000000-0000-0000-0000-0000000ad009', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000e4', 'c0000000-0000-0000-0000-0000000ac002', 'c0000000-0000-0000-0000-0000000ab002', now() + interval '1 hour'),
  ('f0000000-0000-0000-0000-0000000bd001', 'f0000000-0000-0000-0000-000000000c01', 'f0000000-0000-0000-0000-000000000c02', 'f0000000-0000-0000-0000-000000000c03', 'f0000000-0000-0000-0000-0000000000e1', 'f0000000-0000-0000-0000-0000000bc001', 'f0000000-0000-0000-0000-0000000bb001', now() + interval '1 hour');

-- Menu + floor fixtures for org A.
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('c0000000-0000-0000-0000-0000000000c9', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('c0000000-0000-0000-0000-0000000000f9', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', null, 'c0000000-0000-0000-0000-0000000000c9', 'Item', 500, 'USD', 1),
  ('c0000000-0000-0000-0000-0000000000f8', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', null, 'c0000000-0000-0000-0000-0000000000c9', 'SoldOut', 400, 'USD', 2);
insert into menu_item_branch_availability (organization_id, restaurant_id, branch_id, menu_item_id, availability, reason) values
  ('c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-0000000000f8', 'unavailable', 'sold_out');
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('c0000000-0000-0000-0000-00000000ba01', 'c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'T1');

-- ---- helpers ---------------------------------------------------------------
-- submit a dine-in (table T1) or takeaway one-line order: item f9 qty 2 @500.
create or replace function pg_temp.csubmit(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_type text) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.submit', 'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', p_order, 'order_type', p_type,
      'table_id', case when p_type = 'dine_in' then 'c0000000-0000-0000-0000-00000000ba01' end,
      'currency_code', 'USD',
      'subtotal_minor', 1000, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 1000,
      'order_items', jsonb_build_array(jsonb_build_object(
        'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 2,
        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item'))))));
$$;
create or replace function pg_temp.cstatus(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_to text) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.status', 'target_entity', 'order',
    'payload', jsonb_build_object('order_id', p_order, 'new_status', p_to))));
$$;
-- advance an ORDER submitted -> served with four kitchen ops.
create or replace function pg_temp.cserve(p_prefix text, p_order uuid) returns void language plpgsql as $$
begin
  perform pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', p_prefix || '-a', p_order, 'accepted');
  perform pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', p_prefix || '-b', p_order, 'preparing');
  perform pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', p_prefix || '-c', p_order, 'ready');
  perform pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', p_prefix || '-d', p_order, 'served');
end;
$$;
create or replace function pg_temp.cpay(p_op text, p_order uuid) returns jsonb language sql as $$
  select public.sync_push('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op, 'operation_type', 'payment.create', 'target_entity', 'payment',
      'payload', jsonb_build_object('order_id', p_order, 'tender_type', 'card', 'amount_tendered_minor', 0))));
$$;
create or replace function pg_temp.cvoid(p_op text, p_order uuid) returns jsonb language sql as $$
  select public.sync_push('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op, 'operation_type', 'order.void', 'target_entity', 'order',
      'payload', jsonb_build_object('order_id', p_order, 'reason', 'customer left'))));
$$;
-- canonical items_add: one line, item f9 qty 1 @500 (delta 500).
create or replace function pg_temp.cadd(p_pin uuid, p_dev uuid, p_op text, p_order uuid) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.items_add', 'target_entity', 'order',
    'target_id', p_order,
    'payload', jsonb_build_object(
      'order_id', p_order,
      'order_items', jsonb_build_array(jsonb_build_object(
        'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 1,
        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item'))))));
$$;
-- adversarial items_add: independent payload order + (possibly malformed) target.
create or replace function pg_temp.cadd2(p_pin uuid, p_dev uuid, p_op text, p_payload_order uuid, p_target text) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.items_add', 'target_entity', 'order',
    'target_id', p_target,
    'payload', jsonb_build_object(
      'order_id', p_payload_order,
      'order_items', jsonb_build_array(jsonb_build_object(
        'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 1,
        'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item'))))));
$$;
-- items_add with a CUSTOM item list.
create or replace function pg_temp.caddx(p_pin uuid, p_dev uuid, p_op text, p_order uuid, p_items jsonb) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.items_add', 'target_entity', 'order',
    'target_id', p_order,
    'payload', jsonb_build_object('order_id', p_order, 'order_items', p_items))));
$$;
-- canonical round_status.
create or replace function pg_temp.crst(p_pin uuid, p_dev uuid, p_op text, p_round uuid, p_to text) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.round_status', 'target_entity', 'order_service_round',
    'target_id', p_round,
    'payload', jsonb_build_object('round_id', p_round, 'new_status', p_to))));
$$;
-- adversarial round_status.
create or replace function pg_temp.crst2(p_pin uuid, p_dev uuid, p_op text, p_payload_round uuid, p_target text, p_to text) returns jsonb language sql as $$
  select public.sync_push(p_pin, p_dev, jsonb_build_array(jsonb_build_object(
    'local_operation_id', p_op, 'operation_type', 'order.round_status', 'target_entity', 'order_service_round',
    'target_id', p_target,
    'payload', jsonb_build_object('round_id', p_payload_round, 'new_status', p_to))));
$$;

-- ===== (1-8) structural: 15-op CHECK, dispatch arms, ACLs ====================
select ok(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'sync_operations_operation_type_check')
    like '%order.items_add%'
  and (select pg_get_constraintdef(oid) from pg_constraint where conname = 'sync_operations_operation_type_check')
    like '%order.round_status%',
  '1. sync_operations.operation_type CHECK accepts both new operations (15 ops)');
select ok(
  (select bool_and((select prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'app' and p.proname = 'sync_push') like '%when ''' || op || '''%')
     from unnest(array['shift.open','order.submit','order.discount','payment.create','shift.close','order.status','order.void','order.table_move','menu.availability_set','table.status_set','table.link','table.unlink','order.void_ack','order.items_add','order.round_status']) as op),
  '2. app.sync_push carries ALL 15 dispatch arms (13 prior + the two new)');
select ok(
  not has_function_privilege('anon', 'app.add_order_items(uuid,uuid,uuid,text,jsonb,timestamptz)', 'execute'),
  '3. anon cannot execute app.add_order_items');
select ok(
  not has_function_privilege('anon', 'app.update_round_status(uuid,uuid,uuid,text,text)', 'execute'),
  '4. anon cannot execute app.update_round_status');
select ok(
  has_function_privilege('authenticated', 'app.add_order_items(uuid,uuid,uuid,text,jsonb,timestamptz)', 'execute')
  and has_function_privilege('authenticated', 'app.update_round_status(uuid,uuid,uuid,text,text)', 'execute'),
  '5. authenticated may execute both new write RPCs (dispatcher path)');
select ok(
  not has_function_privilege('anon', 'public.pos_order_detail(uuid,uuid,uuid)', 'execute'),
  '6. anon cannot execute public.pos_order_detail');
select ok(
  not has_function_privilege('anon', 'public.pos_ready_feed(uuid,uuid,timestamptz,text,uuid,integer)', 'execute'),
  '7. anon cannot execute public.pos_ready_feed');
select ok(
  has_function_privilege('authenticated', 'public.pos_order_detail(uuid,uuid,uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.pos_ready_feed(uuid,uuid,timestamptz,text,uuid,integer)', 'execute'),
  '8. authenticated may execute both read wrappers');

-- ===== base flow fixtures ====================================================
-- Open ONE shift + drawer on POS-1 (cashier) so payments are possible.
select public.sync_push('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'sh-1', 'operation_type', 'shift.open', 'target_entity', 'shift',
    'payload', jsonb_build_object(
      'shift_id', 'c0000000-0000-0000-0000-00000000fa01',
      'cash_drawer_session_id', 'c0000000-0000-0000-0000-00000000fb01',
      'opening_float_minor', 0))));
-- Orders (dine-in unless stated): o1 (main additions target), o2 (served-state
-- additions), o3 takeaway, o4 (voided-eligibility), o5 (completed-eligibility),
-- o6 (paid-open), o8 (zero-round completion regression), oR1/oR2/oR3 (races),
-- oV (void integration).
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o1', 'c0000000-0000-0000-0000-00000000a001', 'dine_in');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o2', 'c0000000-0000-0000-0000-00000000a002', 'dine_in');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o3', 'c0000000-0000-0000-0000-00000000a003', 'takeaway');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o4', 'c0000000-0000-0000-0000-00000000a004', 'dine_in');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o5', 'c0000000-0000-0000-0000-00000000a005', 'dine_in');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o6', 'c0000000-0000-0000-0000-00000000a006', 'dine_in');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-o8', 'c0000000-0000-0000-0000-00000000a008', 'dine_in');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-r1', 'c0000000-0000-0000-0000-00000000a0b1', 'dine_in');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-r2', 'c0000000-0000-0000-0000-00000000a0b2', 'dine_in');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-r3', 'c0000000-0000-0000-0000-00000000a0b3', 'dine_in');
select pg_temp.csubmit('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'sub-ov', 'c0000000-0000-0000-0000-00000000a0c1', 'dine_in');

-- ===== (9-14) schema self-defence (D-012 layer 4) ============================
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-1', 'c0000000-0000-0000-0000-00000000a001');
select ok(
  (select (status = 'submitted' and revision = 1 and ready_at is null and deleted_at is null)
     from order_service_rounds where order_id = 'c0000000-0000-0000-0000-00000000a001' and round_number = 2),
  '9. a new round carries the safe defaults (submitted, revision 1, no ready stamp)');
select throws_ok(
  $$ insert into order_service_rounds (organization_id, restaurant_id, branch_id, order_id, round_number, device_id, opened_by_employee_profile_id)
     values ('c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-00000000a001', 1, 'c0000000-0000-0000-0000-0000000000d1', 'c0000000-0000-0000-0000-0000000ac002') $$,
  '23514', null, '10. round_number 1 violates the >= 2 CHECK (the original order IS work unit 1)');
select throws_ok(
  $$ insert into order_service_rounds (organization_id, restaurant_id, branch_id, order_id, round_number, device_id, opened_by_employee_profile_id)
     values ('c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-00000000a001', 2, 'c0000000-0000-0000-0000-0000000000d1', 'c0000000-0000-0000-0000-0000000ac002') $$,
  '23505', null, '11. a duplicate round_number per parent violates the unique backstop');
select throws_ok(
  $$ insert into order_service_rounds (organization_id, restaurant_id, branch_id, order_id, round_number, status, ready_at, device_id, opened_by_employee_profile_id)
     values ('c0000000-0000-0000-0000-000000000c01', 'c0000000-0000-0000-0000-000000000c02', 'c0000000-0000-0000-0000-000000000c03', 'c0000000-0000-0000-0000-00000000a001', 9, 'submitted', now(), 'c0000000-0000-0000-0000-0000000000d1', 'c0000000-0000-0000-0000-0000000ac002') $$,
  '23514', null, '12. a pre-ready round may not carry a ready stamp (null-safe CHECK)');
select throws_ok(
  $$ update orders set ready_at = now() where id = 'c0000000-0000-0000-0000-00000000a001' $$,
  '23514', null, '13. orders.ready_at is only legal at/after ready (backward-compatible CHECK)');
select throws_ok(
  $$ update order_items set service_round_id = (select id from order_service_rounds where order_id = 'c0000000-0000-0000-0000-00000000a001' limit 1)
     where order_id = 'c0000000-0000-0000-0000-00000000a002' and service_round_id is null $$,
  '23503', null, '14. an item can NEVER reference a round of a DIFFERENT order (same-parent composite FK)');

-- ===== (15-23) additions core ================================================
select is(
  (select round_number from order_service_rounds where order_id = 'c0000000-0000-0000-0000-00000000a001' and deleted_at is null),
  2, '15. the FIRST addition creates ROUND 2 (the original order is work unit 1)');
select ok(
  (select (revision = 2 and subtotal_minor = 1500 and grand_total_minor = 1500 and status = 'submitted')
     from orders where id = 'c0000000-0000-0000-0000-00000000a001'),
  '16. the parent gained the recomputed delta, bumped revision, and NEVER moved status');
select is(
  (select count(*)::int from order_items oi
     join order_service_rounds r on r.id = oi.service_round_id
     where oi.order_id = 'c0000000-0000-0000-0000-00000000a001' and r.round_number = 2),
  1, '17. the added item belongs to exactly the new round');
select is(
  (select count(*)::int from order_items
     where order_id = 'c0000000-0000-0000-0000-00000000a001' and service_round_id is null),
  1, '18. the ORIGINAL items keep NULL round membership');
select is(
  (pg_temp.caddx('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-2', 'c0000000-0000-0000-0000-00000000a001',
     jsonb_build_array(jsonb_build_object(
       'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 1,
       'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item',
       'modifiers', jsonb_build_array(jsonb_build_object(
         'modifier_option_id', 'c0000000-0000-0000-0000-00000000fc01',
         'option_name_snapshot', 'Extra', 'price_minor_snapshot', 100, 'quantity', 2)))))
   -> 'results' -> 0 ->> 'round_number')::int,
  3, '20. the SECOND addition allocates round 3 (monotonic per parent)');
select ok(
  (select (m.option_name_snapshot = 'Extra' and m.price_minor_snapshot = 100 and m.quantity = 2)
     from order_item_modifiers m
     join order_items oi on oi.id = m.order_item_id
     join order_service_rounds r on r.id = oi.service_round_id
     where r.round_number = 3 and r.order_id = 'c0000000-0000-0000-0000-00000000a001'),
  '19. added-item modifier snapshots are stored (name/price/quantity)');
create temp table add_replay as
  select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-1', 'c0000000-0000-0000-0000-00000000a001') as r;
select ok(
  (select ((r -> 'results' -> 0 ->> 'idempotency_replay')::boolean
           and (r -> 'results' -> 0 ->> 'round_number')::int = 2) from add_replay),
  '21. an EXACT replay returns the SAME round (idempotency_replay=true)');
select is(
  (select count(*)::int from order_service_rounds where order_id = 'c0000000-0000-0000-0000-00000000a001'),
  2, '22. the replay created NO duplicate round (and no duplicate items)');
select is(
  (select count(*)::int from audit_events where action = 'order.items_added'
     and (new_values ->> 'order_id') = 'c0000000-0000-0000-0000-00000000a001'
     and (new_values ->> 'round_number')::int = 2),
  1, '23. exactly ONE order.items_added audit for round 2 (replay wrote no second)');

-- ===== (24-36) eligibility + payload contracts ===============================
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-tw', 'c0000000-0000-0000-0000-00000000a003') -> 'results' -> 0 ->> 'error'),
  'order_not_dine_in', '24. a TAKEAWAY order refuses additions (out of scope this version)');
select pg_temp.cvoid('vd-o4', 'c0000000-0000-0000-0000-00000000a004');
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-void', 'c0000000-0000-0000-0000-00000000a004') -> 'results' -> 0 ->> 'error'),
  'order_not_eligible', '25. a VOIDED order refuses additions');
select pg_temp.cserve('st5', 'c0000000-0000-0000-0000-00000000a005');
select pg_temp.cpay('pay-o5', 'c0000000-0000-0000-0000-00000000a005');
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-done', 'c0000000-0000-0000-0000-00000000a005') -> 'results' -> 0 ->> 'error'),
  'order_not_eligible', '26. a COMPLETED order refuses additions');
select pg_temp.cpay('pay-o6', 'c0000000-0000-0000-0000-00000000a006');
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-paid', 'c0000000-0000-0000-0000-00000000a006') -> 'results' -> 0 ->> 'error'),
  'order_already_settled', '27. a PAID-BUT-OPEN order refuses additions (the payment freeze)');
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-r1', 'c0000000-0000-0000-0000-00000000a0b1');
select is(
  (pg_temp.cpay('pay-r1', 'c0000000-0000-0000-0000-00000000a0b1') -> 'results' -> 0 ->> 'status'),
  'applied', '28. payment IS allowed while an additional round is active (locked)');
select is(
  (pg_temp.caddx('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-disc', 'c0000000-0000-0000-0000-00000000a001',
     jsonb_build_array(jsonb_build_object(
       'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 1,
       'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item',
       'line_discount_minor', 100)))
   -> 'results' -> 0 ->> 'error'),
  'invalid_item_payload', '29. a NONZERO addition-line discount is refused (typed)');
select is(
  (pg_temp.caddx('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-noid', 'c0000000-0000-0000-0000-00000000a001',
     jsonb_build_array(jsonb_build_object(
       'quantity', 1, 'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item')))
   -> 'results' -> 0 ->> 'error'),
  'invalid_item_payload', '30. a line without menu_item_id is refused (typed)');
select is(
  (pg_temp.caddx('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-ghosti', 'c0000000-0000-0000-0000-00000000a001',
     jsonb_build_array(jsonb_build_object(
       'menu_item_id', '99999999-9999-4999-8999-999999999999', 'quantity', 1,
       'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Ghost')))
   -> 'results' -> 0 ->> 'error'),
  'item_unavailable', '31. an UNKNOWN menu item is the uniform item_unavailable refusal (no oracle)');
select is(
  (pg_temp.caddx('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-sold', 'c0000000-0000-0000-0000-00000000a001',
     jsonb_build_array(jsonb_build_object(
       'menu_item_id', 'c0000000-0000-0000-0000-0000000000f8', 'quantity', 1,
       'unit_price_minor_snapshot', 400, 'menu_item_name_snapshot', 'SoldOut')))
   -> 'results' -> 0 ->> 'error'),
  'item_unavailable', '32. a branch-UNAVAILABLE item is refused with the structured reason');
select ok(
  exists (select 1 from audit_events where action = 'order.items_add_denied'
          and (new_values ->> 'denied_reason') = 'order_already_settled'),
  '33. denials are audited with their safe denied_reason');
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'add-kds', 'c0000000-0000-0000-0000-00000000a001') -> 'results' -> 0 ->> 'error'),
  'invalid_device_type', '34. a KDS device may not add items (kitchen_staff on KDS)');
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad004', 'c0000000-0000-0000-0000-0000000000d2', 'add-kds2', 'c0000000-0000-0000-0000-00000000a001') -> 'results' -> 0 ->> 'error'),
  'invalid_device_type', '35. even a CASHIER on a KDS device may not add items (device class first)');
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad005', 'c0000000-0000-0000-0000-0000000000d1', 'add-kpos', 'c0000000-0000-0000-0000-00000000a001') -> 'results' -> 0 ->> 'error'),
  'permission_denied', '36. kitchen_staff on a POS device is denied by ROLE');

-- ===== (37-44) items_add identity hardening + anti-oracle ====================
select is(
  (pg_temp.cadd2('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-1',
                 'c0000000-0000-0000-0000-00000000a001', 'c0000000-0000-0000-0000-00000000a002') -> 'results' -> 0 ->> 'error'),
  'invalid_payload', '37. a changed-target replay of a terminal items_add is rejected BEFORE replay');
select is(
  (select status from sync_operations where local_operation_id = 'add-1'),
  'applied', '38. the stored applied items_add ledger row is unchanged by the hostile replay');
select is(
  (pg_temp.cadd2('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-mm',
                 'c0000000-0000-0000-0000-00000000a001', 'c0000000-0000-0000-0000-00000000a002') -> 'results' -> 0 ->> 'error'),
  'invalid_payload', '39. target A + payload B on a NEW items_add is a malformed envelope');
select ok(
  not exists (select 1 from sync_operations where local_operation_id = 'add-mm'),
  '40. the mismatch leaves NO ledger row');
create temp table addmix as select public.sync_push(
  'c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
  jsonb_build_array(
    jsonb_build_object('local_operation_id', 'st-o6a', 'operation_type', 'order.status', 'target_entity', 'order',
      'payload', jsonb_build_object('order_id', 'c0000000-0000-0000-0000-00000000a006', 'new_status', 'accepted')),
    jsonb_build_object('local_operation_id', 'add-badt', 'operation_type', 'order.items_add', 'target_entity', 'order',
      'target_id', 'not-a-uuid',
      'payload', jsonb_build_object('order_id', 'c0000000-0000-0000-0000-00000000a001',
        'order_items', jsonb_build_array(jsonb_build_object(
          'menu_item_id', 'c0000000-0000-0000-0000-0000000000f9', 'quantity', 1,
          'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item')))))) as r;
select ok(
  (select r -> 'results' -> 0 ->> 'status' = 'applied'
      and r -> 'results' -> 1 ->> 'error' = 'invalid_payload' from addmix),
  '41. a malformed items_add target rejects ONLY its own op — the valid sibling applies');
select ok(
  not exists (select 1 from sync_operations where local_operation_id = 'add-badt'),
  '42. the malformed envelope leaves NO ledger row');
create temp table addprobe as
  select
    (pg_temp.cadd('f0000000-0000-0000-0000-0000000bd001', 'f0000000-0000-0000-0000-0000000000d1', 'add-xt', 'c0000000-0000-0000-0000-00000000a001') -> 'results' -> 0) - 'local_operation_id' as foreign_probe,
    (pg_temp.cadd('f0000000-0000-0000-0000-0000000bd001', 'f0000000-0000-0000-0000-0000000000d1', 'add-gh', '99999999-9999-4999-8999-999999999999') -> 'results' -> 0) - 'local_operation_id' as ghost;
select ok(
  (select foreign_probe = ghost from addprobe),
  '43. a foreign-tenant order and a NONEXISTENT order are indistinguishable (R-003)');
select ok(
  (select f.rejection_reason = g.rejection_reason
     from sync_operations f, sync_operations g
     where f.local_operation_id = 'add-xt' and g.local_operation_id = 'add-gh'),
  '44. the persisted rejection reasons are identical for both probes');

-- ===== (45-60) round status ==================================================
create temp table r1 as
  select id from order_service_rounds
   where order_id = 'c0000000-0000-0000-0000-00000000a001' and round_number = 2;
create temp table r2 as
  select id from order_service_rounds
   where order_id = 'c0000000-0000-0000-0000-00000000a001' and round_number = 3;
select is(
  (pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rs-1a', (select id from r1), 'accepted') -> 'results' -> 0 ->> 'status'),
  'applied', '45. kitchen on KDS: round submitted -> accepted');
select is(
  (pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rs-1b', (select id from r1), 'preparing') -> 'results' -> 0 ->> 'status'),
  'applied', '46. kitchen on KDS: accepted -> preparing');
create temp table rs_ready as
  select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rs-1c', (select id from r1), 'ready') as r;
select ok(
  (select (r -> 'results' -> 0 ->> 'status') = 'applied' from rs_ready)
  and (select ready_at is not null from order_service_rounds where id = (select id from r1)),
  '47. preparing -> ready APPLIES and stamps the WRITE-ONCE ready_at');
select is(
  (pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rs-1c2', (select id from r1), 'ready') -> 'results' -> 0 ->> 'error'),
  'invalid_transition', '48. a REPEATED ready request is invalid_transition (single-step forward only)');
select ok(
  (select ready_at = now() from order_service_rounds where id = (select id from r1)),
  '49. the repeated request did not re-stamp or clear ready_at (write-once)');
select is(
  (pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rs-skip', (select id from r2), 'ready') -> 'results' -> 0 ->> 'error'),
  'invalid_transition', '50. a SKIP (submitted -> ready) is refused');
select is(
  (pg_temp.crst('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'rs-pos', (select id from r2), 'accepted') -> 'results' -> 0 ->> 'error'),
  'invalid_device_type', '51. a POS device may not drive a PRODUCTION step (locked matrix)');
select is(
  (pg_temp.crst('c0000000-0000-0000-0000-0000000ad004', 'c0000000-0000-0000-0000-0000000000d2', 'rs-cash', (select id from r2), 'accepted') -> 'results' -> 0 ->> 'error'),
  'permission_denied', '52. a CASHIER on KDS may not drive a production step');
select is(
  (pg_temp.crst('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'rs-serve', (select id from r1), 'served') -> 'results' -> 0 ->> 'status'),
  'applied', '53. a POS CASHIER serves a READY round (the hand-over step; locked matrix)');
select ok(
  (select bool_and(oi.status = 'pending') from order_items oi
     where oi.order_id = 'c0000000-0000-0000-0000-00000000a001'),
  '54. round transitions mutate NO order_items row (original, own, or other rounds)');
select is(
  (pg_temp.crst('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'rs-serve', (select id from r1), 'served') -> 'results' -> 0 ->> 'idempotency_replay')::boolean,
  true, '55. an EXACT replay of the served transition replays the stored result');
select is(
  (pg_temp.crst('c0000000-0000-0000-0000-0000000ad007', 'c0000000-0000-0000-0000-0000000000d3', 'rs-race', (select id from r1), 'served') -> 'results' -> 0 ->> 'error'),
  'invalid_transition', '56. a SECOND device racing the same transition converges (already served)');
create temp table rmm as
  select pg_temp.crst2('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rs-mm',
                       (select id from r1), (select id::text from r2), 'served') as r;
select ok(
  (select r -> 'results' -> 0 ->> 'error' = 'invalid_payload' from rmm)
  and not exists (select 1 from sync_operations where local_operation_id = 'rs-mm'),
  '57. a round target/payload mismatch is a malformed envelope with NO ledger row');
create temp table rbad as select public.sync_push(
  'c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2',
  jsonb_build_array(
    jsonb_build_object('local_operation_id', 'rs-bad', 'operation_type', 'order.round_status', 'target_entity', 'order_service_round',
      'target_id', 'not-a-uuid',
      'payload', jsonb_build_object('round_id', (select id from r2), 'new_status', 'accepted')),
    jsonb_build_object('local_operation_id', 'rs-good', 'operation_type', 'order.round_status', 'target_entity', 'order_service_round',
      'target_id', (select id::text from r2),
      'payload', jsonb_build_object('round_id', (select id from r2), 'new_status', 'accepted')))) as r;
select ok(
  (select r -> 'results' -> 0 ->> 'error' = 'invalid_payload'
      and r -> 'results' -> 1 ->> 'status' = 'applied' from rbad)
  and not exists (select 1 from sync_operations where local_operation_id = 'rs-bad'),
  '58. a malformed round target rejects only itself; the valid sibling APPLIES');
create temp table rprobe as
  select
    (pg_temp.crst('f0000000-0000-0000-0000-0000000bd001', 'f0000000-0000-0000-0000-0000000000d1', 'rs-xt', (select id from r1), 'accepted') -> 'results' -> 0) - 'local_operation_id' as foreign_probe,
    (pg_temp.crst('f0000000-0000-0000-0000-0000000bd001', 'f0000000-0000-0000-0000-0000000000d1', 'rs-gh', '99999999-9999-4999-8999-999999999998', 'accepted') -> 'results' -> 0) - 'local_operation_id' as ghost;
select ok(
  (select foreign_probe = ghost from rprobe),
  '59. a foreign round and a NONEXISTENT round are indistinguishable (R-003)');
select ok(
  exists (select 1 from audit_events where action = 'order.round_status_updated'
          and (new_values ->> 'from_status') = 'preparing'
          and (new_values ->> 'to_status') = 'ready'
          and (new_values ->> 'round_number')::int = 2),
  '60. round transitions are audited with round_number + from/to (safe scalars)');

-- ===== (61-66) completion integration ========================================
-- RACE A (oR1): paid FIRST (test 28), round still active -> serving the ORDER
-- must NOT complete it; serving the final ROUND must complete it EXACTLY once.
select pg_temp.cserve('str1', 'c0000000-0000-0000-0000-00000000a0b1');
select is(
  (select status from orders where id = 'c0000000-0000-0000-0000-00000000a0b1'),
  'served', '61. RACE A: a PAID served order with an ACTIVE round stays OPEN (rounds_active)');
create temp table r1r as
  select id from order_service_rounds where order_id = 'c0000000-0000-0000-0000-00000000a0b1';
select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rr1-a', (select id from r1r), 'accepted');
select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rr1-b', (select id from r1r), 'preparing');
select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rr1-c', (select id from r1r), 'ready');
create temp table rr1serve as
  select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rr1-d', (select id from r1r), 'served') as r;
select ok(
  (select (r -> 'results' -> 0 ->> 'auto_completed')::boolean from rr1serve)
  and (select status = 'completed' from orders where id = 'c0000000-0000-0000-0000-00000000a0b1'),
  '62. RACE A: serving the FINAL round completes the paid+served parent');
select is(
  (select count(*)::int from audit_events where action = 'order.status_updated'
     and (new_values ->> 'order_id') = 'c0000000-0000-0000-0000-00000000a0b1'
     and (new_values ->> 'completion_mode') = 'automatic'),
  1, '63. the automatic completion audited EXACTLY once (trigger round_served)');
-- RACE B (oR2): round fully served FIRST, order served (unpaid -> stays), THEN
-- the payment completes it through the existing record_payment tail.
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-r2', 'c0000000-0000-0000-0000-00000000a0b2');
create temp table r2r as
  select id from order_service_rounds where order_id = 'c0000000-0000-0000-0000-00000000a0b2';
select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rr2-a', (select id from r2r), 'accepted');
select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rr2-b', (select id from r2r), 'preparing');
select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rr2-c', (select id from r2r), 'ready');
select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rr2-d', (select id from r2r), 'served');
select pg_temp.cserve('str2', 'c0000000-0000-0000-0000-00000000a0b2');
select ok(
  (select status = 'served' from orders where id = 'c0000000-0000-0000-0000-00000000a0b2'),
  '64a. RACE B setup: every round served + order served but UNPAID -> stays open');
create temp table payr2 as
  select pg_temp.cpay('pay-r2', 'c0000000-0000-0000-0000-00000000a0b2') as r;
select ok(
  (select (r -> 'results' -> 0 ->> 'status') = 'applied' from payr2)
  and (select status = 'completed' from orders where id = 'c0000000-0000-0000-0000-00000000a0b2'),
  '64. RACE B: the payment completes the order once every round is served');
-- Manual gate (oR3): paid + served + round ACTIVE -> rounds_not_served.
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-r3', 'c0000000-0000-0000-0000-00000000a0b3');
select pg_temp.cpay('pay-r3', 'c0000000-0000-0000-0000-00000000a0b3');
select pg_temp.cserve('str3', 'c0000000-0000-0000-0000-00000000a0b3');
select is(
  (pg_temp.cstatus('c0000000-0000-0000-0000-0000000ad001', 'c0000000-0000-0000-0000-0000000000d1', 'st-man', 'c0000000-0000-0000-0000-00000000a0b3', 'completed') -> 'results' -> 0 ->> 'error'),
  'rounds_not_served', '65. MANUAL served -> completed refuses while a round is active (typed)');
-- Zero-round regression (o8): the pre-PSC-001C lifecycle is untouched.
select pg_temp.cserve('st8', 'c0000000-0000-0000-0000-00000000a008');
create temp table payo8 as
  select pg_temp.cpay('pay-o8', 'c0000000-0000-0000-0000-00000000a008') as r;
select ok(
  (select (r -> 'results' -> 0 ->> 'status') = 'applied' from payo8)
  and (select status = 'completed' from orders where id = 'c0000000-0000-0000-0000-00000000a008'),
  '66. a ZERO-ROUND order completes exactly as before (historical behavior intact)');

-- ===== (67-71) whole-order void integration ==================================
select pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-ov', 'c0000000-0000-0000-0000-00000000a0c1');
-- never-reused numbers: soft-delete round 2 (fixture), the next add allocates 3.
update order_service_rounds set deleted_at = now()
  where order_id = 'c0000000-0000-0000-0000-00000000a0c1' and round_number = 2;
select is(
  (pg_temp.cadd('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', 'add-ov2', 'c0000000-0000-0000-0000-00000000a0c1') -> 'results' -> 0 ->> 'round_number')::int,
  3, '71. round numbers are NEVER reused (allocation spans deleted/voided rows)');
create temp table rvr as
  select id from order_service_rounds
   where order_id = 'c0000000-0000-0000-0000-00000000a0c1' and round_number = 3;
select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rrv-a', (select id from rvr), 'accepted');
select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rrv-b', (select id from rvr), 'preparing');
select pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rrv-c', (select id from rvr), 'ready');
select pg_temp.cvoid('vd-ov', 'c0000000-0000-0000-0000-00000000a0c1');
select ok(
  (select (status = 'voided' and void_reason = 'customer left' and ready_at is not null)
     from order_service_rounds where id = (select id from rvr)),
  '67. the whole-order void sweeps the ACTIVE round to voided, keeping its ready_at history');
select is(
  (pg_temp.crst('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2', 'rrv-d', (select id from rvr), 'served') -> 'results' -> 0 ->> 'error'),
  'parent_order_voided', '68. no round transition exists after the parent void');
select ok(
  (select kitchen_ack_required and kitchen_ack_at is null
     from orders where id = 'c0000000-0000-0000-0000-00000000a0c1'),
  '69. the PSC-001D cancellation acknowledgement contract is INTACT after the cascade');
select ok(
  (select status = 'voided' from orders where id = 'c0000000-0000-0000-0000-00000000a0c1'),
  '70. the voided parent is terminal — a voided round can never contribute to completion');

-- ===== (72-78) ready feed ====================================================
create temp table feed1 as
  select public.pos_ready_feed('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1') as r;
select ok(
  (select (r ->> 'ok')::boolean
      and jsonb_array_length(r -> 'ready') >= 5
      and exists (select 1 from jsonb_array_elements(r -> 'ready') e where e ->> 'work_unit_type' = 'initial_order')
      and exists (select 1 from jsonb_array_elements(r -> 'ready') e where e ->> 'work_unit_type' = 'service_round')
     from feed1),
  '72. the feed returns BOTH initial-order and service-round ready work units');
select ok(
  (select exists (select 1 from jsonb_array_elements(r -> 'ready') e
                  where e ->> 'work_unit_type' = 'service_round'
                    and e ->> 'work_unit_status' = 'served') from feed1),
  '73. a work unit that LEFT ready keeps its historical ready occurrence (status exposed)');
-- Frozen-clock keyset paging: every stamp in this transaction shares ONE
-- ready_at, so page-by-1 MUST advance on (work_unit_type, work_unit_id).
create temp table fp as
  select public.pos_ready_feed('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1', null, null, null, 1) as p1;
create temp table fp2 as select public.pos_ready_feed(
  'c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
  (select (p1 -> 'next_cursor' ->> 'ready_at')::timestamptz from fp),
  (select p1 -> 'next_cursor' ->> 'work_unit_type' from fp),
  (select (p1 -> 'next_cursor' ->> 'id')::uuid from fp), 1) as p2;
create temp table fp3 as select public.pos_ready_feed(
  'c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
  (select (p2 -> 'next_cursor' ->> 'ready_at')::timestamptz from fp2),
  (select p2 -> 'next_cursor' ->> 'work_unit_type' from fp2),
  (select (p2 -> 'next_cursor' ->> 'id')::uuid from fp2), 1) as p3;
select ok(
  (select count(distinct u) = 3 from (
     select (p1 -> 'ready' -> 0 ->> 'work_unit_id') as u from fp
     union all select (p2 -> 'ready' -> 0 ->> 'work_unit_id') from fp2
     union all select (p3 -> 'ready' -> 0 ->> 'work_unit_id') from fp3) x),
  '74. EQUAL ready_at stamps page deterministically — three pages, three DISTINCT units, none skipped');
select ok(
  (select (p1 -> 'next_cursor') ? 'work_unit_type' from fp),
  '75. the cursor carries work_unit_type (the tie-break the equal-stamp case needs)');
select ok(
  (select bool_and(not exists (
     select 1 from jsonb_object_keys(e) k where k like '%\_minor' escape '\'))
     from feed1, jsonb_array_elements(r -> 'ready') e),
  '76. NO money key reaches any feed row');
select is(
  (select public.pos_ready_feed('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2') ->> 'error'),
  'invalid_device_type', '77. a KDS device may not read the POS ready feed');
select ok(
  (select bool_and(e ? 'parent_order_status' and e ? 'work_unit_status')
     from feed1, jsonb_array_elements(r -> 'ready') e),
  '78. every feed row exposes the CURRENT work-unit and parent statuses');

-- ===== (79-85) POS order detail ==============================================
create temp table det1 as
  select public.pos_order_detail('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
                                 'c0000000-0000-0000-0000-00000000a001') as r;
select ok(
  (select (r ->> 'ok')::boolean
      and jsonb_array_length(r -> 'items') = 3
      and exists (select 1 from jsonb_array_elements(r -> 'items') i where (i -> 'round_number') = 'null'::jsonb)
      and exists (select 1 from jsonb_array_elements(r -> 'items') i where (i ->> 'round_number')::int = 2)
      and jsonb_array_length(r -> 'rounds') = 2
     from det1),
  '79. the detail returns the COMBINED authoritative items (original + rounds) + the round list');
select ok(
  (select (r -> 'order' ->> 'grand_total_minor')::bigint = o.grand_total_minor
      and (r -> 'order' ->> 'revision')::int = o.revision
     from det1, orders o where o.id = 'c0000000-0000-0000-0000-00000000a001'),
  '80. detail totals/revision are the authoritative parent values');
select ok(
  (select ((r ->> 'ok')::boolean and jsonb_array_length(r -> 'items') = 3)
     from (select public.pos_order_detail('c0000000-0000-0000-0000-0000000ad009', 'c0000000-0000-0000-0000-0000000000d4',
                                          'c0000000-0000-0000-0000-00000000a001') as r) x),
  '81. a SECOND authorized POS device reads the SAME complete combined detail');
select ok(
  (select (r -> 'payment' ->> 'receipt_number') is not null
     from (select public.pos_order_detail('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
                                          'c0000000-0000-0000-0000-00000000a0b1') as r) x),
  '82. a paid order''s detail carries the completed payment + receipt number (reprint-complete)');
-- Final correction (Finding 3): the payment block carries the AUTHORITATIVE
-- payment identity and STORED status — the client must never fabricate either.
select ok(
  (select (r -> 'payment' ->> 'payment_id')::uuid = p.id
      and (r -> 'payment' ->> 'payment_status') = p.status
      and p.status = 'completed'
     from (select public.pos_order_detail('c0000000-0000-0000-0000-0000000ad002', 'c0000000-0000-0000-0000-0000000000d1',
                                          'c0000000-0000-0000-0000-00000000a0b1') as r) x,
          payments p
     where p.order_id = 'c0000000-0000-0000-0000-00000000a0b1'
       and p.status   = 'completed'
       and p.deleted_at is null),
  '82b. the detail payment names the REAL payments.id + its stored completed status');
select is(
  (select public.pos_order_detail('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2',
                                  'c0000000-0000-0000-0000-00000000a001') ->> 'error'),
  'invalid_device_type', '83. a KDS device may not read the money-carrying POS detail');
select is(
  (select public.pos_order_detail('c0000000-0000-0000-0000-0000000ad005', 'c0000000-0000-0000-0000-0000000000d1',
                                  'c0000000-0000-0000-0000-00000000a001') ->> 'error'),
  'permission_denied', '84. kitchen_staff on a POS device is denied by role (T-003: the read carries money)');
select ok(
  (select public.pos_order_detail('f0000000-0000-0000-0000-0000000bd001', 'f0000000-0000-0000-0000-0000000000d1',
                                  'c0000000-0000-0000-0000-00000000a001')
        = public.pos_order_detail('f0000000-0000-0000-0000-0000000bd001', 'f0000000-0000-0000-0000-0000000000d1',
                                  '99999999-9999-4999-8999-999999999997')),
  '85. a FOREIGN order and a NONEXISTENT order return the IDENTICAL envelope (no oracle)');

-- ===== (86-89) sync_pull =====================================================
create temp table kpull as
  select public.sync_pull('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2',
                          array['orders','order_items','order_service_rounds']) as r;
select ok(
  (select jsonb_array_length(r -> 'changes' -> 'order_service_rounds' -> 'rows') >= 5 from kpull),
  '86. the kitchen pull delivers the branch''s service rounds');
select ok(
  (select exists (select 1 from jsonb_array_elements(r -> 'changes' -> 'order_items' -> 'rows') e
                  where e ->> 'service_round_id' is not null) from kpull),
  '87. pulled order_items carry their round membership (generic row projection)');
select ok(
  (select bool_and(not exists (
     select 1 from jsonb_object_keys(e) k where k like '%\_minor' escape '\'))
     from kpull, jsonb_array_elements(r -> 'changes' -> 'order_service_rounds' -> 'rows') e),
  '88. round rows are money-free on the kitchen feed (schema + redaction backstop)');
select ok(
  (select (public.sync_pull('c0000000-0000-0000-0000-0000000ad003', 'c0000000-0000-0000-0000-0000000000d2',
                            array['orders']) ->> 'ok')::boolean),
  '89. an OLD client requesting only its known entities is unaffected');

-- ===== (90-92) revoked-device hardening for the new operations ===============
update device_sessions set revoked_at = now(), is_active = false
  where id = 'c0000000-0000-0000-0000-0000000000e3';
create temp table rvk1 as
  select pg_temp.crst2('c0000000-0000-0000-0000-0000000ad007', 'c0000000-0000-0000-0000-0000000000d3', 'rvk-bad',
                       (select id from r2), 'not-a-uuid', 'accepted') as r;
select ok(
  (select r -> 'results' -> 0 ->> 'error' = 'invalid_payload' from rvk1)
  and not exists (select 1 from sync_operations where local_operation_id = 'rvk-bad'),
  '90. REVOKED path: a malformed round target is invalid_payload with NO ledger row');
create temp table rvk2 as
  select pg_temp.crst('c0000000-0000-0000-0000-0000000ad007', 'c0000000-0000-0000-0000-0000000000d3', 'rvk-ok',
                      (select id from r2), 'preparing') as r;
select ok(
  (select r -> 'results' -> 0 ->> 'detail' = 'revoked_device' from rvk2)
  and (select status = 'rejected' and rejection_reason = 'revoked_device'
         from sync_operations where local_operation_id = 'rvk-ok'),
  '91. REVOKED path: a valid-identity round op gets the normal revoked-device recording');
select is(
  (pg_temp.crst2('c0000000-0000-0000-0000-0000000ad007', 'c0000000-0000-0000-0000-0000000000d3', 'rvk-ok',
                 (select id from r2), (select id::text from r1), 'preparing') -> 'results' -> 0 ->> 'error'),
  'invalid_payload', '92. REVOKED path: a changed-target replay of a stored op is rejected before replay');

-- ===== (94-97) CORRECTION Finding 6: the four service-round actions are ======
-- ===== MONEY-FREE — in the REAL trail AND under hostile projection       ======
select ok(
  (select bool_and(coalesce(new_values, '{}'::jsonb)::text not like '%\_minor%'
               and coalesce(old_values, '{}'::jsonb)::text not like '%\_minor%')
     from audit_events
     where action in ('order.items_added', 'order.items_add_denied',
                      'order.round_status_updated', 'order.round_status_denied')),
  '94. F6: NO real service-round audit row carries any monetary key');
select is(
  app.audit_safe_detail('order.items_added', jsonb_build_object(
    'order_code', '#A1B2C3', 'round_number', 2, 'added_item_count', 3,
    'order_status', 'preparing', 'role', 'cashier',
    'subtotal_minor', 999, 'grand_total_minor', 999, 'amount_minor', 555)),
  jsonb_build_object('order_code', '#A1B2C3', 'round_number', 2,
                     'added_item_count', 3, 'order_status', 'preparing',
                     'role', 'cashier'),
  '95. F6: a HOSTILE items_added payload keeps the approved fields and drops every money key');
select ok(
  not (app.audit_safe_detail('order.items_add_denied',
         jsonb_build_object('denied_reason', 'x', 'subtotal_minor', 1)) ? 'subtotal_minor')
  and not (app.audit_safe_detail('order.round_status_updated',
             jsonb_build_object('to_status', 'ready', 'grand_total_minor', 1)) ? 'grand_total_minor')
  and not (app.audit_safe_detail('order.round_status_denied',
             jsonb_build_object('denied_reason', 'x', 'amount_minor', 1)) ? 'amount_minor'),
  '96. F6: hostile money is stripped for the denial and round-status actions too');
select is(
  app.audit_safe_detail('payment.recorded',
    jsonb_build_object('amount_minor', 500, 'order_code', '#A1B2C3')) -> 'amount_minor',
  '500'::jsonb,
  '97. F6: the strip is ACTION-SPECIFIC — approved money-carrying actions keep their keys');

select * from finish();
rollback;
