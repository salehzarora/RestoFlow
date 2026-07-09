-- ============================================================================
-- KITCHEN-MEAT-001 -- pgTAP: modifier-option meat config + order meat snapshot
-- ============================================================================
-- modifier_options.kitchen_meat (owner config) is served to the POS by pos_menu
-- (non-money, so kitchen too). When a cashier selects the option, the POS
-- snapshots it as order_item_modifiers.meat_snapshot via public.sync_push ->
-- app.submit_order (which stores v_modifier -> 'meat_snapshot' verbatim). It is
-- non-money, so it reaches kitchen_staff sync_pull (survives app.redact_money)
-- while all *_minor money stays stripped (KDS money-free, T-003). Both jsonb
-- fields are CHECK-pinned money-free (D-007). Fixtures inserted as BYPASSRLS.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(11);

-- ===== fixtures: org A (POS + cashier session, KDS + kitchen session) ========
insert into organizations (id, name, slug, default_currency) values
  ('e0000000-0000-0000-0000-0000000000a0', 'Org KM', 'km-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-0000000000a0', 'Rest KM1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('e0000000-0000-0000-0000-00000000a1b1', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'Branch KM1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('e0000000-0000-0000-0000-00000000da11', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('e0000000-0000-0000-0000-00000000da22', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('e0000000-0000-0000-0000-00000000fa11', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'e0000000-0000-0000-0000-00000000da11', 'active'),
  ('e0000000-0000-0000-0000-00000000fa22', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'e0000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('e0000000-0000-0000-0000-0000000005a1', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'e0000000-0000-0000-0000-00000000da11', 'e0000000-0000-0000-0000-00000000fa11'),
  ('e0000000-0000-0000-0000-0000000005a2', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'e0000000-0000-0000-0000-00000000da22', 'e0000000-0000-0000-0000-00000000fa22');
insert into app_users (id, email) values
  ('e0000000-0000-0000-0000-00000000ee01', 'km-cashier@example.test'),
  ('e0000000-0000-0000-0000-00000000ee04', 'km-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('e0000000-0000-0000-0000-00000000ab01', 'e0000000-0000-0000-0000-00000000ee01', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('e0000000-0000-0000-0000-00000000ab04', 'e0000000-0000-0000-0000-00000000ee04', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('e0000000-0000-0000-0000-0000000ef001', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'e0000000-0000-0000-0000-00000000ee01', 'e0000000-0000-0000-0000-00000000ab01'),
  ('e0000000-0000-0000-0000-0000000ef004', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'e0000000-0000-0000-0000-00000000ee04', 'e0000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('e0000000-0000-0000-0000-00000000c501', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'e0000000-0000-0000-0000-0000000005a1', 'e0000000-0000-0000-0000-0000000ef001', 'e0000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('e0000000-0000-0000-0000-00000000c504', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', 'e0000000-0000-0000-0000-00000000a1b1', 'e0000000-0000-0000-0000-0000000005a2', 'e0000000-0000-0000-0000-0000000ef004', 'e0000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- ===== menu fixtures: category -> item -> modifier -> option (with meat) ======
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order, is_active) values
  ('e0000000-0000-0000-0000-0000000c1000', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', null, 'Burgers', 0, true);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order, is_active) values
  ('e0000000-0000-0000-0000-0000000117e0', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', null, 'e0000000-0000-0000-0000-0000000c1000', 'Burger', 4200, 'USD', 0, true);
insert into modifiers (id, organization_id, restaurant_id, branch_id, menu_item_id, name, selection_type, is_active) values
  ('e0000000-0000-0000-0000-0000000d1000', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', null, 'e0000000-0000-0000-0000-0000000117e0', 'Size', 'single', true);
insert into modifier_options (id, organization_id, restaurant_id, branch_id, modifier_id, name, price_delta_minor, display_order, is_active, kitchen_meat) values
  ('e0000000-0000-0000-0000-00000000d201', 'e0000000-0000-0000-0000-0000000000a0', 'e0000000-0000-0000-0000-0000000000a1', null, 'e0000000-0000-0000-0000-0000000d1000', 'Double', 900, 0, true, '{"quantity":2,"unit":"قطع"}'::jsonb);

-- ===== (1-4) the predicate: null/object pass; money-key/array fail ============
select ok(app.jsonb_is_meat_object(null), 'predicate: NULL is allowed');
select ok(app.jsonb_is_meat_object('{"quantity":2,"unit":"قطع"}'::jsonb), 'predicate: a {quantity,unit} object is allowed');
select ok(not app.jsonb_is_meat_object('{"quantity":2,"price_minor":5}'::jsonb), 'predicate: an object with a money (_minor) key is rejected (D-007)');
select ok(not app.jsonb_is_meat_object('[{"quantity":2}]'::jsonb), 'predicate: a non-object (array) is rejected');

-- ===== (5) the CHECK rejects a money-key kitchen_meat on the table ============
select throws_ok(
  $$ update public.modifier_options
       set kitchen_meat = '{"quantity":2,"amount_minor":5}'::jsonb
     where id = 'e0000000-0000-0000-0000-00000000d201' $$,
  '23514', null,
  'the modifier_options.kitchen_meat CHECK rejects a money (_minor) key (D-007)');

-- ===== (6-7) pos_menu serves kitchen_meat to cashier AND kitchen (non-money) ==
select is(
  (select o -> 'kitchen_meat'
     from jsonb_array_elements(app.pos_menu('e0000000-0000-0000-0000-00000000c501', 'e0000000-0000-0000-0000-00000000da11') -> 'modifier_options') as o
     where o ->> 'id' = 'e0000000-0000-0000-0000-00000000d201'),
  '{"quantity":2,"unit":"قطع"}'::jsonb,
  'pos_menu (cashier) serves kitchen_meat on the option so the POS can snapshot it');
select ok(
  exists (select 1
     from jsonb_array_elements(app.pos_menu('e0000000-0000-0000-0000-00000000c504', 'e0000000-0000-0000-0000-00000000da22') -> 'modifier_options') as o
     where o ->> 'id' = 'e0000000-0000-0000-0000-00000000d201' and o ? 'kitchen_meat'),
  'pos_menu (kitchen_staff) also carries kitchen_meat (non-money passthrough), while money keys stay omitted');

-- ===== submit an order whose modifier carries meat_snapshot ===================
select public.sync_push(
  'e0000000-0000-0000-0000-00000000c501', 'e0000000-0000-0000-0000-00000000da11',
  jsonb_build_array(jsonb_build_object(
    'local_operation_id', 'km-op-1',
    'operation_type', 'order.submit',
    'target_entity', 'order',
    'payload', jsonb_build_object(
      'order_id', 'e0000000-0000-0000-0000-00000000d001',
      'order_type', 'takeaway', 'currency_code', 'USD',
      'subtotal_minor', 5100, 'discount_total_minor', 0, 'tax_total_minor', 0, 'grand_total_minor', 5100,
      'order_items', jsonb_build_array(jsonb_build_object(
        'menu_item_id', 'e0000000-0000-0000-0000-0000000117e0',
        'quantity', 1, 'unit_price_minor_snapshot', 4200,
        'menu_item_name_snapshot', 'Burger',
        'modifiers', jsonb_build_array(jsonb_build_object(
          'modifier_option_id', 'e0000000-0000-0000-0000-00000000d201',
          'option_name_snapshot', 'Double',
          'price_minor_snapshot', 900, 'quantity', 1,
          'meat_snapshot', jsonb_build_object('quantity', 2, 'unit', 'قطع')))))))));

-- ===== (8-9) meat_snapshot stored verbatim + Arabic unit preserved ===========
select is(
  (select meat_snapshot from order_item_modifiers oim
     join order_items oi on oi.id = oim.order_item_id
     where oi.order_id = 'e0000000-0000-0000-0000-00000000d001'),
  '{"quantity": 2, "unit": "قطع"}'::jsonb,
  'submit_order stores order_item_modifiers.meat_snapshot verbatim (D-008 snapshot)');
select is(
  (select meat_snapshot ->> 'unit' from order_item_modifiers oim
     join order_items oi on oi.id = oim.order_item_id
     where oi.order_id = 'e0000000-0000-0000-0000-00000000d001'),
  'قطع', 'the Arabic meat unit is stored exactly');

-- ===== (10-11) kitchen sync_pull carries meat_snapshot, NO *_minor money ======
select ok(
  exists (select 1
     from jsonb_array_elements(
            app.sync_pull('e0000000-0000-0000-0000-00000000c504', 'e0000000-0000-0000-0000-00000000da22',
              array['order_item_modifiers'], '{}'::jsonb, 500) -> 'changes' -> 'order_item_modifiers' -> 'rows') as r
     where r -> 'meat_snapshot' ->> 'quantity' = '2'),
  'the kitchen sync_pull order_item_modifiers row carries meat_snapshot (reaches the KDS meat total)');
select ok(
  not exists (select 1
     from jsonb_array_elements(
            app.sync_pull('e0000000-0000-0000-0000-00000000c504', 'e0000000-0000-0000-0000-00000000da22',
              array['order_item_modifiers'], '{}'::jsonb, 500) -> 'changes' -> 'order_item_modifiers' -> 'rows') as r
     where r -> 'meat_snapshot' ->> 'quantity' = '2'
       and (r ? 'price_minor_snapshot')),
  'the same kitchen row has NO *_minor money key (KDS money-free, redact_money intact)');

select * from finish();
rollback;
