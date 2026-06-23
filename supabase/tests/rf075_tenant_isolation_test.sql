-- ============================================================================
-- RF-075 — pgTAP: tenant/branch isolation (AC2, TH-1/T-001, RISK R-003)
-- ============================================================================
-- Org A has a paid order (a report row). An org-B manager must NOT see org A's
-- branch in daily_branch_sales_report; an org-A manager queried under the WRONG
-- org context (org B) also sees nothing (org-context binding via can_read_financials).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(4);

-- ---- Org A (with data) ----
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf075ti-a', 'USD');
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
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000ee01', 'rf075ti-a-mgr@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab01', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', 'manager');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-00000000ee01', '00000000-0000-0000-0000-00000000ab01');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000c501', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000a1b1', '00000000-0000-0000-0000-0000000005a1', '00000000-0000-0000-0000-0000000ef001', '00000000-0000-0000-0000-00000000ab01', now() + interval '1 hour');

select app.open_shift('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a5f1','00000000-0000-0000-0000-00000000acd1','00000000-0000-0000-0000-00000000da11','op-open',5000);
select app.submit_order('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-sub1','dine_in',null,null,'USD',null,
  '[{"menu_item_id":"00000000-0000-0000-0000-0000000000f1","quantity":1,"unit_price_minor_snapshot":1000,"menu_item_name_snapshot":"Item"}]'::jsonb,1000,0,0,1000,null);
select app.record_payment('00000000-0000-0000-0000-00000000c501','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','op-pay1','cash',1000,null);

-- ---- Org B (a manager in a different org, no data) ----
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf075ti-b', 'USD');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000b0', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-00000000b1b1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', 'Branch B1', 'UTC');
insert into app_users (id, email) values ('00000000-0000-0000-0000-00000000eeb1', 'rf075ti-b-mgr@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000000bb', '00000000-0000-0000-0000-00000000eeb1', '00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000b1b1', 'manager');

-- ===== org-B manager: cannot see org A =====
set local role authenticated;
set local app.current_app_user_id     = '00000000-0000-0000-0000-00000000eeb1';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select is((select count(*) from public.daily_branch_sales_report
           where branch_id='00000000-0000-0000-0000-00000000a1b1')::int, 0,
          'org-B manager sees ZERO rows for org-A branch');
select is((select count(*) from public.daily_branch_sales_report)::int, 0,
          'org-B manager sees ZERO rows total (no org-B data)');

-- ===== org-A manager (correct context): sees org A =====
set local app.current_app_user_id     = '00000000-0000-0000-0000-00000000ee01';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select count(*) from public.daily_branch_sales_report
           where branch_id='00000000-0000-0000-0000-00000000a1b1')::int, 1,
          'org-A manager sees the org-A branch row');

-- ===== org-A manager under WRONG org context (org B): sees nothing =====
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select is((select count(*) from public.daily_branch_sales_report)::int, 0,
          'org-A manager under org-B context sees ZERO rows (org-context binding)');

select * from finish();
rollback;
