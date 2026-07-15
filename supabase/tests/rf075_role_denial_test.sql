-- ============================================================================
-- RF-075 — pgTAP: role denial (AC2, T-003, RISK R-003)
-- ============================================================================
-- kitchen_staff must read ZERO rows from every RF-075 financial report view
-- (sales / shift lines / void-discount reasons); a manager (financial role)
-- in the same scope reads them (positive control, no over-redaction).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(6);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf075d-a', 'USD');
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
  ('00000000-0000-0000-0000-00000000ee01', 'rf075d-manager@example.test'),
  ('00000000-0000-0000-0000-00000000ee04', 'rf075d-kitchen@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager'),
  ('00000000-0000-0000-0000-00000000ab04', '00000000-0000-0000-0000-00000000ee04', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'kitchen_staff');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into tables (id, organization_id, restaurant_id, branch_id, label, is_active) values
  ('00000000-0000-0000-0000-00000000ab1e', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'RF075D-T1', true);
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

-- one order (paid), one discount, one void, one shift -> all three views have data
select app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000);
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-sub2','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f2","quantity":2,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item2"}]'::jsonb,2000,0,0,2000,null);
select app.apply_discount('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-disc','order',null,'fixed',500,'loyalty',null);
select app.record_payment('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da11','op-pay2','cash',1500,null);
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-00000000da11','op-sub3','dine_in','00000000-0000-0000-0000-00000000ab1e',null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f3","quantity":3,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item3"}]'::jsonb,3000,0,0,3000,null);
select app.void_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-00000000da11','op-void','spilled drink',null);

-- ===== kitchen_staff: ZERO rows from every financial report view (T-003) =====
set local role authenticated;
set local app.current_app_user_id     = '00000000-0000-0000-0000-00000000ee04';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from public.daily_branch_sales_report)::int,          0, 'kitchen_staff: ZERO rows from daily_branch_sales_report');
select is((select count(*) from public.daily_branch_shift_lines)::int,           0, 'kitchen_staff: ZERO rows from daily_branch_shift_lines');
select is((select count(*) from public.daily_branch_void_discount_reasons)::int, 0, 'kitchen_staff: ZERO rows from daily_branch_void_discount_reasons');

-- ===== manager (financial role): SEES the report (positive control) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee01';
select cmp_ok((select count(*) from public.daily_branch_sales_report)::int,          '>', 0, 'manager: SEES daily_branch_sales_report rows');
select cmp_ok((select count(*) from public.daily_branch_shift_lines)::int,           '>', 0, 'manager: SEES daily_branch_shift_lines rows');
select cmp_ok((select count(*) from public.daily_branch_void_discount_reasons)::int, '>', 0, 'manager: SEES daily_branch_void_discount_reasons rows');

select * from finish();
rollback;
