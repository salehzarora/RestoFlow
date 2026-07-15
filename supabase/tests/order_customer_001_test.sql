-- ============================================================================
-- ORDER-CUSTOMER-001 — pgTAP: optional customer display name on POS orders
-- ============================================================================
-- The optional customer_name rides the EXISTING order.submit path end-to-end
-- through public.sync_push -> app.sync_push -> app.submit_order. app.submit_order
-- is UNCHANGED; the display name is stamped onto the just-created order inside
-- the sync_push order.submit branch (trim + empty->null + <=80 cap; tenant-scoped;
-- guarded by `customer_name is null` so it is idempotent and never overwrites).
-- Existing null-customer orders keep working; money/tax is untouched. The name is
-- non-money, so it reaches the kitchen_staff sync_pull (survives app.redact_money)
-- for the KDS ticket while all *_minor money stays stripped (KDS money-free, T-003).
-- Fixtures inserted as the BYPASSRLS connection role (the RF-056/RF-057 convention).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(11);

-- ===== fixtures: org A (POS + cashier session, KDS + kitchen session) ========
insert into organizations (id, name, slug, default_currency) values
  ('c0000000-0000-0000-0000-0000000000a0', 'Org CN', 'cn-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-0000000000a0', 'Rest CN1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('c0000000-0000-0000-0000-00000000a1b1', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'Branch CN1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('c0000000-0000-0000-0000-00000000da11', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'pos'),
  ('c0000000-0000-0000-0000-00000000da22', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'kds');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('c0000000-0000-0000-0000-00000000fa11', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'c0000000-0000-0000-0000-00000000da11', 'active'),
  ('c0000000-0000-0000-0000-00000000fa22', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'c0000000-0000-0000-0000-00000000da22', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('c0000000-0000-0000-0000-0000000005a1', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'c0000000-0000-0000-0000-00000000da11', 'c0000000-0000-0000-0000-00000000fa11'),
  ('c0000000-0000-0000-0000-0000000005a2', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'c0000000-0000-0000-0000-00000000da22', 'c0000000-0000-0000-0000-00000000fa22');
insert into app_users (id, email) values
  ('c0000000-0000-0000-0000-00000000ee01', 'cn-cashier@example.test'),
  ('c0000000-0000-0000-0000-00000000ee04', 'cn-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('c0000000-0000-0000-0000-00000000ab01', 'c0000000-0000-0000-0000-00000000ee01', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'cashier'),
  ('c0000000-0000-0000-0000-00000000ab04', 'c0000000-0000-0000-0000-00000000ee04', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('c0000000-0000-0000-0000-0000000ef001', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'c0000000-0000-0000-0000-00000000ee01', 'c0000000-0000-0000-0000-00000000ab01'),
  ('c0000000-0000-0000-0000-0000000ef004', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'c0000000-0000-0000-0000-00000000ee04', 'c0000000-0000-0000-0000-00000000ab04');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('c0000000-0000-0000-0000-00000000c501', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'c0000000-0000-0000-0000-0000000005a1', 'c0000000-0000-0000-0000-0000000ef001', 'c0000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('c0000000-0000-0000-0000-00000000c504', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', 'c0000000-0000-0000-0000-00000000a1b1', 'c0000000-0000-0000-0000-0000000005a2', 'c0000000-0000-0000-0000-0000000ef004', 'c0000000-0000-0000-0000-00000000ab04', now() + interval '1 hour');

-- sellable menu fixture: submit_order now requires every payload menu_item_id
-- to be a provably sellable menu item (active item + active category, same org).
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('c0000000-0000-0000-0000-00000000ca01', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('c0000000-0000-0000-0000-0000000000f1', 'c0000000-0000-0000-0000-0000000000a0', 'c0000000-0000-0000-0000-0000000000a1', null, 'c0000000-0000-0000-0000-00000000ca01', 'Item', 1000, 'USD', 1);

-- ---- helper: build an order.submit ops array with an optional customer_name.
-- Using jsonb_build_object avoids brittle string escaping for long/RTL names.
create or replace function pg_temp.cn_submit(
  p_op text, p_order_id uuid, p_customer jsonb
) returns jsonb language sql as $$
  select public.sync_push(
    'c0000000-0000-0000-0000-00000000c501',
    'c0000000-0000-0000-0000-00000000da11',
    jsonb_build_array(jsonb_build_object(
      'local_operation_id', p_op,
      'operation_type', 'order.submit',
      'target_entity', 'order',
      'payload', (jsonb_build_object(
        'order_id', p_order_id,
        'order_type', 'takeaway',
        'currency_code', 'USD',
        'subtotal_minor', 1000,
        'discount_total_minor', 0,
        'tax_total_minor', 0,
        'grand_total_minor', 1000,
        'order_items', jsonb_build_array(jsonb_build_object(
          'menu_item_id', 'c0000000-0000-0000-0000-0000000000f1',
          'quantity', 1,
          'unit_price_minor_snapshot', 1000,
          'menu_item_name_snapshot', 'Item'))
      ) || p_customer))));
$$;

-- perform the submits (setup statements; assertions follow)
select pg_temp.cn_submit('cn-op-1', 'c0000000-0000-0000-0000-00000000d001', jsonb_build_object('customer_name', '  Sara Cohen  '));
select pg_temp.cn_submit('cn-op-2', 'c0000000-0000-0000-0000-00000000d002', jsonb_build_object('customer_name', '   '));
select pg_temp.cn_submit('cn-op-3', 'c0000000-0000-0000-0000-00000000d003', '{}'::jsonb);
select pg_temp.cn_submit('cn-op-4', 'c0000000-0000-0000-0000-00000000d004', jsonb_build_object('customer_name', repeat('x', 100)));
select pg_temp.cn_submit('cn-op-5', 'c0000000-0000-0000-0000-00000000d005', jsonb_build_object('customer_name', 'محمد عبد الله'));

-- ===== (1) submit applied + (2) stored trimmed ===============================
select is(
  (select status from orders where id = 'c0000000-0000-0000-0000-00000000d001'),
  'submitted', 'order.submit with a customer name applies (order persisted at submitted)');
select is(
  (select customer_name from orders where id = 'c0000000-0000-0000-0000-00000000d001'),
  'Sara Cohen', 'customer_name is stored TRIMMED (leading/trailing whitespace removed)');

-- ===== (3) whitespace-only name -> empty->null ===============================
select ok(
  (select customer_name is null from orders where id = 'c0000000-0000-0000-0000-00000000d002'),
  'a whitespace-only customer_name is normalized to NULL');

-- ===== (4) NO customer_name key -> NULL (backward compatible) =================
select ok(
  (select customer_name is null from orders where id = 'c0000000-0000-0000-0000-00000000d003'),
  'an order.submit with NO customer_name key leaves customer_name NULL (existing clients keep working)');

-- ===== (5) a name longer than 80 chars is capped at 80 =======================
select is(
  (select length(customer_name) from orders where id = 'c0000000-0000-0000-0000-00000000d004')::int,
  80, 'a >80-char customer_name is truncated to 80 chars');

-- ===== (6) Arabic/Hebrew display name is preserved exactly ====================
select is(
  (select customer_name from orders where id = 'c0000000-0000-0000-0000-00000000d005'),
  'محمد عبد الله', 'an Arabic customer name is stored exactly (ar/he/en supported)');

-- ===== (7) the stamp does NOT bump revision (order stays revision 1) ==========
select is(
  (select revision from orders where id = 'c0000000-0000-0000-0000-00000000d001')::int,
  1, 'stamping customer_name did NOT bump order revision (payment/order.status flow intact)');

-- ===== (8-9) kitchen sync_pull surfaces the name but REDACTS money (T-003) ====
select ok(
  exists (
    select 1
    from jsonb_array_elements(
           app.sync_pull('c0000000-0000-0000-0000-00000000c504', 'c0000000-0000-0000-0000-00000000da22',
             array['orders'], '{}'::jsonb, 500) -> 'changes' -> 'orders' -> 'rows') as r
    where r ->> 'id' = 'c0000000-0000-0000-0000-00000000d001'
      and r ->> 'customer_name' = 'Sara Cohen'),
  'the kitchen sync_pull row for the order carries customer_name (reaches the KDS ticket)');
select ok(
  not exists (
    select 1
    from jsonb_array_elements(
           app.sync_pull('c0000000-0000-0000-0000-00000000c504', 'c0000000-0000-0000-0000-00000000da22',
             array['orders'], '{}'::jsonb, 500) -> 'changes' -> 'orders' -> 'rows') as r
    where r ->> 'id' = 'c0000000-0000-0000-0000-00000000d001'
      and (r ? 'grand_total_minor' or r ? 'subtotal_minor' or r ? 'tax_total_minor')),
  'the same kitchen row has NO *_minor money keys (KDS stays money-free, redact_money intact)');

-- ===== (10-11) idempotent replay: same op keeps the name, no second order =====
select is(
  (pg_temp.cn_submit('cn-op-1', 'c0000000-0000-0000-0000-00000000d001',
     jsonb_build_object('customer_name', '  Sara Cohen  ')) -> 'results' -> 0 ->> 'idempotency_replay')::boolean,
  true, 'replaying the same order.submit op returns the stored result (idempotency_replay)');
select is(
  (select customer_name from orders where id = 'c0000000-0000-0000-0000-00000000d001'),
  'Sara Cohen', 'the replay did not change or duplicate the stamped customer_name');

select * from finish();
rollback;
