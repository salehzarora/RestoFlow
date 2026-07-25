-- ============================================================================
-- PRINT-LAYOUT-001D — pgTAP: order_items.line_position is a stable per-order
-- ordinal populated in submit-array (cart) order, and a service round's items
-- append after the order's existing lines.
--
-- Proves the additive column + the assign_order_item_line_position trigger over
-- the REAL public.sync_push -> app.submit_order / app.add_order_items paths.
-- Fixtures inserted as the BYPASSRLS connection role (RF-056/RF-057 convention).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(11);

-- ===== fixtures: Org D (1 POS device, cashier PIN) ==========================
insert into organizations (id, name, slug, default_currency) values
  ('d0000000-0000-0000-0000-000000000001', 'Org D', 'ord-d', 'USD');
insert into restaurants (id, organization_id, name) values
  ('d0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000001', 'Rest D');
insert into branches (id, organization_id, restaurant_id, name) values
  ('d0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'Branch D');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('d0000000-0000-0000-0000-0000000000d1', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('d0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-0000000000d1', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('d0000000-0000-0000-0000-0000000000e1', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-0000000000d1', 'd0000000-0000-0000-0000-0000000000a1');
insert into app_users (id, email) values
  ('d0000000-0000-0000-0000-00000000ae01', 'd-cash@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('d0000000-0000-0000-0000-00000000ab01', 'd0000000-0000-0000-0000-00000000ae01', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003', 'cashier', '{}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('d0000000-0000-0000-0000-00000000ac01', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-00000000ae01', 'd0000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('d0000000-0000-0000-0000-00000000ad01', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-0000000000e1', 'd0000000-0000-0000-0000-00000000ac01', 'd0000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('d0000000-0000-0000-0000-0000000000c9', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', null, 'Cat D', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('d0000000-0000-0000-0000-0000000000f1', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', null, 'd0000000-0000-0000-0000-0000000000c9', 'Item A', 500, 'USD', 1),
  ('d0000000-0000-0000-0000-0000000000f2', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', null, 'd0000000-0000-0000-0000-0000000000c9', 'Item B', 500, 'USD', 2),
  ('d0000000-0000-0000-0000-0000000000f3', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', null, 'd0000000-0000-0000-0000-0000000000c9', 'Item C', 500, 'USD', 3);
insert into tables (id, organization_id, restaurant_id, branch_id, label) values
  ('d0000000-0000-0000-0000-0000000000b1', 'd0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000003', 'T1');

-- ===== column shape =========================================================
select has_column('public', 'order_items', 'line_position', 'order_items has line_position');
select col_type_is('public', 'order_items', 'line_position', 'integer', 'line_position is integer');
select col_not_null('public', 'order_items', 'line_position', 'line_position is not null');
select col_default_is('public', 'order_items', 'line_position', '0', 'line_position defaults to 0');

-- ===== submit a DINE-IN order whose items are, IN ARRAY ORDER, A, B, C ========
select public.sync_push(
  'd0000000-0000-0000-0000-00000000ad01'::uuid,
  'd0000000-0000-0000-0000-0000000000d1'::uuid,
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'd-op-submit-1',
    'operation_type', 'order.submit',
    'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', 'd0000000-0000-0000-0000-0000000000f9',
      'order_type', 'dine_in',
      'table_id', 'd0000000-0000-0000-0000-0000000000b1',
      'currency_code', 'USD',
      'subtotal_minor', 1500, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 1500,
      'order_items', jsonb_build_array(
        jsonb_build_object('menu_item_id', 'd0000000-0000-0000-0000-0000000000f1', 'quantity', 1, 'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item A'),
        jsonb_build_object('menu_item_id', 'd0000000-0000-0000-0000-0000000000f2', 'quantity', 1, 'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item B'),
        jsonb_build_object('menu_item_id', 'd0000000-0000-0000-0000-0000000000f3', 'quantity', 1, 'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item C'))))));

-- The line_position ordinals are 1,2,3 in the SUBMIT ARRAY order.
select is(
  (select array_agg(menu_item_name_snapshot order by line_position)
     from public.order_items where order_id = 'd0000000-0000-0000-0000-0000000000f9'),
  array['Item A', 'Item B', 'Item C'],
  'items sorted by line_position reproduce the submit array (cart) order');
select is(
  (select line_position from public.order_items
    where order_id = 'd0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item A'),
  1, 'Item A is line_position 1');
select is(
  (select line_position from public.order_items
    where order_id = 'd0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item B'),
  2, 'Item B is line_position 2');
select is(
  (select line_position from public.order_items
    where order_id = 'd0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item C'),
  3, 'Item C is line_position 3');
-- The ordinals are distinct + gap-free (a valid 1..N sequence).
select is(
  (select array_agg(distinct line_position order by line_position)
     from public.order_items where order_id = 'd0000000-0000-0000-0000-0000000000f9'),
  array[1, 2, 3],
  'line_position is a distinct, gap-free 1..N sequence');

-- ===== a service-round addition APPENDS after the order's existing lines =====
select public.sync_push(
  'd0000000-0000-0000-0000-00000000ad01'::uuid,
  'd0000000-0000-0000-0000-0000000000d1'::uuid,
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'd-op-add-1',
    'operation_type', 'order.items_add',
    'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', 'd0000000-0000-0000-0000-0000000000f9',
      'round_id', 'd0000000-0000-0000-0000-0000000000e9',
      'order_items', jsonb_build_array(
        jsonb_build_object('menu_item_id', 'd0000000-0000-0000-0000-0000000000f1', 'quantity', 1, 'unit_price_minor_snapshot', 500, 'menu_item_name_snapshot', 'Item A round'))))));

-- The added round's item takes the next ordinal (4), strictly after the max (3).
select cmp_ok(
  (select line_position from public.order_items
    where order_id = 'd0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot = 'Item A round'),
  '>',
  (select max(line_position) from public.order_items
    where order_id = 'd0000000-0000-0000-0000-0000000000f9' and menu_item_name_snapshot <> 'Item A round'),
  'a round addition appends AFTER the original lines (strictly greater ordinal)');

select * from finish();
rollback;
