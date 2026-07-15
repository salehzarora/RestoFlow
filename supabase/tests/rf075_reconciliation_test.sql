-- ============================================================================
-- RF-075 — pgTAP: daily_branch_sales_report reconciliation (AC1, D-007)
-- ============================================================================
-- One branch-day of real RPC-produced data:
--   order1: subtotal 1000, grand 1000, paid cash 1000
--   order2: subtotal 2000, order-level discount 500 -> grand 1500, paid cash 1500
--   order3: subtotal 3000, grand 3000, VOIDED (excluded from sales)
-- Expected report row (integer _minor, zero drift):
--   order_count 2, gross 3000, discount_total 500, net_sales 2500, tax 0,
--   void_count 1, void_total 3000, collected_total 2500, collected_cash 2500.
-- Asserted as the org-A manager (a financial role); branch.timezone='UTC' makes
-- business_day deterministic so the branch has exactly one report row.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(10);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf075r-a', 'USD');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1', 'UTC');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf075r-manager@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'T1', true);
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00000000ca01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, '00000000-0000-0000-0000-00000000ca01', 'Item', 1000, 'USD', 1),
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, '00000000-0000-0000-0000-00000000ca01', 'Item2', 1000, 'USD', 2),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, '00000000-0000-0000-0000-00000000ca01', 'Item3', 1000, 'USD', 3);

-- real data via the SECURITY DEFINER RPCs (manager pin session)
select app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000);

-- order1: 1 x 1000 -> subtotal/grand 1000; paid 1000
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-sub1','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null);
select app.record_payment('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-pay1','cash',1000,null);

-- order2: 2 x 1000 -> subtotal/grand 2000; order discount 500 -> grand 1500; paid 1500
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-sub2','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f2","quantity":2,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item2"}]'::jsonb,2000,0,0,2000,null);
select app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-disc','order',null,'fixed',500,'loyalty',null);
select app.record_payment('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-pay2','cash',1500,null);

-- order3: 3 x 1000 -> subtotal/grand 3000; VOIDED (no payment)
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-00000000da11','op-sub3','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f3","quantity":3,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item3"}]'::jsonb,3000,0,0,3000,null);
select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-00000000da11','op-void','spilled drink',null);

-- ===== assert as the org-A manager (financial role) =====
set local role authenticated;
set local app.current_app_user_id   = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

select is(
  (select count(*) from public.daily_branch_sales_report
   where branch_id = '00000000-0000-0000-0000-00000000a1b1')::int,
  1, 'exactly one report row for the branch-day');

select is((select order_count          from public.daily_branch_sales_report where branch_id='00000000-0000-0000-0000-00000000a1b1')::int, 2, 'order_count = 2 (voided excluded)');
select is((select gross_minor          from public.daily_branch_sales_report where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 3000::bigint, 'gross_minor = 3000 (pre-discount)');
select is((select discount_total_minor from public.daily_branch_sales_report where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 500::bigint, 'discount_total_minor = 500');
select is((select net_sales_minor      from public.daily_branch_sales_report where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 2500::bigint, 'net_sales_minor = 2500');
select is((select tax_total_minor      from public.daily_branch_sales_report where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 0::bigint, 'tax_total_minor = 0 (passthrough)');
select is((select void_count           from public.daily_branch_sales_report where branch_id='00000000-0000-0000-0000-00000000a1b1')::int, 1, 'void_count = 1');
select is((select void_total_minor     from public.daily_branch_sales_report where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 3000::bigint, 'void_total_minor = 3000 (separate bucket)');
select is((select collected_total_minor from public.daily_branch_sales_report where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint, 2500::bigint, 'collected_total_minor = 2500 (completed payments)');
-- identity: gross - discount_total = net_sales (zero drift)
select is(
  (select gross_minor - discount_total_minor - net_sales_minor
   from public.daily_branch_sales_report where branch_id='00000000-0000-0000-0000-00000000a1b1')::bigint,
  0::bigint, 'reconciliation identity gross - discounts - net = 0 (zero drift)');

select * from finish();
rollback;
