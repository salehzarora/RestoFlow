-- ============================================================================
-- RF-053 — pgTAP: discount money (integer _minor, rounding, clamp) (AC#3)
-- ============================================================================
-- Fixed (_minor) and percentage (basis points) discounts compute integer _minor
-- with round-half-away, clamp so totals never go negative, recompute order/item
-- totals from snapshots, reject invalid values, and do not double-apply on replay.
-- Fixtures inserted as the BYPASSRLS connection role.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(13);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf053m-a', 'USD');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf053m-mgr@example.test'),
  ('00000000-0000-0000-0000-00000000ee03', 'rf053m-cgrant@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role, permissions) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager', '{}'::jsonb),
  ('00000000-0000-0000-0000-00000000ab03', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'cashier', '{"apply_discount":"true"}'::jsonb);
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01'),
  ('00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee03', '00000000-0000-0000-0000-00000000ab03');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000c503', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef003', '00000000-0000-0000-0000-00000000ab03', now() + interval '1 hour');

-- orders: ord1 subtotal 1000, ord2 subtotal 1005, ord3 subtotal 1000, ord4 subtotal 1100 (with item+modifier)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,0,0,1000,'od-1'),
  ('00000000-0000-0000-0000-00000000a0d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1005,0,0,1005,'od-2'),
  ('00000000-0000-0000-0000-00000000a0d3', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1000,0,0,1000,'od-3'),
  ('00000000-0000-0000-0000-00000000a0d4', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-0000000ef001','00000000-0000-0000-0000-00000000ab01','dine_in','submitted','USD',1100,0,0,1100,'od-4');
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor) values
  ('00000000-0000-0000-0000-000000005104', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d4','00000000-0000-0000-0000-0000000000f1','pending',2,'Burger',500,0,1100);
insert into order_item_modifiers (id, organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id, option_name_snapshot, price_minor_snapshot, quantity) values
  ('00000000-0000-0000-0000-000000006104', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-000000005104','00000000-0000-0000-0000-0000000000f2','Cheese',100,1);
-- a VOIDED item on the (non-terminal) ord4 order, to prove it cannot be discounted
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_discount_minor, line_total_minor, void_reason) values
  ('00000000-0000-0000-0000-0000000051f0', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-00000000a1b1','00000000-0000-0000-0000-00000000a0d4','00000000-0000-0000-0000-0000000000f3','voided',1,'Removed',300,0,0,'comp');

-- order-level FIXED 200 on ord1 (subtotal 1000) ------------------------------ 1-2
select is((app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','od-1','order',null,'fixed',200,'promo',null) ->> 'discount_total_minor')::bigint, 200::bigint, 'order-level fixed discount = 200 (_minor)');
select is((select grand_total_minor from orders where id='00000000-0000-0000-0000-00000000a0d1')::bigint, 800::bigint, 'order grand_total recomputed to 800');

-- order-level PERCENTAGE 1000bp (10%) on ord2 (subtotal 1005, half-away) ------ 3-4
select is((app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','od-2','order',null,'percentage',1000,'promo',null) ->> 'discount_total_minor')::bigint, 101::bigint, 'percentage 10% of 1005 = round(100.5) = 101 (half away from zero)');
select is((select grand_total_minor from orders where id='00000000-0000-0000-0000-00000000a0d2')::bigint, 904::bigint, 'order grand_total recomputed to 904');

-- clamp: FIXED 5000 on ord3 (subtotal 1000) -> discount clamped to 1000 ------- 5-6
select is((app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-00000000da11','od-3','order',null,'fixed',5000,'comp',null) ->> 'discount_total_minor')::bigint, 1000::bigint, 'a fixed discount over subtotal is clamped to subtotal (1000)');
select is((select grand_total_minor from orders where id='00000000-0000-0000-0000-00000000a0d3')::bigint, 0::bigint, 'clamped grand_total never goes below zero (0)');

-- invalid values rejected ---------------------------------------------------- 7-8
select throws_ok($$ select app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','od-neg','order',null,'fixed',-100,'x',null) $$, '42501', NULL, 'a negative discount value is rejected');
select throws_ok($$ select app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','od-pct','order',null,'percentage',10001,'x',null) $$, '42501', NULL, 'a percentage over 10000 basis points is rejected');

-- item-level FIXED 300 on ord4 item (base 2*500+100 = 1100) ------------------ 9-11
select is((app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d4','00000000-0000-0000-0000-00000000da11','od-4','order_item','00000000-0000-0000-0000-000000005104','fixed',300,'item promo',null) ->> 'line_discount_minor')::bigint, 300::bigint, 'item-level fixed discount = 300');
select is((select line_total_minor from order_items where id='00000000-0000-0000-0000-000000005104')::bigint, 800::bigint, 'item line_total recomputed to base(1100) - 300 = 800');
select is((select grand_total_minor from orders where id='00000000-0000-0000-0000-00000000a0d4')::bigint, 800::bigint, 'order subtotal/grand recomputed from the discounted line (800)');

-- replay does not double-apply (same key on ord1's order-level fixed) -------- 12
select app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','od-1','order',null,'fixed',200,'promo',null);
select is((select discount_total_minor from orders where id='00000000-0000-0000-0000-00000000a0d1')::bigint, 200::bigint, 'replaying the same discount op does NOT stack (stays 200)');

-- a voided item cannot be discounted (even within a non-terminal order) ------ 13
select throws_ok($$ select app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d4','00000000-0000-0000-0000-00000000da11','od-voiditem','order_item','00000000-0000-0000-0000-0000000051f0','fixed',50,'x',null) $$, '42501', NULL, 'discounting a voided order_item is rejected');

select * from finish();
rollback;
