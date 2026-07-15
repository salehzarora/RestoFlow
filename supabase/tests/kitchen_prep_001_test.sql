-- ============================================================================
-- KITCHEN-PREP-001 — pgTAP: order-time kitchen prep snapshot on order_items
-- ============================================================================
-- Each order item's configured prep components ride the EXISTING order.submit
-- path: public.sync_push -> app.sync_push -> app.submit_order, which now also
-- stores `v_item -> 'prep_snapshot'` into order_items.prep_snapshot. The snapshot
-- is a NON-money jsonb array of {name,quantity,unit} (CHECK-pinned: no *_minor
-- key). It is non-money, so it reaches the kitchen_staff sync_pull (survives
-- app.redact_money) for the KDS prep summary while all *_minor money stays
-- stripped (KDS money-free, T-003). submit_order's money recompute is unchanged.
-- Fixtures inserted as the BYPASSRLS connection role (RF-056/RF-057 convention).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(13);

-- ===== fixtures: org A (POS + cashier session, KDS + kitchen session) ========
insert into organizations (id, name, slug, default_currency) values
  ('d0000000-0000-0000-0000-0000000000a0', 'Org KP', 'kp-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('d0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-0000000000a0', 'Rest KP1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('d0000000-0000-0000-0000-00000000a1b1', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'Branch KP1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('d0000000-0000-0000-0000-00000000da11', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('d0000000-0000-0000-0000-00000000da22', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('d0000000-0000-0000-0000-00000000fa11', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'd0000000-0000-0000-0000-00000000da11', 'active'),
  ('d0000000-0000-0000-0000-00000000fa22', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'd0000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('d0000000-0000-0000-0000-0000000005a1', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'd0000000-0000-0000-0000-00000000da11', 'd0000000-0000-0000-0000-00000000fa11'),
  ('d0000000-0000-0000-0000-0000000005a2', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'd0000000-0000-0000-0000-00000000da22', 'd0000000-0000-0000-0000-00000000fa22');
insert into app_users (id, email) values
  ('d0000000-0000-0000-0000-00000000ee01', 'kp-cashier@example.test'),
  ('d0000000-0000-0000-0000-00000000ee04', 'kp-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('d0000000-0000-0000-0000-00000000ab01', 'd0000000-0000-0000-0000-00000000ee01', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('d0000000-0000-0000-0000-00000000ab04', 'd0000000-0000-0000-0000-00000000ee04', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('d0000000-0000-0000-0000-0000000ef001', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'd0000000-0000-0000-0000-00000000ee01', 'd0000000-0000-0000-0000-00000000ab01'),
  ('d0000000-0000-0000-0000-0000000ef004', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'd0000000-0000-0000-0000-00000000ee04', 'd0000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('d0000000-0000-0000-0000-00000000c501', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'd0000000-0000-0000-0000-0000000005a1', 'd0000000-0000-0000-0000-0000000ef001', 'd0000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('d0000000-0000-0000-0000-00000000c504', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', 'd0000000-0000-0000-0000-00000000a1b1', 'd0000000-0000-0000-0000-0000000005a2', 'd0000000-0000-0000-0000-0000000ef004', 'd0000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- ---- sellable menu fixtures (submit_order now requires proven-sellable items)
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('d0000000-0000-0000-0000-00000000ca01', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('d0000000-0000-0000-0000-0000000000f1', 'd0000000-0000-0000-0000-0000000000a0', 'd0000000-0000-0000-0000-0000000000a1', null, 'd0000000-0000-0000-0000-00000000ca01', 'Double Burger', 1000, 'USD', 1);

-- ---- helper: an order.submit whose single item carries an optional prep_snapshot.
create or replace function pg_temp.kp_submit(
  p_op text, p_order_id uuid, p_prep jsonb
) returns jsonb language sql as $$
  select public.sync_push(
    'd0000000-0000-0000-0000-00000000c501',
    'd0000000-0000-0000-0000-00000000da11',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op,
      'operation_type', 'order.submit',
      'target_entity', 'order',
      'payload', jsonb_build_object(
        'order_id', p_order_id,
        'order_type', 'takeaway',
        'currency_code', 'USD',
        'subtotal_minor', 2000,
        'discount_total_minor', 0,
        'tax_total_minor', 0,
        'grand_total_minor', 2000,
        'order_items', jsonb_build_array(
          (jsonb_build_object(
            'menu_item_id', 'd0000000-0000-0000-0000-0000000000f1',
            'quantity', 2,
            'unit_price_minor_snapshot', 1000,
            'menu_item_name_snapshot', 'Double Burger')
           || case when p_prep is null then '{}'::jsonb
                   else jsonb_build_object('prep_snapshot', p_prep) end))))));
$$;

-- perform the submits (setup statements; assertions follow)
select pg_temp.kp_submit('kp-op-1', 'd0000000-0000-0000-0000-00000000d001',
  '[{"name":"لحم برجر","quantity":2,"unit":"قطع"},{"name":"Bun","quantity":1,"unit":""}]'::jsonb);
select pg_temp.kp_submit('kp-op-2', 'd0000000-0000-0000-0000-00000000d002', null);

-- ===== (1) submit applied =====================================================
select is(
  (select status from orders where id = 'd0000000-0000-0000-0000-00000000d001'),
  'submitted', 'order.submit with a prep snapshot applies (order persisted)');

-- ===== (2) prep_snapshot stored verbatim on the order item ====================
select is(
  (select prep_snapshot from order_items where order_id = 'd0000000-0000-0000-0000-00000000d001'),
  '[{"name":"لحم برجر","quantity":2,"unit":"قطع"},{"name":"Bun","quantity":1,"unit":""}]'::jsonb,
  'order_items.prep_snapshot stores the submitted component array verbatim (D-008 snapshot)');

-- ===== (3) Arabic prep component name preserved exactly =======================
select is(
  (select prep_snapshot -> 0 ->> 'name' from order_items where order_id = 'd0000000-0000-0000-0000-00000000d001'),
  'لحم برجر', 'an Arabic prep component name is stored exactly (ar/he/en supported)');

-- ===== (4) an item with NO prep_snapshot -> NULL (backward compatible) ========
select ok(
  (select prep_snapshot is null from order_items where order_id = 'd0000000-0000-0000-0000-00000000d002'),
  'an order item with NO prep_snapshot leaves the column NULL (existing clients keep working)');

-- ===== (5) kitchen sync_pull carries prep_snapshot on the order item ==========
select ok(
  exists (
    select 1
    from jsonb_array_elements(
           app.sync_pull('d0000000-0000-0000-0000-00000000c504', 'd0000000-0000-0000-0000-00000000da22',
             array['order_items'], '{}'::jsonb, 500) -> 'changes' -> 'order_items' -> 'rows') as r
    where r ->> 'order_id' = 'd0000000-0000-0000-0000-00000000d001'
      and r -> 'prep_snapshot' -> 0 ->> 'name' = 'لحم برجر'),
  'the kitchen sync_pull order_items row carries prep_snapshot (reaches the KDS prep summary)');

-- ===== (6) the same kitchen row has NO *_minor money keys (T-003) =============
select ok(
  not exists (
    select 1
    from jsonb_array_elements(
           app.sync_pull('d0000000-0000-0000-0000-00000000c504', 'd0000000-0000-0000-0000-00000000da22',
             array['order_items'], '{}'::jsonb, 500) -> 'changes' -> 'order_items' -> 'rows') as r
    where r ->> 'order_id' = 'd0000000-0000-0000-0000-00000000d001'
      and (r ? 'unit_price_minor_snapshot' or r ? 'line_total_minor' or r ? 'line_discount_minor')),
  'the same kitchen order_items row has NO *_minor money keys (KDS money-free, redact_money intact)');

-- ===== (7) the CHECK rejects a prep_snapshot element carrying a money key =====
select throws_ok(
  $$ update public.order_items
       set prep_snapshot = '[{"name":"Patty","quantity":1,"unit":"pcs","price_minor":500}]'::jsonb
     where order_id = 'd0000000-0000-0000-0000-00000000d001' $$,
  '23514',
  null,
  'the CHECK rejects a prep_snapshot element carrying a money (_minor) key (D-007)');

-- ===== (8-12) the predicate: null/valid pass; money-key/non-array/non-object fail
select ok(app.jsonb_is_prep_component_array(null), 'predicate: NULL is allowed');
select ok(
  app.jsonb_is_prep_component_array('[{"name":"Patty","quantity":2,"unit":"pcs"}]'::jsonb),
  'predicate: a valid array of {name,quantity,unit} objects is allowed');
select ok(
  not app.jsonb_is_prep_component_array('[{"name":"Patty","amount_minor":5}]'::jsonb),
  'predicate: an element with a money (_minor) key is rejected (D-007)');
select ok(
  not app.jsonb_is_prep_component_array('{"name":"Patty"}'::jsonb),
  'predicate: a non-array (object) is rejected');
select ok(
  not app.jsonb_is_prep_component_array('["not-an-object"]'::jsonb),
  'predicate: an array with a non-object element is rejected');

-- ===== (13) idempotent replay (identical op) returns the stored result =======
select is(
  (pg_temp.kp_submit('kp-op-1', 'd0000000-0000-0000-0000-00000000d001',
     '[{"name":"لحم برجر","quantity":2,"unit":"قطع"},{"name":"Bun","quantity":1,"unit":""}]'::jsonb)
     -> 'results' -> 0 ->> 'idempotency_replay')::boolean,
  true, 'replaying the SAME order.submit op returns the stored result (idempotency_replay), not a new snapshot');

select * from finish();
rollback;
