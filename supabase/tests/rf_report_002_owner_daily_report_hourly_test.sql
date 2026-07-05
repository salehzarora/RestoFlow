-- ============================================================================
-- RF-REPORT-002 — pgTAP: app.owner_daily_report TODAY sales-by-hour buckets.
-- Extends RF-REPORT-001. Org A (Rest A1 tz=UTC: branch A1a; Rest A2 tz=NULL:
-- branch A2a tz-less) and Org B. TODAY on A1a: billed orders at branch-local
-- hours 09:00 and 14:00, plus a voided + a cancelled order (excluded) and a
-- tz-less order (excluded). Asserts:
--   * hourly is a 24-bucket zero-filled array [{hour:0..23, net_minor}];
--   * BILLED net (subtotal - discount) bucketed by branch-local hour;
--   * void/cancelled excluded; tz-less excluded; sum matches daily net;
--   * integer-minor shape; empty scope -> all-zero hourly;
--   * ROLE GATE (kitchen_staff denied) + cross-org isolation + branch scope;
--   * public wrapper INVOKER + locked search_path + authenticated-only (no anon).
-- GUC-FREE (identity GUC only). All UUIDs hex-only. Session pinned to UTC so the
-- branch-local (UTC) hour buckets are deterministic.
-- ============================================================================
begin;
create extension if not exists pgtap with schema extensions;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';

select plan(15);

-- ===== fixture: Org A (Rest A1 tz=UTC + Rest A2 tz=NULL) and Org B ============
insert into organizations (id, name, slug, default_currency) values
  ('00000000-0000-0000-0000-0000000a0000', 'Org A', 'odh-a', 'ILS'),
  ('00000000-0000-0000-0000-0000000b0000', 'Org B', 'odh-b', 'EUR');
insert into restaurants (id, organization_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a0000', 'Rest A1', 'UTC'),
  ('00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a0000', 'Rest A2', null),
  ('00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b0000', 'Rest B1', 'UTC');
insert into branches (id, organization_id, restaurant_id, name, timezone) values
  ('00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', 'Branch A1a', null),
  ('00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', 'Branch A2a', null),
  ('00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', 'Branch B1a', null);
insert into devices (id, organization_id, restaurant_id, branch_id, device_type) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'pos'),
  ('00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', 'pos'),
  ('00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', 'pos');
insert into device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status) values
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', 'active'),
  ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-00000000d003', 'active'),
  ('00000000-0000-0000-0000-00000000c004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', 'active');
insert into device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000c001'),
  ('00000000-0000-0000-0000-00000000e003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-00000000c003'),
  ('00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-00000000c004');
insert into app_users (id, email) values
  ('00000000-0000-0000-0000-00000000f001', 'odh-owner@example.test'),
  ('00000000-0000-0000-0000-00000000f003', 'odh-kitchen@example.test'),
  ('00000000-0000-0000-0000-00000000f005', 'odh-orgb-owner@example.test');
insert into memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ('00000000-0000-0000-0000-0000000a0001', '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0000', null, null, 'org_owner'),
  ('00000000-0000-0000-0000-0000000a0003', '00000000-0000-0000-0000-00000000f003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', 'kitchen_staff'),
  ('00000000-0000-0000-0000-0000000a0005', '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000b0000', null, null, 'org_owner');
insert into employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id) values
  ('00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0000', null, null, '00000000-0000-0000-0000-00000000f001', '00000000-0000-0000-0000-0000000a0001'),
  ('00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000b0000', null, null, '00000000-0000-0000-0000-00000000f005', '00000000-0000-0000-0000-0000000a0005');
insert into pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id, resolved_membership_id, expires_at) values
  ('00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-00000000e003', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', now() + interval '1 hour'),
  ('00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', now() + interval '1 hour');

-- ---- TODAY orders on Branch A1a (Rest A1, tz=UTC), at fixed branch-local hours.
-- H09: O1 completed net 1000. H14: O2 served net 1500 (subtotal 1800 - disc 300)
-- + O3 completed net 500 => bucket 14 = 2000. H09: O4 VOIDED 9999 (excluded);
-- H14: O5 CANCELLED 8888 (excluded). Times are pinned to UTC = the branch zone.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001d001', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 1000, 0,   0, 1000, 'odh-o1', (current_date + interval '9 hours')  at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d002', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'served',    'ILS', 1800, 300, 0, 1500, 'odh-o2', (current_date + interval '14 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d003', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'takeaway','completed', 'ILS', 500,  0,   0, 500,  'odh-o3', (current_date + interval '14 hours') at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d004', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'voided',    'ILS', 9999, 0,   0, 9999, 'odh-o4', (current_date + interval '9 hours')  at time zone 'UTC'),
  ('00000000-0000-0000-0000-00000001d005', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00', '00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'cancelled', 'ILS', 8888, 0,   0, 8888, 'odh-o5', (current_date + interval '14 hours') at time zone 'UTC');
-- O6 TODAY on tz-less Branch A2a — MUST be excluded from hourly (no timezone).
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001d006', '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00', '00000000-0000-0000-0000-00000000d003', '00000000-0000-0000-0000-0000000b0003', '00000000-0000-0000-0000-0000000e0f01', '00000000-0000-0000-0000-0000000a0001', 'dine_in', 'completed', 'ILS', 7777, 0, 0, 7777, 'odh-o6', (current_date + interval '10 hours') at time zone 'UTC');
-- OB1 TODAY on Org B — isolation.
insert into orders (id, organization_id, restaurant_id, branch_id, device_id, pin_session_id, opened_by_employee_profile_id, resolved_membership_id, order_type, status, currency_code, subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor, local_operation_id, created_at) values
  ('00000000-0000-0000-0000-00000001d0b1', '00000000-0000-0000-0000-0000000b0000', '00000000-0000-0000-0000-0000000b1000', '00000000-0000-0000-0000-0000000b1a00', '00000000-0000-0000-0000-00000000d004', '00000000-0000-0000-0000-0000000b0005', '00000000-0000-0000-0000-0000000e0f05', '00000000-0000-0000-0000-0000000a0005', 'dine_in', 'completed', 'EUR', 9000, 0, 0, 9000, 'odh-ob1', (current_date + interval '9 hours') at time zone 'UTC');

-- ===== (1-9) org_owner org-wide (Org A): hourly buckets ======================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_all as select app.owner_daily_report('00000000-0000-0000-0000-0000000a0000', null, null) as res;
reset role;

select is((select (res->>'ok')::boolean from t_all), true, 'org_owner owner_daily_report ok=true');
select is((select jsonb_array_length(res->'hourly') from t_all), 24, 'hourly has 24 buckets (zero-filled 0..23)');
select is((select (res->'hourly'->0->>'hour')::int from t_all), 0, 'first bucket is hour 0');
select is((select (res->'hourly'->23->>'hour')::int from t_all), 23, 'last bucket is hour 23');
select is((select (res->'hourly'->9->>'net_minor')::bigint from t_all), 1000::bigint,
          'hour 9 net_minor = 1000 (O1; voided O4 9999 EXCLUDED)');
select is((select (res->'hourly'->14->>'net_minor')::bigint from t_all), 2000::bigint,
          'hour 14 net_minor = 2000 (O2 net 1500 + O3 500; cancelled O5 EXCLUDED)');
select is((select (res->'hourly'->0->>'net_minor')::bigint from t_all), 0::bigint,
          'hour 0 net_minor = 0 (honest zero-fill, never fabricated)');
select is(
  (select sum((h->>'net_minor')::bigint)::bigint from t_all, jsonb_array_elements(res->'hourly') h),
  3000::bigint, 'hourly total (3000) reconciles with today net_minor');
select is((select (res->'today'->>'net_minor')::bigint from t_all), 3000::bigint,
          'today net_minor = 3000 (matches summed hourly; tz-less O6 excluded)');

-- ===== (10) integer-minor shape: every net_minor is a JSON number =============
select ok(
  (select bool_and(jsonb_typeof(h->'net_minor') = 'number'
                   and jsonb_typeof(h->'hour') = 'number')
     from t_all, jsonb_array_elements(res->'hourly') h),
  'every hourly bucket is integer-shaped {hour:number, net_minor:number} (no float text)');

-- ===== (11) branch filter narrows hourly to Branch A1a ========================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
select is(
  (select (app.owner_daily_report('00000000-0000-0000-0000-0000000a0000','00000000-0000-0000-0000-0000000a1000','00000000-0000-0000-0000-0000000a1a00')->'hourly'->14->>'net_minor')::bigint),
  2000::bigint, 'branch A1a scope: hour 14 net_minor = 2000');
reset role;

-- ===== (12) tz-less branch A2a -> honest ALL-ZERO hourly ======================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';
create temp table t_empty as select app.owner_daily_report(
  '00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a2000', '00000000-0000-0000-0000-0000000a2a00') as res;
reset role;
select ok(
  (select jsonb_array_length(res->'hourly') = 24
     and (select coalesce(sum((h->>'net_minor')::bigint), 0) from jsonb_array_elements(res->'hourly') h) = 0
     and (res->>'ok')::boolean = true from t_empty),
  'tz-less branch yields a 24-bucket ALL-ZERO hourly (excluded rows, never fabricated)');

-- ===== (13) kitchen_staff is DENIED (no hourly leaked) ========================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f003';
select is(
  (select app.owner_daily_report('00000000-0000-0000-0000-0000000a0000', '00000000-0000-0000-0000-0000000a1000', '00000000-0000-0000-0000-0000000a1a00')->>'error'),
  'permission_denied', 'kitchen_staff cannot read the hourly report (permission_denied, no hourly)');
reset role;

-- ===== (14) cross-org caller is structurally rejected (42501) =================
set local role authenticated;
set local app.current_app_user_id = '00000000-0000-0000-0000-00000000f001';  -- Org A owner
select throws_ok(
  $$ select app.owner_daily_report('00000000-0000-0000-0000-0000000b0000', null, null) $$,
  '42501', NULL, 'an Org A owner cannot read the Org B hourly report (cross-org 42501)');
reset role;

-- ===== (15) public wrapper: INVOKER + locked search_path + no anon/PUBLIC ======
select ok(
  (select prosecdef = false from pg_proc where proname='owner_daily_report' and pronamespace='public'::regnamespace and pronargs=3)
  and (select exists(
     select 1 from pg_proc p cross join lateral unnest(coalesce(p.proconfig, '{}'::text[])) as cfg
     where p.proname='owner_daily_report' and p.pronamespace='public'::regnamespace and p.pronargs=3 and cfg like 'search_path=%'))
  and not has_function_privilege('anon', 'public.owner_daily_report(uuid, uuid, uuid)', 'execute')
  and not has_function_privilege('public', 'public.owner_daily_report(uuid, uuid, uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.owner_daily_report(uuid, uuid, uuid)', 'execute'),
  'public.owner_daily_report is INVOKER, search_path-locked, authenticated-only (no anon/PUBLIC)');

select * from finish();
rollback;
