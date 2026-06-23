-- ============================================================================
-- RF-092 — pgTAP: owner/manager dashboard rollups (multi-restaurant/branch)
-- ============================================================================
-- One org with Restaurant A1 (branches b1=1000, b2=2000) + Restaurant A2
-- (branch b3=3000), each with a submitted order (+ item) and a completed cash
-- payment. Proves: org_owner aggregates all branches across both restaurants
-- (AC1); a branch-scoped manager sees only their branch (AC2); rollups reconcile
-- to daily_branch_sales_report (AC3); kitchen_staff denied; cross-tenant denied;
-- read-only. Fixtures inserted as the BYPASSRLS connection role; assertions run
-- as authenticated with the interim GUC identity (no MFA gate on these views).
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(16);

insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000000a0', 'Org A', 'rf092-a', 'USD'),
  ('00000000-0000-0000-0000-0000000000b0', 'Org B', 'rf092-b', 'USD');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-00000000aa11', '00000000-0000-0000-0000-0000000000a0', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-00000000aa21', '00000000-0000-0000-0000-0000000000a0', 'Rest A2', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-00000000ab11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', 'A1 Branch 1', 'UTC'),
  ('00000000-0000-0000-0000-00000000ab12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', 'A1 Branch 2', 'UTC'),
  ('00000000-0000-0000-0000-00000000ab21', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa21', 'A2 Branch 1', 'UTC');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', '00000000-0000-0000-0000-00000000ab11', 'pos'),
  ('00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', '00000000-0000-0000-0000-00000000ab12', 'pos'),
  ('00000000-0000-0000-0000-00000000da21', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa21', '00000000-0000-0000-0000-00000000ab21', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000fa11', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', '00000000-0000-0000-0000-00000000ab11', '00000000-0000-0000-0000-00000000da11', 'active'),
  ('00000000-0000-0000-0000-00000000fa12', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', '00000000-0000-0000-0000-00000000ab12', '00000000-0000-0000-0000-00000000da12', 'active'),
  ('00000000-0000-0000-0000-00000000fa21', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa21', '00000000-0000-0000-0000-00000000ab21', '00000000-0000-0000-0000-00000000da21', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', '00000000-0000-0000-0000-00000000ab11', '00000000-0000-0000-0000-00000000da11', '00000000-0000-0000-0000-00000000fa11'),
  ('00000000-0000-0000-0000-00000000c512', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', '00000000-0000-0000-0000-00000000ab12', '00000000-0000-0000-0000-00000000da12', '00000000-0000-0000-0000-00000000fa12'),
  ('00000000-0000-0000-0000-00000000c513', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa21', '00000000-0000-0000-0000-00000000ab21', '00000000-0000-0000-0000-00000000da21', '00000000-0000-0000-0000-00000000fa21');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000ee0a', 'rf092-owner@example.test'),
  ('00000000-0000-0000-0000-00000000ee0b', 'rf092-manager@example.test'),
  ('00000000-0000-0000-0000-00000000ee0c', 'rf092-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000ee0d', 'rf092-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-00000000ab0a', '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-0000000000a0', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-00000000ab0b', '00000000-0000-0000-0000-00000000ee0b', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', '00000000-0000-0000-0000-00000000ab11', 'manager'),
  ('00000000-0000-0000-0000-00000000ab0c', '00000000-0000-0000-0000-00000000ee0c', '00000000-0000-0000-0000-0000000000a0', null, null, 'kitchen_staff'),
  ('00000000-0000-0000-0000-00000000ab0d', '00000000-0000-0000-0000-00000000ee0d', '00000000-0000-0000-0000-0000000000b0', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-00000000ef01', '00000000-0000-0000-0000-0000000000a0', null, null, '00000000-0000-0000-0000-00000000ee0a', '00000000-0000-0000-0000-00000000ab0a');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-00000000d511', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', '00000000-0000-0000-0000-00000000ab11', '00000000-0000-0000-0000-00000000c511', '00000000-0000-0000-0000-00000000ef01', '00000000-0000-0000-0000-00000000ab0a', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000d512', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa11', '00000000-0000-0000-0000-00000000ab12', '00000000-0000-0000-0000-00000000c512', '00000000-0000-0000-0000-00000000ef01', '00000000-0000-0000-0000-00000000ab0a', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-00000000d513', '00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa21', '00000000-0000-0000-0000-00000000ab21', '00000000-0000-0000-0000-00000000c513', '00000000-0000-0000-0000-00000000ef01', '00000000-0000-0000-0000-00000000ab0a', now() + interval '1 hour');

-- one submitted order + item + completed cash payment per branch (1000/2000/3000)
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a0d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000aa11','00000000-0000-0000-0000-00000000ab11','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000d511','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab0a','dine_in','submitted','USD',1000,1000,'rf092-o1'),
  ('00000000-0000-0000-0000-00000000a0d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000aa11','00000000-0000-0000-0000-00000000ab12','00000000-0000-0000-0000-00000000da12','00000000-0000-0000-0000-00000000d512','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab0a','dine_in','submitted','USD',2000,2000,'rf092-o2'),
  ('00000000-0000-0000-0000-00000000a0d3', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000aa21','00000000-0000-0000-0000-00000000ab21','00000000-0000-0000-0000-00000000da21','00000000-0000-0000-0000-00000000d513','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab0a','dine_in','submitted','USD',3000,3000,'rf092-o3');
insert into order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, quantity, menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor) values
  ('00000000-0000-0000-0000-00000000a1d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000aa11','00000000-0000-0000-0000-00000000ab11','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-0000000000f1',1,'Item',1000,1000),
  ('00000000-0000-0000-0000-00000000a1d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000aa11','00000000-0000-0000-0000-00000000ab12','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-0000000000f2',1,'Item',2000,2000),
  ('00000000-0000-0000-0000-00000000a1d3', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000aa21','00000000-0000-0000-0000-00000000ab21','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-0000000000f3',1,'Item',3000,3000);
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-00000000a2d1', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000aa11','00000000-0000-0000-0000-00000000ab11','00000000-0000-0000-0000-00000000a0d1','00000000-0000-0000-0000-00000000da11','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab0a','cash','completed',1000,1000,0,'USD','rf092-p1'),
  ('00000000-0000-0000-0000-00000000a2d2', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000aa11','00000000-0000-0000-0000-00000000ab12','00000000-0000-0000-0000-00000000a0d2','00000000-0000-0000-0000-00000000da12','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab0a','cash','completed',2000,2000,0,'USD','rf092-p2'),
  ('00000000-0000-0000-0000-00000000a2d3', '00000000-0000-0000-0000-0000000000a0','00000000-0000-0000-0000-00000000aa21','00000000-0000-0000-0000-00000000ab21','00000000-0000-0000-0000-00000000a0d3','00000000-0000-0000-0000-00000000da21','00000000-0000-0000-0000-00000000ef01','00000000-0000-0000-0000-00000000ab0a','cash','completed',3000,3000,0,'USD','rf092-p3');

create temp table before_counts as select
  (select count(*) from orders) o, (select count(*) from order_items) i,
  (select count(*) from payments) p, (select count(*) from branches) b;

-- ===== org_owner: aggregates ALL branches across BOTH restaurants (AC1) =====
set local role authenticated;
set local app.current_app_user_id     = '00000000-0000-0000-0000-00000000ee0a';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000a0';
select is((select order_count from public.dashboard_org_daily_sales where organization_id='00000000-0000-0000-0000-0000000000a0')::int, 3, 'org_owner: org rollup order_count = 3 (all branches)');
select is((select gross_minor from public.dashboard_org_daily_sales where organization_id='00000000-0000-0000-0000-0000000000a0')::bigint, 6000::bigint, 'org_owner: org rollup gross_minor = 6000');
select is((select restaurant_count from public.dashboard_org_daily_sales where organization_id='00000000-0000-0000-0000-0000000000a0')::int, 2, 'org rollup restaurant_count = 2');
select is((select branch_count from public.dashboard_org_daily_sales where organization_id='00000000-0000-0000-0000-0000000000a0')::int, 3, 'org rollup branch_count = 3');
select is((select collected_total_minor from public.dashboard_org_daily_sales where organization_id='00000000-0000-0000-0000-0000000000a0')::bigint, 6000::bigint, 'org rollup collected_total_minor = 6000');
-- reconciliation (AC3): org rollup gross == SUM of visible daily_branch_sales_report
select is(
  (select gross_minor from public.dashboard_org_daily_sales where organization_id='00000000-0000-0000-0000-0000000000a0')::bigint,
  (select sum(gross_minor) from public.daily_branch_sales_report where organization_id='00000000-0000-0000-0000-0000000000a0')::bigint,
  'org rollup reconciles to SUM(daily_branch_sales_report)');
-- restaurant split
select is((select gross_minor from public.dashboard_restaurant_daily_sales where restaurant_id='00000000-0000-0000-0000-00000000aa11')::bigint, 3000::bigint, 'restaurant A1 gross_minor = 3000 (b1+b2)');
select is((select branch_count from public.dashboard_restaurant_daily_sales where restaurant_id='00000000-0000-0000-0000-00000000aa11')::int, 2, 'restaurant A1 branch_count = 2');
select is((select gross_minor from public.dashboard_restaurant_daily_sales where restaurant_id='00000000-0000-0000-0000-00000000aa21')::bigint, 3000::bigint, 'restaurant A2 gross_minor = 3000 (b3)');

-- ===== branch-scoped manager: sees ONLY their branch (AC2) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee0b';
select is((select order_count from public.dashboard_org_daily_sales where organization_id='00000000-0000-0000-0000-0000000000a0')::int, 1, 'branch manager: org rollup order_count = 1 (own branch only)');
select is((select gross_minor from public.dashboard_org_daily_sales where organization_id='00000000-0000-0000-0000-0000000000a0')::bigint, 1000::bigint, 'branch manager: org rollup gross = 1000 (own branch only)');
select is((select gross_minor from public.dashboard_restaurant_daily_sales where restaurant_id='00000000-0000-0000-0000-00000000aa11')::bigint, 1000::bigint, 'branch manager: restaurant A1 rollup = 1000 (only b1, NOT b2)');

-- ===== kitchen_staff: ZERO dashboard rows (financial gate) =====
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000ee0c';
select is((select count(*) from public.dashboard_org_daily_sales)::int, 0, 'kitchen_staff: ZERO org rollup rows');
select is((select count(*) from public.dashboard_restaurant_daily_sales)::int, 0, 'kitchen_staff: ZERO restaurant rollup rows');

-- ===== cross-tenant: org-B owner cannot see org-A rollups =====
set local app.current_app_user_id     = '00000000-0000-0000-0000-00000000ee0d';
set local app.current_organization_id = '00000000-0000-0000-0000-0000000000b0';
select is((select count(*) from public.dashboard_org_daily_sales where organization_id='00000000-0000-0000-0000-0000000000a0')::int, 0, 'cross-tenant: org-B owner sees ZERO org-A rollup rows');

-- ===== read-only: no tenant rows changed =====
reset role;
select ok((select b.o=(select count(*) from orders) and b.i=(select count(*) from order_items)
               and b.p=(select count(*) from payments) and b.b=(select count(*) from branches)
           from before_counts b),
          'read-only: selecting the rollup views created/changed no tenant rows');

select * from finish();
rollback;
