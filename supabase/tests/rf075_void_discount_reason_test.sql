-- ============================================================================
-- RF-075 — pgTAP: void/discount reasons from audit_events (AC3, D-013)
-- ============================================================================
-- An order-level fixed discount (500, reason 'loyalty') and a void (reason
-- 'spilled drink') surface in daily_branch_void_discount_reasons with the
-- reason, operator (employee profile), and discount type/value sourced from
-- audit_events (order.discount_applied / order.voided). The voided order is
-- excluded from net sales and counted in the voids bucket.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(8);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf075vd-a', 'USD');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a0', 'Rest A1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', 'Branch A1', 'UTC');
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'T1', true);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee01', 'rf075vd-manager@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');
insert into menu_categories (id, organization_id, restaurant_id, branch_id, name, display_order) values
  ('00000000-0000-0000-0000-00000000ca7a', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, 'Fixture Food', 1);
insert into menu_items (id, organization_id, restaurant_id, branch_id, menu_category_id, name, base_price_minor, currency_code, display_order) values
  ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, '00000000-0000-0000-0000-00000000ca7a', 'Item2', 1000, 'USD', 1),
  ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', null, '00000000-0000-0000-0000-00000000ca7a', 'Item3', 1000, 'USD', 2);

select app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000);
-- discounted order
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-sub2','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f2","quantity":2,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item2"}]'::jsonb,2000,0,0,2000,null);
select app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-disc','order',null,'fixed',500,'loyalty',null);
-- voided order
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-00000000da11','op-sub3','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f3","quantity":3,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item3"}]'::jsonb,3000,0,0,3000,null);
select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-00000000da11','op-void','spilled drink',null);

set local role authenticated;
set local app.current_app_user_id     = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';

-- void reason + operator from audit
select is((select count(*) from public.daily_branch_void_discount_reasons where action='order.voided')::int, 1, 'one void reason row');
select is((select reason from public.daily_branch_void_discount_reasons where action='order.voided'), 'spilled drink', 'void reason sourced from audit');
select is((select operator_employee_profile_id from public.daily_branch_void_discount_reasons where action='order.voided'),
          '00000000-0000-0000-0000-0000000ef001'::uuid, 'void operator sourced from audit');

-- discount reason + type + value + operator from audit
select is((select count(*) from public.daily_branch_void_discount_reasons where action='order.discount_applied')::int, 1, 'one discount reason row');
select is((select reason from public.daily_branch_void_discount_reasons where action='order.discount_applied'), 'loyalty', 'discount reason sourced from audit');
select is((select discount_type from public.daily_branch_void_discount_reasons where action='order.discount_applied'), 'fixed', 'discount_type sourced from audit');
select is((select discount_value from public.daily_branch_void_discount_reasons where action='order.discount_applied')::bigint, 500::bigint, 'discount_value sourced from audit');

-- voided order is excluded from net sales but counted in the voids bucket
select is(
  (select void_count from public.daily_branch_sales_report where branch_id='00000000-0000-0000-0000-00000000a1b1')::int,
  1, 'voided order in the voids bucket (excluded from net sales)');

select * from finish();
rollback;
