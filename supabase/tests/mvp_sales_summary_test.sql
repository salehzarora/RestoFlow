-- ============================================================================
-- MVP — pgTAP: app.sales_summary (GUC-free today + last-7-days sales summary).
-- Two orgs + two branches with mixed-status orders (incl. a cancelled one) and
-- mixed-status payments (completed + pending): owner sees own-org totals only
-- (RISK R-003); branch filter narrows; cashier rank-denied; cancelled orders
-- and non-completed payments excluded from every sum (D-007 integer minor);
-- 7 zero-filled ascending day entries; public-wrapper introspection.
-- GUC-FREE (identity GUC only), mirroring rf160_list_devices_test.sql.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;

select plan(21);

-- ===== fixture: Org A (Rest A1: branches A1a + A1b) and Org B =================
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0005a1e50a00', 'Org A', 'mvpss-a', 'USD'),
  ('00000000-0000-0000-0000-0005a1e50b00', 'Org B', 'mvpss-b', 'EUR');
insert into restaurants (id, organization_id, name) values
  ('00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a00', 'Rest A1'),
  ('00000000-0000-0000-0000-0005a1e50b10', '00000000-0000-0000-0000-0005a1e50b00', 'Rest B1');
insert into branches (id, organization_id, restaurant_id, name) values
  ('00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', 'Branch A1a'),
  ('00000000-0000-0000-0000-0005a1e50a1b', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', 'Branch A1b'),
  ('00000000-0000-0000-0000-0005a1e50b1a', '00000000-0000-0000-0000-0005a1e50b00', '00000000-0000-0000-0000-0005a1e50b10', 'Branch B1a');
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', 'pos'),
  ('00000000-0000-0000-0000-0005a1e5d002', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1b', 'pos'),
  ('00000000-0000-0000-0000-0005a1e5d003', '00000000-0000-0000-0000-0005a1e50b00', '00000000-0000-0000-0000-0005a1e50b10', '00000000-0000-0000-0000-0005a1e50b1a', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-0005a1e51001', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e5d001', 'active'),
  ('00000000-0000-0000-0000-0005a1e51002', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1b', '00000000-0000-0000-0000-0005a1e5d002', 'active'),
  ('00000000-0000-0000-0000-0005a1e51003', '00000000-0000-0000-0000-0005a1e50b00', '00000000-0000-0000-0000-0005a1e50b10', '00000000-0000-0000-0000-0005a1e50b1a', '00000000-0000-0000-0000-0005a1e5d003', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-0005a1e52001', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e51001'),
  ('00000000-0000-0000-0000-0005a1e52002', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1b', '00000000-0000-0000-0000-0005a1e5d002', '00000000-0000-0000-0000-0005a1e51002'),
  ('00000000-0000-0000-0000-0005a1e52003', '00000000-0000-0000-0000-0005a1e50b00', '00000000-0000-0000-0000-0005a1e50b10', '00000000-0000-0000-0000-0005a1e50b1a', '00000000-0000-0000-0000-0005a1e5d003', '00000000-0000-0000-0000-0005a1e51003');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-0005a1e5e001', 'mvpss-owner@example.test'),
  ('00000000-0000-0000-0000-0005a1e5e002', 'mvpss-cashier@example.test'),
  ('00000000-0000-0000-0000-0005a1e5e003', 'mvpss-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0005a1e5f001', '00000000-0000-0000-0000-0005a1e5e001', '00000000-0000-0000-0000-0005a1e50a00', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0005a1e5f002', '00000000-0000-0000-0000-0005a1e5e002', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', 'cashier'),
  ('00000000-0000-0000-0000-0005a1e5f003', '00000000-0000-0000-0000-0005a1e5e003', '00000000-0000-0000-0000-0005a1e50b00', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e50a00', null, null, '00000000-0000-0000-0000-0005a1e5e001', '00000000-0000-0000-0000-0005a1e5f001'),
  ('00000000-0000-0000-0000-0005a1e5ef02', '00000000-0000-0000-0000-0005a1e50b00', null, null, '00000000-0000-0000-0000-0005a1e5e003', '00000000-0000-0000-0000-0005a1e5f003');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0005a1e5b001', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e52001', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0005a1e5b002', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1b', '00000000-0000-0000-0000-0005a1e52002', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0005a1e5b003', '00000000-0000-0000-0000-0005a1e50b00', '00000000-0000-0000-0000-0005a1e50b10', '00000000-0000-0000-0000-0005a1e50b1a', '00000000-0000-0000-0000-0005a1e52003', '00000000-0000-0000-0000-0005a1e5ef02', '00000000-0000-0000-0000-0005a1e5f003', now() + interval '1 hour');

-- orders TODAY: o1 (A1a, 1000) + o2 (A1a, 2000) + o5 (A1b, 3000) live submitted;
-- o3 (A1a, 5000) CANCELLED; o6 (B1a, 9000) belongs to Org B.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id) values
  ('00000000-0000-0000-0000-0005a1e50d01', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e5b001', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'dine_in', 'submitted', 'USD', 1000, 1000, 'mvpss-o1'),
  ('00000000-0000-0000-0000-0005a1e50d02', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e5b001', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'dine_in', 'submitted', 'USD', 2000, 2000, 'mvpss-o2'),
  ('00000000-0000-0000-0000-0005a1e50d03', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e5b001', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'dine_in', 'cancelled', 'USD', 5000, 5000, 'mvpss-o3'),
  ('00000000-0000-0000-0000-0005a1e50d05', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1b', '00000000-0000-0000-0000-0005a1e5d002', '00000000-0000-0000-0000-0005a1e5b002', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'takeaway', 'submitted', 'USD', 3000, 3000, 'mvpss-o5'),
  ('00000000-0000-0000-0000-0005a1e50d06', '00000000-0000-0000-0000-0005a1e50b00', '00000000-0000-0000-0000-0005a1e50b10', '00000000-0000-0000-0000-0005a1e50b1a', '00000000-0000-0000-0000-0005a1e5d003', '00000000-0000-0000-0000-0005a1e5b003', '00000000-0000-0000-0000-0005a1e5ef02', '00000000-0000-0000-0000-0005a1e5f003', 'dine_in', 'submitted', 'EUR', 9000, 9000, 'mvpss-o6');
-- o4: an A1a order created 3 DAYS AGO (700) — populates one prior 7-day bucket.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-0005a1e50d04', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e5b001', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'dine_in', 'submitted', 'USD', 700, 700, 'mvpss-o4', now() - interval '3 days');

-- payments TODAY: completed 1000 (o1) + 2000 (o2) + 3000 (o5); a PENDING 999 on
-- o2 (excluded); a COMPLETED 5000 on the CANCELLED o3 (excluded: RF-062 forbids
-- this state via RPC; the summary defensively excludes it); Org B completed 9000.
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id) values
  ('00000000-0000-0000-0000-0005a1e5aa01', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e50d01', '00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'cash', 'completed', 1000, 1000, 0, 'USD', 'mvpss-p1'),
  ('00000000-0000-0000-0000-0005a1e5aa02', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e50d02', '00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'cash', 'completed', 2000, 2000, 0, 'USD', 'mvpss-p2'),
  ('00000000-0000-0000-0000-0005a1e5aa03', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1b', '00000000-0000-0000-0000-0005a1e50d05', '00000000-0000-0000-0000-0005a1e5d002', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'cash', 'completed', 3000, 3000, 0, 'USD', 'mvpss-p3'),
  ('00000000-0000-0000-0000-0005a1e5aa04', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e50d02', '00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'cash', 'pending',    999,  999, 0, 'USD', 'mvpss-p4'),
  ('00000000-0000-0000-0000-0005a1e5aa05', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e50d03', '00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'cash', 'completed', 5000, 5000, 0, 'USD', 'mvpss-p5'),
  ('00000000-0000-0000-0000-0005a1e5aa07', '00000000-0000-0000-0000-0005a1e50b00', '00000000-0000-0000-0000-0005a1e50b10', '00000000-0000-0000-0000-0005a1e50b1a', '00000000-0000-0000-0000-0005a1e50d06', '00000000-0000-0000-0000-0005a1e5d003', '00000000-0000-0000-0000-0005a1e5ef02', '00000000-0000-0000-0000-0005a1e5f003', 'cash', 'completed', 9000, 9000, 0, 'EUR', 'mvpss-p7');
-- pay6: the completed payment for the 3-days-ago order (700).
insert into payments (id, organization_id, restaurant_id, branch_id, order_id, device_id, taken_by_employee_profile_id, resolved_membership_id, method, status, amount_minor, tendered_minor, change_minor, currency_code, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-0005a1e5aa06', '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a', '00000000-0000-0000-0000-0005a1e50d04', '00000000-0000-0000-0000-0005a1e5d001', '00000000-0000-0000-0000-0005a1e5ef01', '00000000-0000-0000-0000-0005a1e5f001', 'cash', 'completed', 700, 700, 0, 'USD', 'mvpss-p6', now() - interval '3 days');

-- ===== (1-11) org_owner org-wide: own-org totals only, 7-day shape =============
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0005a1e5e001';
create temp table t_all as select app.sales_summary('00000000-0000-0000-0000-0005a1e50a00', null, null) as res;
reset role;
select is((select (res->>'ok')::boolean from t_all), true, 'org_owner sales_summary returns ok=true');
select is((select res->>'currency_code' from t_all), 'USD', 'currency_code = organizations.default_currency');
select is((select (res->'today'->>'orders_count')::int from t_all), 3,
          'today orders_count = 3 (cancelled + 3-days-ago + Org B orders excluded)');
select is((select (res->'today'->>'payments_count')::int from t_all), 3,
          'today payments_count = 3 completed (pending + cancelled-order + Org B payments excluded)');
select is((select (res->'today'->>'gross_minor')::bigint from t_all), 6000::bigint,
          'today gross_minor = 6000 (integer minor; pending 999 + cancelled-order 5000 + Org B 9000 excluded)');
select is((select jsonb_array_length(res->'last_7_days') from t_all), 7, 'last_7_days has exactly 7 day entries');
select is((select res->'last_7_days'->0->>'day' from t_all), (current_date - 6)::text,
          'the first entry is 6 days ago (ascending)');
select is((select res->'last_7_days'->6->>'day' from t_all), current_date::text,
          'the last entry is today');
select is((select (res->'last_7_days'->3->>'gross_minor')::bigint from t_all), 700::bigint,
          'the 3-days-ago bucket carries its completed 700');
select is((select (res->'last_7_days'->3->>'orders_count')::int from t_all), 1,
          'the 3-days-ago bucket counts its 1 order');
select ok((select (res->'last_7_days'->1->>'orders_count')::int = 0
             and (res->'last_7_days'->1->>'gross_minor')::bigint = 0 from t_all),
          'an activity-free day is zero-filled (orders_count=0, gross_minor=0)');

-- ===== (12-13) branch filter narrows to Branch A1a =============================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0005a1e5e001';
create temp table t_branch as select app.sales_summary(
  '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a') as res;
reset role;
select is((select (res->'today'->>'orders_count')::int from t_branch), 2,
          'branch filter: today orders_count = 2 (A1b order excluded)');
select is((select (res->'today'->>'gross_minor')::bigint from t_branch), 3000::bigint,
          'branch filter: today gross_minor = 3000 (1000 + 2000)');

-- ===== (14) rank denial: in-scope cashier -> permission_denied =================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0005a1e5e002';
create temp table t_cashier as select app.sales_summary(
  '00000000-0000-0000-0000-0005a1e50a00', '00000000-0000-0000-0000-0005a1e50a10', '00000000-0000-0000-0000-0005a1e50a1a') as res;
reset role;
select is((select res->>'error' from t_cashier), 'permission_denied', 'cashier cannot read the sales summary (permission_denied)');

-- ===== (15) cross-org caller is structurally rejected (42501) ==================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0005a1e5e001';  -- Org A owner
select throws_ok(
  $$ select app.sales_summary('00000000-0000-0000-0000-0005a1e50b00', null, null) $$,
  '42501', NULL, 'an Org A owner cannot read the Org B summary (cross-org 42501)');
reset role;

-- ===== (16) public.* wrapper delegates verbatim ================================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-0005a1e5e001';
select is(
  public.sales_summary('00000000-0000-0000-0000-0005a1e50a00', null, null),
  app.sales_summary('00000000-0000-0000-0000-0005a1e50a00', null, null),
  'public.sales_summary delegates verbatim to app.sales_summary');
reset role;

-- ===== (17-21) wrapper introspection: invoker / search_path / grants ===========
select is(
  (select prosecdef from pg_proc where proname='sales_summary' and pronamespace='public'::regnamespace and pronargs=3),
  false, 'public.sales_summary is SECURITY INVOKER (not definer)');
select ok(
  (select exists(
     select 1 from pg_proc p
     cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='sales_summary' and p.pronamespace='public'::regnamespace and p.pronargs=3
       and cfg like 'search_path=%')),
  'public.sales_summary has a locked search_path');
select ok(
  not has_function_privilege('public', 'public.sales_summary(uuid, uuid, uuid)', 'execute'),
  'PUBLIC may NOT execute public.sales_summary (revoked)');
select ok(
  not has_function_privilege('anon', 'public.sales_summary(uuid, uuid, uuid)', 'execute'),
  'anon may NOT execute public.sales_summary');
select ok(
  has_function_privilege('authenticated', 'public.sales_summary(uuid, uuid, uuid)', 'execute'),
  'authenticated MAY execute public.sales_summary');

select * from finish();
rollback;
